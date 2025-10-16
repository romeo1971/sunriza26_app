# Sunriza26 - Vollständige Deployment Dokumentation

## Übersicht

Diese Dokumentation beschreibt die komplette Implementierung des Sunriza26 Avatar-Systems mit:
- **LivePortrait** für Avatar-Dynamics-Generierung
- **Modal.com** für GPU-beschleunigte Video-Verarbeitung
- **Firebase Functions** für Video-Trimming
- **Flutter** für die Mobile App
- **Firebase Storage & Firestore** für Datenspeicherung

---

## 1. LivePortrait - Avatar Dynamics Generierung

### Was ist LivePortrait?

LivePortrait ist ein ML-Modell, das aus einem **Hero-Image** (Gesichtsfoto) und einem **Hero-Video** (Sprechvideo) ein animiertes Video (`idle.mp4`) generiert, das:
- Lippenbewegungen vom Hero-Video übernimmt
- Das Gesicht aus dem Hero-Image animiert
- Atlas, Mask und ROI-JSONs für Live-Animation generiert

### LivePortrait Installation & Versionen

#### System-Requirements
- **Python:** 3.11
- **CUDA:** 12.6.0 (für GPU-Beschleunigung)
- **cuDNN:** 9 (kommt mit PyTorch)
- **FFmpeg:** 7.0.2 (via `imageio-ffmpeg`)
- **GPU:** NVIDIA mit min. 8GB VRAM (für Modal.com)

#### Python Dependencies (requirements.txt)

```txt
# Core ML/AI
torch==2.6.0
torchvision==0.20.0
numpy==2.2.6
opencv-python-headless==4.12.0.88
scikit-image==0.25.2

# ONNX Runtime (GPU)
onnxruntime-gpu==1.20.1

# LivePortrait Dependencies
onnx==1.19.1
tyro==0.9.34
pyyaml==6.0.3
tqdm==4.67.1
imageio[ffmpeg]==2.37.0
pykalman==0.10.2

# Firebase
firebase-admin==6.6.0
google-cloud-storage==2.18.2
google-cloud-firestore==2.19.0

# Modal.com
modal==0.69.194

# Utilities
Pillow==11.0.0
requests==2.32.3
python-dotenv==1.0.1
```

#### LivePortrait Model Installation

1. **Clone LivePortrait Repository:**
```bash
cd /opt
git clone https://github.com/KwaiVGI/LivePortrait.git
cd LivePortrait
```

2. **Download Pretrained Weights:**
```bash
huggingface-cli login
huggingface-cli download KwaiVGI/LivePortrait --local-dir pretrained_weights
```

Die Weights werden heruntergeladen nach:
```
pretrained_weights/
├── live_portrait/
│   ├── base_models/
│   │   ├── appearance_feature_extractor.pth
│   │   ├── motion_extractor.pth
│   │   ├── warping_module.pth
│   │   └── spade_generator.pth
│   └── retargeting_models/
│       └── stitching_retargeting_module.pth
└── insightface/
    └── models/
        └── buffalo_l/
            ├── 1k3d68.onnx
            ├── 2d106det.onnx
            ├── det_10g.onnx
            └── w600k_r50.onnx
```

3. **LivePortrait Konfiguration:**

Wichtige Parameter in `inference.py`:
```python
# Standard Parameter
--flag_lip_zero False          # Lippenbewegungen aktiviert
--flag_eye_retargeting False   # Augen-Bewegungen deaktiviert
--flag_stitching True          # Stitching aktiviert
--flag_relative True           # Relative Bewegungen
--driving_multiplier 1.7       # Bewegungs-Multiplikator (User-anpassbar)
--flag_pasteback True          # Pasteback aktiviert
--flag_do_crop True            # Auto-Crop aktiviert
```

#### FFmpeg Installation & Version

**WICHTIG:** LivePortrait nutzt `imageio-ffmpeg` (Version 7.0.2), welches eigene FFmpeg-Binaries mitbringt!

```bash
# System FFmpeg (optional, wird nicht von LivePortrait genutzt)
apt-get install -y ffmpeg  # Version variiert

# imageio-ffmpeg (WICHTIG für LivePortrait!)
pip install imageio[ffmpeg]==2.37.0
```

**FFmpeg-Versionen:**
- System: 4.4.2 (Ubuntu/Debian)
- imageio-ffmpeg: 7.0.2 (gebundelt)
- **LivePortrait nutzt:** imageio-ffmpeg 7.0.2

#### LivePortrait Workflow

```
Input:
- hero_image.jpg (Hero-Image, z.B. 512x512)
- hero_video.mp4 (Hero-Video, max. 10s, 29 FPS)

LivePortrait Verarbeitung:
1. Face Detection & Cropping
2. Motion Extraction (aus hero_video.mp4)
3. Animation Generation
4. Atlas/Mask/ROI Generation
5. Video Concatenation (Loop)
6. Audio Merge (optional)

Output:
- idle.mp4 (animiertes Gesicht, 29 FPS, H.264)
- atlas.jpg (Textur-Atlas)
- mask.png (Alpha-Maske)
- atlas.json (Atlas-Koordinaten)
- roi.json (Region of Interest)
```

---

## 2. Modal.com - GPU Cloud Platform

### Was ist Modal.com?

Modal.com ist eine Cloud-Plattform für ML/AI-Workloads mit:
- **GPU-Beschleunigung** (NVIDIA A100, T4, etc.)
- **Serverless Functions** (wie AWS Lambda, aber für ML)
- **Container-basiert** (Docker)
- **Auto-Scaling**

### Modal.com Setup

#### 1. Account & Installation

```bash
# Modal CLI installieren
pip install modal==0.69.194

# Login
modal token new
# → Öffnet Browser für Login
# → Token wird lokal gespeichert (~/.modal.toml)
```

#### 2. Modal App Konfiguration (`modal_dynamics.py`)

```python
import modal

# Modal App definieren
app = modal.App("sunriza-dynamics")

# Docker Image mit LivePortrait
image = (
    modal.Image.from_registry(
        "nvidia/cuda:12.6.0-cudnn-devel-ubuntu22.04",
        add_python="3.11"
    )
    .apt_install([
        "git",
        "ffmpeg",
        "libsm6",
        "libxext6",
        "libxrender-dev",
        "libgomp1",
        "libglib2.0-0",
    ])
    .pip_install([
        "torch==2.6.0",
        "torchvision==0.20.0",
        "--index-url", "https://download.pytorch.org/whl/cu121",
    ])
    .pip_install([
        "numpy==2.2.6",
        "onnxruntime-gpu==1.20.1",
        "onnx==1.19.1",
        "opencv-python-headless==4.12.0.88",
        "tyro==0.9.34",
        "pyyaml==6.0.3",
        "tqdm==4.67.1",
        "imageio[ffmpeg]==2.37.0",
        "scikit-image==0.25.2",
        "pykalman==0.10.2",
        "firebase-admin==6.6.0",
        "google-cloud-storage==2.18.2",
        "Pillow==11.0.0",
        "fastapi",
    ])
    .run_commands([
        "git clone https://github.com/KwaiVGI/LivePortrait.git /opt/liveportrait",
        "pip install -e /opt/liveportrait",
        "huggingface-cli download KwaiVGI/LivePortrait --local-dir /opt/liveportrait/pretrained_weights",
    ])
)
```

#### 3. Modal Secrets Setup

**Firebase Service Account:**
```bash
# In Modal Dashboard: Settings → Secrets
# Secret Name: firebase-service-account
# Type: JSON
# Content: Inhalt von service-account-key.json
```

**Wichtig:** Das Secret wird in Modal als Environment Variable verfügbar gemacht:
```python
@app.function(
    image=image,
    gpu="any",  # oder "A100", "T4", etc.
    timeout=600,
    secrets=[modal.Secret.from_name("firebase-service-account")]
)
```

#### 4. Modal Deployment

```bash
# Deploy
modal deploy modal_dynamics.py

# Ausgabe:
# ✓ Created function generate_dynamics
# ✓ View endpoint: https://romeo1971--sunriza-dynamics-generate-dynamics.modal.run
```

**Endpoint URL Format:**
```
https://romeo1971--sunriza-dynamics-generate-dynamics.modal.run
```

#### 5. Modal GPU Konfiguration

**Verfügbare GPU-Typen:**
- `"any"` - Beliebige verfügbare GPU (empfohlen)
- `"T4"` - NVIDIA Tesla T4 (16GB VRAM)
- `"A10G"` - NVIDIA A10G (24GB VRAM)
- `"A100"` - NVIDIA A100 (40GB/80GB VRAM)

**Performance:**
- **CPU:** ~2-3 Minuten für 10s Video
- **GPU (T4):** ~30-45 Sekunden für 10s Video
- **GPU (A100):** ~15-20 Sekunden für 10s Video

#### 6. Modal Kosten (Stand 2025)

**Compute:**
- CPU: $0.0001/s
- GPU T4: $0.0008/s
- GPU A100: $0.0032/s

**Storage:**
- Gratis bis 10GB
- $0.10/GB/Monat darüber

**Beispiel-Rechnung (10s Video mit T4):**
- Generierungszeit: 45s
- Kosten: 45s × $0.0008/s = **$0.036 pro Video**

---

## 3. Firebase Functions - Video Trimming

### Firebase Functions Setup

#### 1. Firebase CLI Installation

```bash
npm install -g firebase-tools
firebase login
firebase init functions
```

#### 2. Functions Dependencies (`functions/package.json`)

```json
{
  "name": "functions",
  "engines": {
    "node": "18"
  },
  "dependencies": {
    "firebase-admin": "^12.7.0",
    "firebase-functions": "^6.1.1",
    "fluent-ffmpeg": "^2.1.3",
    "node-fetch": "^2.7.0",
    "cors": "^2.8.5"
  },
  "devDependencies": {
    "typescript": "^5.7.2",
    "@typescript-eslint/eslint-plugin": "^8.18.2",
    "@typescript-eslint/parser": "^8.18.2",
    "eslint": "^9.18.0"
  }
}
```

#### 3. FFmpeg Installation (Firebase Functions)

FFmpeg wird automatisch in Firebase Functions Layer installiert:

```typescript
// functions/src/index.ts
import * as ffmpegInstaller from '@ffmpeg-installer/ffmpeg';
import * as ffmpeg from 'fluent-ffmpeg';

const ffmpegPath = ffmpegInstaller.path;
if (ffmpegPath) {
  (ffmpeg as any).setFfmpegPath(ffmpegPath);
}
```

#### 4. Firebase Functions Deployment

```bash
cd functions
npm install
npm run build
firebase deploy --only functions
```

**Deployed Function URL:**
```
https://us-central1-sunriza26.cloudfunctions.net/trimVideo
```

#### 5. Firebase Functions Konfiguration

**Ressourcen:**
```typescript
export const trimVideo = functions
  .runWith({
    timeoutSeconds: 180,  // 3 Minuten Timeout
    memory: '2GB'          // 2GB RAM
  })
  .https.onRequest(async (req, res) => {
    // ...
  });
```

**CORS Setup:**
```typescript
import * as cors from 'cors';
const corsHandler = cors({ origin: true });

corsHandler(req, res, async () => {
  // Function body
});
```

---

## 4. Flutter App - Frontend

### Flutter Version & Dependencies

#### 1. Flutter SDK

```bash
flutter --version
# Flutter 3.24.5 • channel stable
# Dart 3.5.4
```

#### 2. Flutter Dependencies (`pubspec.yaml`)

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Firebase
  firebase_core: ^3.8.1
  firebase_auth: ^5.3.3
  firebase_storage: ^12.3.8
  cloud_firestore: ^5.5.1
  firebase_database: ^11.1.7

  # Video
  video_player: ^2.9.2
  chewie: ^1.8.5
  image_picker: ^1.1.2

  # HTTP
  http: ^1.2.2

  # State Management
  provider: ^6.1.2

  # UI
  flutter_svg: ^2.0.10+1
  cached_network_image: ^3.4.1
  
  # Utilities
  path_provider: ^2.1.4
  path: ^1.9.0
  intl: ^0.19.0
```

#### 3. Flutter Service: DynamicsServiceModal

**Location:** `lib/services/dynamics_service_modal.dart`

```dart
class DynamicsServiceModal {
  static const String modalEndpoint = 
    'https://romeo1971--sunriza-dynamics-generate-dynamics.modal.run';

  Future<Map<String, dynamic>> generateDynamics({
    required String avatarId,
    required String dynamicsId,
    required String heroImageUrl,
    required String heroVideoUrl,
    required double drivingMultiplier,
    required double scaleMultiplier,
    required int stitchingRetargetingEyesWidth,
  }) async {
    final response = await http.post(
      Uri.parse(modalEndpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'avatar_id': avatarId,
        'dynamics_id': dynamicsId,
        'hero_image_url': heroImageUrl,
        'hero_video_url': heroVideoUrl,
        'driving_multiplier': drivingMultiplier,
        'scale_multiplier': scaleMultiplier,
        'stitching_retargeting_eyes_width': stitchingRetargetingEyesWidth,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Backend error: ${response.statusCode}');
    }

    return jsonDecode(response.body);
  }
}
```

#### 4. Flutter Service: VideoTrimService

**Location:** `lib/services/video_trim_service.dart`

```dart
class VideoTrimService {
  static const String firebaseFunctionUrl = 
    'https://us-central1-sunriza26.cloudfunctions.net/trimVideo';

  static Future<String?> showTrimDialogAndTrim({
    required BuildContext context,
    required String videoUrl,
    required String avatarId,
    double maxDuration = 10.0,
  }) async {
    // Zeigt Trim-Dialog
    // Ruft Firebase Function auf
    // Uploaded getrimmtes Video
    // Erstellt Firestore Video-Document
    // Gibt neue Video-URL zurück
  }
}
```

#### 5. Flutter Video Player Implementation

**Custom Controls mit Timer:**

```dart
// details_video_media_section.dart
Stack(
  children: [
    // Video (gecroppt)
    ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
        ),
      ),
    ),
    
    // Play/Pause Icon
    ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, VideoPlayerValue value, child) {
        return Icon(
          value.isPlaying ? Icons.pause : Icons.play_arrow,
        );
      },
    ),
    
    // Timer (läuft hoch)
    ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, VideoPlayerValue value, child) {
        return Text(
          _formatDuration(value.position),
          style: TextStyle(
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        );
      },
    ),
  ],
)
```

---

## 5. Firebase Storage & Firestore

### Firebase Storage Struktur

```
avatars/
├── {avatarId}/
│   ├── images/
│   │   ├── hero_image.jpg
│   │   ├── image1.jpg
│   │   └── ...
│   ├── videos/
│   │   ├── hero_video.mp4
│   │   ├── video1.mp4
│   │   └── thumbnails/
│   │       ├── video1_thumb.jpg
│   │       └── ...
│   └── dynamics/
│       ├── basic/
│       │   ├── idle.mp4
│       │   ├── atlas.jpg
│       │   ├── mask.png
│       │   ├── atlas.json
│       │   └── roi.json
│       └── advanced/
│           └── ...
```

### Firestore Daten-Struktur

```javascript
// Collection: avatars
{
  "avatarId": "ABC123",
  "name": "Schatzy",
  "profileImageUrl": "https://...",
  "training": {
    "heroImageUrl": "https://...",
    "heroVideoUrl": "https://...",
    "imageUrls": ["https://...", ...],
    "videoUrls": ["https://...", ...]
  },
  "dynamics": {
    "basic": {
      "status": "ready",  // "generating", "ready", "error"
      "idleVideoUrl": "https://.../idle.mp4",
      "atlasUrl": "https://.../atlas.jpg",
      "maskUrl": "https://.../mask.png",
      "atlasJsonUrl": "https://.../atlas.json",
      "roiJsonUrl": "https://.../roi.json",
      "parameters": {
        "drivingMultiplier": 1.7,
        "scaleMultiplier": 0.41,
        "stitchingRetargetingEyesWidth": 1600
      },
      "createdAt": Timestamp,
      "updatedAt": Timestamp
    }
  }
}
```

---

## 6. Deployment Workflow

### Lokale Entwicklung

```bash
# 1. Flutter App (lokal)
flutter run

# 2. Modal.com (lokal testen)
modal run modal_dynamics.py

# 3. Firebase Functions (lokal emulieren)
firebase emulators:start --only functions
```

### Production Deployment

```bash
# 1. Modal.com Deploy
modal deploy modal_dynamics.py

# 2. Firebase Functions Deploy
cd functions
npm run build
firebase deploy --only functions

# 3. Flutter App Build
flutter build apk --release  # Android
flutter build ios --release  # iOS
```

---

## 7. Wichtige Versionen - Zusammenfassung

### Python & ML
- Python: **3.11**
- PyTorch: **2.6.0** (cu121)
- ONNX Runtime GPU: **1.20.1**
- NumPy: **2.2.6**
- OpenCV: **4.12.0.88**
- imageio[ffmpeg]: **2.37.0** (FFmpeg 7.0.2)
- Firebase Admin: **6.6.0**
- Modal: **0.69.194**

### CUDA & GPU
- CUDA: **12.6.0**
- cuDNN: **9** (via PyTorch)
- NVIDIA Driver: Latest

### Firebase
- Firebase Functions: **6.1.1**
- Firebase Admin: **12.7.0**
- Node.js: **18**
- FFmpeg (Functions): via `@ffmpeg-installer/ffmpeg`

### Flutter
- Flutter: **3.24.5**
- Dart: **3.5.4**
- Firebase Core: **3.8.1**
- Video Player: **2.9.2**
- Chewie: **1.8.5**

---

## 8. Troubleshooting

### LivePortrait Fehler

**Problem: "CUDAExecutionProvider not available"**
- **Ursache:** ONNX Runtime GPU nicht korrekt installiert
- **Lösung:** `pip install onnxruntime-gpu==1.20.1` mit CUDA 12.6

**Problem: "NumPy version mismatch"**
- **Ursache:** NumPy 1.x vs 2.x Inkompatibilität
- **Lösung:** `pip install numpy==2.2.6`

**Problem: "cuDNN not found"**
- **Ursache:** PyTorch installiert cuDNN 9, aber ONNX Runtime braucht cuDNN 8
- **Lösung:** Nutze NVIDIA CUDA Base Image mit passender cuDNN Version

### Modal.com Fehler

**Problem: "Volume /tmp cannot be mounted"**
- **Ursache:** `/tmp` ist reserved in Modal
- **Lösung:** Nutze `/tmp` ohne Volume Mount

**Problem: "Build cached, no changes applied"**
- **Ursache:** Modal cached Docker Image
- **Lösung:** Ändere Base Image Tag oder füge Dummy-Command hinzu

### Firebase Fehler

**Problem: "Timeout after 120s"**
- **Ursache:** Video-Trimming dauert zu lange
- **Lösung:** Erhöhe Timeout auf 180s+ und nutze Stream Copy statt Re-Encoding

### Flutter Fehler

**Problem: "Video not displaying"**
- **Ursache:** Atlas/Mask/ROI fehlen in Firestore
- **Lösung:** Prüfe ob alle Assets hochgeladen wurden

**Problem: "Timer jumping"**
- **Ursache:** Variable Font Width
- **Lösung:** Nutze `fontFeatures: [FontFeature.tabularFigures()]`

---

## 9. Performance Optimierung

### LivePortrait
- Nutze GPU (30x schneller als CPU)
- Trimme Videos auf max. 10s vor Verarbeitung
- Cache Pretrained Weights in Docker Image

### Modal.com
- Nutze `gpu="any"` für beste Verfügbarkeit
- Setze `timeout=600` für lange Videos
- Cache Docker Image (automatisch nach 1. Build)

### Firebase Storage
- Nutze CDN URLs (`alt=media`)
- Komprimiere Videos mit H.264 (CRF 23)
- Generiere Thumbnails für schnelle Previews

### Flutter
- Cache Video Thumbnails lokal
- Nutze `VideoPlayerController` Caching
- Lazy-Load Videos in Galerie

---

## 10. Kosten-Übersicht (monatlich)

### Modal.com
- 100 Videos/Monat à 10s mit T4 GPU: **$3.60**
- Storage (10GB): **Gratis**

### Firebase
- Functions (100 Invocations): **Gratis** (Free Tier)
- Storage (10GB): **$0.26/Monat**
- Firestore (50k Reads, 20k Writes): **Gratis** (Free Tier)

### Gesamt
- **≈ $4-5/Monat** für 100 Videos + Storage

---

## 11. Sicherheit & Best Practices

### API Keys
- ✅ Service Account Keys als Modal Secrets
- ✅ Firebase API Keys in `.env` (nicht in Git!)
- ✅ CORS nur für eigene Domain aktivieren

### Video Upload
- ✅ Max. 10s Video-Länge erzwingen
- ✅ Max. 50MB File Size Limit
- ✅ Validate Video Format (MP4, H.264)

### Firebase Rules
- ✅ Nur authentifizierte User können eigene Avatare bearbeiten
- ✅ Read-only für öffentliche Avatare
- ✅ Storage Rules: Max. 50MB pro Upload

---

## 12. Monitoring & Logs

### Modal.com
- Dashboard: https://modal.com/apps/romeo1971
- Logs: Real-time in Modal Dashboard
- Metrics: Execution Time, GPU Usage, Costs

### Firebase
- Console: https://console.firebase.google.com
- Functions Logs: Cloud Console → Functions → Logs
- Storage: Firebase Console → Storage

### Flutter
- Crashlytics (optional)
- Firebase Analytics (optional)
- Custom Logging via `debugPrint()`

---

**Erstellt:** 2025-01-18  
**Letzte Aktualisierung:** 2025-01-18  
**Version:** 1.0

