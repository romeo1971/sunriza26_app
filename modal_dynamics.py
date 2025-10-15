"""
Modal.com Dynamics Service für Sunriza26
GPU-basierte LivePortrait Avatar-Animation
"""

import modal
import os
import subprocess
import tempfile
from pathlib import Path

# Modal App erstellen
app = modal.App("sunriza-dynamics")

# Docker Image mit allen Dependencies
image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("git", "ffmpeg")
    .pip_install(
        "fastapi",  # Für Web Endpoints
        "firebase-admin==6.4.0",
        "requests==2.31.0",
        "pillow==10.2.0",
    )
    # LivePortrait installieren
    .run_commands(
        "git clone https://github.com/KwaiVGI/LivePortrait.git /opt/liveportrait",
        "cd /opt/liveportrait && pip install torch torchvision --index-url https://download.pytorch.org/whl/cu118",
        "cd /opt/liveportrait && pip install opencv-python-headless numpy tyro pyyaml tqdm imageio scikit-image",
    )
)

@app.function(
    image=image,
    gpu="T4",  # NVIDIA T4 GPU
    timeout=600,  # 10 Minuten max
    secrets=[modal.Secret.from_name("firebase-credentials")],
)
def generate_dynamics_gpu(avatar_id: str, dynamics_id: str, parameters: dict):
    """
    Generiert Dynamics-Video mit LivePortrait auf GPU
    
    Args:
        avatar_id: Firestore Avatar ID
        dynamics_id: Name der Dynamics (z.B. 'basic')
        parameters: Dict mit driving_multiplier, scale, source_max_dim
    
    Returns:
        dict: {"status": "success", "video_url": "...", "duration_sec": 123}
    """
    import firebase_admin
    from firebase_admin import credentials, storage, firestore
    import requests
    import json
    
    print(f"🎭 Starte Dynamics-Generierung: {avatar_id}/{dynamics_id}")
    
    # Firebase initialisieren
    if not firebase_admin._apps:
        # Credentials aus Modal Secret (JSON String)
        cred_json = os.getenv("FIREBASE_CREDENTIALS")
        if cred_json:
            cred_dict = json.loads(cred_json)
            cred = credentials.Certificate(cred_dict)
        else:
            # Fallback: Default Credentials
            cred = None
        
        firebase_admin.initialize_app(cred, {
            'storageBucket': 'sunriza26.firebasestorage.app'
        })
    
    db = firestore.client()
    bucket = storage.bucket()
    
    # 1. Avatar-Daten laden
    avatar_ref = db.collection('avatars').document(avatar_id)
    avatar_doc = avatar_ref.get()
    
    if not avatar_doc.exists:
        raise Exception(f"Avatar {avatar_id} nicht gefunden")
    
    avatar_data = avatar_doc.to_dict()
    
    # 2. URLs holen
    hero_image_url = avatar_data.get('avatarImageUrl')
    hero_video_url = avatar_data.get('training', {}).get('heroVideoUrl')
    
    if not hero_image_url or not hero_video_url:
        raise Exception("Hero-Image oder Hero-Video fehlt")
    
    # 3. Assets herunterladen
    hero_image_path = f'/tmp/{avatar_id}_hero.jpg'
    hero_video_path = f'/tmp/{avatar_id}_hero_video.mp4'
    trimmed_video_path = f'/tmp/{avatar_id}_trimmed.mp4'
    
    print(f"📥 Lade Hero-Image...")
    resp = requests.get(hero_image_url, stream=True, timeout=60)
    resp.raise_for_status()
    with open(hero_image_path, 'wb') as f:
        for chunk in resp.iter_content(chunk_size=8192):
            f.write(chunk)
    
    print(f"📥 Lade Hero-Video...")
    resp = requests.get(hero_video_url, stream=True, timeout=60)
    resp.raise_for_status()
    with open(hero_video_path, 'wb') as f:
        for chunk in resp.iter_content(chunk_size=8192):
            f.write(chunk)
    
    # 4. Video trimmen auf 10 Sekunden
    print(f"✂️ Trimme Video auf 10 Sekunden...")
    subprocess.run([
        'ffmpeg', '-i', hero_video_path,
        '-ss', '0', '-t', '10',
        '-c:v', 'copy', '-y', trimmed_video_path
    ], check=True, capture_output=True)
    
    # 5. LivePortrait starten
    print(f"🎬 Starte LivePortrait mit GPU...")
    
    lp_output_dir = f'/tmp/{avatar_id}_lp_output'
    os.makedirs(lp_output_dir, exist_ok=True)
    
    lp_cmd = [
        'python',
        '/opt/liveportrait/inference.py',
        '-s', hero_image_path,
        '-d', trimmed_video_path,
        '-o', lp_output_dir,
        '--driving_multiplier', str(parameters.get('driving_multiplier', 0.41)),
        '--source-max-dim', str(parameters.get('source_max_dim', 1600)),
        '--scale', str(parameters.get('scale', 1.7)),
        '--animation-region', parameters.get('animation_region', 'all'),
        '--flag-normalize-lip',
        '--flag-pasteback',
    ]
    
    result = subprocess.run(lp_cmd, check=True, capture_output=True, text=True)
    print(result.stdout)
    
    # 6. Output-Video finden
    output_files = list(Path(lp_output_dir).glob('*.mp4'))
    if not output_files:
        raise Exception("LivePortrait Output nicht gefunden")
    
    lp_output = str(output_files[0])
    
    # 7. H.264 Konvertierung
    print(f"🔄 Konvertiere zu H.264...")
    
    final_output = f'/tmp/{avatar_id}_{dynamics_id}_idle.mp4'
    
    subprocess.run([
        'ffmpeg', '-i', lp_output,
        '-c:v', 'libx264',
        '-preset', 'slow',
        '-crf', '18',
        '-pix_fmt', 'yuv420p',
        '-an',  # Kein Audio
        '-y', final_output
    ], check=True, capture_output=True)
    
    # 8. Upload zu Firebase Storage
    print(f"📤 Upload zu Firebase Storage...")
    
    blob = bucket.blob(f'avatars/{avatar_id}/dynamics/{dynamics_id}_idle.mp4')
    blob.upload_from_filename(final_output)
    blob.make_public()
    
    video_url = blob.public_url
    
    # 9. Firestore Update
    print(f"💾 Update Firestore...")
    
    avatar_ref.update({
        f'training.livePortrait.dynamics.{dynamics_id}': {
            'videoUrl': video_url,
            'generatedAt': firestore.SERVER_TIMESTAMP,
            'parameters': parameters,
        }
    })
    
    print(f"✅ Fertig! Video: {video_url}")
    
    return {
        "status": "success",
        "avatar_id": avatar_id,
        "dynamics_id": dynamics_id,
        "video_url": video_url,
    }


@app.function(image=image)
@modal.asgi_app()
def api_generate_dynamics():
    """REST API Endpoint für Flutter App"""
    from fastapi import FastAPI, Request, HTTPException
    web_app = FastAPI()
    
    @web_app.post("/")
    async def generate(request: Request):
        data = await request.json()
        avatar_id = data.get("avatar_id")
        dynamics_id = data.get("dynamics_id", "basic")
        parameters = data.get("parameters", {})
        
        if not avatar_id:
            raise HTTPException(status_code=400, detail="avatar_id required")
        
        # Starte GPU-Funktion
        result = generate_dynamics_gpu.remote(avatar_id, dynamics_id, parameters)
        return result
    
    return web_app


@app.function(image=image)
@modal.asgi_app()
def health():
    from fastapi import FastAPI
    web_app = FastAPI()
    
    @web_app.get("/")
    async def check():
        return {"status": "healthy", "service": "sunriza-dynamics-modal"}
    
    return web_app

