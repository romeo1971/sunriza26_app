# Marketplace & Payout System - Konzept & Kritik

**Stand:** 03.10.2025  
**Status:** 🔍 **KONZEPTPHASE - Noch nicht implementiert**

---

## 🎯 Dein Konzept

### User-Rollen
1. **Käufer** - Kauft Media (Bilder/Videos/Audio)
2. **Verkäufer** - Verkauft eigene Media über seinen Avatar
3. **Platform (IHR)** - Vermittelt & wickelt Zahlungen ab

### Zahlungsfluss (Dein Vorschlag)
```
Käufer zahlt → EUER Stripe → Credits für Verkäufer → Auszahlung über Stripe
```

---

## ⚠️ KRITISCHE ANALYSE

### ❌ Problem 1: Rechtliche Verantwortung
**Dein Plan:**
> "Nutzer kauft von UNS, aber eigentlich verantwortlich ist der verkaufende User"

**Problem:**
- **IHR** seid rechtlich der Verkäufer (aus Käufer-Sicht)
- **IHR** müsst Rechnungen ausstellen
- **IHR** haftet für Urheberrechtsverletzungen
- **IHR** müsst MwSt. abführen
- **IHR** braucht Gewerbeanmeldung pro Land

**Risiko:** 🔴 **SEHR HOCH**

### ❌ Problem 2: Steuer-Chaos
**Dein Plan:**
> "Credits werden gutgeschrieben, dann Auszahlung"

**Problem:**
- Credits = Geldersatz = **E-Geld-Lizenz** erforderlich (BaFin!)
- Auszahlungen = Ihr zahlt Einnahmen → **IHR** müsst versteuern
- Verkäufer müssen dann NOCHMAL versteuern
- **Doppelbesteuerung!**

**Risiko:** 🔴 **SEHR HOCH**

### ❌ Problem 3: Stripe ToS Verletzung
**Dein Plan:**
> "User gibt Stripe API Daten ein, wir verbinden"

**Problem:**
- Stripe verbietet **Account-Sharing**
- API Keys weitergeben = **Verstoß gegen ToS**
- Account-Sperrung droht

**Risiko:** 🔴 **HOCH**

---

## ✅ EMPFOHLENE LÖSUNG: Stripe Connect

### Was ist Stripe Connect?
Stripe's **offizielle** Marketplace-Lösung:
- Verkäufer haben EIGENE Stripe Accounts (Connected Accounts)
- Zahlungen gehen DIREKT an Verkäufer
- IHR bekommt automatisch eure Provision
- Stripe kümmert sich um Steuern, Rechnungen, Haftung

### Vorteile
✅ **Rechtlich sauber** - Verkäufer ist rechtlich Verkäufer  
✅ **Steuerlich korrekt** - Jeder versteuert seine Einnahmen  
✅ **Stripe-konform** - Offiziell unterstützt  
✅ **Keine E-Geld-Lizenz** nötig  
✅ **Automatische Auszahlungen** - Stripe macht das  
✅ **Internationale Skalierung** - Stripe kümmert sich um Länder-Regeln

---

## 🏗️ ARCHITEKTUR: Stripe Connect

### User-Profil Erweiterung
```dart
class UserProfile {
  // Verkäufer-Daten (optional - nur wenn User verkaufen will)
  final bool isSeller;                    // Verkauft der User?
  final String? stripeConnectAccountId;   // Connected Account ID
  final String? stripeConnectStatus;      // pending, active, restricted
  final bool? payoutsEnabled;             // Auszahlungen aktiviert?
  
  // Business-Daten (optional)
  final String? businessName;             // Firmenname (optional)
  final String? businessEmail;            // Firma E-Mail
  final String? businessPhone;            // Firma Telefon
  final String? businessAddress;          // Firma Adresse
  final String? taxId;                    // Steuernummer/USt-ID
  final String? businessType;             // individual, company
  
  // Existing...
  final String? stripeCustomerId;         // Als KÄUFER
  final int credits;
  final int creditsPurchased;
  final int creditsSpent;
}
```

### Zahlungsfluss (Stripe Connect)

#### Option A: Direct Charges (EMPFOHLEN)
```
Käufer zahlt 10€ für Bild
  ↓
Stripe teilt auf:
  → 9,50€ gehen DIREKT an Verkäufer-Account
  → 0,50€ gehen an EUREN Account (Provision)
  ↓
Verkäufer bekommt Geld in 2-7 Tagen auf sein Bankkonto
IHR bekommt Provision sofort
```

**Vorteil:** 
- Keine Credits nötig
- Verkäufer ist rechtlich Verkäufer
- Automatische Auszahlungen
- Steuerlich sauber

#### Option B: Destination Charges
```
Käufer zahlt 10€ an EUCH
  ↓
IHR behaltet 0,50€ Provision
IHR transferiert 9,50€ an Verkäufer
  ↓
Verkäufer bekommt Geld
```

**Nachteil:** IHR seid rechtlich Verkäufer (wie dein aktueller Plan)

### ✅ EMPFEHLUNG: Direct Charges

---

## 💰 PROVISIONS-MODELL

### Beispiel: 20% Platform Fee
```
Verkäufer setzt Preis: 10,00 €
Platform Fee (20%):     2,00 €
Stripe Fee (~3%):       0,33 €
  ↓
Verkäufer erhält:       7,67 €
IHR erhaltet:           2,00 €
Stripe erhält:          0,33 €
```

### Code (vereinfacht)
```dart
// Media-Kauf mit Stripe Connect
final session = await stripe.checkout.sessions.create({
  'line_items': [{
    'price_data': {
      'unit_amount': 1000, // 10,00 €
      'currency': 'eur',
    },
    'quantity': 1,
  }],
  'payment_intent_data': {
    'application_fee_amount': 200, // 2,00 € für euch (20%)
    'transfer_data': {
      'destination': sellerStripeAccountId, // Verkäufer bekommt Rest
    },
  },
});
```

---

## 🔄 ONBOARDING-FLOW: Verkäufer werden

### Schritt 1: "Verkäufer werden" Button im Profil
```dart
ElevatedButton(
  onPressed: () => _startSellerOnboarding(),
  child: Text('Jetzt verkaufen & Geld verdienen'),
)
```

### Schritt 2: Stripe Connect Account erstellen
```typescript
// Cloud Function
export const createConnectedAccount = functions.https.onCall(async (data, context) => {
  const userId = context.auth.uid;
  
  // Stripe Express Account erstellen (einfachste Variante)
  const account = await stripe.accounts.create({
    type: 'express',
    country: data.country || 'DE',
    email: data.email,
    capabilities: {
      card_payments: { requested: true },
      transfers: { requested: true },
    },
  });
  
  // Account Link für Onboarding
  const accountLink = await stripe.accountLinks.create({
    account: account.id,
    refresh_url: 'https://sunriza.app/seller/refresh',
    return_url: 'https://sunriza.app/seller/success',
    type: 'account_onboarding',
  });
  
  // In Firestore speichern
  await admin.firestore().collection('users').doc(userId).update({
    isSeller: true,
    stripeConnectAccountId: account.id,
    stripeConnectStatus: 'pending',
  });
  
  return { url: accountLink.url };
});
```

### Schritt 3: User füllt Stripe-Formular aus
- Stripe zeigt **fertiges Formular** (in User's Sprache)
- User gibt Bankdaten ein
- User bestätigt Identität (KYC)
- Stripe prüft alles

### Schritt 4: Account aktiviert
- Webhook von Stripe: `account.updated`
- Status in Firestore: `stripeConnectStatus = 'active'`
- User kann jetzt Media verkaufen

---

## 📊 DASHBOARD: Verkäufer-Statistiken

### Was User sehen sollten
```dart
class SellerDashboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Earnings
        _buildEarningCard(
          'Einnahmen (diesen Monat)',
          '234,50 €',
        ),
        
        // Pending Payouts
        _buildPayoutCard(
          'Nächste Auszahlung',
          '127,30 €',
          'in 3 Tagen',
        ),
        
        // Sales
        _buildSalesCard(
          'Verkäufe',
          '47 Bilder, 12 Videos, 8 Audios',
        ),
        
        // Stripe Dashboard Link
        ElevatedButton(
          onPressed: () => _openStripeDashboard(),
          child: Text('Zu Stripe Dashboard'),
        ),
      ],
    );
  }
}
```

---

## 🔒 SICHERHEIT & COMPLIANCE

### Was Stripe Connect automatisch macht
✅ **KYC/AML** - Identity Verification  
✅ **Steuer-Compliance** - 1099/W-2 Forms (US), Steuer-IDs  
✅ **Fraud-Detection** - Betrugs-Prävention  
✅ **Chargebacks** - Rückbuchungen  
✅ **Payouts** - Automatische Auszahlungen  
✅ **Multi-Currency** - Internationale Zahlungen  

### Was IHR machen müsst
⚠️ **AGB** - Marketplace-Bedingungen  
⚠️ **Impressum** - Platform-Betreiber  
⚠️ **Datenschutz** - DSGVO-konform  
⚠️ **Content-Moderation** - Illegale Inhalte blockieren  

---

## 💡 CREDITS + STRIPE CONNECT

### Hybrid-Modell (Beste Lösung)

#### Käufer-Seite: Credits (wie bisher)
```
Käufer kauft Credits mit Stripe
Credits = bequeme Zahlung, keine Gebühren pro Kauf
```

#### Verkäufer-Seite: Echtes Geld (Stripe Connect)
```
Verkäufer bekommt echtes Geld auf Bankkonto
KEINE Credits für Verkäufer
```

#### Wie Credits zu Geld werden
```
1. Käufer zahlt 15 Credits für Bild (= 1,50 €)
2. Cloud Function:
   - Zieht 15 Credits vom Käufer ab
   - Erstellt Transfer zu Verkäufer-Account
   - Verkäufer bekommt 1,43 € (nach eurer Provision)
3. Stripe zahlt automatisch an Verkäufer aus
```

**Code:**
```typescript
// Credits zu Geld
export const purchaseMediaWithCredits = functions.https.onCall(async (data, context) => {
  const buyerId = context.auth.uid;
  const { mediaId, credits } = data;
  
  // Media laden
  const media = await getMedia(mediaId);
  const sellerId = media.ownerId;
  const sellerAccount = await getSellerAccount(sellerId);
  
  // Credits abziehen
  await deductCredits(buyerId, credits);
  
  // Geld an Verkäufer transferieren
  const amountInCents = credits * 10; // 1 Credit = 0,10 €
  const platformFee = Math.round(amountInCents * 0.20); // 20% Provision
  
  await stripe.transfers.create({
    amount: amountInCents - platformFee,
    currency: 'eur',
    destination: sellerAccount.stripeConnectAccountId,
    metadata: {
      mediaId,
      buyerId,
      sellerId,
    },
  });
  
  // Transaktion speichern
  await saveTransaction({ ... });
  
  return { success: true };
});
```

---

## 🎯 FINALE LÖSUNG (ABGESTIMMT)

### ✅ Hybrid-Modell: Credits + Stripe Connect

**Käufer-Seite:**
- Kaufen Credits (z.B. 25€ = 250 Credits)
- Zahlen Media mit Credits (bequem, keine Fee pro Kauf)
- Credits gelten 12 Monate

**Verkäufer-Seite:**
- Erhalten echtes Geld via Stripe Connect
- Monatliche Sammel-Auszahlung (nur 1x Stripe-Fee)
- Keine Credits für Verkäufer

**Platform (IHR):**
- Behaltet 20% Provision (Standard, individuell anpassbar)
- Zahlt Ende Monat gesammelt aus
- Habt Liquidität aus Credits-Verkäufen

#### Vorteile
1. **Rechtlich sauber** - Verkäufer ist Verkäufer
2. **Steuerlich korrekt** - Jeder versteuert selbst
3. **Automatische Auszahlungen** - Stripe macht das
4. **Keine E-Geld-Lizenz** nötig
5. **Skalierbar** - International ohne Probleme
6. **Best UX** - Käufer: Credits, Verkäufer: Echtes Geld

#### Nachteile
- Etwas komplexer zu implementieren
- Verkäufer müssen Identität verifizieren (KYC)
- Stripe nimmt ~2-3% von Verkäufer-Einnahmen

---

## 📋 NÄCHSTE SCHRITTE

### Phase 1: UserProfile erweitern
- [ ] Seller-Felder hinzufügen
- [ ] Business-Daten optional
- [ ] Firestore Migration

### Phase 2: Stripe Connect Integration
- [ ] `createConnectedAccount` Function
- [ ] Onboarding-Flow UI
- [ ] Webhook für `account.updated`
- [ ] Seller Dashboard

### Phase 3: Payout-System
- [ ] Credits → Transfer Logic
- [ ] Direktkauf → Split Payment
- [ ] Transaction History für Verkäufer
- [ ] Payout Notifications

### Phase 4: Compliance
- [ ] AGB/Marketplace Terms
- [ ] Seller Agreement
- [ ] Content Moderation
- [ ] Tax Forms Integration

---

## 💰 CASHFLOW-BEISPIEL

### Monat 1
```
10 Käufer kaufen je 25€ Credits
→ IHR habt: 250€ cash auf Stripe

50 Media-Käufe für gesamt 50€ (in Credits)
→ Käufer-Credits: -500 Credits
→ Verkäufer-Guthaben: +50€

Monatsende: Auszahlung
→ IHR zahlt: 40€ (50€ - 20% Provision)
→ IHR behaltet: 210€
```

**Keine Vorfinanzierung nötig** - Credits-Einnahmen decken Auszahlungen!

---

## 📋 IMPLEMENTIERUNGS-PLAN

### Phase 1: UserProfile erweitern ✅ BEREIT
- [x] Seller-Felder
- [x] Business-Daten
- [x] Stripe Connect Account ID

### Phase 2: Stripe Connect Onboarding
- [ ] Cloud Function: `createConnectedAccount`
- [ ] Onboarding UI Flow
- [ ] Webhook: `account.updated`
- [ ] KYC-Status Tracking

### Phase 3: Monatliche Payouts
- [ ] Cloud Scheduler (1x/Monat)
- [ ] Credits → Euro Umrechnung
- [ ] Stripe Transfers an Verkäufer
- [ ] Payout Notifications

### Phase 4: Seller Dashboard
- [ ] Earnings Overview
- [ ] Sales History
- [ ] Payout Schedule
- [ ] Stripe Dashboard Link

---

**LOS GEHT'S!** 🚀

