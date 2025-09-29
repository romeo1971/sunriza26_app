# Sunriza26 - Live AI Assistant

Eine revolutionäre Flutter-App mit Live AI-Assistenten, geklonter Stimme und Echtzeit-Video-Lippensynchronisation.

## 🚀 Features

- **Geklonte Stimme**: Verwendet Google Cloud Text-to-Speech mit Custom Voice Models
- **Live-Video-Lippensynchronisation**: Vertex AI Generative AI für Echtzeit-Video-Synthese
- **Streaming-Optimiert**: Direkte Video-Übertragung ohne Zwischenspeicherung
- **Cross-Platform**: Flutter-App für Android, iOS und Web
- **Firebase-Integration**: Cloud Functions, Storage und Secret Manager

## 🏗️ Architektur

### Backend (Firebase Cloud Functions)
- **Text-to-Speech**: Google Cloud TTS API mit Custom Voice
- **Video-Generierung**: Vertex AI Generative AI für Lippen-Synchronisation
- **Streaming**: HTTP-Streaming für Live-Video-Übertragung
- **Sicherheit**: Firebase Secret Manager für API-Schlüssel

### Frontend (Flutter)
- **Live-Video-Player**: Chewie-basierter Video-Player
- **Streaming-Client**: HTTP-Stream-Parser für Echtzeit-Video
- **State-Management**: Provider für App-State
- **UI/UX**: Material Design 3 mit Dark Theme

## 📋 Voraussetzungen

### Google Cloud Setup
1. **Firebase Projekt**: `tomorrow-3e1c8` auf Blaze-Plan
2. **APIs aktivieren**:
   - Cloud Text-to-Speech API
   - Vertex AI API
   - Secret Manager API
   - Cloud Functions API
   - Cloud Storage API

### Custom Voice Training
1. Audio-Aufnahmen bereitstellen (mindestens 30 Minuten)
2. Custom Voice Model in Google Cloud Console trainieren
3. Voice-Name in Secret Manager speichern

### Referenzvideo
1. 3-minütiges Referenzvideo in Firebase Cloud Storage hochladen
2. URL in Secret Manager konfigurieren

## 🛠️ Installation

### 1. Dependencies installieren

```bash
# Flutter Dependencies
flutter pub get

# Firebase Functions Dependencies
cd functions
npm install
```

### 2. Firebase konfigurieren

```bash
# Firebase CLI installieren (falls nicht vorhanden)
npm install -g firebase-tools

# Firebase Login
firebase login

# Projekt auswählen
firebase use tomorrow-3e1c8
```

### 3. Secrets konfigurieren

```bash
# Secrets in Firebase Secret Manager setzen
firebase functions:secrets:set GOOGLE_CLOUD_PROJECT_ID
firebase functions:secrets:set GOOGLE_CLOUD_LOCATION
firebase functions:secrets:set CUSTOM_VOICE_NAME
firebase functions:secrets:set REFERENCE_VIDEO_URL
```

### 4. Deployment

```bash
# Cloud Functions deployen
firebase deploy --only functions

# Flutter App builden und deployen
flutter build web
firebase deploy --only hosting
```

## 🎯 Verwendung

### 1. App starten
```bash
flutter run
```

### 2. Text eingeben
- Geben Sie den gewünschten Text in das Eingabefeld ein
- Klicken Sie auf "Video generieren"

### 3. Live-Video ansehen
- Das Video wird in Echtzeit generiert und gestreamt
- Lippen-Synchronisation erfolgt automatisch
- Video kann pausiert/fortgesetzt werden

### 4. TTS-Test
- Verwenden Sie "TTS-Test" für reine Audio-Ausgabe
- Nützlich für Debugging und schnelle Tests

## 🔧 Konfiguration

### Environment Variables
```bash
# In functions/.env (für lokale Entwicklung)
GOOGLE_CLOUD_PROJECT_ID=tomorrow-3e1c8
GOOGLE_CLOUD_LOCATION=us-central1
CUSTOM_VOICE_NAME=projects/tomorrow-3e1c8/locations/us-central1/voices/your-voice
REFERENCE_VIDEO_URL=gs://tomorrow-3e1c8.appspot.com/reference-video.mp4
```

### Firebase-Konfiguration
- `firebase_options.dart` mit echten API-Keys aktualisieren
- Projekt-ID und andere Firebase-Konfiguration anpassen

## 📊 Monitoring

### Cloud Functions Logs
```bash
firebase functions:log
```

### Google Cloud Console
- Cloud Functions: Überwachung und Logs
- Vertex AI: Modell-Performance und Kosten
- Text-to-Speech: API-Nutzung und Limits

## 💰 Kosten

### Google Cloud Services
- **Text-to-Speech**: ~$4.00 pro 1M Zeichen
- **Vertex AI**: ~$0.10-0.50 pro Video-Minute
- **Cloud Functions**: ~$0.40 pro 1M Aufrufe
- **Cloud Storage**: ~$0.020 pro GB/Monat

### Optimierung
- Regionen nahe an Nutzern wählen
- Video-Qualität je nach Anwendungsfall anpassen
- Caching für wiederholte Anfragen implementieren

## 🐛 Debugging

### Häufige Probleme
1. **Custom Voice nicht gefunden**: Voice-Name in Secret Manager prüfen
2. **Video-Stream unterbrochen**: Netzwerk-Verbindung und Timeouts prüfen
3. **Hohe Latenz**: Regionen und CDN optimieren

### Logs prüfen
```bash
# Flutter Logs
flutter logs

# Firebase Functions Logs
firebase functions:log --only generateLiveVideo
```

## 🚀 Roadmap

### Version 2.0
- [ ] WebRTC für noch niedrigere Latenz
- [ ] Multiple Custom Voices
- [ ] Video-Templates und -Effekte
- [ ] Batch-Processing für mehrere Videos

### Version 3.0
- [ ] Real-time Voice Cloning
- [ ] Multi-Language Support
- [ ] Advanced Video Effects
- [ ] API für Drittanbieter-Integration

## 📄 Lizenz

Dieses Projekt ist unter der MIT-Lizenz lizenziert.

## 🤝 Beitragen

Beiträge sind willkommen! Bitte erstellen Sie ein Issue oder einen Pull Request.

## 📞 Support

Bei Fragen oder Problemen:
- GitHub Issues erstellen
- Firebase Support kontaktieren
- Google Cloud Support für API-Probleme

---

**Stand: 04.09.2025** - Optimiert für die neuesten Google Cloud AI-Services

## 🌐 Lokalisierung – Sprachdateien automatisch pflegen

Fehlende Übersetzungen in `assets/lang/*.json` können automatisch aufgefüllt werden.

Skript: `scripts/update_lang_translations.py`

- Quelle wählen: `--source en` oder `--source de`
- Nur bestimmte Keys (Prefix): `--only-prefix avatars.details.`
- Englische Fallbacks überschreiben: `--overwrite-english`
- Trockendurchlauf: `--dry-run`

Beispiele:

```bash
# Nur Keys unter avatars.details.* anhand EN auffüllen
python3 scripts/update_lang_translations.py --source en --only-prefix avatars.details.

# Alle fehlenden Werte anhand DE auffüllen, vorhandene EN-Fallbacks neu übersetzen
python3 scripts/update_lang_translations.py --source de --overwrite-english

# Mit DeepL-Autotranslate (falls verfügbar)
export DEEPL_API_KEY=your_key
python3 scripts/update_lang_translations.py --source en --only-prefix avatars.details.
```

Hinweis:
- Ohne DeepL-Key werden fehlende Werte mit dem Quelltext befüllt (Fallback).
- Das Skript korrigiert auch bekannte Tippfehler-Keys (z. B. `ls.regionTitle`).