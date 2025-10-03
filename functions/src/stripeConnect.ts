import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

// Stripe nur initialisieren wenn Secret Key vorhanden
const getStripe = () => {
  const secretKey = functions.config().stripe?.secret_key || process.env.STRIPE_SECRET_KEY || '';
  if (!secretKey) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Stripe Secret Key nicht konfiguriert',
    );
  }
  const Stripe = require('stripe');
  return new Stripe(secretKey, {
    apiVersion: '2025-09-30.clover',
  });
};

/**
 * Erstellt Stripe Connected Account für Verkäufer (Seller Onboarding)
 */
export const createConnectedAccount = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Nutzer muss angemeldet sein',
      );
    }

    const userId = context.auth.uid;
    const { country, email, businessType } = data;

    // Validierung
    if (!country || !email) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Country und Email erforderlich',
      );
    }

    try {
      const stripe = getStripe();

      // User laden
      const userDoc = await admin.firestore().collection('users').doc(userId).get();
      if (!userDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'User nicht gefunden');
      }

      const userData = userDoc.data()!;

      // Prüfen ob bereits Connected Account existiert
      if (userData.stripeConnectAccountId) {
        // Account Status prüfen
        const account = await stripe.accounts.retrieve(userData.stripeConnectAccountId);
        
        // Account Link für Re-Onboarding erstellen falls nötig
        if (!account.charges_enabled || !account.payouts_enabled) {
          const appUrl = functions.config().app?.url || 'http://localhost:4202';
          const accountLink = await stripe.accountLinks.create({
            account: userData.stripeConnectAccountId,
            refresh_url: `${appUrl}/seller/onboarding?refresh=true`,
            return_url: `${appUrl}/seller/onboarding?success=true`,
            type: 'account_onboarding',
          });
          
          return {
            accountId: userData.stripeConnectAccountId,
            url: accountLink.url,
            status: account.charges_enabled && account.payouts_enabled ? 'active' : 'pending',
          };
        }

        return {
          accountId: userData.stripeConnectAccountId,
          status: 'active',
        };
      }

      // Neuen Express Account erstellen (einfachste Variante für Seller)
      const account = await stripe.accounts.create({
        type: 'express',
        country: country.toUpperCase(),
        email,
        business_type: businessType || 'individual',
        capabilities: {
          card_payments: { requested: true },
          transfers: { requested: true },
        },
        settings: {
          payouts: {
            schedule: {
              interval: 'monthly', // Monatliche Auszahlungen
              monthly_anchor: 28, // Am 28. jeden Monats
            },
          },
        },
      });

      // Account Link für Onboarding erstellen
      const appUrl = functions.config().app?.url || 'http://localhost:4202';
      const accountLink = await stripe.accountLinks.create({
        account: account.id,
        refresh_url: `${appUrl}/seller/onboarding?refresh=true`,
        return_url: `${appUrl}/seller/onboarding?success=true`,
        type: 'account_onboarding',
      });

      // In Firestore speichern
      await admin.firestore().collection('users').doc(userId).update({
        isSeller: true,
        stripeConnectAccountId: account.id,
        stripeConnectStatus: 'pending',
        payoutsEnabled: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`Connected Account erstellt: ${account.id} für User ${userId}`);

      return {
        accountId: account.id,
        url: accountLink.url,
        status: 'pending',
      };
    } catch (error: any) {
      console.error('Fehler beim Erstellen des Connected Accounts:', error);
      throw new functions.https.HttpsError('internal', error.message);
    }
  });

/**
 * Webhook Handler für Stripe Connect Account Events
 */
export const stripeConnectWebhook = functions
  .region('us-central1')
  .https.onRequest(async (req, res) => {
    const sig = req.headers['stripe-signature'] as string;
    const webhookSecret = functions.config().stripe?.webhook_secret || process.env.STRIPE_WEBHOOK_SECRET;

    if (!webhookSecret) {
      console.error('Webhook Secret fehlt');
      res.status(500).send('Webhook Secret nicht konfiguriert');
      return;
    }

    let event: any;
    const stripe = getStripe();

    try {
      event = stripe.webhooks.constructEvent(req.rawBody, sig, webhookSecret);
    } catch (err: any) {
      console.error('Webhook Signature Verification failed:', err.message);
      res.status(400).send(`Webhook Error: ${err.message}`);
      return;
    }

    console.log(`Webhook Event: ${event.type}`);

    try {
      switch (event.type) {
        case 'account.updated':
          await handleAccountUpdated(event.data.object);
          break;

        case 'account.application.deauthorized':
          await handleAccountDeauthorized(event.data.object);
          break;

        default:
          console.log(`Unhandled event type: ${event.type}`);
      }

      res.json({ received: true });
    } catch (error: any) {
      console.error('Webhook Handler Error:', error);
      res.status(500).send('Webhook Processing Error');
    }
  });

/**
 * Account Updated - KYC Status, Payouts etc.
 */
async function handleAccountUpdated(account: any) {
  const accountId = account.id;
  console.log(`Account Updated: ${accountId}`);

  // User mit diesem Account finden
  const usersSnapshot = await admin
    .firestore()
    .collection('users')
    .where('stripeConnectAccountId', '==', accountId)
    .limit(1)
    .get();

  if (usersSnapshot.empty) {
    console.log(`Kein User mit Account ${accountId} gefunden`);
    return;
  }

  const userDoc = usersSnapshot.docs[0];
  const userId = userDoc.id;

  // Status ermitteln
  let status = 'pending';
  if (account.details_submitted && account.charges_enabled && account.payouts_enabled) {
    status = 'active';
  } else if (account.requirements?.disabled_reason) {
    status = 'restricted';
  }

  // Firestore aktualisieren
  await admin.firestore().collection('users').doc(userId).update({
    stripeConnectStatus: status,
    payoutsEnabled: account.payouts_enabled || false,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log(`User ${userId} Account Status aktualisiert: ${status}`);
}

/**
 * Account Deauthorized - User hat Zugriff widerrufen
 */
async function handleAccountDeauthorized(account: any) {
  const accountId = account.id;
  console.log(`Account Deauthorized: ${accountId}`);

  // User mit diesem Account finden
  const usersSnapshot = await admin
    .firestore()
    .collection('users')
    .where('stripeConnectAccountId', '==', accountId)
    .limit(1)
    .get();

  if (usersSnapshot.empty) {
    return;
  }

  const userDoc = usersSnapshot.docs[0];
  const userId = userDoc.id;

  // Account entfernen
  await admin.firestore().collection('users').doc(userId).update({
    isSeller: false,
    stripeConnectAccountId: null,
    stripeConnectStatus: 'disabled',
    payoutsEnabled: false,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log(`User ${userId} Account deaktiviert`);
}

/**
 * Media-Kauf mit Credits → Transfer an Verkäufer
 */
export const processCreditsPayment = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Nicht angemeldet');
    }

    const buyerId = context.auth.uid;
    const { mediaId, credits, sellerId, platformFeePercent } = data;

    if (!mediaId || !credits || !sellerId) {
      throw new functions.https.HttpsError('invalid-argument', 'Fehlende Parameter');
    }

    try {
      const stripe = getStripe();
      const salesFeePercent = parseFloat(
        functions.config().platform?.sales_fee_percent || 
        process.env.SALES_FEE_PERCENT || 
        '20'
      );
      const feePercent = platformFeePercent || salesFeePercent;

      // Credits zu Euro (1 Credit = 0,10 €)
      const amountInCents = credits * 10;
      const platformFee = Math.round(amountInCents * (feePercent / 100));
      const sellerAmount = amountInCents - platformFee;

      // Verkäufer Account laden
      const sellerDoc = await admin.firestore().collection('users').doc(sellerId).get();
      if (!sellerDoc.exists || !sellerDoc.data()?.stripeConnectAccountId) {
        throw new functions.https.HttpsError('not-found', 'Verkäufer Account nicht gefunden');
      }

      const sellerAccountId = sellerDoc.data()!.stripeConnectAccountId;

      // Media laden um Avatar ID zu bekommen
      const mediaDoc = await admin
        .firestore()
        .collection('avatars')
        .doc(sellerId)
        .collection('media')
        .doc(mediaId)
        .get();

      const avatarId = mediaDoc.exists ? mediaDoc.data()?.avatarId : null;
      const mediaName = mediaDoc.exists ? mediaDoc.data()?.originalFileName : null;

      // Transfer an Verkäufer
      await stripe.transfers.create({
        amount: sellerAmount,
        currency: 'eur',
        destination: sellerAccountId,
        metadata: { mediaId, buyerId, sellerId, avatarId },
      });

      // Sale speichern (users/{sellerId}/sales/{id})
      await admin.firestore().collection('users').doc(sellerId).collection('sales').add({
        sellerId,
        avatarId,
        mediaId,
        mediaName,
        buyerId,
        credits,
        amount: amountInCents / 100,
        platformFee: platformFee / 100,
        sellerEarnings: sellerAmount / 100,
        status: 'completed',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Verkäufer Earnings aktualisieren
      await admin.firestore().collection('users').doc(sellerId).update({
        pendingEarnings: admin.firestore.FieldValue.increment(sellerAmount / 100),
        totalEarnings: admin.firestore.FieldValue.increment(sellerAmount / 100),
      });

      return { success: true };
    } catch (error: any) {
      console.error('Credits Payment Error:', error);
      throw new functions.https.HttpsError('internal', error.message);
    }
  });

/**
 * Generiert Login Link zum Stripe Dashboard (für Seller)
 */
export const createSellerDashboardLink = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Nutzer muss angemeldet sein',
      );
    }

    const userId = context.auth.uid;

    try {
      const stripe = getStripe();

      // User laden
      const userDoc = await admin.firestore().collection('users').doc(userId).get();
      if (!userDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'User nicht gefunden');
      }

      const userData = userDoc.data()!;
      if (!userData.stripeConnectAccountId) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Kein Connected Account vorhanden',
        );
      }

      // Login Link erstellen
      const loginLink = await stripe.accounts.createLoginLink(
        userData.stripeConnectAccountId,
      );

      return { url: loginLink.url };
    } catch (error: any) {
      console.error('Fehler beim Erstellen des Dashboard Links:', error);
      throw new functions.https.HttpsError('internal', error.message);
    }
  });

