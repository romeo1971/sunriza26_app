import * as functions from 'firebase-functions/v1';
import Stripe from 'stripe';
import * as admin from 'firebase-admin';

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

    const { mediaId, avatarId, amount, currency, mediaName, mediaType, mediaUrl, returnUrl } = data || {};

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
        // Hash-Routing für Flutter Web, damit die Route sicher erkannt wird
        success_url: `${process.env.APP_URL || 'http://localhost:4202'}/#/media/checkout?success=true&type=media&avatarId=${encodeURIComponent(avatarId || '')}&mediaId=${encodeURIComponent(mediaId)}&mediaType=${encodeURIComponent(mediaType || '')}&mediaUrl=${encodeURIComponent(mediaUrl || '')}&session_id={CHECKOUT_SESSION_ID}${returnUrl ? `&return=${encodeURIComponent(returnUrl)}` : ''}`,
        cancel_url: `${process.env.APP_URL || 'http://localhost:4202'}/#/media/checkout?cancelled=true&type=media`,
        metadata: {
          type: 'media_purchase',
          userId: context.auth.uid,
          mediaId,
          avatarId: avatarId || '',
          mediaName: mediaName || 'Media',
          mediaType: mediaType || '',
          mediaUrl: mediaUrl || '',
        },
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

/**
 * Wird vom allgemeinen Stripe-Webhook (stripeCheckout.ts) aufgerufen,
 * wenn md.type === 'media_purchase'. Schreibt eine Transaktion für den Nutzer.
 */
export async function handleMediaPurchaseWebhook(session: Stripe.Checkout.Session, admin: any) {
  try {
    const md: any = session.metadata || {};
    const userId = md.userId as string | undefined;
    if (!userId) {
      console.error('handleMediaPurchaseWebhook: userId fehlt');
      return;
    }

    const amount = session.amount_total || 0; // cents
    const currency = (session.currency || 'eur').toLowerCase();

    const txRef = admin.firestore().collection('users').doc(userId).collection('transactions').doc(String(session.id));
    await txRef.set({
      userId,
      type: 'media_purchase',
      amount,
      currency,
      status: 'completed',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      mediaId: md.mediaId || null,
      mediaType: md.mediaType || null,
      mediaUrl: md.mediaUrl || null,
      mediaName: md.mediaName || 'Media',
      avatarId: md.avatarId || null,
      stripeSessionId: session.id,
      paymentIntent: session.payment_intent || null,
    }, { merge: true });

    console.log(`✅ Media-Transaktion geschrieben: users/${userId}/transactions/${session.id}`);

    // Zusätzlich: Moment-Dokument anlegen (robust, ohne Storage-Kopie)
    try {
      const momentsCol = admin.firestore().collection('users').doc(userId).collection('moments');
      const momentId = momentsCol.doc().id;
      const nowMs = Date.now();
      const type = (md.mediaType as string | undefined) || 'image';
      await momentsCol.doc(momentId).set({
        id: momentId,
        userId,
        avatarId: (md.avatarId as string | undefined) || '',
        type,
        originalUrl: (md.mediaUrl as string | undefined) || '',
        storedUrl: (md.mediaUrl as string | undefined) || '',
        originalFileName: (md.mediaName as string | undefined) || 'Media',
        acquiredAt: nowMs, // als Zahl, kompatibel zum Client
        price: (amount || 0) / 100.0,
        currency: currency === 'usd' ? '$' : '€',
        receiptId: null,
        tags: [],
      });
      console.log(`✅ Moment erstellt: users/${userId}/moments/${momentId}`);
    } catch (e) {
      console.error('⚠️ Moment anlegen im Webhook fehlgeschlagen:', e);
    }
  } catch (e) {
    console.error('handleMediaPurchaseWebhook error', e);
  }
}

/**
 * Kopiert eine vorhandene Datei im Firebase Storage in den Moments‑Ordner des Nutzers.
 * Vermeidet Client‑Download/CORS‑Probleme.
 */
export const copyMediaToMoments = functions
  .region('us-central1')
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Nicht angemeldet');
    }
    const userId = context.auth.uid;
    const mediaUrl: string = (data?.mediaUrl || '').toString();
    const avatarId: string = (data?.avatarId || '').toString();
    const fileName: string | undefined = (data?.fileName || '').toString() || undefined;
    if (!mediaUrl || !avatarId) {
      throw new functions.https.HttpsError('invalid-argument', 'mediaUrl und avatarId erforderlich');
    }

    // Quelle aus Download-URL extrahieren: nach "/o/" bis '?' und URL‑decoden
    const m = mediaUrl.match(/\/o\/(.*?)\?/);
    if (!m || !m[1]) {
      throw new functions.https.HttpsError('invalid-argument', 'Ungültige mediaUrl');
    }
    const srcPath = decodeURIComponent(m[1]);

    const bucket = admin.storage().bucket();

    const ts = Date.now();
    const baseName = fileName || srcPath.split('/').pop() || `moment_${ts}`;
    const destPath = `users/${userId}/moments/${avatarId}/${ts}_${baseName}`;

    try {
      await bucket.file(srcPath).copy(bucket.file(destPath));
      // Signierte URL für direkten Download erzeugen (30 Tage gültig)
      const [signedUrl] = await bucket.file(destPath).getSignedUrl({
        action: 'read',
        expires: Date.now() + 30 * 24 * 3600 * 1000,
        responseDisposition: `attachment; filename="${baseName}"`,
      } as any);
      return { storagePath: destPath, downloadUrl: signedUrl };
    } catch (e: any) {
      throw new functions.https.HttpsError('internal', e?.message || 'Copy fehlgeschlagen');
    }
  });

