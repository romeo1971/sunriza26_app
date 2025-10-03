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
      const stripe = getStripe();
      
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
        success_url: `${functions.config().app?.url || 'http://localhost:4202'}/credits-success?session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: `${functions.config().app?.url || 'http://localhost:4202'}/credits-shop`,
        client_reference_id: userId,
        metadata: {
          userId,
          credits: credits.toString(),
          euroAmount: euroAmount.toString(),
          exchangeRate: exchangeRate?.toString() || '1.0',
          type: 'credits_purchase',
        },
      });

      return {
        sessionId: session.id,
        url: session.url,
      };
    } catch (error: any) {
      console.error('Stripe Checkout Error:', error);
      throw new functions.https.HttpsError(
        'internal',
        `Stripe Error: ${error.message}`,
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

    // Handle payment_intent.succeeded (für Payment Intents mit gespeicherten Karten)
    if (event.type === 'payment_intent.succeeded') {
      const paymentIntent = event.data.object as Stripe.PaymentIntent;
      const { userId, type } = paymentIntent.metadata || {};

      if (!userId || !type) {
        console.error('Fehlende Metadata in PaymentIntent:', paymentIntent.id);
        res.json({ received: true });
        return;
      }

      try {
        if (type === 'credits') {
          // Credits-Kauf mit gespeicherter Karte
          const credits = parseInt(paymentIntent.metadata.credits || '0');
          const euroAmount = parseFloat(paymentIntent.metadata.euroAmount || '0');
          const exchangeRate = parseFloat(paymentIntent.metadata.exchangeRate || '1.0');

          const userRef = admin.firestore().collection('users').doc(userId);
          await userRef.update({
            credits: admin.firestore.FieldValue.increment(credits),
            creditsPurchased: admin.firestore.FieldValue.increment(credits),
          });

          await userRef.collection('transactions').add({
            userId,
            type: 'credit_purchase',
            credits,
            euroAmount,
            amount: paymentIntent.amount,
            currency: paymentIntent.currency,
            exchangeRate,
            paymentIntentId: paymentIntent.id,
            status: 'completed',
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          console.log(`Credits (PaymentIntent): User ${userId} - ${credits} Credits`);
        } else if (type === 'media') {
          // Media-Kauf mit gespeicherter Karte
          const { mediaId, avatarId, mediaName, mediaType, sellerId, platformFeePercent } = paymentIntent.metadata;

          if (!mediaId || !avatarId || !sellerId) {
            console.error('Fehlende Media-Metadata:', paymentIntent.id);
            res.json({ received: true });
            return;
          }

          const price = paymentIntent.amount / 100; // Cents → Euro
          const requiredCredits = Math.round(price / 0.1);

          // 1. Media als gekauft markieren
          await admin.firestore()
            .collection('users')
            .doc(userId)
            .collection('purchased_media')
            .doc(mediaId)
            .set({
              mediaId,
              avatarId,
              type: mediaType || 'unknown',
              price,
              currency: paymentIntent.currency,
              purchasedAt: admin.firestore.FieldValue.serverTimestamp(),
              paymentIntentId: paymentIntent.id,
            });

          // 2. Transaktion anlegen
          await admin.firestore()
            .collection('users')
            .doc(userId)
            .collection('transactions')
            .add({
              userId,
              type: 'media_purchase',
              mediaId,
              mediaName: mediaName || 'Media',
              mediaType: mediaType || 'unknown',
              avatarId,
              amount: paymentIntent.amount,
              currency: paymentIntent.currency,
              paymentIntentId: paymentIntent.id,
              status: 'completed',
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

          // 3. Verkäufer bezahlen (Stripe Connect Transfer)
          const feePercent = parseFloat(platformFeePercent || '20');
          const platformFee = Math.round((paymentIntent.amount * feePercent) / 100);
          const sellerAmount = paymentIntent.amount - platformFee;

          const sellerDoc = await admin.firestore().collection('users').doc(sellerId).get();
          const sellerAccountId = sellerDoc.data()?.stripeConnectAccountId;

          if (sellerAccountId) {
            await stripe.transfers.create({
              amount: sellerAmount,
              currency: paymentIntent.currency,
              destination: sellerAccountId,
              metadata: { mediaId, buyerId: userId, sellerId },
            });

            // Sale speichern
            await admin.firestore()
              .collection('users')
              .doc(sellerId)
              .collection('sales')
              .add({
                sellerId,
                avatarId,
                mediaId,
                mediaName: mediaName || 'Media',
                buyerId: userId,
                credits: requiredCredits,
                amount: price,
                platformFee: platformFee / 100,
                sellerEarnings: sellerAmount / 100,
                status: 'completed',
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
              });

            // Earnings aktualisieren
            await admin.firestore()
              .collection('users')
              .doc(sellerId)
              .update({
                pendingEarnings: admin.firestore.FieldValue.increment(sellerAmount / 100),
                totalEarnings: admin.firestore.FieldValue.increment(sellerAmount / 100),
              });
          }

          console.log(`Media gekauft (PaymentIntent): User ${userId} - Media ${mediaId}`);
        }
      } catch (error: any) {
        console.error('Fehler bei PaymentIntent-Verarbeitung:', error);
        res.status(500).send('Interner Fehler');
        return;
      }
    }

    res.json({ received: true });
  });

