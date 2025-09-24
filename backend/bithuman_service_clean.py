#!/usr/bin/env python3
"""
BitHuman Avatar Service - SAUBERE VERSION
Generiert sprechende Avatar-Videos mit BitHuman API
"""

import os
import tempfile
import shutil
import asyncio
from pathlib import Path

from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.responses import FileResponse
import uvicorn
import hashlib
import requests
import json
import inspect

# BitHuman SDK
try:
    from bithuman import AsyncBithuman
    BITHUMAN_AVAILABLE = True
except ImportError:
    BITHUMAN_AVAILABLE = False
    print("⚠️ BitHuman SDK nicht installiert")

app = FastAPI(title="BitHuman Avatar Service", version="1.0")

# Globale Variablen
runtime = None
API_SECRET_CACHE = None
MODELS_CACHE_DIR = Path(__file__).resolve().parents[1] / "models" / "bithuman"
FIGURES_MAP_PATH = MODELS_CACHE_DIR / "figures.json"

@app.on_event("startup")
async def startup():
    """Service-Initialisierung"""
    global API_SECRET_CACHE
    
    API_SECRET_CACHE = (
        os.getenv("BITHUMAN_API_SECRET") 
        or os.getenv("BITHUMAN_API_KEY")
        or ""
    ).strip()
    
    # Ensure models cache dir exists
    try:
        MODELS_CACHE_DIR.mkdir(parents=True, exist_ok=True)
    except Exception:
        pass

    if API_SECRET_CACHE:
        print("ℹ️ BitHuman: API-Key geladen, Runtime wird per-request erstellt")
    else:
        print("⚠️ BitHuman: API-Key nicht gefunden")

def _hash_file(path: Path) -> str:
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()

def _env(name: str, default: str | None = None) -> str | None:
    v = os.getenv(name)
    return v if v is not None and v.strip() != "" else default

def _requests_headers() -> dict:
    return {
        "Authorization": f"Bearer {API_SECRET_CACHE}",
        "api-secret": API_SECRET_CACHE,  # Fallback: direkte api-secret header
    }

def _load_figures_map() -> dict:
    try:
        if FIGURES_MAP_PATH.exists():
            with open(FIGURES_MAP_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
    except Exception:
        pass
    return {}

def _save_figures_map(data: dict) -> None:
    try:
        FIGURES_MAP_PATH.parent.mkdir(parents=True, exist_ok=True)
        with open(FIGURES_MAP_PATH, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    except Exception:
        pass

def _figure_create(image_path: Path) -> dict:
    """Call BitHuman Figure creation API. Endpoint configurable via env.
    Returns parsed json dict or raises.
    """
    urls_to_try = [
        _env("BITHUMAN_FIGURE_CREATE_URL"),
        _env("BITHUMAN_AGENT_CREATE_URL"),
        # Offizieller Figure-Creation-Endpunkt (Paid, ohne /v1)
        "https://api.bithuman.ai/figure/create",
        "https://api.bithuman.ai/figure",
        "https://auth.api.bithuman.ai/v1/figures",  # Auth-Domain versuchen
        "https://auth.api.bithuman.ai/v1/figures/create",
        "https://api.bithuman.ai/v1/figures",
        "https://api.bithuman.ai/v1/figures/create",
        "https://api.bithuman.ai/figures",
    ]
    last_err = None
    print(f"🎭 Versuche Figure-Erstellung für {image_path.name} mit API-Key: {API_SECRET_CACHE[:10]}...")
    for url in [u for u in urls_to_try if u]:
        try:
            print(f"  📡 Versuche URL: {url}")
            with open(image_path, "rb") as img:
                # Variante 1: Feldname 'image'
                files_image = {"image": (image_path.name, img, "image/jpeg")}
                data_meta = {"name": image_path.stem}
                print(f"     🔄 POST mit 'image'-Feld...")
                r = requests.post(url, headers=_requests_headers(), files=files_image, data=data_meta, timeout=60)
                print(f"     📋 Response: {r.status_code} - {r.text[:500]}")
            if r.status_code // 100 == 2:
                print(f"  ✅ Erfolg mit 'image'-Feld!")
                return r.json() if r.content else {}
            # Variante 2: Feldname 'file'
            with open(image_path, "rb") as img2:
                files_file = {"file": (image_path.name, img2, "image/jpeg")}
                data_meta = {"name": image_path.stem}
                print(f"     🔄 POST mit 'file'-Feld...")
                r = requests.post(url, headers=_requests_headers(), files=files_file, data=data_meta, timeout=60)
                print(f"     📋 Response: {r.status_code} - {r.text[:500]}")
            if r.status_code // 100 == 2:
                print(f"  ✅ Erfolg mit 'file'-Feld!")
                return r.json() if r.content else {}
            print(f"  ❌ URL {url} fehlgeschlagen: {r.status_code}")
            last_err = RuntimeError(f"Figure create failed: {r.status_code} {r.text[:200]}")
        except Exception as e:
            print(f"  💥 Exception bei {url}: {e}")
            last_err = e
    print(f"🚫 Alle Figure-URLs fehlgeschlagen. Letzter Fehler: {last_err}")
    if last_err:
        raise last_err
    return {}

def _download_imx(url: str, target_path: Path) -> Path:
    r = requests.get(url, headers=_requests_headers(), timeout=120, stream=True)
    if r.status_code // 100 != 2:
        raise RuntimeError(f"IMX download failed: {r.status_code}")
    target_path.parent.mkdir(parents=True, exist_ok=True)
    with open(target_path, "wb") as out:
        for chunk in r.iter_content(chunk_size=65536):
            if chunk:
                out.write(chunk)
    return target_path

async def _ensure_model_from_image(local_runtime, image_path: Path, figure_id_in: str | None, model_hash_in: str | None) -> tuple[Path | None, str | None, str | None]:
    """Ensure we have a local .imx for this image and load it into runtime.
    Returns (imx_path, figure_id, runtime_model_hash).
    """
    # Cache key by content hash
    try:
        cache_key = _hash_file(image_path)
    except Exception:
        cache_key = image_path.stem
    imx_path = MODELS_CACHE_DIR / f"{cache_key}.imx"

    figure_id = figure_id_in
    runtime_model_hash = model_hash_in

    # If IMX cached, use it
    if imx_path.exists():
        try:
            # Prefer documented async loader if available
            if hasattr(local_runtime, "load_data_async"):
                await local_runtime.load_data_async(str(imx_path))
            elif hasattr(local_runtime, "load_data"):
                local_runtime.load_data(str(imx_path))
            else:
                # Fallback to set_model if it's the expected API
                await local_runtime.set_model(str(imx_path))
            return imx_path, figure_id, runtime_model_hash
        except Exception as e:
            # If loading cached model fails, remove and re-create
            try:
                imx_path.unlink(missing_ok=True)  # type: ignore[arg-type]
            except Exception:
                pass
            print(f"⚠️ Cached IMX load failed, will re-create: {e}")

    # Create figure via API and get model (or reuse from map)
    figures_map = _load_figures_map()
    cached = figures_map.get(cache_key)
    if cached and not figure_id_in:
        figure_id = cached.get("figure_id") or figure_id
        runtime_model_hash = cached.get("runtime_model_hash") or runtime_model_hash
        cached_imx = cached.get("imx_path")
        if cached_imx:
            p = Path(cached_imx)
            if p.exists():
                try:
                    if hasattr(local_runtime, "load_data_async"):
                        await local_runtime.load_data_async(str(p))
                    elif hasattr(local_runtime, "load_data"):
                        local_runtime.load_data(str(p))
                    else:
                        await local_runtime.set_model(str(p))
                    return p, figure_id, runtime_model_hash
                except Exception:
                    pass

    # Create figure via API and get model
    try:
        resp = _figure_create(image_path)
        # Try to read common fields
        figure_id = figure_id or resp.get("figure_id") or resp.get("id")
        runtime_model_hash = runtime_model_hash or resp.get("runtime_model_hash") or resp.get("model_hash") or resp.get("hash")
        # Try various keys for IMX URL
        imx_url = (
            resp.get("imx_url")
            or resp.get("model_url")
            or resp.get("download_url")
            or (resp.get("model") or {}).get("imx_url")
            or (resp.get("data") or {}).get("imx_url")
        )
        if imx_url:
            _download_imx(imx_url, imx_path)
            # Load into runtime
            if hasattr(local_runtime, "load_data_async"):
                await local_runtime.load_data_async(str(imx_path))
            elif hasattr(local_runtime, "load_data"):
                local_runtime.load_data(str(imx_path))
            else:
                await local_runtime.set_model(str(imx_path))
            # Persist
            figures_map[cache_key] = {
                "figure_id": figure_id,
                "runtime_model_hash": runtime_model_hash,
                "imx_path": str(imx_path),
            }
            _save_figures_map(figures_map)
            return imx_path, figure_id, runtime_model_hash
        # If only hash is available, we rely on runtime created with hash
        return None, figure_id, runtime_model_hash
    except Exception as e:
        print(f"⚠️ Figure/Model provisioning failed: {e}")
        return None, figure_id, runtime_model_hash

@app.get("/")
def health_check():
    """Health Check"""
    return {
        "message": "BitHuman Avatar Service läuft",
        "runtime_initialized": runtime is not None
    }

@app.post("/test/simple")
async def test_simple():
    """Einfacher Test"""
    return {"status": "OK", "message": "Service funktioniert"}

@app.post("/generate-avatar")
async def generate_avatar(
    image: UploadFile = File(...),
    audio: UploadFile = File(...),
    figure_id: str = None,
    runtime_model_hash: str = None,
    imx_url: str = None,
    imx_file: UploadFile | None = File(None),
):
    """
    Generiert Avatar-Video aus Bild und Audio
    
    Args:
        image: Avatar-Bild (JPEG/PNG)
        audio: Audio-Datei (MP3/WAV)
        figure_id: Optionale BitHuman Figure ID
        runtime_model_hash: Optionaler Model Hash
    
    Returns:
        MP4-Video oder Fehlermeldung
    """
    
    if not API_SECRET_CACHE:
        raise HTTPException(status_code=500, detail="BitHuman API-Key nicht verfügbar")
    
    print(f"📋 Parameter: figure_id={figure_id}, runtime_model_hash={runtime_model_hash}, imx_url={imx_url}, imx_file={imx_file is not None}")
    
    # Temporäre Dateien erstellen (persistent!)
    temp_dir = tempfile.mkdtemp()
    temp_path = Path(temp_dir)
    
    try:
        # Dateien speichern
        image_path = temp_path / f"avatar_{image.filename}"
        audio_path = temp_path / f"audio_{audio.filename}"
        output_path = temp_path / "avatar_video.mp4"
        
        # Upload-Dateien speichern
        with open(image_path, "wb") as buffer:
            shutil.copyfileobj(image.file, buffer)
        with open(audio_path, "wb") as buffer:
            shutil.copyfileobj(audio.file, buffer)
        
        print(f"📁 Dateien gespeichert: {image_path}, {audio_path}")
        
        # Bevor irgendetwas anderes passiert: priorisiere bereitgestellte IMX (Datei oder URL)
        selected_imx_path: Path | None = None
        try:
            if imx_file is not None:
                try:
                    imx_bytes = imx_file.file.read()
                    content_hash = hashlib.md5(imx_bytes).hexdigest()
                    direct_imx_path = MODELS_CACHE_DIR / f"{content_hash}.imx"
                    direct_imx_path.parent.mkdir(parents=True, exist_ok=True)
                    with open(direct_imx_path, "wb") as f:
                        f.write(imx_bytes)
                    selected_imx_path = direct_imx_path
                    print(f"✅ IMX aus Upload übernommen: {selected_imx_path}")
                except Exception as e:
                    print(f"⚠️ Upload-IMX konnte nicht übernommen werden: {e}")
            if selected_imx_path is None and imx_url and imx_url.strip() != "":
                try:
                    url_hash = hashlib.md5(imx_url.strip().encode("utf-8")).hexdigest()
                    direct_imx_path = MODELS_CACHE_DIR / f"{url_hash}.imx"
                    if not direct_imx_path.exists():
                        _download_imx(imx_url.strip(), direct_imx_path)
                    selected_imx_path = direct_imx_path
                    print(f"✅ IMX aus URL übernommen: {selected_imx_path}")
                except Exception as e:
                    print(f"⚠️ IMX-URL Download fehlgeschlagen: {e}")
        except Exception:
            pass

        # Falls weiterhin kein IMX gewählt: versuche Default aus ENV oder aus dem Ordner 'avatars/'
        if selected_imx_path is None:
            try:
                default_imx_env = os.getenv("BITHUMAN_DEFAULT_IMX", "").strip()
                if default_imx_env:
                    p = Path(default_imx_env)
                    if p.exists():
                        selected_imx_path = p
                        print(f"✅ IMX aus ENV gewählt: {selected_imx_path}")
                if selected_imx_path is None:
                    avatars_dir = Path(__file__).resolve().parents[1] / "avatars"
                    if avatars_dir.exists():
                        imx_files = [f for f in avatars_dir.iterdir() if f.is_file() and f.suffix.lower() == ".imx"]
                        if imx_files:
                            # Größte .imx nehmen (höchste Wahrscheinlichkeit vollständiges Modell)
                            selected_imx_path = max(imx_files, key=lambda f: f.stat().st_size)
                            print(f"✅ IMX aus Ordner 'avatars' gewählt: {selected_imx_path}")
            except Exception as e:
                print(f"⚠️ Auswahl Default-IMX fehlgeschlagen: {e}")

        # Kein Fake-IMX mehr erzeugen – es wird ausschließlich ein echtes TAR-.imx genutzt
        imx_path = None
            
        # Schritt 2: Erstelle Runtime mit IMX-Pfad (priorisiert bereitgestelltes IMX)
        try:
            chosen = selected_imx_path if selected_imx_path and selected_imx_path.exists() else (imx_path if imx_path and imx_path.exists() else None)
            if chosen is not None:
                print(f"🔧 Runtime mit IMX-Modell (model_path): {chosen}")
                # Runtime direkt mit model_path erstellen, damit Hash korrekt übermittelt wird
                local_runtime = await AsyncBithuman.create(api_secret=API_SECRET_CACHE, model_path=str(chosen))
                # Optional zusätzlich set_model zur Sicherheit
                try:
                    await local_runtime.set_model(str(chosen))
                except Exception:
                    pass
                print("✅ Runtime mit IMX-Modell erstellt")
            else:
                print("🔧 Runtime ohne Modell (nur API-Secret)")
                local_runtime = await AsyncBithuman.create(api_secret=API_SECRET_CACHE)
                print("✅ Runtime erstellt")
                
        except Exception as e:
            print(f"❌ Runtime-Fehler: {e}")
            strict = _env("BITHUMAN_STRICT", "0") == "1"
            if strict:
                raise HTTPException(status_code=500, detail=f"Runtime-Fehler (strict): {e}")
            # Fallback: Einfaches Video aus Bild erstellen
            return await create_fallback_video(image_path, audio_path, output_path)
        
        # Avatar-Generierung mit BitHuman
        try:
            print("🎬 Starte Avatar-Generierung mit BitHuman SDK")
            
            # Wenn kein IMX beim Start geladen wurde, versuche es jetzt über Figure/Cache
            if not (chosen is not None):
                imx_loaded_path, figure_id, runtime_model_hash = await _ensure_model_from_image(local_runtime, image_path, figure_id, runtime_model_hash)

            # 1. Audio korrekt konvertieren (16kHz, Mono, int16)
            import numpy as np
            import librosa
            
            audio_data, _ = librosa.load(str(audio_path), sr=16000, mono=True)
            audio_pcm = (audio_data * 32767).astype(np.int16)
            audio_bytes = audio_pcm.tobytes()
            print(f"✅ Audio konvertiert: {len(audio_pcm)} samples, 16kHz (bytes={len(audio_bytes)})")
            
            # 2. Runtime starten
            await local_runtime.start()
            print("✅ Runtime gestartet")

            # Optional: schneller Model-Check
            if hasattr(local_runtime, "get_first_frame"):
                try:
                    first = local_runtime.get_first_frame()
                    # Falls coroutine, awaited holen
                    if asyncio.iscoroutine(first):
                        await first
                    print("✅ Model-Check OK (first_frame)")
                except Exception as e:
                    print(f"⚠️ Model-Check Hinweis: {e}")
            
            # 3. Audio senden
            await local_runtime.push_audio(audio_bytes, 16000)
            print("✅ Audio gesendet")
            
            # 4. Verarbeitung starten (laut Doku: async generator)
            any_result = None
            try:
                any_result = local_runtime.run()
            except Exception as e:
                print(f"⚠️ run() Aufruf-Fehler: {e}")
            # Falls coroutine: awaiten, falls async generator: direkt nutzen
            if asyncio.iscoroutine(any_result):
                result = await any_result
            elif inspect.isasyncgen(any_result):
                result = any_result
            else:
                # letzter Versuch: direkt await
                try:
                    result = await local_runtime.run()
                except Exception as e:
                    raise RuntimeError(f"run() unsupported return type: {type(any_result)} - {e}")
            print(f"✅ Verarbeitung gestartet: {result}")
            
            # 5. Video-Frames generieren - KORREKTE API VERWENDUNG
            frames = []
            frame_count = 0
            
            # BitHuman Async Generator korrekt verwenden
            try:
                # Das run() gibt einen async generator zurück
                async for frame_data in result:
                    if frame_data is not None and hasattr(frame_data, 'shape'):
                        frames.append(frame_data)
                        frame_count += 1
                        if frame_count >= 60:  # Max 60 Frames
                            break
                print(f"✅ Frames aus run() generator: {frame_count}")
            except Exception as e:
                print(f"⚠️ run() generator: {e}")
                # Kein weiterer Fallback – strikt Doku-konform bleiben
            
            print(f"📹 Gesamt Frames gesammelt: {frame_count}")
            
            # 6. Video erstellen
            if frames and len(frames) > 0:
                import cv2
                
                # MP4-Video erstellen
                fourcc = cv2.VideoWriter_fourcc(*'mp4v')
                height, width = frames[0].shape[:2]
                video_writer = cv2.VideoWriter(str(output_path), fourcc, 30, (width, height))
                
                for frame in frames:
                    video_writer.write(frame)
                
                video_writer.release()
                print(f"🎬 Video erstellt: {frame_count} frames")
                
            else:
                # Strict mode: kein Fallback, wenn aktiviert
                strict = _env("BITHUMAN_STRICT", "1") == "1"
                if strict:
                    raise RuntimeError("Model lieferte keine Frames (strict mode)")
                # Fallback: Video aus Bild
                await create_fallback_video(image_path, audio_path, output_path)
                
        except Exception as e:
            print(f"❌ BitHuman-Fehler: {e}")
            # Strict-Mode erzwingen
            strict = _env("BITHUMAN_STRICT", "0") == "1"
            if strict:
                raise HTTPException(status_code=500, detail=f"BitHuman-Fehler (strict): {e}")
            # Fallback verwenden, wenn nicht strict
            await create_fallback_video(image_path, audio_path, output_path)
            
        finally:
            try:
                await local_runtime.stop()
                print("✅ Runtime gestoppt")
            except:
                pass
        
        # Video-Datei zurückgeben
        if output_path.exists() and output_path.stat().st_size > 0:
            print(f"📁 Video bereit: {output_path.stat().st_size} bytes")
            return FileResponse(
                path=str(output_path),
                media_type="video/mp4",
                filename="avatar_video.mp4"
            )
        else:
            return {"error": "Video konnte nicht erstellt werden"}
            
    except Exception as e:
        print(f"💥 Generierung fehlgeschlagen: {e}")
        raise HTTPException(status_code=500, detail=f"Avatar-Generierung fehlgeschlagen: {e}")

async def create_fallback_video(image_path: Path, audio_path: Path, output_path: Path):
    """Erstellt Fallback-Video aus statischem Bild"""
    try:
        import cv2
        
        # Bild laden
        img = cv2.imread(str(image_path))
        if img is None:
            raise Exception("Bild konnte nicht geladen werden")
        
        # Video-Writer
        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        height, width = img.shape[:2]
        video_writer = cv2.VideoWriter(str(output_path), fourcc, 30, (width, height))
        
        # Bild 90x schreiben (3 Sekunden bei 30fps)
        for _ in range(90):
            video_writer.write(img)
        
        video_writer.release()
        print("🎬 Fallback-Video erstellt")
        return True
        
    except Exception as e:
        print(f"❌ Fallback-Video Fehler: {e}")
        return False

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=4202)
