# Stripe Setup - Test Mode

## Firebase Functions Konfiguration

### 1. Stripe Keys setzen (Test Mode)
```bash
cd functions

# Test Keys von https://dashboard.stripe.com/test/apikeys
firebase functions:config:set stripe.secret_key="sk_test_YOUR_TEST_KEY"
firebase functions:config:set stripe.webhook_secret="whsec_YOUR_WEBHOOK_SECRET"
firebase functions:config:set app.url="http://localhost:4202"

# Config anzeigen
firebase functions:config:get
```

### 2. .env für lokale Entwicklung
Erstelle `functions/.env`:
```bash
STRIPE_SECRET_KEY=sk_test_YOUR_TEST_KEY
STRIPE_WEBHOOK_SECRET=whsec_YOUR_WEBHOOK_SECRET
```

### 3. Stripe Package installieren
```bash
cd functions
npm install stripe@latest
```

### 4. Functions deployen
```bash
firebase deploy --only functions:createCreditsCheckoutSession,functions:stripeWebhook
```

## Stripe Dashboard Setup

### 1. Test Mode aktivieren
- Dashboard: https://dashboard.stripe.com/test/dashboard
- Toggle oben rechts: "Test mode" aktivieren

### 2. Webhook einrichten
1. Dashboard → Developers → Webhooks
2. "Add endpoint"
3. URL: `https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/stripeWebhook`
4. Events auswählen: `checkout.session.completed`
5. Webhook Secret kopieren → `firebase functions:config:set stripe.webhook_secret="whsec_..."`

## Test Cards (Stripe Test Mode)

### Erfolgreiche Zahlungen
- **Visa:** 4242 4242 4242 4242
- **Mastercard:** 5555 5555 5555 4444
- **American Express:** 3782 822463 10005

### CVC & Datum
- **CVC:** Beliebige 3 Ziffern (z.B. 123)
- **Ablaufdatum:** Beliebiges Datum in der Zukunft (z.B. 12/25)
- **PLZ:** Beliebig (z.B. 12345)

### Fehlgeschlagene Zahlungen (zum Testen)
- **Declined:** 4000 0000 0000 0002
- **Insufficient funds:** 4000 0000 0000 9995

## Firestore Security Rules

```javascript
// users/{userId} - Credits-Felder
match /users/{userId} {
  allow read: if request.auth.uid == userId;
  allow update: if request.auth.uid == userId 
    && (!request.resource.data.diff(resource.data).affectedKeys()
      .hasAny(['credits', 'creditsPurchased', 'creditsSpent']));
  
  // Credits NUR über Cloud Function änderbar
  match /transactions/{transactionId} {
    allow read: if request.auth.uid == userId;
    allow create: if false; // Nur Cloud Function
  }
}
```

## Flutter Dependencies

In `pubspec.yaml` sicherstellen:
```yaml
dependencies:
  cloud_functions: ^5.1.4
  url_launcher: ^6.3.1
  firebase_auth: ^5.3.3
```

```bash
flutter pub get
```

## Testing

### 1. Lokale Cloud Functions testen
```bash
cd functions
npm run serve
```

### 2. Flutter App mit lokalen Functions
```dart
// main.dart - Für lokale Development
if (kDebugMode) {
  FirebaseFunctions.instance.useFunctionsEmulator('localhost', 5001);
}
```

### 3. Test-Kauf durchführen
1. App starten
2. Credits Shop öffnen
3. Paket auswählen
4. Stripe Checkout → Test-Karte verwenden
5. Nach erfolgreicher Zahlung: Credits in Firestore prüfen

## Monitoring

### Firebase Console
```
https://console.firebase.google.com/project/YOUR_PROJECT/functions/logs
```

### Stripe Dashboard
```
https://dashboard.stripe.com/test/payments
```

## Troubleshooting

### "Function not found"
```bash
firebase deploy --only functions
```

### Webhook nicht erreichbar
- Prüfe URL in Stripe Dashboard
- Prüfe Firebase Functions Logs
- Teste Webhook mit Stripe CLI:
```bash
stripe listen --forward-to localhost:5001/YOUR_PROJECT/us-central1/stripeWebhook
```

### Credits nicht gutgeschrieben
1. Prüfe Webhook Logs in Stripe Dashboard
2. Prüfe Firebase Functions Logs
3. Prüfe Firestore `users/{userId}/transactions`

## Production Ready

### Live Mode aktivieren
1. Stripe Dashboard → Live mode
2. Neue Live Keys holen
3. Webhook für Production URL einrichten
4. Config updaten:
```bash
firebase functions:config:set stripe.secret_key="sk_live_..."
firebase functions:config:set stripe.webhook_secret="whsec_live_..."
firebase functions:config:set app.url="https://your-production-url.com"
firebase deploy --only functions
```

## Sicherheit

✅ Stripe Keys NIEMALS im Code committen
✅ Nur Test Keys in Test Mode verwenden
✅ Webhook Signature immer validieren
✅ Credits-Updates nur über Cloud Function
✅ Firestore Rules: Credits read-only für Client

