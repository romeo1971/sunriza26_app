# 🚀 Modal.com Setup für Sunriza26 Dynamics

## Warum Modal.com?

✅ **GPU on-demand** - Videos in 30 Sek statt 10 Min  
✅ **Nur zahlen bei Nutzung** - ~$0.01 pro Video  
✅ **Kein Docker-Chaos** - Modal baut alles automatisch  
✅ **Auto-Scaling** - 100 User gleichzeitig kein Problem  
✅ **ML-optimiert** - Perfekt für LivePortrait  

**Kosten:** GPU T4: $0.60/Stunde (nur bei aktiver Nutzung!)

---

## Setup (10 Minuten)

### 1. Modal.com Account erstellen

```bash
# Gehe zu: https://modal.com
# Klicke "Sign Up" → GitHub oder Email
```

### 2. Modal CLI installieren

```bash
pip install modal
```

### 3. Modal Auth

```bash
modal setup
```

→ Browser öffnet sich → Login → Token wird gespeichert

### 4. Firebase Credentials als Secret speichern

```bash
# service-account-key.json Inhalt kopieren
cat service-account-key.json | pbcopy

# Secret erstellen auf modal.com:
# 1. Gehe zu: https://modal.com/secrets
# 2. Klicke "New Secret"
# 3. Name: "firebase-credentials"
# 4. Type: "Custom"
# 5. Key: FIREBASE_CREDENTIALS
# 6. Value: <Paste JSON content>
# 7. Save
```

**ODER via CLI:**

```bash
modal secret create firebase-credentials FIREBASE_CREDENTIALS=@service-account-key.json
```

### 5. Deploy!

```bash
modal deploy modal_dynamics.py
```

**Output:**
```
✓ Created app sunriza-dynamics
✓ Deployed web endpoint api_generate_dynamics
  URL: https://your-workspace--sunriza-dynamics-api-generate-dynamics.modal.run
✓ Deployed web endpoint health
  URL: https://your-workspace--sunriza-dynamics-health.modal.run
```

**FERTIG!** 🎉

---

## Testen

### Health Check

```bash
curl https://your-workspace--sunriza-dynamics-health.modal.run
```

**Response:**
```json
{"status": "healthy", "service": "sunriza-dynamics-modal"}
```

### Dynamics generieren

```bash
curl -X POST https://your-workspace--sunriza-dynamics-api-generate-dynamics.modal.run \
  -H "Content-Type: application/json" \
  -d '{
    "avatar_id": "YOUR_AVATAR_ID",
    "dynamics_id": "basic",
    "parameters": {
      "driving_multiplier": 0.41,
      "scale": 1.7,
      "source_max_dim": 1600
    }
  }'
```

**Response (nach ~30 Sek):**
```json
{
  "status": "success",
  "avatar_id": "xyz",
  "dynamics_id": "basic",
  "video_url": "https://storage.googleapis.com/..."
}
```

---

## Flutter Integration

### 1. Backend URL setzen

In `.env` oder direkt im Code:

```dart
// lib/services/dynamics_service.dart
const DYNAMICS_BACKEND_URL = 'https://your-workspace--sunriza-dynamics-api-generate-dynamics.modal.run';
```

### 2. Request senden

```dart
Future<String> generateDynamics(String avatarId) async {
  final response = await http.post(
    Uri.parse(DYNAMICS_BACKEND_URL),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'avatar_id': avatarId,
      'dynamics_id': 'basic',
      'parameters': {
        'driving_multiplier': 0.41,
        'scale': 1.7,
        'source_max_dim': 1600,
      },
    }),
  );
  
  final data = jsonDecode(response.body);
  return data['video_url'];
}
```

---

## Monitoring & Logs

### Live Logs anschauen

```bash
modal app logs sunriza-dynamics
```

### Dashboard

https://modal.com/apps → sunriza-dynamics

Zeigt:
- Requests pro Tag
- GPU Nutzung
- Kosten
- Fehler

---

## Kosten-Rechnung

**Beispiel:**
- 1 Video = ~1 Minute GPU T4
- GPU T4 = $0.60/Stunde = $0.01/Minute
- **1 Video = $0.01**

**100 Videos/Tag:**
- 100 Videos × $0.01 = $1/Tag
- **~$30/Monat** (bei 100 Videos/Tag)

**Vergleich Cloud Run:**
- Always-on mit 4GB RAM: ~$50/Monat
- Keine GPU → 10x langsamer!

---

## Troubleshooting

### "Secret not found: firebase-credentials"

→ Secret erstellen: https://modal.com/secrets

### "GPU quota exceeded"

→ Modal.com kontaktieren für höhere Quota (oder warten bis nächste Stunde)

### Logs anschauen

```bash
modal app logs sunriza-dynamics --follow
```

---

## Next Steps

1. ✅ Modal deployed
2. ✅ Test läuft durch
3. → Flutter App umstellen auf Modal URL
4. → In Production gehen! 🚀

**Fragen? modal.com/docs**

