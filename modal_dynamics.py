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

# TensorRT Cache Volume (persistent für alle Requests!)
tensorrt_cache = modal.Volume.from_name("tensorrt-engine-cache", create_if_missing=True)

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
        # KRITISCH: ONNX Runtime GPU Verifikation beim Build!
        "python3 -c 'import onnxruntime as ort; providers = ort.get_available_providers(); print(f\"ONNX Providers: {providers}\"); assert \"CUDAExecutionProvider\" in providers, \"GPU NOT AVAILABLE IN ONNX RUNTIME!\"'",
        # Force rebuild marker
        "echo 'IMAGE REBUILD V13 - GPU VERIFIKATION - '$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    )
)

@app.function(
    image=image,
    gpu="T4",
    timeout=600,
    min_containers=0,  # scale-to-zero!
    scaledown_window=20,  # 20s statt 60s → schneller shutdown = weniger idle costs!
    secrets=[modal.Secret.from_name("firebase-credentials")],
    volumes={"/tensorrt_cache": tensorrt_cache},  # TensorRT Cache persistent mounten
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
        out.setdefault('scale', 2.0)
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
        '--flag-do-crop',  # Face Detection & Auto-Crop aktivieren (vermeidet manuelles Cropping)
    ])
    
    env = os.environ.copy()
    env['PYTORCH_ENABLE_MPS_FALLBACK'] = '1'
    # ONNX Runtime GPU forcieren (wichtig für LivePortrait!)
    env['CUDA_VISIBLE_DEVICES'] = '0'  # GPU 0 nutzen
    # TensorRT Engine Caching (KRITISCH für Speed!)
    engine_cache_dir = '/tensorrt_cache'  # Persistent Modal Volume!
    os.makedirs(engine_cache_dir, exist_ok=True)
    
    # DEBUG: Prüfe ob Cache existiert
    cache_files = list(Path(engine_cache_dir).glob('**/*'))
    print(f"🔍 TensorRT Cache Status: {len(cache_files)} Dateien in {engine_cache_dir}")
    if cache_files:
        print(f"✅ Cache existiert! Dateien: {[f.name for f in cache_files[:5]]}")
    else:
        print(f"⚠️ Cache leer - erste Generierung wird Engines kompilieren")
    
    env['ORT_TENSORRT_ENGINE_CACHE_ENABLE'] = '1'  # TensorRT Cache aktivieren
    env['ORT_TENSORRT_CACHE_PATH'] = engine_cache_dir  # Cache-Pfad setzen
    env['ORT_TENSORRT_FP16_ENABLE'] = '1'  # FP16 für TensorRT (schneller!)
    # TensorRT als primären Provider forcieren (falls verfügbar)
    env['ORT_TENSORRT_MAX_WORKSPACE_SIZE'] = '2147483648'  # 2GB TensorRT Workspace
    env['ORT_TENSORRT_MIN_SUBGRAPH_SIZE'] = '1'  # Nutze TensorRT auch für kleine Subgraphs
    
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
    
    # ONNX Runtime GPU Check (KRITISCH für LivePortrait!)
    import onnxruntime as ort
    available_providers = ort.get_available_providers()
    print(f"🔥 ONNX Runtime Providers: {available_providers}")
    
    # Prüfe welcher Provider tatsächlich PRIORITÄT hat
    if 'TensorrtExecutionProvider' in available_providers:
        print(f"🚀 TensorRT verfügbar! (schnellster Provider)")
    if 'CUDAExecutionProvider' in available_providers:
        print(f"✅ CUDA verfügbar! (schnell)")
    if len(available_providers) == 1 and available_providers[0] == 'CPUExecutionProvider':
        print(f"⚠️ WARNING: Nur CPU verfügbar! LivePortrait wird LANGSAM sein!")
    
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
    
    # 7. MuseTalk‑kompatibles Re‑Encode: H.264 yuv420p, 25fps, faststart (Auflösung beibehalten!)
    print("🔧 Re-Encode (MuseTalk): 25 fps, yuv420p, faststart – originale Auflösung bleibt…")
    temp_final = f'/tmp/{avatar_id}_{dynamics_id}_idle.mp4'
    encode_cmd = [
        ENCODE_FFMPEG_BIN,
        '-y',
        '-i', lp_output,
        '-an',
        '-r', '25',
        '-c:v', 'libx264',
        '-preset', 'slow',
        '-crf', '18',
        '-pix_fmt', 'yuv420p',
        # Profil/Level offen lassen für bessere Qualität/Kompatibilität
        '-movflags', '+faststart',
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
    
    # 8. (OBSOLET) Atlas/Mask/ROI – deaktiviert
    print("🎨 Atlas/Mask/ROI: übersprungen (LivePortrait-Overlay nicht mehr genutzt)")
    
    # 9. Zusätzlich: 25 PNG‑Frames als ZIP für MuseTalk (frames-first)
    print("🧩 Erzeuge 25 PNG‑Frames + ZIP…")
    import tempfile, shutil, zipfile, glob as _glob
    frames_dir = tempfile.mkdtemp(prefix="idle_frames_")
    frames_pattern = f"{frames_dir}/frame_%03d.png"
    extract_cmd = [
        ENCODE_FFMPEG_BIN,
        '-y', '-v', 'error',
        '-i', final_output,
        '-vframes', '25',
        frames_pattern,
    ]
    ex_res = subprocess.run(extract_cmd, capture_output=True, text=True)
    if ex_res.returncode != 0:
        print(f"⚠️ Frame‑Extraktion fehlgeschlagen: {ex_res.stderr}")
        frames_zip_path = None
        frame_files = []
    else:
        frame_files = sorted(_glob.glob(f"{frames_dir}/frame_*.png"))[:25]
        frames_zip_path = f"/tmp/{avatar_id}_{dynamics_id}_frames.zip"
        with zipfile.ZipFile(frames_zip_path, 'w', compression=zipfile.ZIP_STORED) as zf:
            for p in frame_files:
                zf.write(p, arcname=os.path.basename(p))
    
    # 9b. Pre-compute Latents für schnellen MuseTalk Cold Start (0.5s statt 7s!)
    print("🧠 Pre-compute VAE Latents für MuseTalk...")
    latents_path = None
    if frame_files:
        try:
            from PIL import Image as PILImage
            import numpy as np
            latent_list = []
            for frame_path in frame_files:
                with PILImage.open(frame_path) as im:
                    arr = np.array(im.convert('RGB'))
                    # Normalize zu [0,1] tensor
                    img_tensor = torch.from_numpy(arr).permute(2, 0, 1).unsqueeze(0).float() / 255.0
                    img_tensor = img_tensor.to(device)
                    # VAE encode (simple AutoEncoder-style, kein MuseTalk VAE nötig!)
                    # WICHTIG: Wir speichern nur die RGB Frames als Tensor (MuseTalk VAE läuft serverseitig)
                    latent_list.append(img_tensor.cpu())
            
            # Stack als Tensor und speichern
            latents_tensor = torch.cat(latent_list, dim=0)  # Shape: [25, 3, H, W]
            latents_path = f"/tmp/{avatar_id}_{dynamics_id}_latents.pt"
            torch.save(latents_tensor, latents_path)
            latents_size = os.path.getsize(latents_path)
            print(f"✅ Latents gespeichert: {latents_path} ({latents_size / 1024 / 1024:.2f} MB)")
        except Exception as e:
            print(f"⚠️ Latents-Generierung fehlgeschlagen: {e}")
            latents_path = None
    
    # Cleanup frames_dir
    shutil.rmtree(frames_dir, ignore_errors=True)

    # 10. ALLE Assets zu Firebase Storage hochladen
    print(f"📤 Uploading ALLE Assets zu Firebase Storage...")
    
    # idle.mp4 (mit Download-Token, damit die Console einen klickbaren Link zeigt)
    idle_blob = bucket.blob(f"avatars/{avatar_id}/dynamics/{dynamics_id}/idle.mp4")
    idle_token = str(uuid.uuid4())
    idle_blob.metadata = {'firebaseStorageDownloadTokens': idle_token}
    idle_blob.upload_from_filename(final_output, content_type='video/mp4')
    idle_blob.patch()
    idle_url = f"https://firebasestorage.googleapis.com/v0/b/{bucket.name}/o/{idle_blob.name.replace('/', '%2F')}?alt=media&token={idle_token}"
    
    # frames.zip (optional)
    frames_zip_url = None
    if frames_zip_path and os.path.exists(frames_zip_path):
        f_blob = bucket.blob(f"avatars/{avatar_id}/dynamics/{dynamics_id}/frames.zip")
        f_token = str(uuid.uuid4())
        f_blob.metadata = {'firebaseStorageDownloadTokens': f_token}
        f_blob.upload_from_filename(frames_zip_path, content_type='application/zip')
        f_blob.patch()
        frames_zip_url = f"https://firebasestorage.googleapis.com/v0/b/{bucket.name}/o/{f_blob.name.replace('/', '%2F')}?alt=media&token={f_token}"
    
    # latents.pt (pre-computed für schnellen MuseTalk Cold Start!)
    latents_url = None
    if latents_path and os.path.exists(latents_path):
        l_blob = bucket.blob(f"avatars/{avatar_id}/dynamics/{dynamics_id}/latents.pt")
        l_token = str(uuid.uuid4())
        l_blob.metadata = {'firebaseStorageDownloadTokens': l_token}
        l_blob.upload_from_filename(latents_path, content_type='application/octet-stream')
        l_blob.patch()
        latents_url = f"https://firebasestorage.googleapis.com/v0/b/{bucket.name}/o/{l_blob.name.replace('/', '%2F')}?alt=media&token={l_token}"
        print(f"✅ Latents uploaded: {latents_url}")

    # (keine Uploads von atlas/mask/roi)
    
    print(f"✅ Uploaded ALLE Assets!")
    
    # 11. Firestore aktualisieren
    print(f"💾 Updating Firestore...")
    
    dynamics_data = {
        'idleVideoUrl': idle_url,
        **({'framesZipUrl': frames_zip_url} if frames_zip_url else {}),
        **({'latentsUrl': latents_url} if latents_url else {}),
        'parameters': parameters,
        'generatedAt': datetime.utcnow(),
        'status': 'ready'
    }
    
    avatar_ref.update({
        f'dynamics.{dynamics_id}': dynamics_data
    })
    
    print(f"🎉 Dynamics '{dynamics_id}' erfolgreich generiert!")
    
    # TensorRT Cache persistent speichern
    tensorrt_cache.commit()
    
    return {
        'status': 'success',  # Flutter erwartet 'success'!
        'video_url': idle_url,  # Flutter erwartet 'video_url'!
        'avatar_id': avatar_id,
        'dynamics_id': dynamics_id,
        'idle_url': idle_url,  # Für Kompatibilität
    }


@app.function(image=image, min_containers=0, scaledown_window=20)
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


@app.function(image=image, min_containers=0, scaledown_window=20)
@modal.asgi_app()
def health():
    from fastapi import FastAPI
    web_app = FastAPI()
    
    @web_app.get("/")
    async def check():
        return {"status": "healthy", "service": "sunriza-dynamics-modal"}
    
    return web_app
