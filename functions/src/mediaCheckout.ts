import * as functions from 'firebase-functions/v1';
import Stripe from 'stripe';

// Stripe nur initialisieren wenn Secret Key vorhanden
const getStripe = () => {
  const secretKey = (process.env.STRIPE_SECRET_KEY || functions.config().stripe?.secret_key || '').trim();
  if (!secretKey) {
    throw new functions.https.HttpsError('failed-precondition', 'Stripe Secret Key nicht konfiguriert');
  }
  return new Stripe(secretKey, { apiVersion: '2025-09-30.clover' });
};

/**
 * Cloud Function: Stripe Checkout Session für Media-Kauf
 */
export const createMediaCheckoutSession = functions
  .region('us-central1')
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Nutzer muss angemeldet sein');
    }

    const { mediaId, avatarId, amount, currency, mediaName, mediaType } = data || {};

    if (!mediaId || !amount || !currency) {
      throw new functions.https.HttpsError('invalid-argument', 'mediaId, amount, currency erforderlich');
    }

    try {
      const stripe = getStripe();
      const session = await stripe.checkout.sessions.create({
        payment_method_types: ['card'],
        line_items: [
          {
            price_data: {
              currency,
              product_data: {
                name: mediaName || 'Media Purchase',
                description: mediaType ? `Type: ${mediaType}` : undefined,
              },
              unit_amount: amount,
            },
            quantity: 1,
          },
        ],
        mode: 'payment',
        success_url: `${process.env.APP_URL || 'http://localhost:4202'}/media/checkout?success=true&session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: `${process.env.APP_URL || 'http://localhost:4202'}/media/checkout?cancelled=true`,
        metadata: { mediaId, avatarId: avatarId || '' },
      });
      return { sessionId: session.id, url: session.url };
    } catch (e: any) {
      throw new functions.https.HttpsError('internal', e.message || 'Stripe Fehler');
    }
  });

/**
 * Webhook-Handler für Media-Kauf (optional)
 */
export const mediaCheckoutWebhook = functions
  .region('us-central1')
  .https.onRequest(async (req: functions.https.Request, res: functions.Response<any>) => {
    const sig = req.headers['stripe-signature'] as string;
    const webhookSecret = (process.env.STRIPE_WEBHOOK_SECRET || functions.config().stripe?.webhook_secret || '').trim();
    if (!webhookSecret) {
      res.status(500).send('Webhook Secret nicht konfiguriert');
      return;
    }

    const stripe = getStripe();
    try {
      // @ts-ignore
      stripe.webhooks.constructEvent((req as any).rawBody || req.body, sig, webhookSecret);
    } catch (err: any) {
      res.status(400).send(`Webhook Error: ${err.message}`);
      return;
    }

    // Hier Payment-Resultate verarbeiten
    res.json({ received: true });
  });

