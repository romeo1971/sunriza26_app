#!/usr/bin/env python3
"""
Backend Endpoint für Dynamics-Generierung
Wird vom Backend (FastAPI) aufgerufen
"""

import sys
import os
import subprocess
import json
from pathlib import Path
from datetime import datetime
import firebase_admin
from firebase_admin import credentials, storage, firestore

# Service Account Key
SERVICE_ACCOUNT_KEY = Path(__file__).parent.parent / "service-account-key.json"

def init_firebase():
    """Initialize Firebase Admin SDK"""
    if not firebase_admin._apps:
        cred = credentials.Certificate(str(SERVICE_ACCOUNT_KEY))
        firebase_admin.initialize_app(cred, {
            'storageBucket': 'sunriza26.firebasestorage.app'
        })
    return storage.bucket(), firestore.client()

def generate_dynamics(avatar_id: str, dynamics_id: str, parameters: dict):
    """
    Generiere Dynamics für einen Avatar
    
    Args:
        avatar_id: Firestore avatar document ID
        dynamics_id: Name der Dynamics (z.B. 'basic', 'lachen')
        parameters: Dict mit driving_multiplier, scale, source_max_dim
    """
    bucket, db = init_firebase()
    
    print(f"🎭 Generiere Dynamics '{dynamics_id}' für Avatar {avatar_id}")
    
    # 1. Avatar-Daten laden
    avatar_ref = db.collection('avatars').document(avatar_id)
    avatar_doc = avatar_ref.get()
    
    if not avatar_doc.exists:
        raise Exception(f"Avatar {avatar_id} nicht gefunden")
    
    avatar_data = avatar_doc.to_dict()
    
    # 2. Hero-Image & Hero-Video laden
    hero_image_url = avatar_data.get('avatarImageUrl')
    hero_video_url = avatar_data.get('training', {}).get('heroVideoUrl')
    
    if not hero_image_url or not hero_video_url:
        raise Exception("Hero-Image oder Hero-Video fehlt")
    
    # 3. Assets herunterladen
    import requests
    
    hero_image_path = f'/tmp/{avatar_id}_hero.jpg'
    hero_video_path = f'/tmp/{avatar_id}_hero_video.mp4'
    
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
    
    # 4. Video trimmen (10 Sekunden)
    trimmed_video_path = f'/tmp/{avatar_id}_trimmed.mp4'
    print(f"✂️ Trimme Video auf 10 Sekunden...")
    
    subprocess.run([
        'ffmpeg', '-i', hero_video_path,
        '-ss', '0', '-t', '10',
        '-c:v', 'copy', '-y', trimmed_video_path
    ], check=True, capture_output=True)
    
    # 5. LivePortrait starten
    print(f"🎬 Starte LivePortrait...")
    
    lp_output_dir = f'/tmp/{avatar_id}_lp_output'
    os.makedirs(lp_output_dir, exist_ok=True)
    
    lp_cmd = [
        'python',
        '/Users/hhsw/Desktop/sunriza/LivePortrait/inference.py',
        '-s', hero_image_path,
        '-d', trimmed_video_path,
        '-o', lp_output_dir,
        '--driving_multiplier', str(parameters.get('driving_multiplier', 0.41)),
        '--source-max-dim', str(parameters.get('source_max_dim', 1600)),
        '--scale', str(parameters.get('scale', 1.7)),
        '--animation-region', parameters.get('animation_region', 'all'),
    ]
    
    # Optional flags
    if parameters.get('flag_normalize_lip', True):
        lp_cmd.append('--flag-normalize-lip')
    
    if parameters.get('flag_pasteback', True):
        lp_cmd.append('--flag-pasteback')
    
    env = os.environ.copy()
    env['PYTORCH_ENABLE_MPS_FALLBACK'] = '1'
    
    subprocess.run(lp_cmd, env=env, check=True, capture_output=False)
    
    # 6. Output-Video finden
    output_files = list(Path(lp_output_dir).glob('*.mp4'))
    if not output_files:
        raise Exception("LivePortrait Output nicht gefunden")
    
    lp_output = str(output_files[0])
    
    # 7. H.264 Konvertierung + Crossfade (ohne Audio!)
    print(f"🔄 Konvertiere zu H.264 + Crossfade...")
    
    temp_output = f'/tmp/{avatar_id}_temp.mp4'
    final_output = f'/tmp/{avatar_id}_{dynamics_id}_idle.mp4'
    
    # Schritt 1: H.264 ohne Audio
    subprocess.run([
        'ffmpeg', '-i', lp_output,
        '-an',  # Kein Audio!
        '-c:v', 'libx264',
        '-preset', 'slow',
        '-crf', '18',
        '-pix_fmt', 'yuv420p',
        '-y', temp_output
    ], check=True, capture_output=True)
    
    # Schritt 2: Crossfade
    duration_result = subprocess.run([
        'ffprobe', '-v', 'error', '-show_entries', 'format=duration',
        '-of', 'default=noprint_wrappers=1:nokey=1', temp_output
    ], capture_output=True, text=True, check=True)
    
    duration = float(duration_result.stdout.strip())
    offset = duration - 1.0
    
    subprocess.run([
        'ffmpeg', '-i', temp_output,
        '-filter_complex',
        f'[0:v]split[main][dup];[dup]trim=start=0:duration=1.0,setpts=PTS-STARTPTS[start];[main][start]xfade=transition=fade:duration=1.0:offset={offset}',
        '-y', final_output
    ], check=True, capture_output=True)
    
    print(f"✅ Video generiert: {final_output}")
    
    # 8. Assets zu Firebase Storage hochladen
    print(f"📤 Uploading zu Firebase Storage...")
    
    storage_path = f"avatars/{avatar_id}/dynamics/{dynamics_id}/idle.mp4"
    blob = bucket.blob(storage_path)
    blob.upload_from_filename(final_output)
    blob.make_public()
    
    idle_url = blob.public_url
    
    print(f"✅ Uploaded: {idle_url}")
    
    # 9. Firestore aktualisieren
    print(f"💾 Updating Firestore...")
    
    dynamics_data = {
        'idleVideoUrl': idle_url,
        'parameters': parameters,
        'generatedAt': datetime.utcnow(),
        'status': 'ready'
    }
    
    avatar_ref.update({
        f'dynamics.{dynamics_id}': dynamics_data
    })
    
    print(f"🎉 Dynamics '{dynamics_id}' erfolgreich generiert!")
    
    return {
        'avatar_id': avatar_id,
        'dynamics_id': dynamics_id,
        'idle_url': idle_url,
        'status': 'ready'
    }

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python generate_dynamics_endpoint.py <avatar_id> <dynamics_id> [driving_multiplier] [scale] [source_max_dim]")
        sys.exit(1)
    
    avatar_id = sys.argv[1]
    dynamics_id = sys.argv[2]
    
    parameters = {
        'driving_multiplier': float(sys.argv[3]) if len(sys.argv) > 3 else 0.41,
        'scale': float(sys.argv[4]) if len(sys.argv) > 4 else 1.7,
        'source_max_dim': int(sys.argv[5]) if len(sys.argv) > 5 else 1600,
    }
    
    result = generate_dynamics(avatar_id, dynamics_id, parameters)
    print(json.dumps(result, indent=2))

