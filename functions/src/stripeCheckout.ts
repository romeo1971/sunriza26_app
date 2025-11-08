import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as functions from 'firebase-functions/v1';
import Stripe from 'stripe';
import * as admin from 'firebase-admin';

// Einfache Rechnungsnummer erzeugen: YYYYMMDD-<6hex>
function generateInvoiceNumber(): string {
  const now = new Date();
  const y = now.getUTCFullYear();
  const m = String(now.getUTCMonth() + 1).padStart(2, '0');
  const d = String(now.getUTCDate()).padStart(2, '0');
  const rand = Math.random().toString(16).slice(2, 8).toUpperCase();
  return `${y}${m}${d}-${rand}`;
}

// Stripe nur initialisieren wenn Secret Key vorhanden (env)
const getStripe = () => {
  const secretKey = (process.env.STRIPE_SECRET_KEY || functions.config().stripe?.secret_key || '').trim();
  if (!secretKey) {
    throw new HttpsError('failed-precondition', 'Stripe Secret Key nicht konfiguriert');
  }
  // Verwende die Stripe-Standardversion (keine API-Version erzwingen)
  return new Stripe(secretKey);
};

export const createCreditsCheckoutSession = onCall({ region: 'us-central1' }, async (req) => {
  const auth = req.auth;
  const data = req.data || {} as any;
  if (!auth) throw new HttpsError('unauthenticated', 'Nutzer muss angemeldet sein');
  const userId = auth.uid;
  const { amount, currency, credits } = data;
  if (!amount || !currency || !credits) {
    throw new HttpsError('invalid-argument', 'Fehlende Parameter: amount, currency, credits erforderlich');
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
          product_data: { name: `${credits} Credits` },
          unit_amount: amount,
        },
        quantity: 1,
      }],
      mode: 'payment',
      success_url: `${process.env.APP_URL || 'http://localhost:4202'}/credits-shop?success=true&session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${process.env.APP_URL || 'http://localhost:4202'}/credits-shop?cancelled=true`,
      client_reference_id: userId,
      metadata: { userId, credits: String(credits), type: 'credits_purchase' },
    });
    return { sessionId: session.id, url: session.url };
  } catch (error: any) {
    if (error.type === 'StripeAuthenticationError') throw new HttpsError('failed-precondition', 'Stripe API Key ungültig oder nicht konfiguriert');
    throw new HttpsError('internal', `Stripe Error: ${error.message || 'Unbekannter Fehler'}`);
  }
});

// Liefert Checkout‑Details (Credits/Amount/Currency) nach Stripe‑Redirect
export const getCreditsCheckoutDetails = onCall({ region: 'us-central1' }, async (req) => {
  const sessionId = String((req.data as any)?.sessionId || '').trim();
  if (!sessionId) throw new HttpsError('invalid-argument', 'sessionId fehlt');
  try {
    const stripe = getStripe();
    const session = await stripe.checkout.sessions.retrieve(sessionId);
    const md: any = session.metadata || {};
    const credits = parseInt(String(md.credits || '0')) || 0;
    return {
      credits,
      amountTotal: session.amount_total || 0,
      currency: session.currency || 'eur',
    };
  } catch (e: any) {
    throw new HttpsError('internal', e?.message || 'Stripe Fehler');
  }
});

// Webhook auf v1 wegen besserer Raw Body Support
export const stripeWebhook = functions
  .region('us-central1')
  .https.onRequest(async (req, res) => {
    const sig = req.headers['stripe-signature'] as string;
    const webhookSecret = (process.env.STRIPE_WEBHOOK_SECRET || functions.config().stripe?.webhook_secret || '').trim();
    if (!webhookSecret) { res.status(500).send('Webhook Secret nicht konfiguriert'); return; }
    const stripe = getStripe();
    let event: Stripe.Event;
    try {
      // v1 hat rawBody automatisch
      event = stripe.webhooks.constructEvent((req as any).rawBody, sig, webhookSecret);
    } catch (err: any) {
      console.error('Webhook Signature Error:', err.message);
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
      const { userId, credits } = md;
      if (!userId || !credits) { 
        console.error('Fehlende Metadata:', md);
        res.status(400).send('Fehlende Metadata'); 
        return; 
      }
      const creditsNum = parseInt(String(credits));
      try {
        console.log(`Credits gutschreiben: ${creditsNum} für User ${userId}`);
        const userRef = admin.firestore().collection('users').doc(userId);
        await userRef.update({
          credits: admin.firestore.FieldValue.increment(creditsNum),
          creditsPurchased: admin.firestore.FieldValue.increment(creditsNum),
        });
        const invoiceNumber = generateInvoiceNumber();
        await userRef.collection('transactions').add({
          userId, type: 'credit_purchase', credits: creditsNum,
          amount: session.amount_total || 0, currency: session.currency || 'eur',
          stripeSessionId: session.id, paymentIntent: session.payment_intent, status: 'completed',
          invoiceNumber,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`✅ Credits erfolgreich gutgeschrieben`);
      } catch (e) { 
        console.error('Firestore Error:', e);
        res.status(500).send('Interner Fehler'); 
        return; 
      }
    }
    res.json({ received: true });
  });

