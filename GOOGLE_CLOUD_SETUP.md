# Google Cloud Vision API Setup

## 1. Google Cloud Console Setup

1. Gehe zu [Google Cloud Console](https://console.cloud.google.com/)
2. Erstelle ein neues Projekt oder wähle ein bestehendes aus
3. Aktiviere die **Cloud Vision API**:
   - Gehe zu "APIs & Services" > "Library"
   - Suche nach "Cloud Vision API"
   - Klicke "Enable"

## 2. Service Account erstellen

1. Gehe zu "APIs & Services" > "Credentials"
2. Klicke "Create Credentials" > "Service Account"
3. Gib einen Namen ein (z.B. "vision-api-service")
4. Klicke "Create and Continue"
5. Wähle "Cloud Vision API User" als Rolle
6. Klicke "Done"

## 3. Service Account Key herunterladen

1. Klicke auf den erstellten Service Account
2. Gehe zum "Keys" Tab
3. Klicke "Add Key" > "Create new key"
4. Wähle "JSON" Format
5. Lade die JSON-Datei herunter

## 4. JSON Key in App integrieren

1. Kopiere die heruntergeladene JSON-Datei in `assets/` Ordner
2. Benenne sie um zu `service-account-key.json`
3. Öffne die JSON-Datei und kopiere den Inhalt
4. Ersetze in `lib/services/cloud_vision_service.dart` die Platzhalter:
   - `"project_id": "your-project-id"` → deine Project ID
   - `"private_key_id": "your-private-key-id"` → aus der JSON
   - `"private_key": "-----BEGIN PRIVATE KEY-----\nYOUR_PRIVATE_KEY\n-----END PRIVATE KEY-----\n"` → aus der JSON
   - `"client_email": "your-service-account@your-project-id.iam.gserviceaccount.com"` → aus der JSON
   - `"client_id": "your-client-id"` → aus der JSON
   - `"client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/your-service-account%40your-project-id.iam.gserviceaccount.com"` → aus der JSON

## 5. Kosten

- **Erste 1000 Bilder pro Monat**: KOSTENLOS
- **Danach**: ~$1.50 pro 1000 Bilder
- **Preise**: https://cloud.google.com/vision/pricing

## 6. Was wird erkannt

Die API erkennt ALLES:
- ✅ **Personen**: man, woman, person, face
- ✅ **Kleidung**: hat, shirt, pants, dress
- ✅ **Objekte**: car, tree, building, phone
- ✅ **Szenen**: outdoor, beach, park, indoor
- ✅ **Explizite Inhalte**: adult, nude, racy, violence
- ✅ **Emotionen**: happy, sad, angry, surprised
- ✅ **Text**: Erkannte Texte im Bild
- ✅ **Logos**: Marken und Logos
- ✅ **Landmarks**: Bekannte Orte
- ✅ **Web-Entitäten**: Ähnliche Bilder im Web

## 7. Testen

Nach dem Setup:
1. Lade ein Bild hoch
2. Schaue in die Konsole für erkannte Tags
3. Teste die Suche mit verschiedenen Begriffen
