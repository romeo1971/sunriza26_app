# Credits System - Dokumentation

## Übersicht
Das Credits-System ermöglicht es Nutzern, Credits zu kaufen und damit Medien (Bilder, Videos, Audio) im Chat zu entsperren, ohne jedes Mal erneut eine Stripe-Transaktion durchführen zu müssen.

## Vorteile
1. **Keine wiederkehrenden Transaktionsgebühren** - Nutzer zahlen nur einmal die Stripe-Gebühr beim Credit-Kauf
2. **Schnellere Zahlungen** - Sofortige Credit-Abbuchung ohne Stripe-Checkout
3. **Bessere UX** - Kein Verlassen der App für Mikrotransaktionen
4. **Mehr Geld für Creator** - Weniger Gebühren = mehr Einnahmen

## Credit-Wert
- **1 Credit = 0,10 €** (oder entsprechender Dollar-Betrag)
- Umrechnung erfolgt automatisch basierend auf gewählter Währung (€ / $)

## Credit-Pakete
Verfügbare Pakete im Credits-Shop:
- **5 €** → 50 Credits
- **10 €** → 100 Credits
- **25 €** → 250 Credits
- **50 €** → 500 Credits
- **100 €** → 1000 Credits

Alle Preise **zzgl. 0,25 € Stripe-Gebühr** (fix)

## Zahlungsregeln
### Unter 2 €
- **NUR Credits-Zahlung möglich**
- Grund: Stripe-Gebühr (0,25 €) wäre unverhältnismäßig hoch

### Ab 2 €
- **Wahlmöglichkeit zwischen:**
  1. Credits (wenn vorhanden)
  2. Direkte Stripe-Zahlung

## Datenmodell

### User Credits
```dart
// In UserProfile erweitern:
class UserProfile {
  // ... existing fields
  final int credits; // Verfügbare Credits
  final int creditsSpent; // Ausgegebene Credits (Tracking)
  final int creditsPurchased; // Gekaufte Credits (Tracking)
}
```

### Firestore Structure
```
users/{userId}/
  ├── credits: int
  ├── creditsSpent: int
  └── creditsPurchased: int

users/{userId}/transactions/
  └── {transactionId}/
      ├── type: 'credit_purchase' | 'credit_spent'
      ├── amount: int (Credits)
      ├── price: double (Euro/Dollar)
      ├── currency: string ('eur' | 'usd')
      ├── stripeSessionId: string?
      ├── mediaId: string? (wenn credit_spent)
      ├── createdAt: timestamp
      └── status: 'pending' | 'completed' | 'failed'
```

## Credits Shop Screen
**Route:** `/credits-shop`

**Features:**
- Währungsauswahl (€ / $)
- 5 Credit-Pakete zur Auswahl
- Erklärung warum Credits kaufen
- Info über Stripe-Gebühr
- Kaufbestätigung mit Preisübersicht

**Navigation:**
1. Hamburger Menu → "Credits kaufen"
2. Media Gallery → "Credits →" Link

## Stripe-Integration (TODO)

### Firebase Cloud Function: `createCreditsCheckoutSession`
```typescript
import * as functions from 'firebase-functions';
import Stripe from 'stripe';

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

export const createCreditsCheckoutSession = functions.https.onCall(async (data, context) => {
  const { amount, currency, credits, userId } = data;
  
  const session = await stripe.checkout.sessions.create({
    payment_method_types: ['card'],
    line_items: [{
      price_data: {
        currency: currency,
        product_data: {
          name: `${credits} Credits`,
          images: ['LOGO_URL'],
        },
        unit_amount: amount, // in Cents
      },
      quantity: 1,
    }],
    mode: 'payment',
    success_url: 'APP_URL/credits-success?session_id={CHECKOUT_SESSION_ID}',
    cancel_url: 'APP_URL/credits-shop',
    metadata: {
      userId,
      credits,
    },
  });
  
  return { sessionId: session.id, url: session.url };
});
```

### Webhook: Stripe Payment Success
```typescript
export const stripeWebhook = functions.https.onRequest(async (req, res) => {
  const sig = req.headers['stripe-signature'];
  const event = stripe.webhooks.constructEvent(req.rawBody, sig, WEBHOOK_SECRET);
  
  if (event.type === 'checkout.session.completed') {
    const session = event.data.object;
    const { userId, credits } = session.metadata;
    
    // Credits zum User hinzufügen
    await admin.firestore().collection('users').doc(userId).update({
      credits: admin.firestore.FieldValue.increment(parseInt(credits)),
      creditsPurchased: admin.firestore.FieldValue.increment(parseInt(credits)),
    });
    
    // Transaktion speichern
    await admin.firestore().collection('users').doc(userId).collection('transactions').add({
      type: 'credit_purchase',
      amount: parseInt(credits),
      price: session.amount_total / 100,
      currency: session.currency,
      stripeSessionId: session.id,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      status: 'completed',
    });
  }
  
  res.json({ received: true });
});
```

## Media-Unlock mit Credits

### Ablauf
1. User klickt auf verpixeltes Media im Chat
2. Popup zeigt:
   - Preview
   - Preis (z.B. "20 Credits" oder "2,00 €")
   - "Anzeigen" / "Verwerfen" Buttons
3. Wenn Preis < 2 €:
   - Nur Credits-Option
4. Wenn Preis ≥ 2 €:
   - Credits ODER Stripe-Zahlung wählbar
5. Bei Credits-Zahlung:
   - Sofortige Abbuchung
   - Media unlock
   - Speicherung in Shared Moments

### Code-Beispiel
```dart
Future<void> unlockMediaWithCredits(String mediaId, int creditCost) async {
  final userId = FirebaseAuth.instance.currentUser!.uid;
  
  // Check: Hat User genug Credits?
  final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
  final currentCredits = userDoc.data()?['credits'] ?? 0;
  
  if (currentCredits < creditCost) {
    // Zeige "Nicht genug Credits" + Link zu Credits-Shop
    return;
  }
  
  // Credits abbuchen
  await FirebaseFirestore.instance.collection('users').doc(userId).update({
    'credits': FieldValue.increment(-creditCost),
    'creditsSpent': FieldValue.increment(creditCost),
  });
  
  // Transaktion speichern
  await FirebaseFirestore.instance.collection('users').doc(userId).collection('transactions').add({
    'type': 'credit_spent',
    'amount': creditCost,
    'mediaId': mediaId,
    'createdAt': FieldValue.serverTimestamp(),
    'status': 'completed',
  });
  
  // Media zu Shared Moments hinzufügen
  await FirebaseFirestore.instance.collection('sharedMoments').add({
    'userId': userId,
    'mediaId': mediaId,
    'unlockedAt': FieldValue.serverTimestamp(),
  });
}
```

## Sicherheit
- **Backend-Validation:** Alle Credit-Transaktionen über Cloud Functions
- **Atomare Updates:** Firestore Transactions für Credit-Änderungen
- **Webhook-Verification:** Stripe Signature Check
- **User-Auth:** Nur eigene Credits änderbar

## Nächste Schritte
1. [ ] Credits zu `UserProfile` hinzufügen (Model + Firestore)
2. [ ] Firebase Cloud Function `createCreditsCheckoutSession` implementieren
3. [ ] Stripe Webhook für Credit-Gutschrift
4. [ ] Credits-Anzeige im User-Profil
5. [ ] Media-Unlock mit Credits im Chat
6. [ ] "Nicht genug Credits" Dialog mit Shop-Link
7. [ ] Admin-Panel: Credits manuell hinzufügen (Support)
8. [ ] Transaktions-History im User-Profil

## Design-Prinzipien
- 💎 Diamant-Icon für Credits (GMBC-Gradient optional)
- Klare Preis-Anzeige: "20 💎" oder "2,00 €"
- Immer beide Optionen zeigen (wenn verfügbar)
- Erklärung der Vorteile prominent platzieren

