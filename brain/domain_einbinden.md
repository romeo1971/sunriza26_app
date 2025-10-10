# 🌐 Domain hauau.com mit Firebase verbinden

## ✅ **Web-Build ist fertig!**
Deine App liegt jetzt in: `build/web/`

---

## **Schritt 1: Firebase Hosting deployen**

```bash
cd /Users/hhsw/Desktop/sunriza/sunriza26
firebase deploy --only hosting
```

Dies deployed deine App auf die Standard-Firebase-URL:
- `https://sunriza26.web.app`
- `https://sunriza26.firebaseapp.com`

---

## **Schritt 2: Custom Domain hinzufügen**

### **In der Firebase Console:**

1. **Firebase Console öffnen:**
   - https://console.firebase.google.com
   - Projekt **sunriza26** auswählen

2. **Hosting → Custom Domain:**
   - Links im Menü: **Hosting** klicken
   - Button: **Custom domain hinzufügen**

3. **Domain eingeben:**
   - `hauau.com` eingeben
   - Optional: `www.hauau.com` auch hinzufügen (empfohlen)

4. **DNS-Einträge notieren:**
   Firebase zeigt dir TXT- und A-Records an, z.B.:
   ```
   TXT  @  google-site-verification=abc123...
   A    @  151.101.1.195
   A    @  151.101.65.195
   ```

---

## **Schritt 3: DNS bei deinem Domain-Anbieter einstellen**

**Wo hast du hauau.com registriert?** (z.B. GoDaddy, Namecheap, Strato, etc.)

### **Bei deinem Domain-Anbieter:**

1. **DNS-Einstellungen öffnen** für hauau.com

2. **TXT-Record hinzufügen:**
   ```
   Type: TXT
   Name: @
   Value: google-site-verification=abc123...  (von Firebase)
   ```

3. **A-Records hinzufügen:**
   ```
   Type: A
   Name: @
   Value: 151.101.1.195  (von Firebase)
   
   Type: A
   Name: @
   Value: 151.101.65.195  (von Firebase)
   ```

4. **Für www.hauau.com (optional aber empfohlen):**
   ```
   Type: CNAME
   Name: www
   Value: sunriza26.web.app
   ```

---

## **Schritt 4: Verifizierung abwarten**

- Firebase prüft die DNS-Einträge (kann 5 Min - 24 Std dauern)
- Sobald verifiziert: **SSL-Zertifikat wird automatisch erstellt** (kostenlos!)
- Domain ist dann live: `https://hauau.com` 🎉

---

## **Zusammenfassung:**

```bash
# 1. Deploy
firebase deploy --only hosting

# 2. Firebase Console → Hosting → Custom Domain
# 3. DNS-Einträge bei Domain-Anbieter eintragen
# 4. Warten (5 Min - 24 Std)
# 5. Fertig! ✅
```

---

## **💡 Tipps:**

- **www.hauau.com auch einrichten** (Standard-Best-Practice)
- **SSL ist automatisch** (Let's Encrypt via Firebase)
- **CDN inklusive** (weltweit schnell)
- **Kein extra Hosting-Kosten** (Firebase Free Tier)

---

## **🚨 Häufige Probleme:**

**Problem:** DNS-Änderung dauert lange
**Lösung:** Warte 24h, manchmal dauert die Propagierung

**Problem:** SSL-Fehler
**Lösung:** Geduld, SSL-Zertifikat wird automatisch erstellt (bis zu 24h)

**Problem:** Domain-Anbieter hat andere Felder
**Lösung:** Suche nach "DNS Management" oder "Advanced DNS"

