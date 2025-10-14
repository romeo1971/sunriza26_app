from fastapi import FastAPI, BackgroundTasks
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import uvicorn
import subprocess
import sys

app = FastAPI()

class DynamicsRequest(BaseModel):
    avatar_id: str
    dynamics_id: str
    parameters: dict

@app.get("/")
async def root():
    """Backend ist jetzt nur noch für andere Services da - BitHuman übernimmt Avatar-Generierung"""
    return {"message": "Backend läuft - Avatar-Generierung erfolgt über BitHuman SDK"}

@app.get("/health")
async def health():
    """Health Check für das Backend"""
    return {"status": "healthy", "service": "sunriza26-backend"}

@app.post("/generate-dynamics")
async def generate_dynamics(request: DynamicsRequest, background_tasks: BackgroundTasks):
    """Generiere Dynamics für einen Avatar (Live Avatar Animation)"""
    
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
        "message": "Dynamics-Generierung gestartet (läuft im Hintergrund, ca. 3-5 Minuten)"
    }

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
        
        subprocess.run(cmd, check=True, cwd='/Users/hhsw/Desktop/sunriza/sunriza26/backend')
        print(f"✅ Dynamics '{dynamics_id}' für Avatar {avatar_id} erfolgreich generiert")
    except Exception as e:
        print(f"❌ Fehler bei Dynamics-Generierung: {e}")


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8002)
