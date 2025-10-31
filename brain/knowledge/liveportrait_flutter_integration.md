# LivePortrait × Flutter × Python (GPU) — Pragmatiker-Setup

**Ziel:** günstig, lokal, robust. Architektur, API-Design, lauffähige Code-Skeletons (Python/FastAPI + Flutter), Queue/Scaling-Hinweise und ein Dockerfile (CUDA).

---

## Architektur (einfach & belastbar)

- **Flutter-App (iOS/Android/Web)**  
  – UI, nimmt **Text** (oder Audio), **Foto**, optional Stimme (Referenz-WAV).  
  – Ruft Python-API (HTTPS) auf, zeigt Fortschritt, spielt Ergebnis-MP4.

- **Python GPU-Backend (FastAPI)**  
  – `POST /tts`: Text → `audio.wav` (Coqui **XTTS‑v2** lokal).  
  – `POST /animate`: `source.jpg` + `audio.wav` → `out.mp4` (LivePortrait).  
  – `GET /jobs/{id}`: asynchron, Status + Result-URL.  
  – *(optional)* `POST /refine`: Wav2Lip‑ONNX‑HQ Post‑Step.

- **Worker/Queue (Celery + Redis)**  
  – Jobs **nicht** im Webprozess rendern; stabiler & skalierbar.  
  – 1–N GPU‑Worker (pro GPU 1–2 Concurrency).

- **Storage**  
  – Artefakte unter `/data/<job-id>/…`, NGINX Static für Downloads/Streaming.

---

## API-Contract (minimal)

```http
POST /tts
  body: { text: string, lang?: "de", voice_clone_wav?: file }
  ret:  { audio_url: string, audio_id: string }

POST /animate   (multipart/form-data)
  fields: source_image (file), audio (file or audio_id), fps=25, size=512
  ret:   { job_id: string, status: "queued" }

GET  /jobs/{job_id}
  ret: { status: "queued|running|done|error",
         progress?: int, video_url?: string, log_tail?: string }

GET  /health
```

> Optional: **WebSocket** `/ws/jobs/{job_id}` für Live‑Progress.

---

## Python/FastAPI + Celery (Skeleton)

**`app/main.py`**
```python
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from pydantic import BaseModel
from fastapi.responses import JSONResponse
from pathlib import Path
import uuid, shutil, os
from celery import Celery

DATA = Path("/data"); DATA.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="Avatar API")
celery = Celery("worker", broker=os.getenv("REDIS_URL", "redis://redis:6379/0"),
                backend=os.getenv("REDIS_URL", "redis://redis:6379/0"))

class TTSReq(BaseModel):
    text: str
    lang: str = "de"

@app.post("/tts")
def tts(req: TTSReq):
    job = uuid.uuid4().hex
    jdir = DATA / job; jdir.mkdir(parents=True, exist_ok=True)
    wav = jdir / "audio.wav"

    # Hinweis: in Produktion XTTS-Modell einmal beim App-Start laden
    from TTS.api import TTS
    tts = TTS("tts_models/multilingual/multi-dataset/xtts_v2")
    tts.tts_to_file(text=req.text, language=req.lang, file_path=str(wav))
    return {"audio_url": f"/static/{job}/audio.wav", "audio_id": job}

@app.post("/animate")
async def animate(source_image: UploadFile = File(...),
                  audio: UploadFile | None = None,
                  audio_id: str | None = Form(default=None),
                  fps: int = Form(default=25),
                  size: int = Form(default=512)):
    job = uuid.uuid4().hex
    jdir = DATA / job; jdir.mkdir(parents=True, exist_ok=True)
    img_path = jdir / "source.jpg"
    with open(img_path, "wb") as f: shutil.copyfileobj(source_image.file, f)

    if audio is None and not audio_id:
        raise HTTPException(400, "audio or audio_id required")

    if audio_id:
        wav_path = DATA / audio_id / "audio.wav"
    else:
        wav_path = jdir / "audio.wav"
        with open(wav_path, "wb") as f: shutil.copyfileobj(audio.file, f)

    # Celery-Job
    task = run_liveportrait.delay(str(img_path), str(wav_path), str(jdir), fps, size)
    return {"job_id": task.id, "status": "queued"}

@app.get("/jobs/{job_id}")
def job_status(job_id: str):
    res = celery.AsyncResult(job_id)
    payload = {"status": res.status.lower()}
    if res.status == "SUCCESS":
        payload["video_url"] = res.result
    elif res.status == "FAILURE":
        payload["error"] = str(res.result)
    return payload
```

**`app/worker.py`**
```python
from celery import Celery
from pathlib import Path
import subprocess, os

celery = Celery("worker", broker=os.getenv("REDIS_URL", "redis://redis:6379/0"),
                backend=os.getenv("REDIS_URL", "redis://redis:6379/0"))

LIVEPORTRAIT_DIR = Path("/opt/liveportrait")  # Repo-Checkout + Weights
PY = "python"  # ggf. venv Pfad

@celery.task(bind=True)
def run_liveportrait(self, img_path, wav_path, job_dir, fps, size):
    job_dir = Path(job_dir)
    out = job_dir / "out.mp4"

    cmd = [
        PY, str(LIVEPORTRAIT_DIR / "infer_audio.py"),
        "--source", img_path,
        "--audio", wav_path,
        "--out", str(out),
        "--fps", str(fps),
        "--size", str(size)
    ]
    env = os.environ.copy()
    env["CUDA_VISIBLE_DEVICES"] = env.get("CUDA_VISIBLE_DEVICES", "0")

    proc = subprocess.run(cmd, env=env, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr[:4000])

    # (Optional) Wav2Lip-ONNX-HQ Refinement hier nachschalten…
    return f"/static/{Path(job_dir).name}/out.mp4"
```

---

## Docker-Compose (CUDA) – produktionsnah

**`docker-compose.yml`**
```yaml
version: "3.9"
services:
  api:
    build: ./docker
    ports: ["8080:8080"]
    volumes: ["./data:/data", "./weights:/weights"]
    environment:
      - REDIS_URL=redis://redis:6379/0
    deploy:
      resources:
        reservations:
          devices:
            - capabilities: ["gpu"]
  worker:
    build: ./docker
    command: ["celery", "-A", "app.worker", "worker", "-l", "INFO", "-Q", "default"]
    volumes: ["./data:/data", "./weights:/weights", "./liveportrait:/opt/liveportrait"]
    environment:
      - REDIS_URL=redis://redis:6379/0
    deploy:
      resources:
        reservations:
          devices:
            - capabilities: ["gpu"]
  redis:
    image: redis:7
  nginx:
    image: nginx:alpine
    volumes:
      - ./data:/usr/share/nginx/html:ro
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    ports: ["8081:80"]
```

**`docker/Dockerfile`**
```dockerfile
FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04
RUN apt-get update && apt-get install -y python3 python3-venv python3-pip git ffmpeg && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY app/ /app/app
RUN pip3 install --upgrade pip \
 && pip3 install fastapi uvicorn[standard] celery redis TTS==0.21.3 torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124
# LivePortrait Repo separat in /opt/liveportrait mounten (mit Weights)
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
```

> **Setup-Hinweise**  
> 1) **LivePortrait‑Repo** und **Weights** vorab nach `/opt/liveportrait` (Volume).  
> 2) **XTTS‑v2** lädt die Gewichte beim ersten Lauf in den Cache (`~/.cache/tts`). Für Offline: vorwärmen und Cache mounten.  
> 3) **FFmpeg** ist installiert → MP4 Output.

---

## Flutter‑Client (Dart)

**`pubspec.yaml`**: `http`, `file_picker`, `video_player`

**Upload/Calls**
```dart
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:convert';

Future<String> createTts(String text) async {
  final resp = await http.post(
    Uri.parse("https://your-api.example.com/tts"),
    headers: {"Content-Type": "application/json"},
    body: jsonEncode({"text": text, "lang": "de"}),
  );
  final j = jsonDecode(resp.body);
  return j["audio_id"]; // or use j["audio_url"]
}

Future<String> startAnimate(File imageFile, {String? audioId, File? audioFile}) async {
  final req = http.MultipartRequest("POST", Uri.parse("https://your-api.example.com/animate"));
  req.files.add(await http.MultipartFile.fromPath("source_image", imageFile.path));
  if (audioId != null) {
    req.fields["audio_id"] = audioId;
  } else if (audioFile != null) {
    req.files.add(await http.MultipartFile.fromPath("audio", audioFile.path));
  }
  final resp = await req.send();
  final body = await resp.stream.bytesToString();
  return jsonDecode(body)["job_id"];
}

Future<Map<String, dynamic>> pollJob(String jobId) async {
  final resp = await http.get(Uri.parse("https://your-api.example.com/jobs/$jobId"));
  return jsonDecode(resp.body);
}
```

**Verwendung**
```dart
final img = await FilePicker.platform.pickFiles(type: FileType.image);
final audioId = await createTts("Hallo, das ist mein Testtext.");
final jobId = await startAnimate(File(img!.files.single.path!), audioId: audioId);

// Polling
Map<String, dynamic> status;
do {
  await Future.delayed(Duration(seconds: 2));
  status = await pollJob(jobId);
} while (status["status"] == "running" || status["status"] == "queued");

if (status["status"] == "done") {
  final videoUrl = status["video_url"]; // -> per video_player abspielen
}
```

---

## Qualitäts‑Booster (optional)

- **Wav2Lip‑ONNX‑HQ** als Post‑Step nur bei harten Phonemen/Namen → exaktere Lippen ohne viel Extra‑Zeit.  
- **Real‑ESRGAN** Post‑Upscale für 720p→1080p.  
- **Speaker‑Clone**: 3–10 s Referenz‑WAV in `/tts` mitschicken → XTTS‑v2 `speaker_wav` verwenden.  
- **Sicherheits‑Rails**: Bild‑Einwilligung, Lizenzen (Stimmen/Modelle), simpler NSFW‑Filter.

---

## Skalierung & Betrieb

- **1 GPU = 1 Worker** (Queue‑Tiefe 1–2). Horizontal skalieren via `docker compose up --scale worker=N`.  
- **Warmup**: Beim Start 1 Dummy‑Job, damit Weights im VRAM/Cache liegen.  
- **Timeouts**: API kurz halten, Render immer in Celery.  
- **Observability**: Prometheus/Stats + Log‑Aggregation; Job‑IDs im Log prefixen.  
- **Caching**: gleicher Text → gleicher Audio‑Hash → Audio wiederverwenden.

---

## Nützliche Links

- **LivePortrait (Repo + Audio‑Driven‑Fork)**  
  - Offizielles Repo: https://github.com/KwaiVGI/LivePortrait  
  - Audio‑Driven‑Fork (Community): https://github.com/Hekenye/LivePortrait-AudioDriven

- **EMO – Emote Portrait Alive**  
  - Repo: https://github.com/wyhsirius/EMO  
  - Projekt/Paper: https://wyhsirius.github.io/EMO/  |  https://arxiv.org/abs/2403.11800

- **Coqui XTTS‑v2**  
  - Model Card/Download: https://huggingface.co/coqui/XTTS-v2

- **Wav2Lip‑ONNX‑HQ**  
  - Repo/Fork: https://github.com/instant-high/wav2lip-onnx-HQ
```

# Ende
