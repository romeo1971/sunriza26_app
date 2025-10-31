from fastapi import FastAPI, BackgroundTasks, HTTPException
from fastapi.responses import JSONResponse, FileResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uvicorn
import subprocess
import sys
import os
import tempfile
import requests
import shutil

app = FastAPI()

# CORS für Flutter
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class DynamicsRequest(BaseModel):
    avatar_id: str
    dynamics_id: str
    parameters: dict

class TrimVideoRequest(BaseModel):
    video_url: str
    start_time: float
    end_time: float

@app.get("/")
async def root():
    """Backend ist jetzt nur noch für andere Services da - BitHuman übernimmt Avatar-Generierung"""
    return {"message": "Backend läuft - Avatar-Generierung erfolgt über BitHuman SDK"}

@app.get("/health")
async def health():
    """Health Check für das Backend"""
    return {"status": "healthy", "service": "sunriza26-backend"}

@app.get("/api/elevenlabs/voices")
async def get_elevenlabs_voices():
    """Proxy für ElevenLabs Voices API (umgeht Flutter SSL-Problem)"""
    try:
        api_key = os.getenv("ELEVENLABS_API_KEY")
        if not api_key:
            raise HTTPException(status_code=500, detail="ELEVENLABS_API_KEY fehlt")
        
        response = requests.get(
            "https://api.elevenlabs.io/v1/voices",
            headers={"xi-api-key": api_key},
            timeout=10
        )
        response.raise_for_status()
        return response.json()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/generate-dynamics")
async def generate_dynamics(request: DynamicsRequest, background_tasks: BackgroundTasks):
    """Generiere Dynamics für einen Avatar (Live Avatar Animation)"""
    
    # Schätze Generierungszeit basierend auf source_max_dim
    source_max_dim = request.parameters.get('source_max_dim', 1600)
    estimated_seconds = _estimate_generation_time(source_max_dim)
    
    # Starte Dynamics-Generierung im Hintergrund
    background_tasks.add_task(
        _run_dynamics_generation,
        request.avatar_id,
        request.dynamics_id,
        request.parameters
    )
    
    return {
        "status": "generating",
        "avatar_id": request.avatar_id,
        "dynamics_id": request.dynamics_id,
        "estimated_seconds": estimated_seconds,
        "message": f"Dynamics-Generierung gestartet (geschätzt: {estimated_seconds // 60} Min {estimated_seconds % 60} Sek)"
    }

def _estimate_generation_time(source_max_dim: int) -> int:
    """
    Schätzt die Generierungszeit basierend auf Bildgröße
    
    Returns: Geschätzte Zeit in Sekunden
    """
    # Empirische Werte (müssen angepasst werden basierend auf deinem System)
    # GPU: ~180s für 1600px, CPU: ~600s für 1600px
    
    base_time = 180  # Sekunden für 1600px (mit GPU)
    
    # Skaliere basierend auf source_max_dim
    # Größere Bilder = länger
    if source_max_dim <= 512:
        return int(base_time * 0.5)  # ~90s
    elif source_max_dim <= 1024:
        return int(base_time * 0.7)  # ~126s
    elif source_max_dim <= 1600:
        return int(base_time * 1.0)  # ~180s
    else:  # 2048+
        return int(base_time * 1.5)  # ~270s
    
    # TODO: CPU-Erkennung und längere Zeit für CPU
    # if not has_gpu():
    #     base_time *= 3  # 3x länger ohne GPU

def _run_dynamics_generation(avatar_id: str, dynamics_id: str, parameters: dict):
    """Hintergrund-Task für Dynamics-Generierung"""
    try:
        cmd = [
            sys.executable,
            'generate_dynamics_endpoint.py',
            avatar_id,
            dynamics_id,
            str(parameters.get('driving_multiplier', 0.41)),
            str(parameters.get('scale', 1.7)),
            str(parameters.get('source_max_dim', 1600)),
        ]
        
        subprocess.run(cmd, check=True, cwd='/app')
        print(f"✅ Dynamics '{dynamics_id}' für Avatar {avatar_id} erfolgreich generiert")
    except Exception as e:
        print(f"❌ Fehler bei Dynamics-Generierung: {e}")


@app.post("/trim-video")
async def trim_video(request: TrimVideoRequest):
    """Trimmt ein Video von start_time bis end_time (in Sekunden)"""
    
    # 1. Prüfe ob ffmpeg verfügbar ist
    if shutil.which('ffmpeg') is None:
        raise HTTPException(status_code=500, detail="ffmpeg nicht installiert")
    
    # 2. Video von URL herunterladen
    temp_dir = tempfile.gettempdir()
    input_filename = f"input_{os.urandom(8).hex()}.mp4"
    output_filename = f"trimmed_{os.urandom(8).hex()}.mp4"
    input_path = os.path.join(temp_dir, input_filename)
    output_path = os.path.join(temp_dir, output_filename)
    
    try:
        print(f"📥 Lade Video herunter: {request.video_url}")
        response = requests.get(request.video_url, timeout=120)
        response.raise_for_status()
        
        with open(input_path, 'wb') as f:
            f.write(response.content)
        
        # 3. Video mit ffmpeg trimmen
        duration = request.end_time - request.start_time
        print(f"✂️ Trimme Video: {request.start_time}s bis {request.end_time}s (Dauer: {duration}s)")
        
        cmd = [
            'ffmpeg',
            '-i', input_path,
            '-ss', str(request.start_time),
            '-t', str(duration),
            '-c:v', 'libx264',
            '-c:a', 'aac',
            '-y',
            output_path
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode != 0:
            print(f"❌ ffmpeg Fehler: {result.stderr}")
            raise HTTPException(status_code=500, detail=f"ffmpeg Fehler: {result.stderr}")
        
        print(f"✅ Video getrimmt: {output_filename}")
        
        # 4. Datei zum Download bereitstellen
        return FileResponse(
            path=output_path,
            media_type='video/mp4',
            filename=output_filename,
            headers={
                "Content-Disposition": f"attachment; filename={output_filename}"
            }
        )
        
    except requests.RequestException as e:
        raise HTTPException(status_code=400, detail=f"Video konnte nicht heruntergeladen werden: {str(e)}")
    except Exception as e:
        print(f"❌ Fehler beim Video-Trimming: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        # Cleanup Input-Datei
        if os.path.exists(input_path):
            os.remove(input_path)


if __name__ == "__main__":
    import os
    port = int(os.getenv("PORT", 8002))  # Cloud Run nutzt PORT env var, lokal default 8002
    uvicorn.run(app, host="0.0.0.0", port=port)
