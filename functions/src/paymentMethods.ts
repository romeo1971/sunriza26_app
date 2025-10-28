import * as functions from 'firebase-functions/v1';
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
  const secretKey = process.env.STRIPE_SECRET_KEY || functions.config().stripe?.secret_key;
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
  const userDoc = await admin.firestore().collection('users').doc(userId).get();
  if (!userDoc.exists) {
    throw new functions.https.HttpsError('not-found', 'User nicht gefunden');
  }
  const userData = userDoc.data()!;
  if (userData.stripeCustomerId) {
    return userData.stripeCustomerId;
  }
  const customer = await stripe.customers.create({ metadata: { userId } });
  await admin.firestore().collection('users').doc(userId).update({ stripeCustomerId: customer.id });
  return customer.id;
}

/**
 * Setup Intent erstellen (Karte hinzufügen)
 */
export const createSetupIntent = functions.https.onCall(async (data: any, context: functions.https.CallableContext) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Nicht angemeldet');
  }
  try {
    const stripe = getStripe();
    const userId = context.auth.uid;
    const customerId = await getOrCreateCustomer(userId);
    const setupIntent = await stripe.setupIntents.create({
      customer: customerId,
      payment_method_types: ['card'],
    });
    return { clientSecret: setupIntent.client_secret, customerId };
  } catch (error: any) {
    console.error('Setup Intent Error:', error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});

/**
 * Gespeicherte Zahlungsmethoden abrufen
 */
export const getPaymentMethods = functions.https.onCall(async (_data: any, context: functions.https.CallableContext) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Nicht angemeldet');
  }
  try {
    const stripe = getStripe();
    const userId = context.auth.uid;
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    if (!userDoc.exists) {
      return { paymentMethods: [] };
    }
    const customerId = userDoc.data()!.stripeCustomerId;
    if (!customerId) {
      return { paymentMethods: [] };
    }
    const paymentMethods = await stripe.paymentMethods.list({ customer: customerId, type: 'card' });
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
export const deletePaymentMethod = functions.https.onCall(async (data: any, context: functions.https.CallableContext) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Nicht angemeldet');
  }
  const { paymentMethodId } = data || {};
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
export const setDefaultPaymentMethod = functions.https.onCall(async (data: any, context: functions.https.CallableContext) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Nicht angemeldet');
  }
  const { paymentMethodId } = data || {};
  if (!paymentMethodId) {
    throw new functions.https.HttpsError('invalid-argument', 'paymentMethodId fehlt');
  }
  try {
    const stripe = getStripe();
    const userId = context.auth.uid;
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    if (!userDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'User nicht gefunden');
    }
    const customerId = userDoc.data()!.stripeCustomerId;
    if (!customerId) {
      throw new functions.https.HttpsError('failed-precondition', 'Kein Stripe Customer');
    }
    await stripe.customers.update(customerId, { invoice_settings: { default_payment_method: paymentMethodId } });
    return { success: true };
  } catch (error: any) {
    console.error('Set Default Payment Method Error:', error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});

/**
 * Payment Intent mit gespeicherter Karte erstellen
 */
export const createPaymentIntentWithCard = functions.https.onCall(async (data: any, context: functions.https.CallableContext) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Nicht angemeldet');
  }
  const { amount, currency, paymentMethodId, metadata } = data || {};
  if (!amount || !currency) {
    throw new functions.https.HttpsError('invalid-argument', 'amount und currency erforderlich');
  }
  try {
    const stripe = getStripe();
    const userId = context.auth.uid;
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    if (!userDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'User nicht gefunden');
    }
    const customerId = userDoc.data()!.stripeCustomerId;
    if (!customerId) {
      throw new functions.https.HttpsError('failed-precondition', 'Kein Stripe Customer');
    }
    const paymentIntent = await stripe.paymentIntents.create({
      amount,
      currency: String(currency).toLowerCase(),
      customer: customerId,
      payment_method: paymentMethodId || undefined,
      confirm: !!paymentMethodId,
      automatic_payment_methods: paymentMethodId ? undefined : { enabled: true },
      metadata: { userId, ...(metadata || {}) },
    });
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

