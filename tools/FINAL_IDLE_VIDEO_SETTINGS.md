# 🎬 FINALE idle.mp4 Generierung - Produktions-Einstellungen

**Stand:** 13. Oktober 2024, 17:18 Uhr  
**Status:** ✅ PRODUKTIONSBEREIT  
**Tester:** Schatzy Avatar  

---

## 🎯 SCHNELLSTART

```bash
cd /Users/hhsw/Desktop/sunriza/sunriza26
source venv/bin/activate
python tools/generate_idle_from_hero_video.py
```

**Das Script:**
1. Holt `heroVideoUrl` von Schatzy aus Firebase
2. Lädt Video herunter
3. Startet LivePortrait mit optimalen Parametern
4. Konvertiert zu H.264 (höchste Qualität)
5. Speichert nach `assets/avatars/schatzy/idle.mp4`

---

## ✅ FINALE PARAMETER

### LivePortrait CLI:
```bash
python /Users/hhsw/Desktop/sunriza/LivePortrait/inference.py \
  -s schatzy_hero.jpg \
  -d /tmp/schatzy_hero_video.mp4 \
  -o /tmp/idle_from_hero.mp4 \
  --driving_multiplier 0.40 \
  --flag-normalize-lip \
  --animation-region all \
  --flag-pasteback \
  --source-max-dim 1600
```

### FFmpeg Post-Processing:
```bash
ffmpeg -i input.mp4 \
  -c:v libx264 \
  -preset slow \
  -crf 18 \
  -pix_fmt yuv420p \
  -y output.mp4
```

---

## 📊 PARAMETER-DETAILS

| Parameter | Wert | Warum? |
|-----------|------|--------|
| `driving_multiplier` | **0.40** | Perfekte Balance (10 Versuche: 0.08-0.70) |
| `flag-normalize-lip` | **TRUE** | Neutralisiert Lächeln im Ruhezustand |
| `animation-region` | **all** | Volle Expression (Augen, Mund, Wangen, Kopf) |
| `flag-pasteback` | **TRUE** | 🔥 KRITISCH: Behält Körper + Original-Qualität! |
| `source-max-dim` | **1600** | Maximale Dimension = Source-Image Höhe |
| `ffmpeg crf` | **18** | Höchste Qualität (niedriger = besser) |

---

## 🔥 KRITISCHE ERKENNTNISSE

### Problem 1: Verpixelung
**Ursache:** LivePortrait verarbeitet intern nur 512x512  
**Lösung:** `--flag-pasteback` fügt animiertes Gesicht zurück ins Original-Bild!

### Problem 2: Körper fehlt
**Ursache:** Ohne `--flag-pasteback` croppt LivePortrait nur Gesicht  
**Lösung:** Mit `--flag-pasteback` bleibt Körper sichtbar!

### Problem 3: Downscaling auf 720x1280
**Ursache:** Wir haben fälschlicherweise für Mobile downgeskaliert  
**Lösung:** Original-Auflösung (1200x1600) behalten!

---

## 📈 QUALITÄTS-ABLAUF

```
1️⃣ Source-Image:        1200x1600 (Original mit Körper)
                        ↓
2️⃣ LivePortrait:        512x512 (intern, nur Gesicht)
                        ↓
3️⃣ flag-pasteback:      1200x1600 (Gesicht zurück ins Original!)
                        ↓
4️⃣ FFmpeg (CRF 18):     1200x1600 (Nur Codec, KEIN Resize!)
                        ↓
5️⃣ Output:              1200x1600 ✅ PERFEKT!
```

---

## 📝 VERLAUF (Alle Versuche)

| # | Multiplier | Pasteback | Resolution | Ergebnis |
|---|------------|-----------|------------|----------|
| 1 | 0.08 | ❌ | 512→720x1280 | Nur Schaukeln |
| 2 | 0.15 | ❌ | 512→720x1280 | Kaum Veränderung |
| 3 | 0.35 | ❌ | 512→720x1280 | Etwas steif |
| 4 | 0.45 | ❌ | 512→720x1280 | Mund zu offen |
| 5 | 0.50 | ❌ | 512→720x1280 | Eingefroren (lip-retarget) |
| 6 | 0.65 | ❌ | 512→720x1280 | Dauerlächeln |
| 7 | 0.70 | ❌ | 512→720x1280 | Fratze! |
| 8 | 0.40 | ❌ | 512→720x1280 | Gut, aber verpixelt |
| 9 | 0.40 | ❌ | 512→1200x1600 | Hochskaliert = verpixelt |
| 10 | **0.40** | **✅** | **Original** | **✅ PERFEKT!** |

---

## 🚀 FLUTTER INTEGRATION

### Aktueller Code:
```dart
// In avatar_chat_screen.dart
VideoPlayerController.asset('assets/avatars/schatzy/idle.mp4')
```

### Für Production (Firebase Storage):
```dart
// assets/avatars/{avatarId}/idle.mp4
final idleUrl = training['livePortrait']['idleVideoUrl'];
VideoPlayerController.network(idleUrl)
```

---

## 🎚️ ZUKÜNFTIGE SLIDER-INTEGRATION

### In avatar_details_screen.dart:
```dart
// State Variables
double _livePortraitMultiplier = 0.40;  // Range: 0.0 - 1.0
bool _livePortraitNormalizeLip = true;
String _livePortraitRegion = 'all';  // 'all', 'exp', 'pose', 'lip', 'eyes'

// Slider Widget (wie voiceStability)
Slider(
  value: _livePortraitMultiplier.clamp(0.0, 1.0),
  min: 0.0,
  max: 1.0,
  divisions: 20,
  label: _livePortraitMultiplier.toStringAsFixed(2),
  onChanged: (v) => setState(() => _livePortraitMultiplier = v),
  onChangeEnd: (_) => _saveLivePortraitParams(),
)

// Speichern in Firestore
training['livePortrait'] = {
  'drivingMultiplier': 0.40,
  'normalizeLip': true,
  'animationRegion': 'all',
  'idleVideoUrl': 'gs://...idle.mp4',
};
```

---

## 📦 REQUIREMENTS

### Python Packages:
```bash
pip install firebase-admin requests
```

### System Tools:
```bash
brew install ffmpeg
```

### LivePortrait:
```bash
# Bereits installiert in:
/Users/hhsw/Desktop/sunriza/LivePortrait/
```

---

## 🔧 TROUBLESHOOTING

### Problem: "Schatzy nicht gefunden"
**Lösung:** Script sucht nach `firstName` oder `nickname` = "Schatzy"

### Problem: Video verpixelt
**Lösung:** Prüfe ob `--flag-pasteback` gesetzt ist!

### Problem: Kein Körper sichtbar
**Lösung:** Prüfe ob `--flag-pasteback` gesetzt ist!

### Problem: Dauerlächeln
**Lösung:** Prüfe ob `--flag-normalize-lip` gesetzt ist!

### Problem: Fratze / zu stark
**Lösung:** Reduziere `--driving_multiplier` (aktuell 0.40)

---

## 📞 KONTAKT

Bei Fragen zu diesen Einstellungen:
- Dokumentation: `tools/LIVEPORTRAIT_PARAMS_LOG.md`
- Script: `tools/generate_idle_from_hero_video.py`
- ChatGPT Doku: `brain/live_avatar_full_bundle/`

---

**✅ DIESE EINSTELLUNGEN SIND PRODUKTIONSBEREIT!**

