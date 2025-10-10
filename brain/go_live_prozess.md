# 🚀 Go-Live Prozess für sunriza26

## **1️⃣ Code committen & pushen**
```bash
cd /Users/hhsw/Desktop/sunriza/sunriza26
git add .
git commit -m "Hero images feature complete - ready for production"
git push origin main
```

## **2️⃣ Firebase für Produktion vorbereiten**

### **A) Firestore Security Rules deployen:**
```bash
firebase deploy --only firestore:rules
```

### **B) Firebase Hosting (falls Web-App):**
```bash
flutter build web --release
firebase deploy --only hosting
```

## **3️⃣ Mobile Apps bauen**

### **iOS (Apple App Store):**
```bash
# 1. Version erhöhen in pubspec.yaml
# version: 1.0.1+2  (z.B.)

# 2. iOS Build erstellen
flutter build ios --release

# 3. In Xcode öffnen und zu App Store hochladen
open ios/Runner.xcworkspace
```

### **Android (Google Play Store):**
```bash
# 1. App Bundle erstellen
flutter build appbundle --release

# 2. Bundle liegt hier:
# build/app/outputs/bundle/release/app-release.aab
```

## **4️⃣ In Stores hochladen**

### **iOS:**
- Xcode → Product → Archive
- Upload to App Store Connect
- TestFlight für Beta-Testing (optional)
- Submit for Review

### **Android:**
- Google Play Console öffnen
- Neue Version erstellen
- `.aab` Datei hochladen
- Submit for Review

## **5️⃣ Wichtige Checkliste vor Go-Live**

```bash
# A) Tests laufen lassen
flutter test

# B) Linter prüfen
flutter analyze

# C) Dependencies aktualisieren
flutter pub upgrade

# D) Performance Check
flutter build apk --release --analyze-size
```

## **📋 Was brauchst du noch?**

1. **Apple Developer Account** ($99/Jahr) für iOS
2. **Google Play Developer Account** ($25 einmalig) für Android
3. **App Icons & Screenshots** für Store-Listings
4. **Privacy Policy URL** (Pflicht für beide Stores)
5. **App Store Beschreibungen** (Deutsch & Englisch)

---

## **🎯 Schnellster Weg zum Testen:**
```bash
# Firebase Hosting (Web) - in 2 Minuten live:
flutter build web --release
firebase deploy --only hosting
# → https://deine-app.web.app
```

Möchtest du mit **Web**, **iOS** oder **Android** anfangen? Ich helfe dir beim jeweiligen Prozess! 🚀

