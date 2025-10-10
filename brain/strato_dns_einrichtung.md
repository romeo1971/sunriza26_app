# 🌐 hauau.com mit Firebase verbinden - Strato Anleitung

## **Schritt-für-Schritt für Strato**

---

## **1️⃣ Firebase deployen**

```bash
cd /Users/hhsw/Desktop/sunriza/sunriza26
firebase deploy --only hosting
```

Deine App ist dann unter diesen URLs erreichbar:
- `https://sunriza26.web.app`
- `https://sunriza26.firebaseapp.com`

---

## **2️⃣ Custom Domain in Firebase hinzufügen**

1. **Firebase Console öffnen:**
   - https://console.firebase.google.com
   - Projekt **sunriza26** auswählen

2. **Hosting öffnen:**
   - Im linken Menü auf **Hosting** klicken

3. **Domain hinzufügen:**
   - Button **Custom domain hinzufügen** klicken
   - `hauau.com` eingeben (ohne www)
   - **Weiter** klicken

4. **DNS-Einträge notieren:**
   Firebase zeigt dir jetzt die benötigten DNS-Einträge an:
   ```
   TXT Record:
   @  →  google-site-verification=abc123xyz...

   A Records:
   @  →  151.101.1.195
   @  →  151.101.65.195
   ```
   ⚠️ **Diese Werte NICHT schließen** - du brauchst sie gleich!

---

## **3️⃣ DNS bei Strato einrichten**

### **A) Strato Kundencenter öffnen:**

1. Login: https://www.strato.de/apps/CustomerService
2. **Domains & SSL** → **Domains verwalten**
3. Domain **hauau.com** auswählen
4. **DNS-Einstellungen** oder **Managed DNS** klicken

### **B) DNS-Einträge anlegen:**

#### **1. TXT-Record für Verifizierung:**
```
Record-Typ:     TXT
Name/Host:      @ (oder leer lassen)
Wert/Value:     google-site-verification=abc123xyz...
TTL:            3600 (oder Standard)
```

#### **2. A-Records für die Domain:**

**Erster A-Record:**
```
Record-Typ:     A
Name/Host:      @ (oder leer lassen)
Ziel/Value:     151.101.1.195
TTL:            3600
```

**Zweiter A-Record:**
```
Record-Typ:     A
Name/Host:      @ (oder leer lassen)
Ziel/Value:     151.101.65.195
TTL:            3600
```

#### **3. CNAME für www.hauau.com (empfohlen):**
```
Record-Typ:     CNAME
Name/Host:      www
Ziel/Value:     sunriza26.web.app
TTL:            3600
```

---

## **4️⃣ Alte Einträge entfernen (wichtig!)**

⚠️ **Entferne bei Strato diese alten Einträge:**
- Alte A-Records für @ (wenn vorhanden)
- Alte AAAA-Records für @ (IPv6, wenn vorhanden)

**Behalte:**
- MX-Records (für E-Mail)
- SPF/DKIM-Records (für E-Mail)

---

## **5️⃣ Speichern & Warten**

1. **Änderungen speichern** in Strato
2. **Zurück zu Firebase Console**
3. Button **Verifizieren** klicken

**Wartezeit:**
- Strato DNS-Propagierung: 5 Min - 24 Stunden
- SSL-Zertifikat: automatisch (bis zu 24h nach Verifizierung)

---

## **🎯 Strato-spezifische Tipps:**

### **DNS-Einträge bei Strato finden:**
- **Strato V-Server / Managed Server:**
  → Domain-Verwaltung → Managed DNS
  
- **Strato Paket / Webhosting:**
  → Domains → Domain verwalten → DNS-Einstellungen

### **Häufige Strato-Besonderheiten:**

1. **@ oder leer lassen?**
   - Bei Strato meist **@ verwenden**
   - Wenn @ nicht funktioniert, **Feld leer lassen**

2. **Punkt am Ende?**
   - Bei CNAME: `sunriza26.web.app` (OHNE Punkt)
   - Strato fügt den Punkt automatisch hinzu

3. **Priority/Priorität:**
   - Bei A-Records: **leer lassen** oder **0**

4. **TTL (Time to Live):**
   - Standard: **3600** (1 Stunde)
   - Oder einfach Strato-Standard übernehmen

---

## **✅ Prüfung ob DNS funktioniert:**

Nach 1-2 Stunden kannst du prüfen:

```bash
# TXT-Record prüfen:
nslookup -type=TXT hauau.com

# A-Records prüfen:
nslookup hauau.com

# Sollte zeigen: 151.101.1.195 und 151.101.65.195
```

---

## **🚨 Probleme bei Strato:**

### **Problem:** "DNS-Einstellungen nicht verfügbar"
**Lösung:** 
- Bei Strato Premium-Paket manchmal deaktiviert
- Strato-Support kontaktieren: "Managed DNS aktivieren"

### **Problem:** "A-Record kann nicht hinzugefügt werden"
**Lösung:**
- Alten A-Record erst löschen
- Dann neuen hinzufügen

### **Problem:** "Domain zeigt alte Seite"
**Lösung:**
- Browser-Cache leeren (Strg+Shift+R / Cmd+Shift+R)
- Inkognito-Modus testen
- DNS-Propagierung kann bis 24h dauern

---

## **📞 Strato Support:**

Falls Probleme auftreten:
- Hotline: 030 - 300 146 000
- Chat: https://www.strato.de/service/
- Sage: "Ich möchte Managed DNS für hauau.com aktivieren"

---

## **🎉 Fertig!**

Nach erfolgreicher Einrichtung ist deine App erreichbar unter:
- https://hauau.com (mit SSL!)
- https://www.hauau.com (mit SSL!)

**Automatisch inklusive:**
- ✅ SSL/HTTPS (Let's Encrypt)
- ✅ CDN (weltweit schnell)
- ✅ DDoS-Schutz
- ✅ Unbegrenzte Bandbreite (Firebase Free Tier: 10GB/Monat)

