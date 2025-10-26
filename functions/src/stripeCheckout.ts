import * as functions from 'firebase-functions';
import Stripe from 'stripe';
import * as admin from 'firebase-admin';
import { handleMediaPurchaseWebhook } from './mediaCheckout';

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
 * Erstellt eine Stripe Checkout Session für Credits-Kauf
 * 
 * Test Mode: Verwende Stripe Test Keys
 * Live Mode: Verwende Stripe Live Keys
 */
export const createCreditsCheckoutSession = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    // Auth-Check
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Nutzer muss angemeldet sein',
      );
    }

    const userId = context.auth.uid;
    const {
      euroAmount,
      amount, // Preis in Cents (EUR oder USD)
      currency, // 'eur' oder 'usd'
      exchangeRate,
      credits,
    } = data;

    // Validierung
    if (!amount || !currency || !credits || !euroAmount) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Fehlende Parameter: amount, currency, credits, euroAmount erforderlich',
      );
    }

    if (currency !== 'eur' && currency !== 'usd') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Währung muss eur oder usd sein',
      );
    }

    try {
      console.log('Creating Credits Checkout Session for user:', userId);
      console.log('Credits:', credits, 'Amount:', amount, 'Currency:', currency);
      
      const stripe = getStripe();
      console.log('Stripe initialized successfully');
      
      // Checkout Session erstellen
      const session = await stripe.checkout.sessions.create({
        payment_method_types: ['card'],
        line_items: [
          {
            price_data: {
              currency: currency,
              product_data: {
                name: `${credits} Credits`,
                description: `${credits} Credits für Sunriza (Basis: ${euroAmount} EUR)`,
                images: [
                  'https://firebasestorage.googleapis.com/v0/b/sunriza26.appspot.com/o/app-icon.png?alt=media',
                ],
              },
              unit_amount: amount, // in Cents
            },
            quantity: 1,
          },
        ],
        mode: 'payment',
        success_url: `${functions.config().app?.url || 'http://localhost:4202'}/credits-shop?success=true&session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: `${functions.config().app?.url || 'http://localhost:4202'}/credits-shop?cancelled=true`,
        client_reference_id: userId,
        metadata: {
          userId,
          credits: credits.toString(),
          euroAmount: euroAmount.toString(),
          exchangeRate: exchangeRate?.toString() || '1.0',
          type: 'credits_purchase',
        },
      });

      console.log('Checkout Session created:', session.id);
      
      return {
        sessionId: session.id,
        url: session.url,
      };
    } catch (error: any) {
      console.error('❌ Stripe Checkout Error:', error);
      console.error('Error details:', {
        message: error.message,
        type: error.type,
        code: error.code,
        stack: error.stack,
      });
      
      // Spezifische Fehler
      if (error.type === 'StripeAuthenticationError') {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Stripe API Key ungültig oder nicht konfiguriert',
        );
      }
      
      throw new functions.https.HttpsError(
        'internal',
        `Stripe Error: ${error.message || 'Unbekannter Fehler'}`,
      );
    }
  });

/**
 * Stripe Webhook Handler
 * Verarbeitet erfolgreiche Zahlungen und schreibt Credits gut
 */
export const stripeWebhook = functions
  .region('us-central1')
  .https.onRequest(async (req, res) => {
    const sig = req.headers['stripe-signature'] as string;
    const webhookSecret =
      functions.config().stripe?.webhook_secret || process.env.STRIPE_WEBHOOK_SECRET || '';

    if (!webhookSecret) {
      console.error('Webhook Secret fehlt');
      res.status(500).send('Webhook Secret nicht konfiguriert');
      return;
    }

    let event: Stripe.Event;
    const stripe = getStripe();

    try {
      event = stripe.webhooks.constructEvent(req.rawBody, sig, webhookSecret);
    } catch (err: any) {
      console.error('Webhook Signature Verification failed:', err.message);
      res.status(400).send(`Webhook Error: ${err.message}`);
      return;
    }

    // Handle checkout.session.completed
    if (event.type === 'checkout.session.completed') {
      const session = event.data.object as Stripe.Checkout.Session;
      const { userId, credits, euroAmount, exchangeRate, type } = session.metadata || {};

      // Media-Kauf: Separater Handler
      if (type === 'media_purchase') {
        await handleMediaPurchaseWebhook(session, admin);
        res.json({ received: true });
        return;
      }

      // Credits-Kauf
      if (!userId || !credits) {
        console.error('Fehlende Metadata in Session:', session.id);
        res.status(400).send('Fehlende Metadata');
        return;
      }

      const creditsNum = parseInt(credits);
      const euroAmountNum = parseFloat(euroAmount || '0');
      const exchangeRateNum = parseFloat(exchangeRate || '1.0');

      try {
        // Credits zum User hinzufügen
        const userRef = admin.firestore().collection('users').doc(userId);
        await userRef.update({
          credits: admin.firestore.FieldValue.increment(creditsNum),
          creditsPurchased: admin.firestore.FieldValue.increment(creditsNum),
        });

        // Transaktion speichern
        await userRef.collection('transactions').add({
          userId,
          type: 'credit_purchase',
          credits: creditsNum,
          euroAmount: euroAmountNum,
          amount: session.amount_total || 0,
          currency: session.currency || 'eur',
          exchangeRate: exchangeRateNum,
          stripeSessionId: session.id,
          paymentIntent: session.payment_intent,
          status: 'completed',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(
          `Credits gutgeschrieben: User ${userId} - ${creditsNum} Credits`,
        );
      } catch (error: any) {
        console.error('Fehler beim Credits gutschreiben:', error);
        res.status(500).send('Interner Fehler');
        return;
      }
    }

    res.json({ received: true });
  });

