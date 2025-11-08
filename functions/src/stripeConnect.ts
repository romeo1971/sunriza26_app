import * as functions from 'firebase-functions/v1';
import * as admin from 'firebase-admin';

// Stripe nur initialisieren wenn Secret Key vorhanden
const getStripe = () => {
  const secretKey = (process.env.STRIPE_SECRET_KEY || functions.config().stripe?.secret_key || '').trim();
  if (!secretKey) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Stripe Secret Key nicht konfiguriert',
    );
  }
  const Stripe = require('stripe');
  return new Stripe(secretKey);
};

/**
 * Erstellt Stripe Connected Account für Verkäufer (Seller Onboarding)
 */
export const createConnectedAccount = functions
  .region('us-central1')
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Nutzer muss angemeldet sein',
      );
    }

    const userId = context.auth.uid;
    const { country, email, businessType } = data || {};

    if (!country || !email) {
      throw new functions.https.HttpsError('invalid-argument', 'Country und Email erforderlich');
    }

    try {
      const stripe = getStripe();
      const userDoc = await admin.firestore().collection('users').doc(userId).get();
      if (!userDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'User nicht gefunden');
      }

      const userData = userDoc.data()!;

      if (userData.stripeConnectAccountId) {
        const account = await stripe.accounts.retrieve(userData.stripeConnectAccountId);
        if (!account.charges_enabled || !account.payouts_enabled) {
          const appUrl = process.env.APP_URL || functions.config().app?.url || 'http://localhost:4202';
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
        return { accountId: userData.stripeConnectAccountId, status: 'active' };
      }

      const account = await stripe.accounts.create({
        type: 'express',
        country: String(country).toUpperCase(),
        email,
        business_type: businessType || 'individual',
        capabilities: { card_payments: { requested: true }, transfers: { requested: true } },
        settings: { payouts: { schedule: { interval: 'monthly', monthly_anchor: 28 } } },
      });

      const appUrl = process.env.APP_URL || functions.config().app?.url || 'http://localhost:4202';
      const accountLink = await stripe.accountLinks.create({
        account: account.id,
        refresh_url: `${appUrl}/seller/onboarding?refresh=true`,
        return_url: `${appUrl}/seller/onboarding?success=true`,
        type: 'account_onboarding',
      });

      await admin.firestore().collection('users').doc(userId).update({
        isSeller: true,
        stripeConnectAccountId: account.id,
        stripeConnectStatus: 'pending',
        payoutsEnabled: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return { accountId: account.id, url: accountLink.url, status: 'pending' };
    } catch (error: any) {
      // Ausführliches Stripe-Fehlerlogging für schnelle Diagnose
      try {
        console.error('Fehler beim Erstellen des Connected Accounts:', {
          message: error?.message,
          type: error?.type,
          code: error?.code,
          param: error?.param,
          requestId: error?.requestId || error?.raw?.requestId,
          raw: error?.raw,
          stack: error?.stack,
        });
      } catch (_) {
        console.error('Fehler beim Erstellen des Connected Accounts (fallback):', error);
      }
      throw new functions.https.HttpsError('internal', error.message);
    }
  });

export const stripeConnectWebhook = functions
  .region('us-central1')
  .https.onRequest(async (req: functions.https.Request, res: functions.Response<any>) => {
    const sig = req.headers['stripe-signature'] as string;
    // Eigener Secret für CONNECT‑Webhook, damit Checkout und Connect getrennte Secrets nutzen können
    const webhookSecret = (
      process.env.STRIPE_CONNECT_WEBHOOK_SECRET
      || functions.config().stripe?.connect_webhook_secret
      || ''
    ).trim();
    if (!webhookSecret) {
      res.status(500).send('Webhook Secret nicht konfiguriert');
      return;
    }

    const stripe = getStripe();
    let event: any;
    try {
      // @ts-ignore rawBody bei v1 vorhanden, in Emulator aufsetzen
      event = stripe.webhooks.constructEvent((req as any).rawBody || (req as any).raw || req.body, sig, webhookSecret);
    } catch (err: any) {
      res.status(400).send(`Webhook Error: ${err.message}`);
      return;
    }

    try {
      const t = String(event.type || '');
      if (
        t === 'account.updated' ||
        t.startsWith('v2.core.account.updated') ||
        t.startsWith('v2.core.account[') // includes requirements/configuration.* updates
      ) {
        await handleAccountUpdated(event.data.object);
      } else if (t === 'account.application.deauthorized' || t === 'v2.core.account.closed') {
        await handleAccountDeauthorized(event.data.object);
      } else {
        // ignore other v2 events like account_person.*
      }
      res.json({ received: true });
    } catch (error: any) {
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

export const processCreditsPayment = functions
  .region('us-central1')
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Nicht angemeldet');
    }

    const buyerId = context.auth.uid;
    const { mediaId, credits, sellerId, platformFeePercent } = data || {};
    if (!mediaId || !credits || !sellerId) {
      throw new functions.https.HttpsError('invalid-argument', 'Fehlende Parameter');
    }

    try {
      const stripe = getStripe();
      const salesFeePercent = parseFloat(process.env.SALES_FEE_PERCENT || functions.config().platform?.sales_fee_percent || '20');
      const feePercent = platformFeePercent || salesFeePercent;
      const amountInCents = credits * 10;
      const platformFee = Math.round(amountInCents * (feePercent / 100));
      const sellerAmount = amountInCents - platformFee;

      const sellerDoc = await admin.firestore().collection('users').doc(sellerId).get();
      if (!sellerDoc.exists || !sellerDoc.data()?.stripeConnectAccountId) {
        throw new functions.https.HttpsError('not-found', 'Verkäufer Account nicht gefunden');
      }
      const sellerAccountId = sellerDoc.data()!.stripeConnectAccountId;

      const mediaDoc = await admin.firestore().collection('avatars').doc(sellerId).collection('media').doc(mediaId).get();
      const avatarId = mediaDoc.exists ? mediaDoc.data()?.avatarId : null;
      const mediaName = mediaDoc.exists ? mediaDoc.data()?.originalFileName : null;

      await stripe.transfers.create({ amount: sellerAmount, currency: 'eur', destination: sellerAccountId, metadata: { mediaId, buyerId, sellerId, avatarId } });

      await admin.firestore().collection('users').doc(sellerId).collection('sales').add({
        sellerId, avatarId, mediaId, mediaName, buyerId, credits,
        amount: amountInCents / 100,
        platformFee: platformFee / 100,
        sellerEarnings: sellerAmount / 100,
        status: 'completed',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

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
 * Manuelle Status-Aktualisierung: liest den aktuellen Connect-Status von Stripe
 * und schreibt ihn in users/{uid}. Für UI-„Status prüfen“-Button gedacht.
 */
export const refreshSellerStatus = functions
  .region('us-central1')
  .https.onCall(async (_data: any, context: functions.https.CallableContext) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Nutzer muss angemeldet sein');
    }
    const userId = context.auth.uid;
    try {
      const stripe = getStripe();
      const userDoc = await admin.firestore().collection('users').doc(userId).get();
      if (!userDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'User nicht gefunden');
      }
      const d = userDoc.data()!;
      const accId: string | undefined = d.stripeConnectAccountId;
      if (!accId) {
        throw new functions.https.HttpsError('failed-precondition', 'Kein verbundenes Verkäufer-Konto vorhanden');
      }
      const account = await stripe.accounts.retrieve(accId);
      let status = 'pending';
      if ((account as any).details_submitted && (account as any).charges_enabled && (account as any).payouts_enabled) {
        status = 'active';
      } else if ((account as any)?.requirements?.disabled_reason) {
        status = 'restricted';
      }
      await admin.firestore().collection('users').doc(userId).update({
        stripeConnectStatus: status,
        payoutsEnabled: (account as any).payouts_enabled || false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return { status, payoutsEnabled: (account as any).payouts_enabled || false };
    } catch (error: any) {
      console.error('refreshSellerStatus error:', error);
      throw new functions.https.HttpsError('internal', error?.message || 'Unbekannter Fehler');
    }
  });

/**
 * Verkäufer‑Konto trennen: löscht (Test) bzw. deaktiviert das verbundene Express‑Konto
 * und setzt die Felder im User‑Dokument zurück.
 */
export const disconnectSellerAccount = functions
  .region('us-central1')
  .https.onCall(async (_data: any, context: functions.https.CallableContext) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Nutzer muss angemeldet sein');
    }
    const userId = context.auth.uid;
    try {
      const stripe = getStripe();
      const ref = admin.firestore().collection('users').doc(userId);
      const snap = await ref.get();
      if (!snap.exists) {
        throw new functions.https.HttpsError('not-found', 'User nicht gefunden');
      }
      const accId = (snap.data() as any)?.stripeConnectAccountId as string | undefined;
      if (accId) {
        try {
          await stripe.accounts.del(accId);
        } catch (e) {
          // Falls nicht löschbar (LIVE), ignoriere und setze Status auf disabled
          console.warn('accounts.del failed, continue with local cleanup', e);
        }
      }
      await ref.update({
        isSeller: false,
        stripeConnectAccountId: admin.firestore.FieldValue.delete(),
        stripeConnectStatus: 'disabled',
        payoutsEnabled: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return { ok: true };
    } catch (error: any) {
      console.error('disconnectSellerAccount error:', error);
      throw new functions.https.HttpsError('internal', error?.message || 'Unbekannter Fehler');
    }
  });

/**
 * Nur Anfrage: Verkäufer‑Konto‑Auflösung beantragen (wird von Admin/Plattform ausgeführt).
 */
export const requestSellerDisconnect = functions
  .region('us-central1')
  .https.onCall(async (_data: any, context: functions.https.CallableContext) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Nutzer muss angemeldet sein');
    }
    const userId = context.auth.uid;
    try {
      const stripe = getStripe();
      const userRef = admin.firestore().collection('users').doc(userId);
      const snap = await userRef.get();
      const accId = (snap.data() as any)?.stripeConnectAccountId as string | undefined;
      const ts = Date.now().toString();
      if (accId) {
        try {
          await stripe.accounts.update(accId, {
            metadata: {
              disconnect_requested: 'true',
              disconnect_requested_at: ts,
            },
          } as any);
        } catch (e) {
          console.warn('metadata update failed', e);
        }
      }
      await admin.firestore().collection('users').doc(userId).set({
        sellerDisconnectRequested: true,
        sellerDisconnectRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      return { ok: true };
    } catch (e: any) {
      console.error('requestSellerDisconnect error:', e);
      throw new functions.https.HttpsError('internal', e?.message || 'Unbekannter Fehler');
    }
  });

export const createSellerDashboardLink = functions
  .region('us-central1')
  .https.onCall(async (_data: any, context: functions.https.CallableContext) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Nutzer muss angemeldet sein');
    }
    const userId = context.auth.uid;
    try {
      const stripe = getStripe();
      const userDoc = await admin.firestore().collection('users').doc(userId).get();
      if (!userDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'User nicht gefunden');
      }
      const userData = userDoc.data()!;
      if (!userData.stripeConnectAccountId) {
        throw new functions.https.HttpsError('failed-precondition', 'Kein Connected Account vorhanden');
      }
      const loginLink = await stripe.accounts.createLoginLink(userData.stripeConnectAccountId);
      return { url: loginLink.url };
    } catch (error: any) {
      console.error('Fehler beim Erstellen des Dashboard Links:', error);
      throw new functions.https.HttpsError('internal', error.message);
    }
  });

