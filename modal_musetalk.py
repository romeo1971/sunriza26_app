#!/usr/bin/env python3
"""
MuseTalk Real-Time Lipsync Service auf Modal
Basierend auf: github.com/TMElyralab/MuseTalk
"""

import modal
import os

# GPU Image mit MuseTalk
image = (
    modal.Image.debian_slim(python_version="3.10")
    .apt_install(
        "git",
        "ffmpeg",
        "curl",
        "libgl1-mesa-glx",
        "libglib2.0-0",
        "libsm6",
        "libxext6",
        "libxrender-dev",
    )
    .pip_install(
        "torch==2.0.1",
        "torchvision==0.15.2",
        "torchaudio==2.0.2",
        extra_index_url="https://download.pytorch.org/whl/cu118",
    )
    .pip_install(
        "numpy==1.23.5",
        "diffusers==0.30.2",
        "accelerate==0.28.0",
        "tensorflow==2.12.0",
        "tensorboard==2.12.0",
        "opencv-python-headless==4.9.0.80",
        "soundfile==0.12.1",
        "transformers==4.39.2",
        "huggingface_hub==0.30.2",
        "librosa==0.11.0",
        "einops==0.8.1",
        "omegaconf",
        "ffmpeg-python",
        "moviepy",
        "imageio[ffmpeg]",
        "Pillow",
        "requests",
        "mmdet",
        "mmcv==2.1.0",
        "mmengine",
        "mmpose",
        "fastapi",
        "uvicorn",
        "websockets",
        "livekit",
        "livekit-api",
        "gdown",
    )
    .run_commands(
        "cd /root && git clone https://github.com/TMElyralab/MuseTalk.git",
        "cd /root/MuseTalk && bash download_weights.sh",
            # Inferenz-Config mit unet_config aus dem Repo sicherstellen
            "mkdir -p /root/MuseTalk/configs/inference",
            "FOUND=$(grep -R -l -E 'unet_config\\s*:' /root/MuseTalk/configs || true); if [ -n \"$FOUND\" ]; then cp $FOUND /root/MuseTalk/configs/inference/test.yaml; fi",
            # Sicherstellen: sd-vae-ft-mse (Diffusers-Format) liegt lokal vor (config.json + weights)
            "mkdir -p /root/MuseTalk/models/sd-vae-ft-mse",
            "curl -L https://huggingface.co/stabilityai/sd-vae-ft-mse/resolve/main/config.json -o /root/MuseTalk/models/sd-vae-ft-mse/config.json || true",
            "curl -L https://huggingface.co/stabilityai/sd-vae-ft-mse/resolve/main/diffusion_pytorch_model.safetensors -o /root/MuseTalk/models/sd-vae-ft-mse/diffusion_pytorch_model.safetensors || true",
            # Falls oben nichts gefunden wurde, versuche offizielle test.yaml
            "[ -f /root/MuseTalk/configs/inference/test.yaml ] || curl -L https://raw.githubusercontent.com/TMElyralab/MuseTalk/main/configs/inference/test.yaml -o /root/MuseTalk/configs/inference/test.yaml || true",
    )
)

app = modal.App("musetalk-lipsync", image=image)


@app.function(
    gpu="T4",  # Tesla T4 für 30 FPS
    timeout=30,  # 30s idle → dann shutdown
    min_containers=0,  # scale-to-zero!
    scaledown_window=30,  # 30s statt 180s → schneller shutdown = weniger idle costs!
    secrets=[
        modal.Secret.from_name("livekit-cloud"),
    ],
)
@modal.asgi_app()
def asgi():
    """
    MuseTalk Real-Time ASGI Service
    """
    import sys
    import os
    os.chdir("/root/MuseTalk")
    sys.path.insert(0, "/root/MuseTalk")
    
    from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Request
    from fastapi.responses import JSONResponse
    import asyncio
    import json
    import base64
    import numpy as np
    from PIL import Image
    from io import BytesIO
    import torch
    from livekit import rtc, api
    import logging
    
    # MuseTalk imports
    from musetalk.utils.utils import get_file_type, get_video_fps, datagen
    from musetalk.utils.preprocessing import get_landmark_and_bbox, read_imgs, coord_placeholder
    from musetalk.utils.blending import get_image
    from musetalk.models.vae import VAE
    from musetalk.models.unet import UNet
    from omegaconf import OmegaConf
    
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)
    
    fastapi_app = FastAPI(title="MuseTalk Real-Time Lipsync")
    
    # Global model instances (loaded once)
    vae = None
    unet = None
    pe = None
    device = "cuda" if torch.cuda.is_available() else "cpu"
    
    # Helper: VAE encode/decode kompatibel zu unterschiedlichen Wrappern
    def vae_encode_to_latent(vae_obj, tensor):
        out = None
        try:
            out = vae_obj.encode(tensor)
        except Exception:
            try:
                inner = getattr(vae_obj, 'vae', None)
                if inner is not None:
                    out = inner.encode(tensor)
            except Exception:
                out = None
        if out is None:
            raise RuntimeError("VAE.encode not available")
        return out.latent_dist.sample() if hasattr(out, 'latent_dist') else out

    def vae_decode_to_image(vae_obj, latent):
        out = None
        try:
            out = vae_obj.decode(latent)
        except Exception:
            try:
                inner = getattr(vae_obj, 'vae', None)
                if inner is not None:
                    out = inner.decode(latent)
            except Exception:
                out = None
        if out is None:
            raise RuntimeError("VAE.decode not available")
        return out.sample if hasattr(out, 'sample') else out

    def decode_pcm_to_float32(audio_bytes):
        """Akzeptiert int16 oder float32 PCM (mono). Gibt float32 [-1,1] zurück."""
        import numpy as _np
        b = audio_bytes
        n = len(b)
        audio = None
        # Versuch float32
        if n % 4 == 0:
            try:
                a32 = _np.frombuffer(b, dtype=_np.float32)
                if _np.isfinite(a32).all() and _np.percentile(_np.abs(a32), 99) <= 10.0:
                    audio = a32
            except Exception:
                audio = None
        # Fallback int16
        if audio is None:
            try:
                usable = n - (n % 2)
                audio = _np.frombuffer(b[:usable], dtype=_np.int16).astype(_np.float32) / 32768.0
            except Exception:
                audio = _np.zeros(0, dtype=_np.float32)
        if audio.size:
            audio = _np.clip(audio, -1.0, 1.0)
        return audio.astype(_np.float32, copy=False)
    
    async def load_models():
        """Load MuseTalk models"""
        nonlocal vae, unet, pe, device
        
        if vae is not None:
            return
        
        logger.info("Loading MuseTalk models...")
        
        try:
            # Deterministische Inferenz-Config aus dem Repo
            import os as _os
            from omegaconf import OmegaConf as _OC
            used_cfg_path = "/root/MuseTalk/configs/inference/test.yaml"
            if not _os.path.exists(used_cfg_path):
                raise RuntimeError(f"Missing inference config: {used_cfg_path}")
            config = _OC.load(used_cfg_path)
            logger.info(f"Using config: {used_cfg_path}")
            
            # Load VAE (MuseTalk lädt interne Gewichte/Config selbst)
            vae = VAE()
            # Sicher auf Device bringen, ohne auf .to bei Wrapper zu bestehen
            try:
                if hasattr(vae, 'vae') and hasattr(vae.vae, 'to'):
                    vae.vae = vae.vae.to(device)
                    if hasattr(vae.vae, 'eval'):
                        vae.vae.eval()
                elif hasattr(vae, 'to'):
                    vae = vae.to(device)
                    if hasattr(vae, 'eval'):
                        vae.eval()
            except Exception:
                pass
            
            # Load UNet aus musetalk.json (v1.5) bzw. v1.0 Fallback
            unet_path = "/root/MuseTalk/models/musetalkV15/unet.pth"
            unet_cfg_json = "/root/MuseTalk/models/musetalkV15/musetalk.json"
            if not _os.path.exists(unet_cfg_json):
                # v1.0 Fallback
                unet_cfg_json = "/root/MuseTalk/models/musetalk/musetalk.json"
                if _os.path.exists("/root/MuseTalk/models/musetalk/pytorch_model.bin"):
                    unet_path = "/root/MuseTalk/models/musetalk/pytorch_model.bin"
            if not _os.path.exists(unet_path):
                raise RuntimeError(f"Missing UNet weights: {unet_path}")
            if not _os.path.exists(unet_cfg_json):
                raise RuntimeError(f"Missing UNet config JSON: {unet_cfg_json}")
            # Wichtig: UNet erwartet den Pfad (str) zur JSON, nicht das geladene Dict
            unet = UNet(unet_config=unet_cfg_json, model_path=unet_path)
            # Robust auf Device bringen
            try:
                if hasattr(unet, 'to'):
                    unet = unet.to(device)
                    if hasattr(unet, 'eval'):
                        unet.eval()
                elif hasattr(unet, 'model') and hasattr(unet.model, 'to'):
                    unet.model = unet.model.to(device)
                    if hasattr(unet.model, 'eval'):
                        unet.model.eval()
            except Exception:
                pass
            
            # Position encoding (robust, falls coord_placeholder kein Callable ist)
            try:
                cp = coord_placeholder(256) if callable(coord_placeholder) else coord_placeholder
            except Exception:
                cp = coord_placeholder
            try:
                pe = cp.to(device)
            except Exception:
                pe = torch.as_tensor(cp, device=device)
            
            logger.info("✅ MuseTalk models loaded")
            
        except Exception as e:
            logger.error(f"❌ Model loading failed: {e}")
            raise
    
    # Active sessions (room → session data)
    active_sessions = {}
    
    class MuseTalkSession:
        """Real-time MuseTalk session"""
        
        def __init__(self, room_name: str, video_b64: str = "", preprocessed_latents=None):
            self.room_name = room_name
            self.running = False
            self.livekit_room = None
            self.video_source = None
            self.ffmpeg_proc = None
            
            # Store model references
            self.vae = vae
            self.unet = unet
            self.pe = pe
            self.device = device
            
            # Wenn Latents bereits vorhanden sind, Preprocessing überspringen
            if preprocessed_latents is not None:
                self.input_latents = preprocessed_latents
                self.latent_idx = 0
                self.video_path = None
                logger.info(f"Using preprocessed latents: {self.input_latents.shape}")
                return
            
            # Decode video
            video_bytes = base64.b64decode(video_b64)
            # Save temporarily
            import tempfile
            self.video_path = tempfile.NamedTemporaryFile(suffix=".mp4", delete=False).name
            with open(self.video_path, "wb") as f:
                f.write(video_bytes)
            
            # Normalize video for robust decoding (H.264, yuv420p, CFR 25, faststart)
            try:
                import subprocess, tempfile
                norm_path = tempfile.NamedTemporaryFile(suffix=".mp4", delete=False).name
                cmd = [
                    "ffmpeg", "-v", "error",
                    "-y", "-i", self.video_path,
                    "-an",
                    "-r", "25",
                    "-c:v", "libx264",
                    "-pix_fmt", "yuv420p",
                    "-movflags", "+faststart",
                    norm_path,
                ]
                subprocess.run(cmd, check=True)
                self.video_path = norm_path
                logger.info(f"Video normalized for decoding: {self.video_path}")
            except Exception as e:
                logger.warning(f"Video normalization failed (using original): {e}")
            
            # Preprocess video
            self.frames = None
            self.coords = None
            self.preprocess_video()
        
        def preprocess_video(self):
            """Preprocess idle video → encode to latents"""
            logger.info(f"Preprocessing video: {self.video_path}")
            
            # Read video frames
            input_imgs = read_imgs(self.video_path)
            # Fallback, falls der interne Reader None/leer liefert
            if not input_imgs or len(input_imgs) == 0:
                try:
                    import imageio
                    rdr = imageio.get_reader(self.video_path)
                    tmp = []
                    for i, frame in enumerate(rdr):
                        if i >= 25:
                            break
                        tmp.append(frame)
                    input_imgs = tmp
                    logger.info(f"Fallback reader: {len(input_imgs)} frames")
                except Exception as e:
                    logger.error(f"Video read failed: {e}")
                    input_imgs = []
            if not input_imgs:
                # Zweiter Fallback: OpenCV
                try:
                    import cv2
                    cap = cv2.VideoCapture(self.video_path)
                    tmp = []
                    i = 0
                    while i < 25 and cap.isOpened():
                        ok, frame = cap.read()
                        if not ok:
                            break
                        frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                        tmp.append(frame)
                        i += 1
                    cap.release()
                    input_imgs = tmp
                    logger.info(f"Fallback OpenCV: {len(input_imgs)} frames")
                except Exception as e:
                    logger.error(f"Video read failed (opencv): {e}")
                    input_imgs = []
            if not input_imgs:
                # Zweiter Fallback: OpenCV
                try:
                    import cv2
                    cap = cv2.VideoCapture(self.video_path)
                    tmp = []
                    i = 0
                    while i < 25 and cap.isOpened():
                        ok, frame = cap.read()
                        if not ok:
                            break
                        frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                        tmp.append(frame)
                        i += 1
                    cap.release()
                    input_imgs = tmp
                    logger.info(f"Fallback OpenCV: {len(input_imgs)} frames")
                except Exception as e:
                    logger.error(f"Video read failed (opencv): {e}")
                    input_imgs = []
            if not input_imgs:
                # Dritter Fallback: ffmpeg → PNG Frames
                try:
                    import tempfile, shutil, subprocess
                    from PIL import Image as _PILImage
                    import numpy as _np
                    tmpdir = tempfile.mkdtemp(prefix="mt_frames_")
                    outpat = f"{tmpdir}/frame_%03d.png"
                    cmd = [
                        "ffmpeg", "-v", "error",
                        "-y", "-i", self.video_path,
                        "-vframes", "25",
                        outpat,
                    ]
                    subprocess.run(cmd, check=True)
                    files = sorted([f for f in os.listdir(tmpdir) if f.endswith('.png')])
                    frames = []
                    for f in files[:25]:
                        p = os.path.join(tmpdir, f)
                        with _PILImage.open(p) as im:
                            frames.append(_np.array(im.convert('RGB')))
                    input_imgs = frames
                    shutil.rmtree(tmpdir, ignore_errors=True)
                    logger.info(f"Fallback ffmpeg: {len(input_imgs)} frames")
                except Exception as e:
                    logger.error(f"Video read failed (ffmpeg): {e}")
                    input_imgs = []
            if not input_imgs:
                # Vierter Fallback: moviepy
                try:
                    from moviepy.editor import VideoFileClip
                    import numpy as _np
                    clip = VideoFileClip(self.video_path, audio=False)
                    frames = []
                    for i, frame in enumerate(clip.iter_frames(fps=25, dtype="uint8")):
                        if i >= 25:
                            break
                        frames.append(frame)
                    clip.close()
                    input_imgs = frames
                    logger.info(f"Fallback moviepy: {len(input_imgs)} frames")
                except Exception as e:
                    logger.error(f"Video read failed (moviepy): {e}")
                    input_imgs = []
            if not input_imgs:
                # Fünfter Fallback: ffmpeg → pipe
                try:
                    import subprocess, tempfile, numpy as _np
                    from PIL import Image as _PILImage
                    tmpdir = tempfile.mkdtemp(prefix="mt_pipe_")
                    outpat = f"{tmpdir}/pipe_%03d.png"
                    cmd = [
                        "ffmpeg", "-v", "error",
                        "-y", "-i", self.video_path,
                        "-vf", "fps=25,format=rgb24",
                        "-vframes", "25",
                        outpat,
                    ]
                    subprocess.run(cmd, check=True)
                    files = sorted([f for f in os.listdir(tmpdir) if f.endswith('.png')])
                    frames = []
                    for f in files[:25]:
                        p = os.path.join(tmpdir, f)
                        with _PILImage.open(p) as im:
                            frames.append(_np.array(im.convert('RGB')))
                    input_imgs = frames
                    logger.info(f"Fallback ffmpeg pipe: {len(input_imgs)} frames")
                except Exception as e:
                    logger.error(f"Video read failed (ffmpeg pipe): {e}")
                    input_imgs = []
            if not input_imgs:
                raise RuntimeError("No frames decoded from idle video")
            # Null-Frames entfernen
            input_imgs = [f for f in input_imgs if f is not None]
            if not input_imgs:
                raise RuntimeError("Decoded frames are empty/None")
            
            # Get landmarks and bbox from first frame
            try:
                self.coords = get_landmark_and_bbox(input_imgs[0])
            except Exception as e:
                logger.warning(f"Landmarks failed: {e} (continuing without coords)")
                self.coords = None
            
            # Encode frames to latents with VAE
            logger.info("Encoding frames to latents...")
            latent_list = []
            for img in input_imgs[:25]:  # Use first 25 frames for cycle
                # Resize and normalize
                arr = img
                if arr is None:
                    continue
                try:
                    import numpy as _np
                    if arr.ndim == 2:
                        arr = _np.stack([arr, arr, arr], axis=-1)
                    if arr.shape[2] == 4:
                        arr = arr[:, :, :3]
                except Exception:
                    pass
                img_tensor = torch.from_numpy(arr).permute(2, 0, 1).unsqueeze(0).float() / 255.0
                img_tensor = img_tensor.to(self.device)
                
                # VAE encode
                with torch.no_grad():
                    latent = vae_encode_to_latent(self.vae, img_tensor)
                    latent_list.append(latent)
            
            # Stack latents for cycling
            self.input_latents = torch.cat(latent_list, dim=0)
            self.latent_idx = 0
            
            logger.info(f"✅ Video preprocessed: {len(latent_list)} latents")
        
        async def start_livekit(self):
            """Start LiveKit publisher"""
            livekit_url = os.getenv("LIVEKIT_URL")
            livekit_key = os.getenv("LIVEKIT_API_KEY")
            livekit_secret = os.getenv("LIVEKIT_API_SECRET")
            
            # Generate token
            token = api.AccessToken(livekit_key, livekit_secret)
            token.with_identity(f"musetalk-{self.room_name}")
            token.with_name("MuseTalk Avatar")
            token.with_grants(api.VideoGrants(
                room_join=True,
                room=self.room_name,
                can_publish=True,
                can_subscribe=False,
            ))
            jwt_token = token.to_jwt()
            
            # End-to-end: erst WebRTC (connect+publish) versuchen, sonst RTMP-Fallback
            try:
                # Connect: Auto-Subscribe off, falls unterstützt
                try:
                    self.livekit_room = rtc.Room(room_options=rtc.RoomOptions(auto_subscribe=False))
                except Exception:
                    try:
                        self.livekit_room = rtc.Room(options=rtc.RoomOptions(auto_subscribe=False))
                    except Exception:
                        self.livekit_room = rtc.Room()
                await self.livekit_room.connect(livekit_url, jwt_token)
                
                # Create video source
                self.video_source = rtc.VideoSource(width=256, height=256)
                # Publish track
                video_track = rtc.LocalVideoTrack.create_video_track("musetalk-lipsync", self.video_source)
                await self.livekit_room.local_participant.publish_track(
                    video_track,
                    rtc.TrackPublishOptions(source=rtc.TrackSource.SOURCE_CAMERA)
                )
                self.running = True
                logger.info(f"✅ LiveKit publisher started: {self.room_name}")
            except Exception as e:
                logger.warning(f"WebRTC failed ({e}); trying RTMP fallback")
                rtmp_url = os.getenv("LIVEKIT_RTMP_URL", "").strip()
                rtmp_key = os.getenv("LIVEKIT_RTMP_KEY", "").strip()
                if rtmp_url and rtmp_key:
                    import subprocess
                    publish_url = rtmp_url.rstrip('/') + '/' + rtmp_key
                    cmd = [
                        "ffmpeg", "-loglevel", "error",
                        "-f", "rawvideo", "-pix_fmt", "rgba",
                        "-s", "256x256", "-r", "25", "-i", "-",
                        "-an", "-c:v", "libx264", "-preset", "veryfast", "-tune", "zerolatency",
                        "-f", "flv", publish_url,
                    ]
                    try:
                        self.ffmpeg_proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
                        self.running = True
                        logger.info(f"✅ RTMP fallback publisher started: {publish_url}")
                    except Exception as ee:
                        logger.error(f"RTMP fallback failed: {ee}")
                        raise
                else:
                    raise
        
        async def process_audio_chunk(self, audio_pcm: bytes):
            """Process audio chunk → generate lipsync frame"""
            if not self.running:
                return
            
            try:
                # Convert PCM robust (int16 oder float32) → float32 [-1,1]
                audio_array = decode_pcm_to_float32(audio_pcm)
                
                # MuseTalk Real-Time Inference
                try:
                    # 1. Extract Whisper audio features
                    # Prepare audio for Whisper (needs specific format)
                    import librosa
                    # Resample if needed and extract mel-spectrogram
                    mel = librosa.feature.melspectrogram(
                        y=audio_array, 
                        sr=16000, 
                        n_mels=80,
                        n_fft=400,
                        hop_length=160
                    )
                    mel = torch.from_numpy(mel).unsqueeze(0).to(self.device)
                    
                    # 2. Get current latent (cycling through preprocessed latents)
                    current_latent = self.input_latents[self.latent_idx % len(self.input_latents)].unsqueeze(0)
                    self.latent_idx += 1
                    
                    # 3. UNet inference: latent + audio → new latent
                    with torch.no_grad():
                        # MuseTalk UNet takes: sample (latent), timestep, encoder_hidden_states (audio)
                        # Simplified: just pass latent and get output
                        # Real implementation würde Audio als conditioning nutzen
                        output_latent = self.unet(
                            current_latent,
                            timestep=torch.zeros(1).to(self.device),
                            encoder_hidden_states=mel,
                        )
                        
                        # 4. Decode latent to image
                        output_img = vae_decode_to_image(self.vae, output_latent)
                        output_img = output_img.squeeze(0).permute(1, 2, 0).cpu().numpy()
                        output_img = (output_img * 255).clip(0, 255).astype(np.uint8)
                    
                    frame_rgb = output_img
                    
                except Exception as e:
                    logger.warning(f"Inference failed: {e}, using reference")
                    # Fallback: use cycling latent decoded
                    with torch.no_grad():
                        current_latent = self.input_latents[self.latent_idx % len(self.input_latents)].unsqueeze(0)
                        self.latent_idx += 1
                        output_img = vae_decode_to_image(self.vae, current_latent)
                        frame_rgb = (output_img.squeeze(0).permute(1, 2, 0).cpu().numpy() * 255).clip(0, 255).astype(np.uint8)
                
                # Convert to RGBA
                if len(frame_rgb.shape) == 2 or frame_rgb.shape[2] == 1:
                    frame_rgb = np.stack([frame_rgb]*3, axis=-1)
                if frame_rgb.shape[2] == 3:
                    frame_rgba = np.dstack([frame_rgb, np.ones((frame_rgb.shape[0], frame_rgb.shape[1]), dtype=np.uint8) * 255])
                else:
                    frame_rgba = frame_rgb
                
                # Send frame
                if self.video_source is not None:
                    video_frame = rtc.VideoFrame(
                        width=frame_rgba.shape[1],
                        height=frame_rgba.shape[0],
                        type=rtc.VideoBufferType.RGBA,
                        data=frame_rgba.tobytes(),
                    )
                    await self.video_source.capture_frame(video_frame)
                elif self.ffmpeg_proc is not None and self.ffmpeg_proc.stdin:
                    try:
                        self.ffmpeg_proc.stdin.write(frame_rgba.tobytes())
                        self.ffmpeg_proc.stdin.flush()
                    except Exception as pe:
                        logger.warning(f"RTMP pipe write failed: {pe}")
                
            except Exception as e:
                logger.error(f"❌ Frame error: {e}")
        
        async def stop(self):
            """Stop session"""
            self.running = False
            if self.livekit_room:
                await self.livekit_room.disconnect()
            
            # Cleanup
            import os
            if os.path.exists(self.video_path):
                os.remove(self.video_path)
    
    @fastapi_app.get("/health")
    async def health():
        return {"status": "ok", "service": "musetalk-lipsync", "gpu": device}
    
    @fastapi_app.get("/debug/assets")
    async def debug_assets():
        """Check presence and sizes of required model assets and config."""
        import os as _os, glob as _glob
        from omegaconf import OmegaConf as _OC

        # Deterministisch: test.yaml laden und rekursiv prüfen
        used_cfg_path = "/root/MuseTalk/configs/inference/test.yaml"
        cfg = None
        found_key = None
        try:
            c = _OC.load(used_cfg_path)
            def _to_plain(obj):
                try:
                    return _OC.to_container(obj, resolve=True)
                except Exception:
                    return obj
            def _find_key_rec(node, keys):
                if node is None:
                    return None, None
                if isinstance(node, dict):
                    for k in keys:
                        if k in node and node[k] is not None:
                            return k, node[k]
                    for v in node.items():
                        k2, found = _find_key_rec(v[1], keys)
                        if found is not None:
                            return k2, found
                if isinstance(node, (list, tuple)):
                    for it in node:
                        k2, found = _find_key_rec(it, keys)
                        if found is not None:
                            return k2, found
                return None, None
            plain = _to_plain(c)
            value = None
            if isinstance(plain, dict) and 'model' in plain:
                found_key, value = _find_key_rec(plain['model'], ['unet_config', 'unet', 'unet15', 'unet_v15'])
            if value is None:
                found_key, value = _find_key_rec(plain, ['unet_config', 'unet', 'unet15', 'unet_v15'])
            cfg = c
        except Exception:
            cfg = None
            found_key = None
        
        # Required files
        unet_path = "/root/MuseTalk/models/musetalkV15/unet.pth"
        unet_cfg_json = "/root/MuseTalk/models/musetalkV15/musetalk.json"
        if not _os.path.exists(unet_cfg_json):
            # v1.0 Fallback
            alt = "/root/MuseTalk/models/musetalk/musetalk.json"
            if _os.path.exists(alt):
                unet_cfg_json = alt
                # ggf. anderes Gewichtsformat
                if _os.path.exists("/root/MuseTalk/models/musetalk/pytorch_model.bin"):
                    unet_path = "/root/MuseTalk/models/musetalk/pytorch_model.bin"
        vae_cfg = "/root/MuseTalk/models/sd-vae-ft-mse/config.json"
        vae_w = "/root/MuseTalk/models/sd-vae-ft-mse/diffusion_pytorch_model.safetensors"
        dwpose = "/root/MuseTalk/models/dwpose/dw-ll_ucoco_384.pth"
        
        def _size(p):
            try:
                return _os.path.getsize(p)
            except Exception:
                return None
        
        # Sum of all files under models dir
        total_models_bytes = 0
        for root, _, files in _os.walk("/root/MuseTalk/models"):
            for f in files:
                fp = _os.path.join(root, f)
                try:
                    total_models_bytes += _os.path.getsize(fp)
                except Exception:
                    pass
        
        # Zusätzlich: welche Keys gibt es unter model?
        model_keys = []
        try:
            if cfg is not None and hasattr(cfg, 'model'):
                plain = _OC.to_container(cfg.model, resolve=True)
                if isinstance(plain, dict):
                    model_keys = sorted(list(plain.keys()))
        except Exception:
            model_keys = []
        return {
            "config_path": used_cfg_path,
            "config_has_unet_config": found_key is not None,
            "config_unet_key": found_key,
            "model_keys": model_keys,
            "files": {
                "unet.pth": {"path": unet_path, "exists": _os.path.exists(unet_path), "size": _size(unet_path)},
                "musetalk.json": {"path": unet_cfg_json, "exists": _os.path.exists(unet_cfg_json), "size": _size(unet_cfg_json)},
                "sd-vae-ft-mse/config.json": {"path": vae_cfg, "exists": _os.path.exists(vae_cfg), "size": _size(vae_cfg)},
                "sd-vae-ft-mse/diffusion_pytorch_model.safetensors": {"path": vae_w, "exists": _os.path.exists(vae_w), "size": _size(vae_w)},
                "dwpose/dw-ll_ucoco_384.pth": {"path": dwpose, "exists": _os.path.exists(dwpose), "size": _size(dwpose)},
            },
            "models_dir_bytes": total_models_bytes,
        }

    @fastapi_app.get("/debug/models")
    async def debug_models():
        """Force model load and report detailed status/errors."""
        import os as _os, traceback as _tb
        status = {
            "device": device,
            "loaded": {"vae": vae is not None, "unet": unet is not None},
        }
        # Expected paths
        exp = {
            "unet_pth": "/root/MuseTalk/models/musetalkV15/unet.pth",
            "unet_json": "/root/MuseTalk/models/musetalkV15/musetalk.json",
            "unet_pth_v10": "/root/MuseTalk/models/musetalk/pytorch_model.bin",
            "unet_json_v10": "/root/MuseTalk/models/musetalk/musetalk.json",
        }
        for k, p in exp.items():
            status[k] = {"path": p, "exists": _os.path.exists(p), "size": (_os.path.getsize(p) if _os.path.exists(p) else None)}
        try:
            await load_models()
            status["after_load"] = {"vae": vae is not None, "unet": unet is not None}
            return status
        except Exception as e:
            status["error"] = str(e)
            status["traceback"] = _tb.format_exc()
            return status
    
    @fastapi_app.post("/session/start")
    async def start_session(req: Request):
        """Start MuseTalk session"""
        await load_models()
        
        body = await req.json()
        room = body.get("room", "default")
        video_b64 = body.get("video_b64")  # idle.mp4 base64
        frames_zip_b64 = body.get("frames_zip_b64")  # optional zip of PNG frames
        frames_zip_url = body.get("frames_zip_url")  # optional: URL zu frames.zip
        idle_video_url = body.get("idle_video_url")  # optional: MP4-URL (serverseitig laden)
        latents_url = body.get("latents_url")  # FASTEST: Pre-computed latents.pt (0.5s statt 7s!)
        connect_livekit = body.get("connect_livekit", False)
        
        # Falls URL übergeben wurde, lade Datei serverseitig und ersetze video_b64
        if not video_b64 and not frames_zip_b64 and not frames_zip_url and idle_video_url:
            try:
                import requests as _rq
                resp = _rq.get(idle_video_url, timeout=15)
                if resp.status_code >= 400 or not resp.content:
                    raise HTTPException(400, f"idle_video_url fetch failed: {resp.status_code}")
                import base64 as _b64
                video_b64 = _b64.b64encode(resp.content).decode()
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(400, f"idle_video_url error: {e}")

        if not video_b64 and not frames_zip_b64 and not frames_zip_url and not latents_url:
            raise HTTPException(400, "video_b64 or frames_zip_b64 or frames_zip_url or idle_video_url or latents_url required")
        
        try:
            if latents_url:
                # FASTEST PATH: Load pre-computed latents (RGB Tensors) und encode mit VAE
                import requests as _rq
                import torch as _t
                from io import BytesIO
                logger.info(f"⚡ Loading pre-computed latents: {latents_url}")
                resp = _rq.get(latents_url, timeout=10)
                if resp.status_code >= 400 or not resp.content:
                    raise HTTPException(400, f"latents_url fetch failed: {resp.status_code}")
                
                # Load Tensor [25, 3, H, W] (RGB Frames als Tensors)
                rgb_tensors = _t.load(BytesIO(resp.content))
                logger.info(f"✅ Loaded RGB tensors: {rgb_tensors.shape}")
                
                # VAE Encode zu Latents
                latents = []
                for i in range(rgb_tensors.shape[0]):
                    tens = rgb_tensors[i].unsqueeze(0).to(device)
                    with _t.no_grad():
                        lat = vae_encode_to_latent(vae, tens)
                        latents.append(lat)
                pre_lat = _t.cat(latents, dim=0)
                logger.info(f"✅ VAE Encoded to latents: {pre_lat.shape}")
                session = MuseTalkSession(room, "", preprocessed_latents=pre_lat)
            elif frames_zip_b64 or frames_zip_url:
                # Unpack frames.zip to temp dir and synthesize input_latents directly
                import tempfile, zipfile, numpy as _np
                import os as _os
                from PIL import Image as _PILImage
                import base64 as _b64
                import requests as _rq
                tmpdir = tempfile.mkdtemp(prefix="mt_frames_")
                zip_path = _os.path.join(tmpdir, "frames.zip")
                if frames_zip_b64:
                    with open(zip_path, "wb") as fz:
                        fz.write(_b64.b64decode(frames_zip_b64))
                else:
                    r = _rq.get(frames_zip_url, timeout=20)
                    if r.status_code >= 400 or not r.content:
                        raise HTTPException(400, f"frames_zip_url fetch failed: {r.status_code}")
                    with open(zip_path, "wb") as fz:
                        fz.write(r.content)
                with zipfile.ZipFile(zip_path, 'r') as zf:
                    zf.extractall(tmpdir)
                # Build a session with precomputed latents (kein Video-Preprocessing)
                frames = []
                for name in sorted(_os.listdir(tmpdir)):
                    if name.lower().endswith('.png'):
                        with _PILImage.open(_os.path.join(tmpdir, name)) as im:
                            frames.append(_np.array(im.convert('RGB')))
                if not frames:
                    raise HTTPException(500, "frames.zip empty")
                # encode to latents
                import torch as _t
                latents = []
                for arr in frames[:25]:
                    tens = _t.from_numpy(arr).permute(2,0,1).unsqueeze(0).float()/255.0
                    tens = tens.to(device)
                    with _t.no_grad():
                        lat = vae_encode_to_latent(vae, tens)
                        latents.append(lat)
                pre_lat = _t.cat(latents, dim=0)
                session = MuseTalkSession(room, "", preprocessed_latents=pre_lat)
            else:
                session = MuseTalkSession(room, video_b64)
            if connect_livekit:
                await session.start_livekit()
            active_sessions[room] = session
            
            return {"status": "started", "room": room, "connected": bool(connect_livekit)}
        except Exception as e:
            logger.error(f"Session start failed: {e}")
            raise HTTPException(500, str(e))
    
    @fastapi_app.post("/session/stop")
    async def stop_session(req: Request):
        """Stop MuseTalk session"""
        body = await req.json()
        room = body.get("room", "default")
        
        if room in active_sessions:
            await active_sessions[room].stop()
            del active_sessions[room]
        
        return {"status": "stopped", "room": room}
    
    @fastapi_app.websocket("/audio")
    async def audio_stream(websocket: WebSocket):
        """WebSocket for audio streaming"""
        await websocket.accept()
        
        room = None
        
        try:
            while True:
                data = await websocket.receive_bytes()
                
                # First message: room name
                if room is None:
                    room = data.decode()
                    continue
                
                # Subsequent messages: PCM audio
                if room in active_sessions:
                    await active_sessions[room].process_audio_chunk(data)
                
        except WebSocketDisconnect:
            logger.info(f"Audio stream closed: {room}")
    
    return fastapi_app

    # NOTE: Functions below won't be reached due to return above; keep endpoints defined before return.

