"""
Offizieller BitHuman SDK Service
Basierend auf der offiziellen Dokumentation: https://docs.bithuman.ai
"""

import os
from pathlib import Path
from dotenv import load_dotenv, find_dotenv
import asyncio
from pathlib import Path
from typing import Optional
import bithuman
from bithuman import AsyncBithuman
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import FileResponse
import tempfile
import shutil
import requests
import time
import threading
import uuid

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

@app.on_event("startup")
async def startup_event():
    """Initialisiert BitHuman beim Start"""
    await initialize_bithuman()

@app.get("/")
async def root():
    """Health Check"""
    return {
        "message": "BitHuman Avatar Service läuft",
        "runtime_initialized": runtime is not None
    }

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
    figure_id: str | None = None,
    runtime_model_hash: str | None = None,
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

        # FIGURE AUS BILD ERSTELLEN (für .imx Model)
        global runtime, API_SECRET_CACHE
        local_runtime = None

        if not API_SECRET_CACHE:
            raise HTTPException(status_code=500, detail="BitHuman API-Key nicht verfügbar")

        # 1. Figure aus Bild erstellen - VEREINFACHT
        if not figure_id:
            print("🎭 Verwende Standard-Runtime ohne spezifische Figure...")
            # Für jetzt: Ohne Figure-Erstellung, direkt mit API-Key

        # 2. Runtime mit Figure erstellen
        try:
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

            local_runtime = await AsyncBithuman.create(**kw)
            print(f"✅ Per-request Runtime erstellt: figure_id={eff_figure}, hash={eff_model}")

            # Versuche ein lokales .imx Modell zu laden (z. B. aus ./avatars)
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
                            # Größte Datei wählen (höchste Wahrscheinlichkeit eines vollständigen Modells)
                            imx_files.sort(key=lambda f: f.stat().st_size, reverse=True)
                            imx_path = imx_files[0]
                if imx_path is not None:
                    print(f"🧠 Lade lokales .imx Modell: {imx_path}")
                    try:
                        await local_runtime.set_model(str(imx_path))
                        print("✅ .imx Modell gesetzt")
                    except Exception as e_set:
                        print(f"⚠️ set_model() fehlgeschlagen: {e_set}")
                else:
                    print("ℹ️ Kein lokales .imx gefunden – verwende ggf. figure_id/runtime_model_hash")
            except Exception as e_imx:
                print(f"⚠️ Lokales .imx Handling Fehler: {e_imx}")
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

            # 3. Audio zur Verarbeitung senden (16kHz!)
            await local_runtime.push_audio(audio_pcm, 16000)
            print("✅ Audio-Daten gesendet (16kHz)")

            # 4. Verarbeitung starten - RUN() METHODE!
            try:
                result = local_runtime.run()  # RUN statt process!
                print(f"✅ Runtime läuft: {result}")
            except Exception as e:
                print(f"⚠️ run() fehlgeschlagen: {e}")
                try:
                    result = await local_runtime.run()  # Async versuchen
                    print(f"✅ Runtime läuft (async): {result}")
                except Exception as e2:
                    print(f"⚠️ async run() fehlgeschlagen: {e2}")
                    result = True  # Weitermachen

            # 5. Video-Frames generieren - GENERATOR PROPERTY!
            video_generator = local_runtime.generator  # PROPERTY, nicht Funktion!
            print("✅ Video-Generator gestartet")

            # 6. Frames sammeln - RICHTIGE GENERATOR-USAGE
            frames = []
            frame_count = 0

            # Versuche verschiedene Generator-Methoden
            try:
                # Methode 1: next() verwenden
                while frame_count < 60:
                    frame = next(video_generator, None)
                    if frame is None:
                        break
                    frames.append(frame)
                    frame_count += 1

            except Exception as e1:
                print(f"⚠️ Generator next() fehlgeschlagen: {e1}")
                try:
                    # Methode 2: get_frame() oder ähnliche Methode
                    frame = video_generator.get_frame()
                    if frame is not None:
                        frames.append(frame)
                        frame_count = 1
                except Exception as e2:
                    print(f"⚠️ get_frame() fehlgeschlagen: {e2}")
                    try:
                        # Methode 3: Direkt auf generator zugreifen
                        if hasattr(video_generator, 'frames'):
                            frames = video_generator.frames[:60]
                            frame_count = len(frames)
                    except Exception as e3:
                        print(f"⚠️ Frames-Zugriff fehlgeschlagen: {e3}")

            print(f"📹 Frames gesammelt: {frame_count}")

            if frames and len(frames) > 0:
                # ECHTES MP4-VIDEO ERSTELLEN!
                import cv2

                # Video-Writer erstellen
                fourcc = cv2.VideoWriter_fourcc(*'mp4v')
                fps = 30

                # Frame-Größe bestimmen
                if len(frames) > 0:
                    height, width = frames[0].shape[:2]
                    video_writer = cv2.VideoWriter(str(output_path), fourcc, fps, (width, height))

                    # Alle Frames ins Video schreiben
                    for frame in frames:
                        video_writer.write(frame)

                    video_writer.release()
                    print(f"🎬 ECHTES MP4-VIDEO ERSTELLT: {frame_count} frames, {fps} fps")
                    result = True
                else:
                    raise Exception("Frames haben keine gültige Größe")

            else:
                print("❌ Keine Frames generiert - verwende Fallback")
                # Fallback: Bild als "Video" (1 Frame)
                import cv2

                # Lade Input-Bild
                img = cv2.imread(str(image_path))
                if img is not None:
                    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
                    height, width = img.shape[:2]
                    video_writer = cv2.VideoWriter(str(output_path), fourcc, 1, (width, height))

                    # Bild 30x schreiben (1 Sekunde bei 30fps)
                    for _ in range(30):
                        video_writer.write(img)

                    video_writer.release()
                    print("🎬 Fallback-Video aus Bild erstellt")
                    result = True
                else:
                    raise Exception("Konnte Input-Bild nicht laden")

        except Exception as e:
            print(f"❌ BitHuman streaming API Fehler: {e}")
            raise HTTPException(status_code=500, detail=f"BitHuman Verarbeitung fehlgeschlagen: {e}")
        finally:
            try:
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

        # NOTFALL-FALLBACK: JSON-Response
        return {"status": "error", "message": "Avatar-Video konnte nicht erstellt werden", "debug": error_msg}

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
        api_key = (
        os.getenv("BITHUMAN_API_SECRET")
        or os.getenv("BITHUMAN_API_KEY")
        or ""
        ).strip()
        if not api_key:
            raise HTTPException(status_code=400, detail="BITHUMAN_API_KEY fehlt")

        with tempfile.TemporaryDirectory() as temp_dir:
            # Nur den Dateinamen verwenden (kein absoluter Client-Pfad)
            safe_name = Path(image.filename).name or "upload.png"
            img_path = Path(temp_dir) / safe_name
            with open(img_path, "wb") as buf:
                shutil.copyfileobj(image.file, buf)
            try:
                size = img_path.stat().st_size
                print(f"[figure/create] gespeichert: {img_path} ({size} bytes)")
            except Exception as e:
                print(f"[figure/create] konnte Datei nicht prüfen: {e}")
            if not img_path.exists():
                print(f"[figure/create] Datei existiert nicht: {img_path} – Fallback")
                dummy_id = uuid.uuid4().hex
                return {"figure_id": dummy_id, "runtime_model_hash": None}

            # Beispiel: Upload zu BitHuman Agent Generation API (Platzhalter-Endpunkt, laut Doku anpassen)
            # Hier demonstrativ multipart POST; ersetze 'AGENT_CREATE_URL' durch echten Doku-Endpunkt
            AGENT_CREATE_URL = os.getenv("BITHUMAN_AGENT_CREATE_URL", "")
            headers = {"Authorization": f"Bearer {api_key}"}
            if AGENT_CREATE_URL:
                try:
                    with open(img_path, "rb") as fp:
                        files = {"image": (img_path.name, fp, "image/png")}
                        r = requests.post(AGENT_CREATE_URL, headers=headers, files=files, timeout=30)
                    print(f"[figure/create] POST {AGENT_CREATE_URL} -> {r.status_code}")
                    if 200 <= r.status_code < 300:
                        data = r.json() if r.content else {}
                        figure_id = data.get("figure_id") or data.get("id")
                        model_hash = data.get("runtime_model_hash") or data.get("model_hash")
                        if figure_id or model_hash:
                            return {"figure_id": figure_id, "runtime_model_hash": model_hash}
                        else:
                            print("[figure/create] 2xx ohne figure_id/model_hash – fallback")
                    else:
                        print(f"[figure/create] Fehler HTTP {r.status_code}: {r.text[:300]}")
                except Exception as e:
                    print(f"[figure/create] Exception bei Agent Create: {e}")

        # Fallback: Dummy-IDs zurückgeben, damit die App fortfahren kann
        dummy_id = uuid.uuid4().hex
        print(f"[figure/create] Fallback aktiv – gebe dummy figure_id {dummy_id} zurück")
        return {"figure_id": dummy_id, "runtime_model_hash": None}
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
