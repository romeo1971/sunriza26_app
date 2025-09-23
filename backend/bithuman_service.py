"""
Offizieller BitHuman SDK Service
Basierend auf der offiziellen Dokumentation: https://docs.bithuman.ai
"""

import os
from pathlib import Path
import io
from dotenv import load_dotenv, find_dotenv
import asyncio
from pathlib import Path
from typing import Optional
import bithuman
from bithuman import AsyncBithuman
from fastapi import FastAPI, UploadFile, File, Form, HTTPException, Request
from fastapi.responses import FileResponse
import tempfile
import shutil
import requests
import time
import threading
import uuid
import subprocess
import traceback
from typing import Tuple

# BitHuman SDK initialisieren
runtime = None
API_SECRET_CACHE = None
JOBS: dict[str, dict] = {}

async def initialize_bithuman():
    """Initialisiert BitHuman SDK mit offiziellem API Secret"""
    global runtime

    try:
        # API Secret aus ENV (beide Varianten akzeptieren)
        api_secret = (
            os.getenv("BITHUMAN_API_SECRET")
            or os.getenv("BITHUMAN_API_KEY")
            or ""
        ).strip()
        global runtime, API_SECRET_CACHE
        API_SECRET_CACHE = api_secret if api_secret else None
        # Keine Runtime beim Start erzwingen – per-request initialisieren
        runtime = None
        print("ℹ️ BitHuman: API-Key geladen, Runtime wird per-request erstellt")
        return True

    except Exception as e:
        print(f"❌ BitHuman Initialisierung fehlgeschlagen: {e}")
        return False

async def create_avatar_video(image_path: str, audio_path: str, output_path: str) -> bool:
    """
    Erstellt Avatar-Video mit offiziellem BitHuman SDK

    Args:
        image_path: Pfad zum Avatar-Bild
        audio_path: Pfad zur Audio-Datei
        output_path: Ausgabe-Pfad für Video

    Returns:
        bool: True wenn erfolgreich
    """
    try:
        if not runtime:
            print("⚠️ Globale Runtime nicht initialisiert – verwende per-request Runtime.")

        # Avatar-Video mit offiziellem SDK erstellen
        result = await runtime.create_avatar_video(
            image_path=image_path,
            audio_path=audio_path,
            output_path=output_path
        )

        if result and os.path.exists(output_path):
            print(f"✅ Avatar-Video erstellt: {output_path}")
            return True
        else:
            print("❌ Avatar-Video-Erstellung fehlgeschlagen")
            return False

    except Exception as e:
        print(f"❌ BitHuman Avatar-Erstellung Fehler: {e}")
        return False

# FastAPI Endpoints
app = FastAPI(title="BitHuman Avatar Service")

# .env laden (Projekt-Root bevorzugt)
try:
    env_path = Path(__file__).resolve().parents[1] / ".env"
    if env_path.exists():
        load_dotenv(str(env_path), override=True)
    else:
        load_dotenv(find_dotenv(), override=True)
except Exception:
    pass

# OpenAI Client (für Whisper STT)
try:
    from openai import OpenAI  # openai>=1.35.0
    OPENAI_CLIENT = OpenAI(api_key=os.getenv("OPENAI_API_KEY")) if os.getenv("OPENAI_API_KEY") else None
except Exception:
    OPENAI_CLIENT = None

# ------------------------------
# Beyond Presence URL-Helfer
# ------------------------------
def _bp_versioned_base() -> str:
    """Ermittelt die BP Basis-URL und stellt sicher, dass sie auf /v1 zeigt.

    Beispiele:
      - https://api.bey.dev        -> https://api.bey.dev/v1
      - https://api.bey.dev/       -> https://api.bey.dev/v1
      - https://api.bey.dev/v1     -> https://api.bey.dev/v1
      - https://api.bey.dev/v1/    -> https://api.bey.dev/v1
    """
    base = (os.getenv("BP_API_BASE_URL") or "https://api.bey.dev").strip()
    base = base.rstrip("/")
    if not base.endswith("/v1"):
        base = base + "/v1"
    return base

def _bp_headers() -> dict:
    key = (os.getenv("BP_API_KEY") or "").strip()
    if not key:
        raise HTTPException(status_code=500, detail="BP API Konfiguration fehlt")
    # Einige BP-Deployments erwarten zusätzlich einen expliziten API-Key Header
    return {
        "Authorization": f"Bearer {key}",
        "X-API-Key": key,
    }

async def _try_load_imx_into_global_runtime() -> bool:
    """Versucht beim Start ein lokales .imx in die globale Runtime zu laden."""
    try:
        global runtime, API_SECRET_CACHE
        if not API_SECRET_CACHE:
            return False
        # Pfad aus ENV oder aus ./avatars größtes .imx wählen
        imx_env = os.getenv("BITHUMAN_IMX_PATH", "").strip()
        imx_path: Optional[Path] = None
        if imx_env:
            p = Path(imx_env)
            if p.exists() and p.is_file() and p.suffix.lower() == ".imx":
                imx_path = p
        if imx_path is None:
            avatars_dir = Path(__file__).resolve().parents[1] / "avatars"
            if avatars_dir.exists() and avatars_dir.is_dir():
                imx_files = [f for f in avatars_dir.iterdir() if f.is_file() and f.suffix.lower() == ".imx"]
                if imx_files:
                    imx_files.sort(key=lambda f: f.stat().st_size, reverse=True)
                    imx_path = imx_files[0]
        if imx_path is None:
            print("ℹ️ Startup: kein lokales .imx gefunden")
            return False
        # Runtime erstellen und Modell setzen
        print(f"🧠 Startup: lade .imx in globale Runtime: {imx_path}")
        rt = await AsyncBithuman.create(
            api_secret=API_SECRET_CACHE,
            model_path=str(imx_path),
        )
        runtime = rt
        print("✅ Startup: .imx Modell global gesetzt")
        return True
    except Exception as e:
        print(f"⚠️ Startup .imx Laden fehlgeschlagen: {e}")
        return False


@app.on_event("startup")
async def startup_event():
    """Initialisiert BitHuman beim Start"""
    await initialize_bithuman()
    # Optional: globales .imx laden
    await _try_load_imx_into_global_runtime()


@app.post("/stt/whisper")
async def stt_whisper(audio: UploadFile = File(...), language: str | None = Form(None)):
    """Speech-to-Text via OpenAI Whisper. Erwartet Multipart 'audio'.
    .env: OPENAI_API_KEY erforderlich.
    """
    try:
        if OPENAI_CLIENT is None:
            raise HTTPException(status_code=500, detail="OPENAI_API_KEY fehlt oder Client nicht initialisiert")
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td) / (audio.filename or "audio.m4a")
            with open(tmp, "wb") as buf:
                shutil.copyfileobj(audio.file, buf)
            # Whisper Transkription
            with open(tmp, "rb") as f:
                resp = OPENAI_CLIENT.audio.transcriptions.create(
                    model="whisper-1",
                    file=f,
                    language=language or None,
                    response_format="json",
                )
            text = None
            try:
                text = getattr(resp, "text", None)
            except Exception:
                pass
            if not text:
                # fallback: resp ist dict-ähnlich
                try:
                    text = resp["text"]
                except Exception:
                    pass
            if not text:
                raise HTTPException(status_code=502, detail="Whisper lieferte keinen Text")
            return {"text": text}
    except HTTPException:
        raise
    except Exception as e:
        print(f"[stt/whisper] Exception: {e}\n{traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=f"STT Fehler: {e}")

@app.get("/")
async def root():
    """Health Check"""
    return {
        "message": "BitHuman Avatar Service läuft",
        "runtime_initialized": runtime is not None
    }

@app.post("/bp/speech-to-video")
async def bp_speech_to_video(
    request: Request,
    audio: UploadFile | None = File(None),
    text: str | None = Form(None),
    avatarId: str | None = Form(None),
    avatarImageUrl: str | None = Form(None),
):
    """Proxy zu Beyond Presence Speech-to-Video.
    Unterstützt Multipart (audio, avatarId) oder JSON (text, avatarId).
    Erwartet .env: BP_API_BASE_URL, BP_API_KEY
    """
    try:
        bp_base = _bp_versioned_base()
        headers = _bp_headers()

        candidate_urls = [
            f"{bp_base}/speech-to-video",
            f"{bp_base}/video/speech-to-video",
            f"{bp_base}/videos/speech-to-video",
        ]

        # Multipart mit Audio
        if audio is not None:
            with tempfile.TemporaryDirectory() as td:
                tmp_audio = Path(td) / (audio.filename or "audio.mp3")
                with open(tmp_audio, "wb") as buf:
                    shutil.copyfileobj(audio.file, buf)
                files = {
                    "audio": (tmp_audio.name, open(tmp_audio, "rb"), "audio/mpeg"),
                }
                data = {}
                if avatarId:
                    data["avatarId"] = avatarId
                if avatarImageUrl:
                    data["avatarImageUrl"] = avatarImageUrl
                last_err = None
                r = None
                for url in candidate_urls:
                    r = requests.post(url, headers=headers, files=files, data=data, timeout=120)
                    if 200 <= r.status_code < 300:
                        break
                    last_err = f"{r.status_code} {r.text[:300]}"
                if not (200 <= r.status_code < 300):
                    raise HTTPException(status_code=r.status_code, detail=f"BP Fehler: {last_err or r.text[:500]}")
                # Bytes → Temp MP4
                out_dir = Path(td)
                out_path = out_dir / "bp_video.mp4"
                with open(out_path, "wb") as f:
                    f.write(r.content)
                return FileResponse(path=str(out_path), media_type="video/mp4", filename="bp_video.mp4")

        # JSON Body (Text)
        try:
            body = await request.json()
        except Exception:
            body = None
        if not body and not text:
            raise HTTPException(status_code=400, detail="text oder audio erforderlich")
        payload = body or {"text": text}
        if avatarId and not payload.get("avatarId"):
            payload["avatarId"] = avatarId
        if avatarImageUrl and not payload.get("avatarImageUrl"):
            payload["avatarImageUrl"] = avatarImageUrl

        last_err = None
        r = None
        for url in candidate_urls:
            r = requests.post(url, headers={**headers, "Content-Type": "application/json"}, json=payload, timeout=120)
            if 200 <= r.status_code < 300:
                break
            last_err = f"{r.status_code} {r.text[:300]}"
        if not (200 <= r.status_code < 300):
            raise HTTPException(status_code=r.status_code, detail=f"BP Fehler: {last_err or r.text[:500]}")
        with tempfile.TemporaryDirectory() as td2:
            out_path = Path(td2) / "bp_video.mp4"
            with open(out_path, "wb") as f:
                f.write(r.content)
            return FileResponse(path=str(out_path), media_type="video/mp4", filename="bp_video.mp4")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Proxy Fehler: {e}")

@app.post("/bp/avatar/upload-video")
async def bp_avatar_upload_video(video: UploadFile = File(...), avatarId: str | None = Form(None)):
    """Proxy: Lade ein Referenz-Video zu Beyond Presence hoch (Avatar/Asset).
    Erwartet Env: BP_AVATAR_UPLOAD_URL (falls nicht gesetzt, wird /avatars verwendet).
    """
    try:
        bp_base = _bp_versioned_base()
        headers = _bp_headers()

        override_url = (os.getenv("BP_AVATAR_UPLOAD_URL") or "").strip()
        # Einige Dokumentationen verwenden /v1/avatar oder /v1/avatars/upload
        # Wir versuchen der Reihe nach mehrere bekannte Pfade, bis einer 2xx liefert
        candidate_urls = [
            override_url if override_url else f"{bp_base}/avatars",
            f"{bp_base}/avatar",
            f"{bp_base}/avatars/upload",
        ]

        with tempfile.TemporaryDirectory() as td:
            tmp_video = Path(td) / (video.filename or "video.mp4")
            with open(tmp_video, "wb") as buf:
                shutil.copyfileobj(video.file, buf)
            mime = "video/mp4"
            with open(tmp_video, "rb") as fsrc:
                data_bytes = fsrc.read()
            data = {}
            if avatarId:
                data["avatarId"] = avatarId
            last_err_txt = None
            r = None
            for url in candidate_urls:
                # Für jeden Versuch frische Streams verwenden
                files = {
                    "file": (tmp_video.name, io.BytesIO(data_bytes), mime),
                    "video": (tmp_video.name, io.BytesIO(data_bytes), mime),
                }
                r = requests.post(url, headers=headers, files=files, data=data, timeout=120)
                if 200 <= r.status_code < 300:
                    break
                last_err_txt = f"{r.status_code} {r.text[:300]}"
            if not (200 <= r.status_code < 300):
                raise HTTPException(status_code=r.status_code, detail=f"BP Avatar Upload Fehler: {last_err_txt or r.text[:500]}")
            try:
                return r.json()
            except Exception:
                return {"status": "ok"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Proxy Fehler: {e}")


def _extract_frame_with_ffmpeg(in_path: str, out_jpg_path: str) -> bool:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        return False
    try:
        cmd = [
            ffmpeg,
            "-y",
            "-i",
            in_path,
            "-frames:v",
            "1",
            "-q:v",
            "2",
            out_jpg_path,
        ]
        subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return True
    except Exception:
        return False


def _extract_frame_with_opencv(in_path: str, out_jpg_path: str) -> bool:
    try:
        import cv2
    except Exception:
        return False
    try:
        cap = cv2.VideoCapture(in_path)
        ok, frame = cap.read()
        cap.release()
        if not ok or frame is None:
            return False
        ok2 = cv2.imwrite(out_jpg_path, frame, [int(cv2.IMWRITE_JPEG_QUALITY), 90])
        return bool(ok2)
    except Exception:
        return False


@app.post("/bp/avatar/from-video")
async def bp_avatar_from_video(
    request: Request,
    video: UploadFile | None = File(None),
    videoUrl: str | None = Form(None),
    avatarId: str | None = Form(None),
):
    """Erstellt/aktualisiert einen BP-Avatar aus einem Video, indem ein Poster-Frame erzeugt
    und als Bild zu BP /v1/avatars (Feldname 'image') hochgeladen wird. Eignet sich für iOS/Android,
    da die App nur URL/Datei übergibt und die Extraktion serverseitig erfolgt.
    """
    try:
        # JSON Body unterstützen
        try:
            body = await request.json()
        except Exception:
            body = None
        if body and not video and not videoUrl:
            videoUrl = body.get("videoUrl") or videoUrl
            avatarId = body.get("avatarId") or avatarId

        print(f"[bp/avatar/from-video] incoming: video={'yes' if video else 'no'}, videoUrl={(videoUrl or '').strip()[:120]}")
        if not video and not (videoUrl and videoUrl.strip()):
            raise HTTPException(status_code=400, detail="video oder videoUrl erforderlich")

        bp_base = _bp_versioned_base()
        headers = _bp_headers()

        with tempfile.TemporaryDirectory() as td:
            td_path = Path(td)
            # Video in Temp laden
            video_path = td_path / ("input.mp4" if not video else (video.filename or "upload.mp4"))
            if video is not None:
                with open(video_path, "wb") as buf:
                    shutil.copyfileobj(video.file, buf)
            else:
                try:
                    r = requests.get(videoUrl, timeout=60)
                    if r.status_code != 200 or not r.content:
                        raise HTTPException(status_code=502, detail=f"Download fehlgeschlagen: {r.status_code}")
                    with open(video_path, "wb") as f:
                        f.write(r.content)
                    print(f"[bp/avatar/from-video] downloaded video: {video_path} size={len(r.content)} bytes")
                except HTTPException:
                    raise
                except Exception as e:
                    raise HTTPException(status_code=500, detail=f"Video-Download Fehler: {e}")

            # Poster-Frame extrahieren
            jpg_path = td_path / "poster.jpg"
            ffmpeg_path = shutil.which("ffmpeg")
            print(f"[bp/avatar/from-video] ffmpeg found: {ffmpeg_path}")
            ok = _extract_frame_with_ffmpeg(str(video_path), str(jpg_path))
            if not ok:
                print("[bp/avatar/from-video] ffmpeg failed, trying OpenCV…")
                ok = _extract_frame_with_opencv(str(video_path), str(jpg_path))
            if not ok or (not jpg_path.exists() or jpg_path.stat().st_size == 0):
                raise HTTPException(status_code=500, detail="Frame-Extraktion fehlgeschlagen")
            else:
                try:
                    print(f"[bp/avatar/from-video] poster: {jpg_path} size={jpg_path.stat().st_size} bytes")
                except Exception:
                    pass

            # Upload zu BP: /v1/avatars Feldname 'image'
            url = f"{bp_base}/avatars"
            files = {
                "image": (jpg_path.name, open(jpg_path, "rb"), "image/jpeg"),
            }
            data = {}
            if avatarId:
                data["avatarId"] = avatarId
            print(f"[bp/avatar/from-video] POST {url} (fields: {list(data.keys())})")
            r = requests.post(url, headers=headers, files=files, data=data, timeout=120)
            print(f"[bp/avatar/from-video] BP response: {r.status_code}")
            try:
                snippet = (r.text or "")[:400]
                print(f"[bp/avatar/from-video] BP body: {snippet}")
            except Exception:
                pass
            if not (200 <= r.status_code < 300):
                raise HTTPException(status_code=r.status_code, detail=r.text[:500] if r.text else f"HTTP {r.status_code}")
            try:
                return r.json()
            except Exception:
                return {"status": "ok"}
    except HTTPException:
        raise
    except Exception as e:
        print(f"[bp/avatar/from-video] Exception: {e}\n{traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=f"Proxy Fehler: {e}")

@app.get("/debug/methods")
async def debug_methods():
    """Debug: Zeigt verfügbare BitHuman API-Methoden"""
    try:
        if not API_SECRET_CACHE:
            return {"error": "BitHuman API-Key nicht verfügbar"}

        # Erstelle temporäre Runtime
        test_runtime = await AsyncBithuman.create(api_secret=API_SECRET_CACHE)
        methods = [method for method in dir(test_runtime) if not method.startswith('_')]
        return {"available_methods": methods}
    except Exception as e:
        return {"error": f"Debug-Fehler: {e}"}

@app.post("/test/simple")
async def test_simple_avatar():
    """Einfacher Test ohne Dateien"""
    return {"status": "OK", "message": "Test erfolgreich"}

@app.post("/test/video")
async def test_video_creation():
    """Test Video-Erstellung ohne BitHuman"""
    try:
        import tempfile
        import cv2
        import numpy as np
        from pathlib import Path

        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            video_path = temp_path / "test_video.mp4"

            # Erstelle Test-Video
            fourcc = cv2.VideoWriter_fourcc(*'mp4v')
            video_writer = cv2.VideoWriter(str(video_path), fourcc, 30, (640, 480))

            # 30 Frames mit verschiedenen Farben
            for i in range(30):
                frame = np.full((480, 640, 3), (i*8, 100, 200), dtype=np.uint8)
                video_writer.write(frame)

            video_writer.release()

            if video_path.exists():
                return FileResponse(
                    path=str(video_path),
                    media_type="video/mp4",
                    filename="test_video.mp4"
                )
            else:
                return {"error": "Video nicht erstellt"}

    except Exception as e:
        return {"error": f"Video-Test fehlgeschlagen: {e}"}

@app.post("/generate-avatar")
async def generate_avatar(
    image: UploadFile = File(...),
    audio: UploadFile = File(...),
    figure_id: str | None = Form(None),
    runtime_model_hash: str | None = Form(None),
):
    """
    Generiert Avatar-Video mit BitHuman SDK

    Args:
        image: Avatar-Bild (PNG/JPG)
        audio: Audio-Datei (MP3/WAV)

    Returns:
        Video-Datei oder Fehler
    """
    try:
        # Temporäre Dateien erstellen - PERSISTENT!
        temp_dir = tempfile.mkdtemp()  # Nicht auto-delete!
        temp_path = Path(temp_dir)

        # Dateien speichern
        image_path = temp_path / f"avatar_{image.filename}"
        audio_path = temp_path / f"audio_{audio.filename}"
        output_path = temp_path / "avatar_video.mp4"

        # Upload-Dateien speichern
        with open(image_path, "wb") as buffer:
            shutil.copyfileobj(image.file, buffer)
        with open(audio_path, "wb") as buffer:
            shutil.copyfileobj(audio.file, buffer)

        print(f"📁 Dateien gespeichert:")
        print(f"   🖼️ Bild: {image_path}")
        print(f"   🎵 Audio: {audio_path}")
        # Eingehende Parameter loggen
        try:
            print(f"[generate-avatar] params: figure_id={figure_id}, runtime_model_hash={runtime_model_hash}")
        except Exception:
            pass

        # FIGURE AUS BILD ERSTELLEN (für .imx Model)
        global runtime, API_SECRET_CACHE
        local_runtime = None

        if not API_SECRET_CACHE:
            raise HTTPException(status_code=500, detail="BitHuman API-Key nicht verfügbar")

        # 1. Figure aus Bild erstellen - VEREINFACHT
        if not figure_id:
            print("🎭 Verwende Standard-Runtime ohne spezifische Figure...")
            # Für jetzt: Ohne Figure-Erstellung, direkt mit API-Key

        # 2. Runtime mit Figure erstellen (globale Runtime bevorzugen, wenn vorhanden)
        try:
            # Wenn globale Runtime vorhanden, wiederverwenden (nicht stoppen)
            if runtime is not None:
                local_runtime = runtime
                print("♻️ Verwende globale Runtime")
            # Andernfalls per-request erstellen
            kw = {"api_secret": API_SECRET_CACHE}
            # Optional: Defaults aus .env verwenden, falls nichts aus der App kommt
            env_figure = os.getenv("BITHUMAN_DEFAULT_FIGURE_ID", "").strip() or None
            env_model = os.getenv("BITHUMAN_DEFAULT_MODEL_HASH", "").strip() or None
            eff_figure = figure_id or env_figure
            eff_model = runtime_model_hash or env_model
            if eff_figure:
                kw["figure_id"] = eff_figure
            if eff_model:
                kw["runtime_model_hash"] = eff_model

            if local_runtime is None:
                local_runtime = await AsyncBithuman.create(**kw)
                print(f"✅ Per-request Runtime erstellt: figure_id={eff_figure}, hash={eff_model}")

            # Versuche ein lokales .imx Modell zu nutzen
            try:
                imx_env = os.getenv("BITHUMAN_IMX_PATH", "").strip()
                imx_path: Optional[Path] = None
                if imx_env:
                    p = Path(imx_env)
                    if p.exists() and p.is_file() and p.suffix.lower() == ".imx":
                        imx_path = p
                if imx_path is None:
                    avatars_dir = Path(__file__).resolve().parents[1] / "avatars"
                    if avatars_dir.exists() and avatars_dir.is_dir():
                        imx_files = [f for f in avatars_dir.iterdir() if f.is_file() and f.suffix.lower() == ".imx"]
                        if imx_files:
                            imx_files.sort(key=lambda f: f.stat().st_size, reverse=True)
                            imx_path = imx_files[0]

                if imx_path is not None and local_runtime is None:
                    # Direkt mit model_path initialisieren statt set_model()
                    kw_with_model = dict(kw)
                    kw_with_model["model_path"] = str(imx_path)
                    local_runtime = await AsyncBithuman.create(**kw_with_model)
                    print(f"✅ Runtime mit .imx initialisiert: {imx_path}")
                elif imx_path is None:
                    print("ℹ️ Kein lokales .imx gefunden – verwende ggf. figure_id/runtime_model_hash")
            except Exception as e_imx:
                print(f"⚠️ .imx Handling Fehler: {e_imx}")
        except Exception as e:
            print(f"❌ Per-request Runtime Fehler: {e}")
            raise HTTPException(status_code=500, detail=f"BitHuman Runtime-Erstellung fehlgeschlagen: {e}")

        # Avatar-Video mit BitHuman erstellen
        if not local_runtime:
            raise HTTPException(status_code=500, detail="BitHuman Runtime nicht bereit")

        # BitHuman Figure/Runtime-API verwenden (streaming-basiert)
        print(f"🔍 Verwende BitHuman streaming API...")

        try:
            # ECHTE BITHUMAN INTEGRATION - JETZT RICHTIG!
            print("🚀 ECHTE BitHuman Avatar-Generierung startet...")

            # 1. Audio KORREKT konvertieren: 16kHz, Mono, int16
            import numpy as np
            import librosa

            # Audio laden und zu 16kHz konvertieren (nicht 44.1kHz!)
            audio_data, _ = librosa.load(str(audio_path), sr=16000, mono=True)
            audio_pcm = (audio_data * 32767).astype(np.int16)
            print(f"✅ Audio KORREKT konvertiert: {len(audio_pcm)} samples, 16000 Hz, int16")

            # 2. Runtime starten
            await local_runtime.start()
            print("✅ BitHuman Runtime gestartet")

            # 3. Audio zur Verarbeitung senden (16kHz!) – Bytes verwenden
            audio_bytes = audio_pcm.tobytes()
            await local_runtime.push_audio(audio_bytes, 16000)
            print("✅ Audio-Daten gesendet (16kHz)")

            # 4. Verarbeitung starten und Frames sammeln (bis zur Audiolänge)
            frames = []
            fps = 30
            try:
                audio_duration_s = float(len(audio_pcm)) / 16000.0
            except Exception:
                audio_duration_s = 5.0
            max_frames = max(1, int((audio_duration_s + 0.2) * fps))
            try:
                run_gen = local_runtime.run()
                # Async-Generator
                if hasattr(run_gen, "__aiter__"):
                    print("✅ Runtime läuft (async generator)")
                    async for frame in run_gen:
                        frames.append(frame)
                        if len(frames) >= max_frames:
                            break
                else:
                    # Sync-Iterator fallback
                    print("✅ Runtime läuft (sync iterator)")
                    for frame in run_gen:
                        frames.append(frame)
                        if len(frames) >= max_frames:
                            break
            except Exception as e_run:
                print(f"⚠️ Frame-Iteration fehlgeschlagen: {e_run}")

            print(f"📹 Frames gesammelt: {len(frames)}")

            if frames and len(frames) > 0:
                # ECHTES MP4-VIDEO ERSTELLEN und AUDIO MUXEN
                import cv2

                # Video ohne Audio zuerst schreiben
                fourcc = cv2.VideoWriter_fourcc(*'mp4v')
                height, width = frames[0].shape[:2]
                temp_video = output_path.with_name("avatar_video_no_audio.mp4")
                video_writer = cv2.VideoWriter(str(temp_video), fourcc, fps, (width, height))

                for frame in frames:
                    video_writer.write(frame)

                video_writer.release()
                print(f"🎬 Video ohne Audio erstellt: {len(frames)} frames @ {fps} fps")

                # Audio in das Video muxen (ffmpeg bevorzugt)
                ffmpeg = shutil.which("ffmpeg")
                if ffmpeg:
                    try:
                        cmd = [
                            ffmpeg, "-y",
                            "-i", str(temp_video),
                            "-i", str(audio_path),
                            "-c:v", "copy",
                            "-c:a", "aac",
                            "-shortest",
                            str(output_path),
                        ]
                        print("🔊 ffmpeg mux:", " ".join(cmd))
                        subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                        result = True
                    except subprocess.CalledProcessError as e:
                        print(f"⚠️ ffmpeg mux fehlgeschlagen: {e}")
                        result = False
                else:
                    # Fallback: MoviePy
                    try:
                        from moviepy.editor import VideoFileClip, AudioFileClip
                        v = VideoFileClip(str(temp_video))
                        a = AudioFileClip(str(audio_path))
                        v = v.set_audio(a)
                        v.write_videofile(
                            str(output_path),
                            codec="libx264",
                            audio_codec="aac",
                            fps=fps,
                            verbose=False,
                            logger=None,
                        )
                        result = True
                    except Exception as e:
                        print(f"⚠️ MoviePy mux fehlgeschlagen: {e}")
                        result = False

                # Temp-Datei aufräumen
                try:
                    if temp_video.exists():
                        temp_video.unlink()
                except Exception:
                    pass

            else:
                print("❌ Keine Frames generiert - Fallback statisches Video + Audio")
                import cv2

                img = cv2.imread(str(image_path))
                if img is None:
                    raise Exception("Konnte Input-Bild nicht laden")

                height, width = img.shape[:2]
                temp_video = output_path.with_name("fallback_no_audio.mp4")
                fourcc = cv2.VideoWriter_fourcc(*'mp4v')
                video_writer = cv2.VideoWriter(str(temp_video), fourcc, fps, (width, height))

                # Frames entsprechend Audiolänge schreiben
                total_frames = max(1, int((audio_duration_s + 0.2) * fps))
                for _ in range(total_frames):
                    video_writer.write(img)

                video_writer.release()

                # Audio muxen
                ffmpeg = shutil.which("ffmpeg")
                if ffmpeg:
                    try:
                        cmd = [
                            ffmpeg, "-y",
                            "-i", str(temp_video),
                            "-i", str(audio_path),
                            "-c:v", "copy",
                            "-c:a", "aac",
                            "-shortest",
                            str(output_path),
                        ]
                        print("🔊 ffmpeg mux (fallback):", " ".join(cmd))
                        subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                        result = True
                    except subprocess.CalledProcessError as e:
                        print(f"⚠️ ffmpeg mux (fallback) fehlgeschlagen: {e}")
                        result = False
                else:
                    try:
                        from moviepy.editor import VideoFileClip, AudioFileClip
                        v = VideoFileClip(str(temp_video))
                        a = AudioFileClip(str(audio_path))
                        v = v.set_audio(a)
                        v.write_videofile(
                            str(output_path),
                            codec="libx264",
                            audio_codec="aac",
                            fps=fps,
                            verbose=False,
                            logger=None,
                        )
                        result = True
                    except Exception as e:
                        print(f"⚠️ MoviePy mux (fallback) fehlgeschlagen: {e}")
                        result = False

                try:
                    if temp_video.exists():
                        temp_video.unlink()
                except Exception:
                    pass

        except Exception as e:
            print(f"❌ BitHuman streaming API Fehler: {e}")
            raise HTTPException(status_code=500, detail=f"BitHuman Verarbeitung fehlgeschlagen: {e}")
        finally:
            # Globale Runtime nicht stoppen, per-request Runtimes schon
            try:
                if local_runtime is not None and local_runtime is not runtime:
                    await local_runtime.stop()
                    print("✅ BitHuman Runtime gestoppt")
            except:
                pass

        # SICHERER FILE-RESPONSE
        if result and output_path.exists() and output_path.stat().st_size > 0:
            print(f"📁 Video-Datei bereit: {output_path} ({output_path.stat().st_size} bytes)")
            return FileResponse(
                path=str(output_path),
                media_type="video/mp4",
                filename="avatar_video.mp4"
            )
        else:
            error_msg = f"Video-Datei nicht gefunden oder leer: exists={output_path.exists()}"
            if output_path.exists():
                error_msg += f", size={output_path.stat().st_size}"
            print(f"❌ {error_msg}")

            # Wichtig: mit Fehlerstatus antworten, damit der Client kein JSON als MP4 behandelt
            raise HTTPException(status_code=502, detail=error_msg)

    except Exception as e:
        print(f"💥 Avatar-Generierung Fehler: {e}")
        raise HTTPException(
        status_code=500,
        detail=f"Avatar-Generierung Fehler: {str(e)}"
        )


@app.post("/figure/create")
async def create_figure(image: UploadFile = File(...)):
    """Agent/ Figure aus Bild erzeugen (Agent Generation API)."""
    try:
        # Token/Key priorisieren: API_TOKEN > API_SECRET > API_KEY
        api_token = (
            os.getenv("BITHUMAN_API_TOKEN")
            or os.getenv("BITHUMAN_API_SECRET")
            or os.getenv("BITHUMAN_API_KEY")
            or ""
        ).strip()
        if not api_token:
            raise HTTPException(status_code=400, detail="BitHuman API Token/Key fehlt")

        # Bild lokal persistieren
        with tempfile.TemporaryDirectory() as temp_dir:
            safe_name = Path(image.filename).name or "upload.png"
            img_path = Path(temp_dir) / safe_name
            with open(img_path, "wb") as buf:
                shutil.copyfileobj(image.file, buf)

            try:
                size = img_path.stat().st_size
                print(f"[figure/create] gespeichert: {img_path} ({size} bytes)")
            except Exception as e:
                print(f"[figure/create] Stat-Fehler: {e}")

            if not img_path.exists() or img_path.stat().st_size == 0:
                raise HTTPException(status_code=400, detail="Upload-Bild fehlt/leer")

            # Ziel-URL: env override, sonst Default aus Doku
            agent_create_url = (
                os.getenv("BITHUMAN_AGENT_CREATE_URL")
                or "https://api.bithuman.ai/v1/figures"
            ).strip()

            headers = {
                "Authorization": f"Bearer {api_token}",
                "Accept": "application/json",
            }

            # Content-Type wird von requests bei files automatisch gesetzt
            try:
                mime = "image/png"
                if safe_name.lower().endswith((".jpg", ".jpeg")):
                    mime = "image/jpeg"
                with open(img_path, "rb") as fp:
                    files = {"image": (img_path.name, fp, mime)}
                    r = requests.post(agent_create_url, headers=headers, files=files, timeout=60)
                print(f"[figure/create] POST {agent_create_url} -> {r.status_code}")

                # Fehler klar an Client zurückgeben
                if not (200 <= r.status_code < 300):
                    detail = r.text[:500] if r.text else f"HTTP {r.status_code}"
                    raise HTTPException(status_code=502, detail=f"BitHuman Figure API Fehler: {detail}")

                data = r.json() if r.content else {}

                # Robust Felder extrahieren
                figure_id = (
                    data.get("figure_id")
                    or data.get("id")
                    or (data.get("data") or {}).get("figure_id")
                    or (data.get("result") or {}).get("id")
                )
                model_hash = (
                    data.get("runtime_model_hash")
                    or data.get("model_hash")
                    or data.get("hash")
                    or (data.get("data") or {}).get("runtime_model_hash")
                )

                if not figure_id and not model_hash:
                    # Möglich: API liefert Job/Task; gib Rohdaten mit 202 zurück?
                    # Für jetzt: 502, damit Client nicht mit Dummy fortfährt
                    raise HTTPException(status_code=502, detail="Figure API lieferte keine figure_id/model_hash")

                try:
                    print(f"[figure/create] result: figure_id={figure_id}, runtime_model_hash={model_hash}")
                except Exception:
                    pass

                return {"figure_id": figure_id, "runtime_model_hash": model_hash}

            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=500, detail=f"Figure-Erstellung fehlgeschlagen: {e}")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/figure/job/{job_id}")
async def figure_job_status(job_id: str):
    job = JOBS.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="job not found")
    return job

@app.get("/health")
async def health():
    """Detaillierter Health Check"""
    return {
        "status": "healthy",
        "service": "bithuman-avatar-service",
        "runtime_ready": runtime is not None,
        "version": "1.0.0"
    }

if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("BITHUMAN_PORT", "4202"))
    uvicorn.run(app, host="0.0.0.0", port=port)
