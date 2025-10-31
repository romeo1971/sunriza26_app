import { onCall, onRequest, HttpsError } from 'firebase-functions/v2/https';
import Stripe from 'stripe';
import * as admin from 'firebase-admin';

// Stripe nur initialisieren wenn Secret Key vorhanden (env)
const getStripe = () => {
  const secretKey = (process.env.STRIPE_SECRET_KEY || '').trim();
  if (!secretKey) {
    throw new HttpsError('failed-precondition', 'Stripe Secret Key nicht konfiguriert');
  }
  return new Stripe(secretKey, { apiVersion: '2025-09-30.clover' });
};

export const createCreditsCheckoutSession = onCall({ region: 'us-central1' }, async (req) => {
  const auth = req.auth;
  const data = req.data || {} as any;
  if (!auth) throw new HttpsError('unauthenticated', 'Nutzer muss angemeldet sein');
  const userId = auth.uid;
  const { euroAmount, amount, currency, exchangeRate, credits } = data;
  if (!amount || !currency || !credits || !euroAmount) {
    throw new HttpsError('invalid-argument', 'Fehlende Parameter: amount, currency, credits, euroAmount erforderlich');
  }
  if (currency !== 'eur' && currency !== 'usd') {
    throw new HttpsError('invalid-argument', 'Währung muss eur oder usd sein');
  }
  try {
    const stripe = getStripe();
    const session = await stripe.checkout.sessions.create({
      payment_method_types: ['card'],
      line_items: [{
        price_data: {
          currency,
          product_data: { name: `${credits} Credits`, description: `${credits} Credits für Sunriza (Basis: ${euroAmount} EUR)` },
          unit_amount: amount,
        },
        quantity: 1,
      }],
      mode: 'payment',
      success_url: `${process.env.APP_URL || 'http://localhost:4202'}/credits-shop?success=true&session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${process.env.APP_URL || 'http://localhost:4202'}/credits-shop?cancelled=true`,
      client_reference_id: userId,
      metadata: { userId, credits: String(credits), euroAmount: String(euroAmount), exchangeRate: exchangeRate ? String(exchangeRate) : '1.0', type: 'credits_purchase' },
    });
    return { sessionId: session.id, url: session.url };
  } catch (error: any) {
    if (error.type === 'StripeAuthenticationError') throw new HttpsError('failed-precondition', 'Stripe API Key ungültig oder nicht konfiguriert');
    throw new HttpsError('internal', `Stripe Error: ${error.message || 'Unbekannter Fehler'}`);
  }
});

export const stripeWebhook = onRequest({ region: 'us-central1' }, async (req, res) => {
  const sig = req.headers['stripe-signature'] as string;
  const webhookSecret = (process.env.STRIPE_WEBHOOK_SECRET || '').trim();
  if (!webhookSecret) { res.status(500).send('Webhook Secret nicht konfiguriert'); return; }
  const stripe = getStripe();
  let event: Stripe.Event;
  try {
    // @ts-ignore
    event = stripe.webhooks.constructEvent(req.rawBody || req.body, sig, webhookSecret);
  } catch (err: any) {
    res.status(400).send(`Webhook Error: ${err.message}`);
    return;
  }
  if (event.type === 'checkout.session.completed') {
    const session = event.data.object as Stripe.Checkout.Session;
    const md: any = session.metadata || {};
    if (md.type === 'media_purchase') {
      try {
        const path = './mediaCheckout';
        const mod = await import(path);
        if (mod && typeof mod.handleMediaPurchaseWebhook === 'function') {
          await mod.handleMediaPurchaseWebhook(session, admin);
        }
      } catch (_) {}
      res.json({ received: true });
      return;
    }
    const { userId, credits, euroAmount, exchangeRate } = md;
    if (!userId || !credits) { res.status(400).send('Fehlende Metadata'); return; }
    const creditsNum = parseInt(String(credits));
    const euroAmountNum = parseFloat(String(euroAmount || '0'));
    const exchangeRateNum = parseFloat(String(exchangeRate || '1.0'));
    try {
      const userRef = admin.firestore().collection('users').doc(userId);
      await userRef.update({
        credits: admin.firestore.FieldValue.increment(creditsNum),
        creditsPurchased: admin.firestore.FieldValue.increment(creditsNum),
      });
      await userRef.collection('transactions').add({
        userId, type: 'credit_purchase', credits: creditsNum, euroAmount: euroAmountNum,
        amount: session.amount_total || 0, currency: session.currency || 'eur', exchangeRate: exchangeRateNum,
        stripeSessionId: session.id, paymentIntent: session.payment_intent, status: 'completed',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (e) { res.status(500).send('Interner Fehler'); return; }
  }
  res.json({ received: true });
});

