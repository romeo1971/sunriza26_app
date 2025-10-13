# LivePortrait Parameter Log

## ✅ FINALE PRODUKTIONS-VERSION (17:18 Uhr - 13.10.2024)

### 🎯 BESTE VERSION (MIT KÖRPER, VOLLE QUALITÄT):
```bash
python LivePortrait/inference.py \
  -s schatzy_hero.jpg \
  -d <heroVideoUrl from Firebase> \
  -o idle.mp4 \
  --driving_multiplier 0.40 \
  --flag-normalize-lip \
  --animation-region all \
  --flag-pasteback \
  --source-max-dim 1600

# Post-Processing:
ffmpeg -i output.mp4 \
  -c:v libx264 \
  -preset slow \
  -crf 18 \
  -pix_fmt yuv420p \
  idle.mp4
```

### 📊 FINALE PARAMETER:

| Parameter | Wert | Bedeutung |
|-----------|------|-----------|
| `driving_multiplier` | **0.40** | 40% Intensität (perfekte Balance!) |
| `flag-normalize-lip` | **True** | Neutralisiert Lächeln im Source-Bild |
| `animation-region` | **all** | Volle Expression + Pose |
| `flag-pasteback` | **True** | ✅ WICHTIG: Behält Körper im Video! |
| `source-max-dim` | **1600** | Maximale Dimension (Source-Image Höhe) |
| `output-resolution` | **1200x1600** | Original-Größe (KEIN Downscaling!) |
| `ffmpeg-crf` | **18** | Höchste Qualität (18 statt 19) |

### 📈 VERLAUF (alle Versuche):

| Multiplier | Region | Normalize-Lip | Lip-Retarget | Ergebnis |
|------------|--------|---------------|--------------|----------|
| 0.08 | all | ❌ | ❌ | Nur Schaukeln, zu wenig |
| 0.15 | all | ❌ | ❌ | Kaum Veränderung |
| 0.35 | all | ✅ | ❌ | Fast gut, etwas steif |
| 0.45 | all | ✅ | ❌ | Gut, aber Mund zu offen |
| 0.50 | all | ✅ | ✅ | Gesicht eingefroren (nur Mund) |
| 0.65 | all | ❌ | ❌ | Dauerlächeln, zu stark |
| 0.70 | exp | ✅ | ❌ | Fratze! Zu extrem |
| **0.40** | **all** | **✅** | **❌** | **✅ FINALE VERSION!** |
| 0.42 | all | ✅ | ❌ | Dickeres Gesicht, verworfen! |

### 🎯 FINALE ENTSCHEIDUNG (17:18 Uhr):

**0.40 + flag-pasteback + KEIN Downscaling = PERFEKT!**

### 🔥 KRITISCHE ERKENNTNISSE:

1. **LivePortrait verarbeitet intern nur 512x512!**
   - Deshalb immer verpixelt, wenn man hochskaliert
   - **Lösung:** `--flag-pasteback` nutzt Original-Bild und fügt nur Gesicht ein!

2. **KEIN Downscaling auf 720x1280!**
   - Original-Auflösung behalten: 1200x1600
   - Körper bleibt sichtbar (wie im Source-Image)
   - FFmpeg nur für Codec-Konvertierung (H.264), NICHT skalieren!

3. **Qualitäts-Ablauf:**
   ```
   Source-Image: 1200x1600 ✅
   → LivePortrait (intern 512x512 für Gesicht)
   → flag-pasteback: Gesicht zurück ins Original (1200x1600) ✅
   → FFmpeg: Nur Codec (CRF 18) ✅
   → Output: 1200x1600 mit Körper! ✅
   ```

### 📝 WICHTIGE NOTIZEN:

- **Hero-Video** muss realistische Gesichts-Bewegungen haben (Lachen + neutral)
- **flag-pasteback** ist ESSENTIELL für Körper + Qualität!
- **source-max-dim** auf Höhe des Source-Images setzen
- **NIEMALS auf 720x1280 downskalieren** - zerstört Qualität!
- **0.40** ist empirisch ermittelter Mittelwert aus 10 Versuchen
- **CRF 18** für höchste Qualität (Standard war 19)

---

## Für Flutter Details Screen Slider:

```dart
// In avatar_details_screen.dart
double _livePortraitMultiplier = 0.40;  // Range: 0.0 - 1.0
bool _livePortraitNormalizeLip = true;
String _livePortraitRegion = 'all';  // 'all', 'exp', 'pose', 'lip', 'eyes'

// Speichern in Firestore:
training['livePortrait'] = {
  'drivingMultiplier': 0.40,
  'normalizeLip': true,
  'animationRegion': 'all',
};
```

