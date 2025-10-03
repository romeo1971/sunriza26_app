import * as functions from 'firebase-functions';
import Stripe from 'stripe';

// Stripe nur initialisieren wenn Secret Key vorhanden
const getStripe = () => {
  const secretKey = functions.config().stripe?.secret_key || process.env.STRIPE_SECRET_KEY || '';
  if (!secretKey) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Stripe Secret Key nicht konfiguriert',
    );
  }
  return new Stripe(secretKey, {
    apiVersion: '2025-09-30.clover',
  });
};

/**
 * Cloud Function: Stripe Checkout Session für Media-Kauf
 */
export const createMediaCheckoutSession = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Nutzer muss angemeldet sein',
      );
    }

    const {
      mediaId,
      avatarId,
      amount,
      currency,
      mediaName,
      mediaType,
    } = data;

    if (!mediaId || !amount || !currency) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Fehlende Parameter',
      );
    }

    // Preis-Check: Mindestens 2€
    const minAmount = currency === 'eur' ? 200 : 220; // 2€ bzw. 2.20$
    if (amount < minAmount) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Zahlungen unter 2€ nur mit Credits möglich',
      );
    }

    try {
      const userId = context.auth.uid;
      const appUrl = functions.config().app?.url || 'http://localhost:4202';
      const stripe = getStripe();

      // Stripe Session erstellen
      const session = await stripe.checkout.sessions.create({
        payment_method_types: ['card'],
        line_items: [
          {
            price_data: {
              currency,
              product_data: {
                name: mediaName || 'Media-Kauf',
                description: `${mediaType} - Avatar ${avatarId}`,
              },
              unit_amount: amount, // in Cents
            },
            quantity: 1,
          },
        ],
        mode: 'payment',
        success_url: `${appUrl}/payment-success?session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: `${appUrl}/payment-cancel`,
        metadata: {
          userId,
          mediaId,
          avatarId,
          mediaType: mediaType || 'unknown',
          type: 'media_purchase',
        },
      });

      return { url: session.url };
    } catch (error: any) {
      console.error('Stripe Checkout Error:', error);
      throw new functions.https.HttpsError('internal', error.message);
    }
  });

/**
 * Webhook: Media-Kauf abschließen nach erfolgreicher Zahlung
 * (wird vom stripeWebhook in stripeCheckout.ts aufgerufen)
 */
export async function handleMediaPurchaseWebhook(
  session: Stripe.Checkout.Session,
  admin: any,
) {
  const metadata = session.metadata;
  if (!metadata || metadata.type !== 'media_purchase') return;

  const userId = metadata.userId;
  const mediaId = metadata.mediaId;
  const avatarId = metadata.avatarId;
  const mediaType = metadata.mediaType;

  if (!userId || !mediaId) {
    console.error('Fehlende Metadaten für Media-Kauf');
    return;
  }

  try {
    const userRef = admin.firestore().collection('users').doc(userId);

    // Transaktion anlegen
    await userRef.collection('transactions').add({
      userId,
      type: 'media_purchase',
      mediaId,
      avatarId,
      mediaType,
      amount: session.amount_total ? session.amount_total / 100 : 0,
      currency: session.currency || 'eur',
      stripeSessionId: session.id,
      paymentIntent: session.payment_intent,
      status: 'completed',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Media als gekauft markieren
    await userRef.collection('purchased_media').doc(mediaId).set({
      mediaId,
      avatarId,
      type: mediaType,
      amount: session.amount_total ? session.amount_total / 100 : 0,
      currency: session.currency || 'eur',
      purchasedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`Media-Kauf erfolgreich: User ${userId} - Media ${mediaId}`);
  } catch (error: any) {
    console.error('Fehler beim Media-Kauf verarbeiten:', error);
  }
}

