# GPU Optimierung für Modal.com LivePortrait

## Status: ✅ GPU ist aktiv (Tesla T4)

### Aktuelle Konfiguration:

#### 1. Modal.com GPU Setup
```python
@app.function(
    image=image,
    gpu="T4",  # NVIDIA Tesla T4 GPU
    timeout=600,
)
```

#### 2. Docker Image (NVIDIA CUDA 12.6)
```python
modal.Image.from_registry("nvidia/cuda:12.6.0-cudnn-devel-ubuntu22.04")
```

#### 3. Dependencies (GPU-optimiert)
```bash
# PyTorch mit CUDA 12.1 Support
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121

# ONNX Runtime GPU (KRITISCH für LivePortrait!)
pip install onnxruntime-gpu

# Versionen (EXAKT wie lokal):
numpy==2.2.6
onnx==1.19.1
opencv-python-headless==4.12.0.88
```

#### 4. Umgebungsvariablen (GPU forcieren)
```python
env = os.environ.copy()
env['PYTORCH_ENABLE_MPS_FALLBACK'] = '1'
env['CUDA_VISIBLE_DEVICES'] = '0'  # GPU 0 nutzen
env['ORT_TENSORRT_ENGINE_CACHE_ENABLE'] = '1'  # TensorRT Cache
```

#### 5. GPU Checks im Code
```python
# PyTorch GPU Check
import torch
print(f"GPU verfügbar: {torch.cuda.is_available()}")
print(f"GPU Name: {torch.cuda.get_device_name(0)}")

# ONNX Runtime GPU Check (KRITISCH!)
import onnxruntime as ort
providers = ort.get_available_providers()
print(f"ONNX Runtime Providers: {providers}")
if 'CUDAExecutionProvider' in providers:
    print("✅ ONNX Runtime nutzt GPU!")
else:
    print("⚠️ WARNING: ONNX Runtime nutzt CPU!")
```

## Performance-Erwartungen:

| Komponente | CPU (ohne GPU) | GPU (Tesla T4) |
|------------|----------------|----------------|
| LivePortrait | 90-120 Sekunden | 20-40 Sekunden |
| Video Processing | 10-15 Sekunden | 5-10 Sekunden |
| **GESAMT** | **~120 Sekunden** | **~30-50 Sekunden** |

## Troubleshooting:

### Problem: "ONNX Runtime nutzt nur CPU"
**Ursache:** `onnxruntime-gpu` nicht korrekt installiert oder cuDNN-Version inkompatibel.

**Lösung:**
1. Prüfe CUDA/cuDNN Versionen:
   ```bash
   nvidia-smi  # CUDA Version
   dpkg -l | grep cudnn  # cuDNN Version
   ```

2. Prüfe ONNX Runtime Installation:
   ```bash
   python -c "import onnxruntime as ort; print(ort.get_available_providers())"
   # Erwartete Ausgabe: ['CUDAExecutionProvider', 'CPUExecutionProvider', ...]
   ```

3. Falls `CUDAExecutionProvider` fehlt:
   ```bash
   pip uninstall onnxruntime onnxruntime-gpu
   pip install onnxruntime-gpu --no-cache-dir
   ```

### Problem: "GPU out of memory"
**Ursache:** Video zu groß oder mehrere Requests parallel.

**Lösung:**
1. Reduziere `source-max-dim` (Standard: 1600 → 1024)
2. Erhöhe Modal Timeout (Standard: 600s → 900s)
3. Upgrade GPU: `gpu="T4"` → `gpu="A10G"` (teurer, aber 3x schneller)

### Problem: LivePortrait dauert trotz GPU lange
**Ursache:** `imageio-ffmpeg` nutzt CPU für Encoding.

**Lösung:**
1. Prüfe FFmpeg Version:
   ```bash
   ffmpeg -version | head -1
   # Erwartete Ausgabe: ffmpeg version 7.0.2
   ```

2. Nutze Hardware-Encoding (falls verfügbar):
   ```python
   # In modal_dynamics.py (Post-Processing)
   subprocess.run([
       'ffmpeg', '-i', input_video,
       '-c:v', 'h264_nvenc',  # NVIDIA GPU Encoder!
       '-preset', 'fast',
       '-b:v', '5M',
       output_video
   ])
   ```

## Monitoring:

### Logs überprüfen:
```bash
modal logs sunriza-dynamics --tail 100
```

### Erwartete Log-Ausgaben (bei GPU):
```
🔥 GPU verfügbar: True (Anzahl: 1)
🔥 GPU Name: Tesla T4
🔥 ONNX Runtime Providers: ['CUDAExecutionProvider', 'CPUExecutionProvider', ...]
✅ ONNX Runtime nutzt GPU (CUDAExecutionProvider)!
⏱️ LivePortrait dauerte: 25.3 Sekunden  # <-- SOLLTE ~20-40s sein!
```

### Bei CPU-Betrieb (PROBLEM!):
```
🔥 GPU verfügbar: True (Anzahl: 1)
🔥 GPU Name: Tesla T4
🔥 ONNX Runtime Providers: ['CPUExecutionProvider']
⚠️ WARNING: ONNX Runtime nutzt nur CPU! LivePortrait wird LANGSAM sein!
⏱️ LivePortrait dauerte: 104.6 Sekunden  # <-- ZU LANGSAM!
```

## Kosten-Optimierung:

| GPU Typ | Preis/Stunde | Performance | Empfehlung |
|---------|--------------|-------------|------------|
| T4 | $0.60 | Baseline | ✅ Standard |
| A10G | $1.50 | 3x schneller | Für High-Traffic |
| A100 | $4.00 | 5x schneller | Nur für extrem hohe Last |

**Aktuell:** T4 ist optimal für Sunriza (Balance aus Kosten & Performance).

## Nächste Schritte:

1. ✅ Deploy mit GPU-Checks: `modal deploy modal_dynamics.py`
2. 🔍 Teste Dynamics-Generierung und prüfe Logs
3. 📊 Überprüfe ob "CUDAExecutionProvider" in Logs erscheint
4. ⏱️ Messe LivePortrait-Dauer (sollte ~20-40s sein)
5. 🚀 Falls weiterhin CPU: Image neu builden mit `--force`

## Wichtige Notizen:

- **Modal.com cached Images!** Änderungen am Image erfordern manchmal `modal deploy --force`.
- **GPU ist NICHT das gleiche wie ONNX Runtime GPU!** PyTorch kann GPU nutzen, aber ONNX Runtime trotzdem CPU.
- **CUDAExecutionProvider ist KRITISCH!** Ohne ihn läuft LivePortrait auf CPU (langsam).
- **T4 GPU kostet ~$0.60/Stunde** → Bei 30s/Request = ~2000 Requests für $10.

---

**Letzte Aktualisierung:** 17.10.2025, 00:50 Uhr
**Status:** GPU aktiv, ONNX Runtime Check hinzugefügt

