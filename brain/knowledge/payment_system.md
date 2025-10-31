# Zahlungssystem - Komplett-Übersicht

## ✅ Implementierte Features

### 1. Credits-System
- **Kauf:** Stripe Checkout für 5€, 10€, 25€, 50€, 100€ Pakete
- **1 Credit = 0,10 €** (oder USD-Äquivalent mit Live-Wechselkurs)
- **Tracking:** `credits`, `creditsPurchased`, `creditsSpent` in `UserProfile`
- **Stripe-Gebühr:** 0,25 € (einmalig beim Credits-Kauf)

### 2. Media-Käufe
**Zwei Zahlungswege:**
1. **Mit Credits** (immer möglich, keine Zusatzgebühren)
2. **Mit Karte (Stripe)** (nur bei Preisen ≥ 2€, zzgl. Stripe-Gebühr)

**Unterstützte Media-Typen:**
- Bilder
- Videos
- Audio-Dateien
- Bundles (mehrere Medien gleichzeitig)

### 3. Transaktionsverwaltung
**TransactionType:**
- `credit_purchase` - Credits gekauft
- `credit_spent` - Credits ausgegeben für Media
- `media_purchase` - Media direkt mit Karte gekauft

**Gespeicherte Daten:**
- Preis, Währung, Wechselkurs
- Stripe Session ID, Payment Intent
- Media-Details (ID, Name, Typ, Avatar)
- Status (pending, completed, failed, refunded)
- Zeitstempel

### 4. eRechnung (PDF)
**Cloud Function:** `generateInvoice`
- Generiert PDF mit `pdfkit`
- Uploads zu Firebase Storage
- Signierte URL (7 Tage gültig)
- Rechnungsnummer: `INV-YYYY-00001` (auto-increment)

**Rechnungs-Daten:**
- Firmendaten (Sunriza GmbH)
- Kunde (Name, E-Mail, Adresse)
- Position (Credits oder Media)
- Preis, MwSt., Gesamt
- Zahlungsmethode (Stripe)

### 5. UI-Screens
**PaymentOverviewScreen:**
- Credits-Übersicht (verfügbar, gekauft, ausgegeben)
- Navigation zu Credits-Shop, Transaktionen, Zahlungsmethoden, Warenkorb

**TransactionsScreen:**
- Liste aller Transaktionen (Filter: Alle, Credits, Media)
- Download-Button für PDF-Rechnung
- Details-Dialog mit vollständigen Infos

**CreditsShopScreen:**
- Credit-Pakete anzeigen
- Währungsauswahl (€ / $)
- Live-Wechselkurs (TODO: API-Integration)
- Stripe-Gebühr-Erklärung
- Stripe Checkout Integration

**MediaPurchaseDialog:**
- Preis & erforderliche Credits anzeigen
- Verfügbare Credits prüfen
- Zwei Buttons: "Mit Credits zahlen" oder "Mit Karte zahlen"
- Weiterleitung zu Credits-Shop bei Guthaben-Mangel

### 6. Services
**MediaPurchaseService:**
- `hasEnoughCredits()` - Prüft Credits-Guthaben
- `hasMediaAccess()` - Prüft ob Media bereits gekauft
- `purchaseMediaWithCredits()` - Batch-Update: Credits abziehen, Transaktion anlegen, Media freischalten
- `purchaseMediaWithStripe()` - Stripe Checkout Session erstellen
- `purchaseMediaBundle()` - Mehrere Medien gleichzeitig kaufen

### 7. Cloud Functions
**Implementiert:**
- `createCreditsCheckoutSession` - Stripe Checkout für Credits
- `stripeWebhook` - Verarbeitet Stripe Events
- `createMediaCheckoutSession` - Stripe Checkout für Media-Kauf
- `handleMediaPurchaseWebhook` - Verarbeitet Media-Kauf nach Zahlung
- `generateInvoice` - PDF-Rechnung generieren

## 📋 Datenmodelle

### UserProfile (users/{userId})
```typescript
{
  credits: number,              // Verfügbare Credits
  creditsPurchased: number,     // Gesamt gekaufte Credits
  creditsSpent: number,         // Gesamt ausgegebene Credits
  stripeCustomerId: string?,    // Stripe Customer ID
  ...
}
```

### Transaction (users/{userId}/transactions/{id})
```typescript
{
  userId: string,
  type: 'credit_purchase' | 'credit_spent' | 'media_purchase',
  credits?: number,
  amount?: number,
  currency?: string,
  exchangeRate?: number,
  stripeSessionId?: string,
  paymentIntent?: string,
  status: 'pending' | 'completed' | 'failed' | 'refunded',
  createdAt: Timestamp,
  
  // Nur bei Media-Käufen:
  mediaId?: string,
  mediaType?: 'image' | 'video' | 'audio' | 'bundle',
  mediaUrl?: string,
  mediaName?: string,
  avatarId?: string,
  mediaIds?: string[],
  
  // Rechnung:
  invoiceNumber?: string,
  invoicePdfUrl?: string,
}
```

### PurchasedMedia (users/{userId}/purchased_media/{mediaId})
```typescript
{
  mediaId: string,
  avatarId: string,
  type: 'image' | 'video' | 'audio',
  price?: number,
  currency?: string,
  credits?: number,
  purchasedAt: Timestamp,
  bundleTransactionId?: string,  // Falls Teil eines Bundles
}
```

## 🚀 Deployment

### 1. Stripe Keys setzen
```bash
cd functions
firebase functions:config:set stripe.secret_key="sk_test_..."
firebase functions:config:set stripe.webhook_secret="whsec_..."
firebase functions:config:set app.url="http://localhost:4202"
```

### 2. NPM Dependencies
```bash
cd functions
npm install stripe pdfkit @google-cloud/storage @types/pdfkit
```

### 3. Functions deployen
```bash
firebase deploy --only functions
```

### 4. Stripe Webhook konfigurieren
- Dashboard: https://dashboard.stripe.com/test/webhooks
- Event: `checkout.session.completed`
- URL: `https://REGION-PROJECT.cloudfunctions.net/stripeWebhook`

## ⚠️ TODOs

### Sofort:
- [ ] Live Exchange Rate API (z.B. exchangerate-api.com)
- [ ] Webhook Secret in Stripe Dashboard kopieren
- [ ] Test-Käufe durchführen

### Später:
- [ ] MwSt.-Berechnung (abhängig vom Land)
- [ ] Refund-Logik (Rückerstattungen)
- [ ] Email-Benachrichtigungen bei Kauf
- [ ] Warenkorb-System (gebündelte Media-Käufe)
- [ ] Payment Methods Management (Kreditkarten speichern)

## 🧪 Testing

### Test-Karten (Stripe Test Mode):
- **Visa:** `4242 4242 4242 4242`
- **Mastercard:** `5555 5555 5555 4444`
- **CVC:** `123`
- **Datum:** `12/25`
- **PLZ:** `12345`

### Test-Flow:
1. Credits kaufen (z.B. 10€ → 100 Credits)
2. Media mit Credits kaufen (z.B. Audio 1,50€ → 15 Credits)
3. Transaktion prüfen (TransactionsScreen)
4. PDF-Rechnung herunterladen
5. Credits-Stand prüfen (PaymentOverviewScreen)

## 🔐 Sicherheit

### Firestore Rules (TODO):
```
match /users/{userId}/transactions/{transactionId} {
  allow read: if request.auth.uid == userId;
  allow write: if false;  // Nur Cloud Functions dürfen schreiben
}

match /users/{userId}/purchased_media/{mediaId} {
  allow read: if request.auth.uid == userId;
  allow write: if false;  // Nur Cloud Functions dürfen schreiben
}
```

### API Keys:
- ✅ Stripe Secret Key in Firebase Functions Config
- ✅ Webhook Secret für Signatur-Verifizierung
- ⚠️ NIEMALS in Client-Code (Flutter) verwenden!

## 📞 Support

Bei Problemen:
1. Firebase Functions Logs prüfen: `firebase functions:log`
2. Stripe Dashboard Events prüfen
3. Client-Side Logs in Flutter Console

