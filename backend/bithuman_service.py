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
        # Temporäre Dateien erstellen
        with tempfile.TemporaryDirectory() as temp_dir:
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
            
            # Wenn figure_id/hash übergeben: per-request Runtime initialisieren
            global runtime, API_SECRET_CACHE
            local_runtime = runtime
            if (figure_id or runtime_model_hash) and API_SECRET_CACHE:
                try:
                    kw = {"api_secret": API_SECRET_CACHE}
                    if figure_id:
                        kw["figure_id"] = figure_id
                    if runtime_model_hash:
                        kw["runtime_model_hash"] = runtime_model_hash
                    local_runtime = await AsyncBithuman.create(**kw)
                except Exception as e:
                    print(f"❌ Per-request Runtime Fehler: {e}")
                    local_runtime = runtime

            # Avatar-Video mit BitHuman erstellen (lokale oder globale Runtime)
            if not local_runtime:
                raise HTTPException(status_code=500, detail="BitHuman Runtime nicht bereit")
            result = await local_runtime.create_avatar_video(
                image_path=str(image_path),
                audio_path=str(audio_path),
                output_path=str(output_path)
            )
            
            if success and output_path.exists():
                # Video-Datei zurückgeben
                return FileResponse(
                    path=str(output_path),
                    media_type="video/mp4",
                    filename="avatar_video.mp4"
                )
            else:
                raise HTTPException(
                    status_code=500,
                    detail="Avatar-Video-Erstellung fehlgeschlagen"
                )
                
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
            img_path = Path(temp_dir) / image.filename
            with open(img_path, "wb") as buf:
                shutil.copyfileobj(image.file, buf)

            # Beispiel: Upload zu BitHuman Agent Generation API (Platzhalter-Endpunkt, laut Doku anpassen)
            # Hier demonstrativ multipart POST; ersetze 'AGENT_CREATE_URL' durch echten Doku-Endpunkt
            AGENT_CREATE_URL = os.getenv("BITHUMAN_AGENT_CREATE_URL", "https://api.bithuman.ai/agent/create")
            files = {"image": (image.filename, open(img_path, "rb"), "image/png")}
            headers = {"Authorization": f"Bearer {api_key}"}
            r = requests.post(AGENT_CREATE_URL, headers=headers, files=files, timeout=30)
            if 200 <= r.status_code < 300:
                data = r.json() if r.content else {}
                figure_id = data.get("figure_id") or data.get("id")
                model_hash = data.get("runtime_model_hash") or data.get("model_hash")
                if not (figure_id or model_hash):
                    raise HTTPException(status_code=500, detail="BitHuman Agent Create: figure_id fehlt")
                return {"figure_id": figure_id, "runtime_model_hash": model_hash}

            # 5xx/Timeout → asynchroner Retry-Job
            job_id = uuid.uuid4().hex
            JOBS[job_id] = {"status": "pending", "error": None, "figure_id": None, "runtime_model_hash": None}

            def _retry_job():
                try:
                    backoff = [2, 4, 8, 16, 30]
                    for sec in backoff:
                        try:
                            rr = requests.post(AGENT_CREATE_URL, headers=headers, files=files, timeout=30)
                            if 200 <= rr.status_code < 300:
                                dd = rr.json() if rr.content else {}
                                fid = dd.get("figure_id") or dd.get("id")
                                mh = dd.get("runtime_model_hash") or dd.get("model_hash")
                                if fid or mh:
                                    JOBS[job_id] = {"status": "done", "error": None, "figure_id": fid, "runtime_model_hash": mh}
                                    return
                            else:
                                JOBS[job_id]["error"] = f"HTTP {rr.status_code}"
                        except Exception as _e:
                            JOBS[job_id]["error"] = str(_e)
                        time.sleep(sec)
                    JOBS[job_id]["status"] = "failed"
                except Exception as e:
                    JOBS[job_id] = {"status": "failed", "error": str(e), "figure_id": None, "runtime_model_hash": None}

            threading.Thread(target=_retry_job, daemon=True).start()
            return {"job_id": job_id}, 202
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
