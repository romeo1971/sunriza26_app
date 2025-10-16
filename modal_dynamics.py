#!/usr/bin/env python3
"""
Modal.com Dynamics Service für Sunriza26
1:1 Kopie von backend/generate_dynamics_endpoint.py
NUR angepasst für Modal.com Deployment
"""

import modal
import sys
import os
import subprocess
import json
from pathlib import Path
from datetime import datetime
from typing import List
import uuid

# FFmpeg-/FFprobe-Pfade robust bestimmen (nutze /usr/local wenn vorhanden, sonst PATH)
FFMPEG_BIN = '/usr/local/bin/ffmpeg' if os.path.exists('/usr/local/bin/ffmpeg') else 'ffmpeg'
FFPROBE_BIN = '/usr/local/bin/ffprobe' if os.path.exists('/usr/local/bin/ffprobe') else 'ffprobe'

# Modal App
app = modal.App("sunriza-dynamics")

# Docker Image mit GPU Support - NVIDIA CUDA 12.6 Base Image für neueste onnxruntime-gpu!
# FORCE REBUILD v9: 2025-10-16-09:26 - FFmpeg 8.0 REQUIRED for xfade!
image = (
    modal.Image.from_registry("nvidia/cuda:12.6.0-cudnn-devel-ubuntu22.04", add_python="3.11")
    .apt_install("git", "wget", "xz-utils", "ffmpeg")  # System FFmpeg als Fallback
    .pip_install(
        "fastapi",
        "firebase-admin==6.4.0",
        "requests==2.31.0",
        "pillow==10.2.0",
        "huggingface_hub",
    )
    .run_commands(
        # Verwende System-FFmpeg (aus apt) – Download-Blockaden im Builder umgehen
        "ffmpeg -version",
        "git clone https://github.com/KwaiVGI/LivePortrait.git /opt/liveportrait",
        # PyTorch mit CUDA 12.1 Support
        "cd /opt/liveportrait && pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121",
        # EXAKT die gleichen Versionen wie lokal
        "cd /opt/liveportrait && pip install numpy==2.2.6 onnx==1.19.1 onnxruntime-gpu opencv-python-headless==4.12.0.88 tyro==0.9.34 pyyaml==6.0.3 tqdm==4.67.1 imageio[ffmpeg]==2.37.0 scikit-image==0.25.2 pykalman==0.10.2",
        # PATCH LivePortrait's video.py für höhere Encoding-Qualität (CRF 23 → 15)
        "cd /opt/liveportrait && sed -i \"s/'crf': '23'/'crf': '15'/g\" src/utils/video.py || true",
        "cd /opt/liveportrait && sed -i \"s/'crf': 23/'crf': 15/g\" src/utils/video.py || true",
        # Pretrained Weights  
        "cd /opt/liveportrait && huggingface-cli download KwaiVGI/LivePortrait --local-dir pretrained_weights",
        # Verify FFmpeg verfügbar
        "which ffmpeg && ffmpeg -version | head -1",
        # Force rebuild marker
        "echo 'IMAGE REBUILD V12 - full clean rebuild - '$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    )
)

@app.function(
    image=image,
    gpu="T4",
    timeout=600,
    secrets=[modal.Secret.from_name("firebase-credentials")],
)
def generate_dynamics(avatar_id: str, dynamics_id: str, parameters: dict):
    """
    1:1 KOPIE von backend/generate_dynamics_endpoint.py
    Generiere Dynamics für einen Avatar
    
    Args:
        avatar_id: Firestore avatar document ID
        dynamics_id: Name der Dynamics (z.B. 'basic', 'lachen')
        parameters: Dict mit driving_multiplier, scale, source_max_dim
    """
    import firebase_admin
    from firebase_admin import credentials, storage, firestore
    import requests
    from huggingface_hub import snapshot_download
    # Sicherstellen, dass die LivePortrait-Weights vollständig vorhanden sind
    def _ensure_lp_weights(force: bool = False) -> None:
        weights_dir = "/opt/liveportrait/pretrained_weights"
        try:
            os.makedirs(weights_dir, exist_ok=True)
            # Prüfe grob, ob genügend .pth Dateien vorhanden sind und nicht 0 Bytes groß
            pth_files: List[Path] = list(Path(weights_dir).rglob("*.pth"))
            ok = (len(pth_files) >= 5) and all(f.stat().st_size > 1024 for f in pth_files)
            if force or not ok:
                print("⬇️ Lade/prüfe LivePortrait Weights von HuggingFace…")
                snapshot_download(
                    repo_id="KwaiVGI/LivePortrait",
                    local_dir=weights_dir,
                    local_dir_use_symlinks=False,
                    allow_patterns=["pretrained_weights/*"],
                    resume_download=True,
                )
        except Exception as e:
            print(f"⚠️ Konnte Weights nicht verifizieren/laden: {e}")
    
    # Firebase initialisieren (Modal: aus Secret, lokal: aus File)
    if not firebase_admin._apps:
        cred_json = os.getenv("FIREBASE_CREDENTIALS")
        if cred_json:
            cred_dict = json.loads(cred_json)
            cred = credentials.Certificate(cred_dict)
        else:
            cred = None
        
        firebase_admin.initialize_app(cred, {
            'storageBucket': 'sunriza26.firebasestorage.app'
        })
    
    bucket = storage.bucket()
    db = firestore.client()
    
    print(f"🎭 Generiere Dynamics '{dynamics_id}' für Avatar {avatar_id}")
    
    # 1. Avatar-Daten laden
    avatar_ref = db.collection('avatars').document(avatar_id)
    avatar_doc = avatar_ref.get()
    
    if not avatar_doc.exists:
        raise Exception(f"Avatar {avatar_id} nicht gefunden")
    
    avatar_data = avatar_doc.to_dict()
    
    # Hilfsfunktion: Parameter normalisieren (camelCase ➜ snake_case) und Defaults setzen
    def _norm_params(p: dict) -> dict:
        p = p or {}
        m = {
            'drivingMultiplier': 'driving_multiplier',
            'normalizeLip': 'flag_normalize_lip',
            'flagNormalizeLip': 'flag_normalize_lip',
            'pasteback': 'flag_pasteback',
            'flagPasteback': 'flag_pasteback',
            'animationRegion': 'animation_region',
            'sourceMaxDim': 'source_max_dim',
            'source_maxdim': 'source_max_dim',
        }
        out = {}
        for k, v in p.items():
            key = m.get(k, k)
            out[key] = v
        # Defaults wie lokal
        out.setdefault('driving_multiplier', 0.41)
        out.setdefault('flag_normalize_lip', True)
        out.setdefault('flag_pasteback', True)
        out.setdefault('animation_region', 'all')
        out.setdefault('source_max_dim', 1600)
        out.setdefault('scale', 1.7)
        return out

    # 2. Hero-Image & Hero-Video laden
    hero_image_url = avatar_data.get('avatarImageUrl')
    hero_video_url = avatar_data.get('training', {}).get('heroVideoUrl')
    
    if not hero_image_url or not hero_video_url:
        raise Exception("Hero-Image oder Hero-Video fehlt")
    
    # 3. Assets herunterladen
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
    
    # 4. Video trimmen (10 Sekunden) - EXAKT wie lokal!
    trimmed_video_path = f'/tmp/{avatar_id}_trimmed.mp4'
    print(f"✂️ Trimme Video auf 10 Sekunden...")
    
    # Zeige Input-Größen
    hero_video_size = os.path.getsize(hero_video_path)
    hero_image_size = os.path.getsize(hero_image_path)
    print(f"📊 Hero-Video: {hero_video_size / 1024 / 1024:.2f} MB")
    print(f"📊 Hero-Image: {hero_image_size / 1024:.2f} KB")
    
    trim_cmd = [
        FFMPEG_BIN, '-i', hero_video_path,
        '-ss', '0', '-t', '10',
        '-c:v', 'copy', '-y', trimmed_video_path
    ]
    result = subprocess.run(trim_cmd, capture_output=True)
    if result.returncode != 0:
        print(f"❌ Trimmen fehlgeschlagen!")
        sys.exit(1)
    
    # Zeige getrimte Video-Größe
    trimmed_size = os.path.getsize(trimmed_video_path)
    print(f"📊 Getrimtes Video: {trimmed_size / 1024 / 1024:.2f} MB")
    
    # 5. LivePortrait starten
    print(f"🎬 Starte LivePortrait...")
    
    lp_output_dir = f'/tmp/{avatar_id}_lp_output'
    os.makedirs(lp_output_dir, exist_ok=True)
    
    # Modal: LivePortrait in /opt/liveportrait installiert
    python_executable = sys.executable
    liveportrait_path = '/opt/liveportrait/inference.py'
    
    norm = _norm_params(parameters)
    lp_cmd = [
        python_executable,
        liveportrait_path,
        '-s', hero_image_path,
        '-d', trimmed_video_path,
        '-o', lp_output_dir,
        '--driving_multiplier', str(norm.get('driving_multiplier')),
    ]
    
    # Flags in EXAKT derselben Reihenfolge wie lokaler Test!
    if bool(norm.get('flag_normalize_lip')):
        lp_cmd.append('--flag-normalize-lip')
    
    lp_cmd.extend([
        '--animation-region', str(norm.get('animation_region')),
    ])
    
    if bool(norm.get('flag_pasteback')):
        lp_cmd.append('--flag-pasteback')
    
    lp_cmd.extend([
        '--source-max-dim', str(norm.get('source_max_dim')),
        '--scale', str(norm.get('scale')),
    ])
    
    env = os.environ.copy()
    env['PYTORCH_ENABLE_MPS_FALLBACK'] = '1'
    
    # EXAKT wie lokaler Test: OHNE cwd, OHNE check, nur capture_output=False!
    print(f"🧩 LP-Parameter (normalisiert): {norm}")
    print(f"🎬 LivePortrait Command: {' '.join(lp_cmd)}")
    print(f"🎬 Starte LivePortrait Ausführung...")
    
    # WICHTIG: Prüfe ob GPU verfügbar ist!
    import torch
    gpu_available = torch.cuda.is_available()
    gpu_count = torch.cuda.device_count() if gpu_available else 0
    print(f"🔥 GPU verfügbar: {gpu_available} (Anzahl: {gpu_count})")
    if gpu_available:
        print(f"🔥 GPU Name: {torch.cuda.get_device_name(0)}")
    
    # DEBUG: Welches FFmpeg nutzt imageio-ffmpeg?
    import imageio_ffmpeg
    ffmpeg_exe = imageio_ffmpeg.get_ffmpeg_exe()
    ffmpeg_version_result = subprocess.run([ffmpeg_exe, '-version'], capture_output=True, text=True)
    print(f"🎬 imageio-ffmpeg nutzt: {ffmpeg_version_result.stdout.split(chr(10))[0]}")
    print(f"🎬 FFmpeg binary path: {ffmpeg_exe}")
    # Für den Re-Encode verwenden wir dieselbe FFmpeg-Binary wie LivePortrait (keine Mischversionen)
    ENCODE_FFMPEG_BIN = ffmpeg_exe if os.path.exists(ffmpeg_exe) else FFMPEG_BIN
    print(f"🎬 Encode FFmpeg gewählt: {ENCODE_FFMPEG_BIN}")
    
    import time
    start_time = time.time()
    
    # Weights verifizieren (vor dem ersten Lauf)
    _ensure_lp_weights(force=False)

    result = subprocess.run(lp_cmd, env=env, capture_output=False, text=True)
    
    elapsed = time.time() - start_time
    print(f"⏱️ LivePortrait dauerte: {elapsed:.1f} Sekunden")
    
    if result.returncode != 0:
        print(f"❌ LivePortrait fehlgeschlagen – versuche Weights neu zu laden und einmal neu zu starten…")
        _ensure_lp_weights(force=True)
        result = subprocess.run(lp_cmd, env=env, capture_output=False, text=True)
        if result.returncode != 0:
            print(f"❌ LivePortrait erneut fehlgeschlagen!")
            sys.exit(1)
    
    print(f"✅ LivePortrait erfolgreich beendet (returncode: {result.returncode})")
    
    # 6. Output-Video finden – PRODUKTIONS-VERSION (ohne Vergleichspanels!)
    # LivePortrait schreibt u.a.:
    #  - *_trimmed.mp4            ← gewünschtes Produktionsvideo (ohne Audio)
    #  - *_trimmed_with_audio.mp4
    #  - *_trimmed_concat.mp4     ← Seiten-by-Seiten Vergleich (NICHT verwenden!)
    import glob
    candidates = glob.glob(f"{lp_output_dir}/*_trimmed.mp4")
    # Filter aus: keine _with_audio oder _concat
    candidates = [c for c in candidates if ('_with_audio' not in c and '_concat' not in c)]
    
    if not candidates:
        print(f"❌ *_trimmed.mp4 nicht gefunden, prüfe generische .mp4 ohne _concat/_with_audio...")
        all_candidates = glob.glob(f"{lp_output_dir}/*.mp4")
        candidates = [c for c in all_candidates if ('_with_audio' not in c and '_concat' not in c)]
    
    if not candidates:
        print(f"❌ LivePortrait Output nicht gefunden!")
        sys.exit(1)
    
    # Falls mehrere, wähle die größte Datei (robuster gegen Benennungsvarianten)
    lp_output = max(candidates, key=lambda p: os.path.getsize(p))
    print(f"✅ Gefunden (ohne Vergleichspanels): {lp_output}")
    
    # WICHTIG: Zeige LivePortrait Output-Größe VOR FFmpeg!
    lp_size = os.path.getsize(lp_output)
    print(f"📊 LivePortrait Output Größe: {lp_size} bytes ({lp_size / 1024 / 1024:.2f} MB)")
    print(f"📊 LivePortrait Output Pfad: {lp_output}")
    
    # 7. All‑I Re‑Encode mit imageio‑ffmpeg (robust in allen Playern)
    print("🔧 Re-Encode: All‑I, stumm, 29 fps, Faststart, Timescale 90000…")
    temp_final = f'/tmp/{avatar_id}_{dynamics_id}_idle.mp4'
    encode_cmd = [
        ENCODE_FFMPEG_BIN,
        '-y',
        '-fflags', '+genpts',
        '-i', lp_output,
        '-an',                 # Audio entfernen
        '-vf', 'fps=29,setpts=N/(29*TB)',  # harte, saubere Timeline
        '-r', '29',
        '-vsync', 'cfr',
        '-c:v', 'libx264',
        '-preset', 'slow',
        '-crf', '18',
        '-x264opts', 'keyint=1:min-keyint=1:scenecut=0',
        '-movflags', '+faststart',
        '-video_track_timescale', '90000',
        '-pix_fmt', 'yuv420p',
        temp_final,
    ]
    enc_res = subprocess.run(encode_cmd, capture_output=True, text=True)
    if enc_res.returncode != 0:
        print(f"❌ Re-Encode fehlgeschlagen: {enc_res.stderr}")
        sys.exit(1)
    final_output = temp_final
    final_size = os.path.getsize(final_output)
    print(f"✅ Final (All‑I, stumm): {final_output}")
    print(f"📊 Final: {final_size} bytes ({final_size / 1024 / 1024:.2f} MB)")
    
    # DEBUG: Speichere ALLE Zwischenschritte + LivePortrait Outputs!
    print(f"🔍 DEBUG: Speichere ALLE Debug-Dateien nach brain/hilfeLP/...")
    
    # 1. LivePortrait Raw Output (mit Download-Token für klickbaren Link)
    lp_raw_debug = bucket.blob(f"brain/hilfeLP/{avatar_id}/01_liveportrait_raw.mp4")
    lp_raw_token = str(uuid.uuid4())
    lp_raw_debug.metadata = {'firebaseStorageDownloadTokens': lp_raw_token}
    lp_raw_debug.upload_from_filename(lp_output, content_type='video/mp4')
    lp_raw_debug.patch()  # stellt sicher, dass Token in Console erscheint
    lp_raw_size = os.path.getsize(lp_output)
    lp_raw_url = f"https://firebasestorage.googleapis.com/v0/b/{bucket.name}/o/{lp_raw_debug.name.replace('/', '%2F')}?alt=media&token={lp_raw_token}"
    print(f"  📁 01_liveportrait_raw.mp4: VOR Upload: {lp_raw_size / 1024 / 1024:.2f} MB")
    lp_raw_debug.reload()
    print(f"     NACH Upload zu Firebase: {lp_raw_debug.size / 1024 / 1024:.2f} MB")
    print(f"     🌐 URL: {lp_raw_url}")
    
    # 2. Final (idle.mp4 Basis) – mit Download-Token
    final_debug = bucket.blob(f"brain/hilfeLP/{avatar_id}/02_final_idle.mp4")
    final_token = str(uuid.uuid4())
    final_debug.metadata = {'firebaseStorageDownloadTokens': final_token}
    final_debug.upload_from_filename(final_output, content_type='video/mp4')
    final_debug.patch()
    final_size_dbg = os.path.getsize(final_output)
    final_url_dbg = f"https://firebasestorage.googleapis.com/v0/b/{bucket.name}/o/{final_debug.name.replace('/', '%2F')}?alt=media&token={final_token}"
    print(f"  📁 02_final_idle.mp4: VOR Upload: {final_size_dbg / 1024 / 1024:.2f} MB")
    final_debug.reload()
    print(f"     NACH Upload zu Firebase: {final_debug.size / 1024 / 1024:.2f} MB")
    print(f"     🌐 URL: {final_url_dbg}")
    
    # 8. Generiere Atlas/Mask/ROI für Lippen-Sync (NÖTIG für Flutter Chat!)
    print(f"🎨 Generiere Atlas/Mask/ROI...")
    
    from PIL import Image, ImageFilter, ImageDraw
    import math
    
    # Hero-Image laden
    hero_img = Image.open(hero_image_path).convert("RGB")
    W, H = hero_img.size
    
    # ROI berechnen (Mund-Region)
    w = int(W * 0.32)
    h = int(H * 0.18)
    x = int(W * 0.34)
    y = int(H * 0.68)
    roi = {'x': x, 'y': y, 'w': w, 'h': h}
    
    # Maske mit Feathering erstellen
    mask_img = Image.new('L', (w, h), 0)
    mask_draw = ImageDraw.Draw(mask_img)
    mask_draw.rounded_rectangle((0, 0, w-1, h-1), radius=int(min(w, h) * 0.12), fill=255)
    mask_img = mask_img.filter(ImageFilter.GaussianBlur(radius=12))
    
    # Atlas erstellen (Viseme-Zellen)
    visemes = ["Rest", "AI", "E", "U", "O", "MBP", "FV", "L", "WQ", "R", "CH", "TH"]
    mouth = hero_img.crop((x, y, x+w, y+h)).convert("RGBA")
    cols = rows = int(math.ceil(math.sqrt(len(visemes))))
    cell_w, cell_h = w, h
    atlas_img = Image.new("RGBA", (cell_w * cols, cell_h * rows), (0, 0, 0, 0))
    cells = {}
    
    for idx, name in enumerate(visemes):
        cx, cy = idx % cols, idx // cols
        atlas_img.paste(mouth, (cx * cell_w, cy * cell_h))
        cells[name] = {"x": cx * cell_w, "y": cy * cell_h, "w": cell_w, "h": cell_h}
    
    atlas_meta = {
        "grid": {"cols": cols, "rows": rows},
        "classes": visemes,
        "cells": cells,
        "mask": "mask.png",
        "roi": roi
    }
    
    # Assets speichern
    atlas_path = f'/tmp/{avatar_id}_atlas.png'
    mask_path = f'/tmp/{avatar_id}_mask.png'
    atlas_json_path = f'/tmp/{avatar_id}_atlas.json'
    roi_json_path = f'/tmp/{avatar_id}_roi.json'
    
    atlas_img.save(atlas_path)
    mask_img.save(mask_path)
    
    with open(atlas_json_path, 'w') as f:
        json.dump(atlas_meta, f, indent=2)
    with open(roi_json_path, 'w') as f:
        json.dump(roi, f, indent=2)
    
    # 9. ALLE Assets zu Firebase Storage hochladen
    print(f"📤 Uploading ALLE Assets zu Firebase Storage...")
    
    # idle.mp4 (mit Download-Token, damit die Console einen klickbaren Link zeigt)
    idle_blob = bucket.blob(f"avatars/{avatar_id}/dynamics/{dynamics_id}/idle.mp4")
    idle_token = str(uuid.uuid4())
    idle_blob.metadata = {'firebaseStorageDownloadTokens': idle_token}
    idle_blob.upload_from_filename(final_output, content_type='video/mp4')
    idle_blob.patch()
    idle_url = f"https://firebasestorage.googleapis.com/v0/b/{bucket.name}/o/{idle_blob.name.replace('/', '%2F')}?alt=media&token={idle_token}"
    
    # atlas.png
    atlas_blob = bucket.blob(f"avatars/{avatar_id}/dynamics/{dynamics_id}/atlas.png")
    atlas_token = str(uuid.uuid4())
    atlas_blob.metadata = {'firebaseStorageDownloadTokens': atlas_token}
    atlas_blob.upload_from_filename(atlas_path, content_type='image/png')
    atlas_blob.patch()
    atlas_url = f"https://firebasestorage.googleapis.com/v0/b/{bucket.name}/o/{atlas_blob.name.replace('/', '%2F')}?alt=media&token={atlas_token}"
    
    # mask.png
    mask_blob = bucket.blob(f"avatars/{avatar_id}/dynamics/{dynamics_id}/mask.png")
    mask_token = str(uuid.uuid4())
    mask_blob.metadata = {'firebaseStorageDownloadTokens': mask_token}
    mask_blob.upload_from_filename(mask_path, content_type='image/png')
    mask_blob.patch()
    mask_url = f"https://firebasestorage.googleapis.com/v0/b/{bucket.name}/o/{mask_blob.name.replace('/', '%2F')}?alt=media&token={mask_token}"
    
    # atlas.json
    atlas_json_blob = bucket.blob(f"avatars/{avatar_id}/dynamics/{dynamics_id}/atlas.json")
    atlas_json_token = str(uuid.uuid4())
    atlas_json_blob.metadata = {'firebaseStorageDownloadTokens': atlas_json_token}
    atlas_json_blob.upload_from_filename(atlas_json_path, content_type='application/json')
    atlas_json_blob.patch()
    atlas_json_url = f"https://firebasestorage.googleapis.com/v0/b/{bucket.name}/o/{atlas_json_blob.name.replace('/', '%2F')}?alt=media&token={atlas_json_token}"
    
    # roi.json
    roi_json_blob = bucket.blob(f"avatars/{avatar_id}/dynamics/{dynamics_id}/roi.json")
    roi_json_token = str(uuid.uuid4())
    roi_json_blob.metadata = {'firebaseStorageDownloadTokens': roi_json_token}
    roi_json_blob.upload_from_filename(roi_json_path, content_type='application/json')
    roi_json_blob.patch()
    roi_json_url = f"https://firebasestorage.googleapis.com/v0/b/{bucket.name}/o/{roi_json_blob.name.replace('/', '%2F')}?alt=media&token={roi_json_token}"
    
    print(f"✅ Uploaded ALLE Assets!")
    
    # 10. Firestore aktualisieren
    print(f"💾 Updating Firestore...")
    
    dynamics_data = {
        'idleVideoUrl': idle_url,
        'atlasUrl': atlas_url,
        'maskUrl': mask_url,
        'atlasJsonUrl': atlas_json_url,
        'roiJsonUrl': roi_json_url,
        'parameters': parameters,
        'generatedAt': datetime.utcnow(),
        'status': 'ready'
    }
    
    avatar_ref.update({
        f'dynamics.{dynamics_id}': dynamics_data
    })
    
    print(f"🎉 Dynamics '{dynamics_id}' erfolgreich generiert!")
    
    return {
        'status': 'success',  # Flutter erwartet 'success'!
        'video_url': idle_url,  # Flutter erwartet 'video_url'!
        'avatar_id': avatar_id,
        'dynamics_id': dynamics_id,
        'idle_url': idle_url,  # Für Kompatibilität
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
        
        result = generate_dynamics.remote(avatar_id, dynamics_id, parameters)
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
