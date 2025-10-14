# 🚀 Render.com Deployment Anleitung

## ✅ Voraussetzungen

- [x] Render.com Account erstellt
- [x] GitHub Account verbunden
- [ ] Backend Code in Git Repository
- [ ] Firebase Service Account Key

---

## 📋 Schritt-für-Schritt Anleitung

### 1️⃣ **Code zu Git pushen**

```bash
# Im sunriza26 Verzeichnis
cd /Users/hhsw/Desktop/sunriza/sunriza26

# Git initialisieren (falls noch nicht geschehen)
git add backend/

# Commit
git commit -m "Add Render.com deployment files"

# Push zu GitHub
git push origin main
```

---

### 2️⃣ **Render.com Service erstellen**

1. Gehe zu https://dashboard.render.com
2. Klicke **"New +"** → **"Blueprint"**
3. Wähle dein **GitHub Repository** aus
4. Render erkennt automatisch `backend/render.yaml`
5. Klicke **"Apply"**

**Alternativ: Manuell erstellen**
1. **"New +"** → **"Web Service"**
2. Verbinde dein GitHub Repo
3. Settings:
   - **Name:** `sunriza-backend`
   - **Region:** Frankfurt (EU)
   - **Branch:** `main`
   - **Root Directory:** `backend`
   - **Environment:** Docker
   - **Dockerfile Path:** `./Dockerfile`
   - **Plan:** Starter ($7/Monat)

---

### 3️⃣ **Umgebungsvariablen setzen**

Im Render Dashboard → Service → **Environment**:

```yaml
LIVEPORTRAIT_PATH=/opt/liveportrait/inference.py
PYTORCH_ENABLE_MPS_FALLBACK=1
PORT=8002
```

---

### 4️⃣ **Firebase Service Account hochladen**

**Wichtig:** Der Service Account Key muss als **Secret File** hochgeladen werden!

1. Im Render Dashboard → Service → **Secret Files**
2. Klicke **"Add Secret File"**
3. **Filename:** `service-account-key.json`
4. **Contents:** Kopiere den Inhalt von `/Users/hhsw/Desktop/sunriza/sunriza26/service-account-key.json`
5. **Save**

---

### 5️⃣ **Deployment starten**

1. Render startet automatisch das Deployment
2. **Build-Zeit:** ~10-15 Minuten (beim ersten Mal)
   - Python Installation
   - Dependencies Installation
   - LivePortrait Git Clone
   - Pretrained Weights Download

3. **Status verfolgen:**
   - Dashboard → Service → **Logs**
   - Warte bis "Build succeeded"

---

### 6️⃣ **Service URL bekommen**

Nach erfolgreichem Deployment:
- URL: `https://sunriza-backend.onrender.com`
- Health Check: `https://sunriza-backend.onrender.com/health`
- API Docs: `https://sunriza-backend.onrender.com/docs`

---

### 7️⃣ **Flutter App anpassen**

Im `.env` File:

```env
# Alte Zeile (lokal):
# DYNAMICS_API_BASE_URL=http://localhost:8002

# Neue Zeile (Produktion):
DYNAMICS_API_BASE_URL=https://sunriza-backend.onrender.com
```

---

## 🧪 Testen

### **Health Check**
```bash
curl https://sunriza-backend.onrender.com/health
```

Erwartete Response:
```json
{"status": "healthy", "service": "sunriza26-backend"}
```

### **Dynamics Generierung testen**
```bash
curl -X POST https://sunriza-backend.onrender.com/generate-dynamics \
  -H "Content-Type: application/json" \
  -d '{
    "avatar_id": "test123",
    "dynamics_id": "basic",
    "parameters": {
      "driving_multiplier": 0.41,
      "scale": 1.7,
      "source_max_dim": 1600
    }
  }'
```

---

## ⚠️ Wichtige Hinweise

### **Cold Start**
- Render pausiert Services nach 15 Min Inaktivität (Free/Starter Plan)
- Erste Anfrage nach Pause: ~30 Sekunden bis Service wieder läuft
- **Lösung:** Upgrade auf Standard Plan ($25/Monat) → No Cold Start

### **CPU-only**
- Render.com hat **keine GPU** → Generierung ist **3x langsamer**
- Erwartete Zeit: **9-15 Minuten** (statt 3-5 Min mit GPU)
- Backend schätzt Zeit automatisch

### **Disk Space**
- Temporäre Videos werden in `/tmp` gespeichert
- 5 GB Disk Space konfiguriert
- Videos werden nach Upload gelöscht

### **LivePortrait Weights**
- Werden beim ersten Build heruntergeladen (~500 MB)
- Bei jedem neuen Build werden sie neu geladen
- **Hinweis:** Erste Generierung kann länger dauern

---

## 💰 Kosten

| Plan | Preis | Features |
|------|-------|----------|
| **Free** | $0/Monat | 750 Stunden/Monat, Cold Start nach 15 Min |
| **Starter** | $7/Monat | Mehr RAM, weniger Cold Starts |
| **Standard** | $25/Monat | Kein Cold Start, mehr Performance |

**Empfehlung für Start:** Starter ($7/Monat)

---

## 🔄 Auto-Deploy

Jedes Mal wenn du zu `main` pushst, deployed Render automatisch:

```bash
git add .
git commit -m "Update backend"
git push origin main
# → Render deployed automatisch!
```

---

## 🐛 Troubleshooting

### **Build schlägt fehl**
```bash
# Logs checken im Render Dashboard
# Häufige Probleme:
# - service-account-key.json fehlt
# - LivePortrait Weights nicht heruntergeladen
# - Python Dependencies fehlen
```

### **Service startet nicht**
```bash
# Health Check prüfen:
curl https://sunriza-backend.onrender.com/health

# Logs checken:
# Dashboard → Service → Logs → "Runtime Logs"
```

### **Generierung zu langsam**
```bash
# Normal für CPU-only!
# Erwarte 9-15 Minuten
# Für schneller: Google Cloud Run mit GPU nutzen
```

---

## 🎯 Nächste Schritte

1. ✅ Service deployen
2. ✅ Health Check testen
3. ✅ Flutter `.env` anpassen
4. ✅ Test-Generierung durchführen
5. ✅ In echter App testen

**Bei Problemen:** Check die Logs im Render Dashboard!

---

## 📞 Support

- Render Docs: https://docs.render.com
- LivePortrait: https://github.com/KwaiVGI/LivePortrait
- Sunriza Backend: `/backend/PRODUCTION_SETUP.md`

