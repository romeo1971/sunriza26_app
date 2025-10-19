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
            # Sicherstellen: sd-vae-ft-mse (Diffusers-Format) liegt lokal vor (config.json + weights)
            "mkdir -p /root/MuseTalk/models/sd-vae-ft-mse",
            "curl -L https://huggingface.co/stabilityai/sd-vae-ft-mse/resolve/main/config.json -o /root/MuseTalk/models/sd-vae-ft-mse/config.json || true",
            "curl -L https://huggingface.co/stabilityai/sd-vae-ft-mse/resolve/main/diffusion_pytorch_model.safetensors -o /root/MuseTalk/models/sd-vae-ft-mse/diffusion_pytorch_model.safetensors || true",
            # (keine zusätzliche Kopie mehr nötig)
    )
)

app = modal.App("musetalk-lipsync-v2", image=image)


@app.function(
    gpu="T4",  # Tesla T4 für 30 FPS
    timeout=3600,
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
    
    async def load_models():
        """Load MuseTalk models"""
        nonlocal vae, unet, pe, device
        
        if vae is not None:
            return
        
        logger.info("Loading MuseTalk models...")
        
        try:
            # Load offizielle Inferenz-Config aus dem Repo
            config = OmegaConf.load("/root/MuseTalk/configs/inference/test.yaml")
            
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
            
            # Load UNet (MuseTalk 1.5) – mit gefundener Konfiguration
            unet_cfg = config.model.unet_config
            unet = UNet(unet_config=unet_cfg, model_path="/root/MuseTalk/models/musetalkV15/unet.pth")
            unet = unet.to(device).eval()
            
            # Position encoding
            pe = coord_placeholder(256).to(device)
            
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
            
            # Connect (Standardoptionen)
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
        
        async def process_audio_chunk(self, audio_pcm: bytes):
            """Process audio chunk → generate lipsync frame"""
            if not self.running:
                return
            
            try:
                # Convert PCM to numpy array (16kHz, mono, float32)
                audio_array = np.frombuffer(audio_pcm, dtype=np.int16).astype(np.float32) / 32768.0
                
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
                
                # Send to LiveKit
                video_frame = rtc.VideoFrame(
                    width=frame_rgba.shape[1],
                    height=frame_rgba.shape[0],
                    type=rtc.VideoBufferType.RGBA,
                    data=frame_rgba.tobytes(),
                )
                
                await self.video_source.capture_frame(video_frame)
                
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
    
    @fastapi_app.post("/session/start")
    async def start_session(req: Request):
        """Start MuseTalk session"""
        await load_models()
        
        body = await req.json()
        room = body.get("room", "default")
        video_b64 = body.get("video_b64")  # idle.mp4 base64
        frames_zip_b64 = body.get("frames_zip_b64")  # optional zip of PNG frames
        
        if not video_b64 and not frames_zip_b64:
            raise HTTPException(400, "video_b64 or frames_zip_b64 required")
        
        try:
            if frames_zip_b64:
                # Unpack frames.zip to temp dir and synthesize input_latents directly
                import tempfile, zipfile, numpy as _np
                import os as _os
                from PIL import Image as _PILImage
                tmpdir = tempfile.mkdtemp(prefix="mt_frames_")
                with open(_os.path.join(tmpdir, "frames.zip"), "wb") as fz:
                    fz.write(base64.b64decode(frames_zip_b64))
                with zipfile.ZipFile(_os.path.join(tmpdir, "frames.zip"), 'r') as zf:
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
            await session.start_livekit()
            active_sessions[room] = session
            
            return {"status": "started", "room": room}
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

