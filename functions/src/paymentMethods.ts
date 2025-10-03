import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

/**
 * Payment Methods Management
 * - Karten speichern (Setup Intent)
 * - Karten abrufen
 * - Karten löschen
 * - Standard-Karte setzen
 */

// Stripe initialisieren (conditional)
function getStripe() {
  const secretKey = functions.config().stripe?.secret_key || process.env.STRIPE_SECRET_KEY;
  if (!secretKey) {
    throw new functions.https.HttpsError('failed-precondition', 'Stripe Secret Key nicht konfiguriert');
  }
  const stripe = require('stripe')(secretKey, { apiVersion: '2025-09-30.clover' });
  return stripe;
}

/**
 * Stripe Customer ID holen oder erstellen
 */
async function getOrCreateCustomer(userId: string): Promise<string> {
  const stripe = getStripe();
  
  // UserProfile laden
  const userDoc = await admin.firestore().collection('users').doc(userId).get();
  if (!userDoc.exists) {
    throw new functions.https.HttpsError('not-found', 'User nicht gefunden');
  }

  const userData = userDoc.data()!;
  
  // Bereits vorhanden?
  if (userData.stripeCustomerId) {
    return userData.stripeCustomerId;
  }

  // Neu erstellen
  const customer = await stripe.customers.create({
    metadata: { userId },
  });

  // In Firestore speichern
  await admin.firestore().collection('users').doc(userId).update({
    stripeCustomerId: customer.id,
  });

  return customer.id;
}

/**
 * Setup Intent erstellen (Karte hinzufügen)
 */
export const createSetupIntent = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Nicht angemeldet');
  }

  try {
    const stripe = getStripe();
    const userId = context.auth.uid;
    const customerId = await getOrCreateCustomer(userId);

    // Setup Intent erstellen
    const setupIntent = await stripe.setupIntents.create({
      customer: customerId,
      payment_method_types: ['card'],
    });

    return {
      clientSecret: setupIntent.client_secret,
      customerId,
    };
  } catch (error: any) {
    console.error('Setup Intent Error:', error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});

/**
 * Gespeicherte Zahlungsmethoden abrufen
 */
export const getPaymentMethods = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Nicht angemeldet');
  }

  try {
    const stripe = getStripe();
    const userId = context.auth.uid;

    // UserProfile laden
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    if (!userDoc.exists) {
      return { paymentMethods: [] };
    }

    const customerId = userDoc.data()!.stripeCustomerId;
    if (!customerId) {
      return { paymentMethods: [] };
    }

    // Zahlungsmethoden von Stripe laden
    const paymentMethods = await stripe.paymentMethods.list({
      customer: customerId,
      type: 'card',
    });

    // Customer laden um default zu erkennen
    const customer = await stripe.customers.retrieve(customerId);

    return {
      paymentMethods: paymentMethods.data.map((pm: any) => ({
        id: pm.id,
        brand: pm.card.brand,
        last4: pm.card.last4,
        expMonth: pm.card.exp_month,
        expYear: pm.card.exp_year,
        isDefault: pm.id === (customer as any).invoice_settings?.default_payment_method,
      })),
    };
  } catch (error: any) {
    console.error('Get Payment Methods Error:', error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});

/**
 * Zahlungsmethode löschen
 */
export const deletePaymentMethod = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Nicht angemeldet');
  }

  const { paymentMethodId } = data;
  if (!paymentMethodId) {
    throw new functions.https.HttpsError('invalid-argument', 'paymentMethodId fehlt');
  }

  try {
    const stripe = getStripe();
    await stripe.paymentMethods.detach(paymentMethodId);
    return { success: true };
  } catch (error: any) {
    console.error('Delete Payment Method Error:', error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});

/**
 * Standard-Zahlungsmethode setzen
 */
export const setDefaultPaymentMethod = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Nicht angemeldet');
  }

  const { paymentMethodId } = data;
  if (!paymentMethodId) {
    throw new functions.https.HttpsError('invalid-argument', 'paymentMethodId fehlt');
  }

  try {
    const stripe = getStripe();
    const userId = context.auth.uid;

    // UserProfile laden
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    if (!userDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'User nicht gefunden');
    }

    const customerId = userDoc.data()!.stripeCustomerId;
    if (!customerId) {
      throw new functions.https.HttpsError('failed-precondition', 'Kein Stripe Customer');
    }

    // Standard setzen
    await stripe.customers.update(customerId, {
      invoice_settings: {
        default_payment_method: paymentMethodId,
      },
    });

    return { success: true };
  } catch (error: any) {
    console.error('Set Default Payment Method Error:', error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});

/**
 * Payment Intent mit gespeicherter Karte erstellen
 * Für: Credits kaufen, Media kaufen (≥2€)
 */
export const createPaymentIntentWithCard = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Nicht angemeldet');
  }

  const { amount, currency, paymentMethodId, metadata } = data;
  
  if (!amount || !currency) {
    throw new functions.https.HttpsError('invalid-argument', 'amount und currency erforderlich');
  }

  try {
    const stripe = getStripe();
    const userId = context.auth.uid;

    // UserProfile laden
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    if (!userDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'User nicht gefunden');
    }

    const customerId = userDoc.data()!.stripeCustomerId;
    if (!customerId) {
      throw new functions.https.HttpsError('failed-precondition', 'Kein Stripe Customer');
    }

    // Payment Intent erstellen
    const paymentIntent = await stripe.paymentIntents.create({
      amount, // in Cents
      currency: currency.toLowerCase(),
      customer: customerId,
      payment_method: paymentMethodId || undefined,
      confirm: paymentMethodId ? true : false, // Auto-confirm wenn Karte angegeben
      automatic_payment_methods: paymentMethodId ? undefined : { enabled: true },
      metadata: {
        userId,
        ...metadata,
      },
    });

    // Bei erfolgreicher Zahlung: Webhook verarbeitet den Rest
    return {
      clientSecret: paymentIntent.client_secret,
      status: paymentIntent.status,
      paymentIntentId: paymentIntent.id,
    };
  } catch (error: any) {
    console.error('Create Payment Intent Error:', error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});

