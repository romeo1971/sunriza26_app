"""
Offizieller BitHuman SDK Service
Basierend auf der offiziellen Dokumentation: https://docs.bithuman.ai
"""

import os
import asyncio
from pathlib import Path
from typing import Optional
import bithuman
from bithuman import AsyncBithuman
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import FileResponse
import tempfile
import shutil

# BitHuman SDK initialisieren
runtime = None

async def initialize_bithuman():
    """Initialisiert BitHuman SDK mit offiziellem API Secret"""
    global runtime
    
    try:
        # Offizielles API Secret
        api_secret = "DxGRMKb9fuMDiNHMO648VgU3MA81zP4hSZvdLFFV43nKYeMelG6x5QfrSH8UyvIRZ"
        
        # Model-Pfad (wird automatisch heruntergeladen)
        model_path = "models/einstein.imx"
        
        # Offizielle SDK-Initialisierung nach Dokumentation
        runtime = await AsyncBithuman.create(
            model_path=model_path,
            api_secret=api_secret,
        )
        print("✅ BitHuman SDK mit offiziellem API Secret initialisiert")
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
            print("❌ BitHuman Runtime nicht initialisiert")
            return False
            
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
    audio: UploadFile = File(...)
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
            
            # Avatar-Video mit BitHuman erstellen
            success = await create_avatar_video(
                str(image_path),
                str(audio_path),
                str(output_path)
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
    uvicorn.run(app, host="0.0.0.0", port=8000)
