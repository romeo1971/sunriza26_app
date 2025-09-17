from fastapi import FastAPI, UploadFile, File
from fastapi.responses import FileResponse, JSONResponse
import uvicorn
import shutil
import requests
import time
import os
from sonic_workflow import build_workflow

COMFY_API_URL = "http://127.0.0.1:8188"   # ComfyUI muss parallel laufen
UPLOAD_DIR = "uploads"
OUTPUT_DIR = "ComfyUI/output"            # Standard-Ausgabe von ComfyUI

os.makedirs(UPLOAD_DIR, exist_ok=True)

app = FastAPI()

@app.post("/generate")
async def generate(image: UploadFile = File(...), audio: UploadFile = File(...)):
    """
    Empfängt Bild + Audio von Flutter,
    sendet Workflow an ComfyUI,
    wartet auf Video und gibt es zurück.
    """
    print(f"Received files: image={image.filename}, audio={audio.filename}")

    # Dateien speichern
    image_path = os.path.join(UPLOAD_DIR, image.filename)
    audio_path = os.path.join(UPLOAD_DIR, audio.filename)

    with open(image_path, "wb") as buffer:
        shutil.copyfileobj(image.file, buffer)
    with open(audio_path, "wb") as buffer:
        shutil.copyfileobj(audio.file, buffer)

    print(f"Files saved: {image_path}, {audio_path}")

    # Workflow bauen - ComfyUI erwartet relative Pfade
    output_name = f"sonic_{int(time.time())}"
    # Kopiere Dateien nach ComfyUI/input/ für ComfyUI
    comfy_input_dir = "../ComfyUI/input"
    os.makedirs(comfy_input_dir, exist_ok=True)
    
    comfy_image_path = os.path.join(comfy_input_dir, os.path.basename(image_path))
    comfy_audio_path = os.path.join(comfy_input_dir, os.path.basename(audio_path))
    
    shutil.copy2(image_path, comfy_image_path)
    shutil.copy2(audio_path, comfy_audio_path)
    
    # Relative Pfade für ComfyUI
    relative_image_path = f"input/{os.path.basename(image_path)}"
    relative_audio_path = f"input/{os.path.basename(audio_path)}"
    
    workflow = build_workflow(relative_image_path, relative_audio_path, output_name)
    print(f"Workflow built for output: {output_name}")
    print(f"Image: {relative_image_path}, Audio: {relative_audio_path}")

    # Workflow an ComfyUI senden
    print(f"Sending to ComfyUI: {COMFY_API_URL}/prompt")
    r = requests.post(f"{COMFY_API_URL}/prompt", json=workflow)
    print(f"ComfyUI response: {r.status_code} - {r.text}")
    
    if r.status_code != 200:
        return JSONResponse(status_code=500, content={"error": "ComfyUI error", "details": r.text})

    # Auf fertiges Video warten
    video_file = None
    print(f"Waiting for video in: {OUTPUT_DIR}")
    for i in range(60):  # bis zu 60 Sekunden warten
        print(f"Check {i+1}/60 for video...")
        if os.path.exists(OUTPUT_DIR):
            for f in os.listdir(OUTPUT_DIR):
                if f.startswith(output_name) and f.endswith(".mp4"):
                    video_file = os.path.join(OUTPUT_DIR, f)
                    print(f"Found video: {video_file}")
                    break
        if video_file:
            break
        time.sleep(2)

    if not video_file:
        return JSONResponse(status_code=500, content={"error": "Timeout: Kein Video gefunden"})

    return FileResponse(video_file, media_type="video/mp4", filename=os.path.basename(video_file))


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
