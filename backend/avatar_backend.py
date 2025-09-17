import os
import asyncio
import json
import requests
import tempfile
from pathlib import Path
from typing import Optional
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel
import bithuman
from bithuman import AsyncBithuman

# FastAPI App
app = FastAPI(title="Avatar Backend", version="1.0.0")

# CORS für Flutter
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Globale Variablen
runtime = None
UPLOAD_FOLDER = "avatars"
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# Pydantic Models
class SpeakRequest(BaseModel):
    text: str
    imx: str

# BitHuman SDK Initialisierung - dynamisch je nach Avatar
async def initialize_bithuman():
    """Initialisiert BitHuman SDK nur wenn Avatar-Modell vorhanden"""
    global runtime
    
    try:
        # Prüfe ob irgendein Avatar-Modell vorhanden ist
        models_dir = "models"
        if not os.path.exists(models_dir):
            os.makedirs(models_dir, exist_ok=True)
        
        # Suche nach .imx Dateien
        imx_files = [f for f in os.listdir(models_dir) if f.endswith('.imx')]
        
        if not imx_files:
            print("⚠️ BitHuman: Kein Avatar-Modell gefunden - wird beim Upload initialisiert")
            runtime = None
            return True
        
        # Verwende das erste gefundene Modell
        model_path = os.path.join(models_dir, imx_files[0])
        print(f"🎭 BitHuman: Verwende Avatar-Modell: {imx_files[0]}")
        
        # API Secret aus Umgebungsvariable
        api_secret = os.getenv('BITHUMAN_API_KEY', 'DxGRMKb9fuMDiNHMO648VgU3MA81zP4hSZvdLFFV43nKYeMelG6x5QfrSH8UyvIRZ')
        
        # Offizielle SDK-Initialisierung
        runtime = await AsyncBithuman.create(
            model_path=model_path,
            api_secret=api_secret,
        )
        print("✅ BitHuman SDK initialisiert")
        return True
        
    except Exception as e:
        print(f"⚠️ BitHuman: Wird beim Avatar-Upload initialisiert - {e}")
        runtime = None
        return True

# BitHuman Avatar wechseln
async def switch_avatar(imx_filename: str):
    """Wechselt zu einem anderen Avatar-Modell"""
    global runtime
    
    try:
        model_path = os.path.join("models", imx_filename)
        if not os.path.exists(model_path):
            print(f"❌ Avatar-Modell nicht gefunden: {imx_filename}")
            return False
        
        # Stoppe aktuellen Runtime
        if runtime:
            await runtime.stop()
        
        # API Secret aus Umgebungsvariable
        api_secret = os.getenv('BITHUMAN_API_KEY', 'DxGRMKb9fuMDiNHMO648VgU3MA81zP4hSZvdLFFV43nKYeMelG6x5QfrSH8UyvIRZ')
        
        # Neuen Runtime starten
        runtime = await AsyncBithuman.create(
            model_path=model_path,
            api_secret=api_secret,
        )
        print(f"✅ Avatar gewechselt zu: {imx_filename}")
        return True
        
    except Exception as e:
        print(f"❌ Avatar-Wechsel fehlgeschlagen: {e}")
        return False

# ElevenLabs TTS
async def generate_tts(text: str) -> Optional[str]:
    """Generiert TTS Audio mit ElevenLabs"""
    try:
        api_key = os.getenv('ELEVENLABS_API_KEY')
        voice_id = os.getenv('ELEVENLABS_VOICE_ID', 'pNInz6obpgDQGcFmaJgB')
        
        if not api_key:
            print("⚠️ ElevenLabs API Key nicht gesetzt")
            return None
            
        url = f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}"
        headers = {
            "xi-api-key": api_key,
            "Content-Type": "application/json"
        }
        data = {
            "text": text,
            "voice_settings": {
                "stability": 0.4,
                "similarity_boost": 0.75,
                "style": 0.0,
                "use_speaker_boost": True,
            }
        }
        
        response = requests.post(url, headers=headers, json=data)
        
        if response.status_code == 200:
            # Audio in temporärem Verzeichnis speichern
            temp_dir = tempfile.gettempdir()
            audio_path = os.path.join(temp_dir, f"tts_{os.urandom(4).hex()}.wav")
            
            with open(audio_path, "wb") as f:
                f.write(response.content)
                
            print(f"✅ TTS Audio erstellt: {audio_path}")
            return audio_path
        else:
            print(f"❌ ElevenLabs Fehler: {response.status_code}")
            return None
            
    except Exception as e:
        print(f"❌ TTS Fehler: {e}")
        return None

# Avatar Video Generierung
async def create_avatar_video(image_path: str, audio_path: str, output_path: str) -> bool:
    """Erstellt Avatar-Video mit BitHuman SDK"""
    try:
        if not runtime:
            print("❌ BitHuman Runtime nicht initialisiert")
            return False
            
        # Avatar-Video erstellen
        success = await runtime.create_avatar_video(
            image_path=image_path,
            audio_path=audio_path,
            output_path=output_path
        )
        
        if success:
            print(f"✅ Avatar-Video erstellt: {output_path}")
            return True
        else:
            print("❌ Avatar-Video-Generierung fehlgeschlagen")
            return False
            
    except Exception as e:
        print(f"❌ Avatar-Video Fehler: {e}")
        return False

# API Endpoints
@app.on_event("startup")
async def startup_event():
    """Startup Event - Initialisiert BitHuman SDK"""
    await initialize_bithuman()

@app.get("/")
async def root():
    """Root Endpoint"""
    return {"message": "Avatar Backend läuft", "status": "healthy"}

@app.get("/health")
async def health():
    """Health Check"""
    return {
        "status": "healthy",
        "bithuman_ready": runtime is not None,
        "service": "avatar-backend"
    }

@app.post("/upload_imx")
async def upload_imx_file(file: UploadFile = File(...)):
    """Lädt .imx Avatar-Modell hoch"""
    try:
        # Stelle sicher, dass models Verzeichnis existiert
        models_dir = "models"
        os.makedirs(models_dir, exist_ok=True)
        
        file_path = os.path.join(models_dir, file.filename)
        
        with open(file_path, "wb") as f:
            content = await file.read()
            f.write(content)
            
        print(f"✅ Avatar hochgeladen: {file.filename}")
        
        # BitHuman mit neuem Avatar initialisieren
        await switch_avatar(file.filename)
        
        return {"status": "OK", "filename": file.filename}
        
    except Exception as e:
        print(f"❌ Upload Fehler: {e}")
        raise HTTPException(status_code=500, detail=f"Upload fehlgeschlagen: {str(e)}")

@app.post("/speak")
async def speak(req: SpeakRequest):
    """Startet Avatar-Sprechen mit Text"""
    try:
        print(f"🗣️ Avatar-Sprechen: {req.text}")
        
        # 1. TTS Audio generieren
        audio_path = await generate_tts(req.text)
        if not audio_path:
            raise HTTPException(status_code=500, detail="TTS-Generierung fehlgeschlagen")
            
        # 2. Avatar-Modell laden
        imx_path = os.path.join(UPLOAD_FOLDER, req.imx)
        if not os.path.exists(imx_path):
            raise HTTPException(status_code=404, detail="Avatar-Modell nicht gefunden")
            
        # 3. Avatar-Video erstellen (falls BitHuman verfügbar)
        if runtime:
            output_path = os.path.join(tempfile.gettempdir(), f"avatar_{os.urandom(4).hex()}.mp4")
            success = await create_avatar_video(imx_path, audio_path, output_path)
            
            if success:
                return {
                    "status": "spoken",
                    "audio_path": audio_path,
                    "video_path": output_path,
                    "message": "Avatar spricht jetzt!"
                }
        
        # Fallback: Nur Audio
        return {
            "status": "audio_only",
            "audio_path": audio_path,
            "message": "Audio generiert (Avatar-Video nicht verfügbar)"
        }
        
    except Exception as e:
        print(f"❌ Speak Fehler: {e}")
        raise HTTPException(status_code=500, detail=f"Speak fehlgeschlagen: {str(e)}")

@app.get("/download/{filename}")
async def download_file(filename: str):
    """Download für generierte Dateien"""
    file_path = os.path.join(tempfile.gettempdir(), filename)
    
    if os.path.exists(file_path):
        return FileResponse(file_path, filename=filename)
    else:
        raise HTTPException(status_code=404, detail="Datei nicht gefunden")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
