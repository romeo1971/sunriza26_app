"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.copyMediaToMoments = exports.mediaCheckoutWebhook = exports.createMediaCheckoutSession = void 0;
exports.handleMediaPurchaseWebhook = handleMediaPurchaseWebhook;
const functions = __importStar(require("firebase-functions/v1"));
const stripe_1 = __importDefault(require("stripe"));
const admin = __importStar(require("firebase-admin"));
// Stripe nur initialisieren wenn Secret Key vorhanden
const getStripe = () => {
    var _a;
    const secretKey = (process.env.STRIPE_SECRET_KEY || ((_a = functions.config().stripe) === null || _a === void 0 ? void 0 : _a.secret_key) || '').trim();
    if (!secretKey) {
        throw new functions.https.HttpsError('failed-precondition', 'Stripe Secret Key nicht konfiguriert');
    }
    return new stripe_1.default(secretKey, { apiVersion: '2025-09-30.clover' });
};
/**
 * Cloud Function: Stripe Checkout Session für Media-Kauf
 */
exports.createMediaCheckoutSession = functions
    .region('us-central1')
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Nutzer muss angemeldet sein');
    }
    const { mediaId, avatarId, amount, currency, mediaName, mediaType, mediaUrl } = data || {};
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
            // Success-Seite die postMessage an iframe parent sendet
            success_url: `${process.env.APP_URL || 'http://localhost:4202'}/stripe_success.html?avatarId=${encodeURIComponent(avatarId || '')}&mediaId=${encodeURIComponent(mediaId)}&mediaName=${encodeURIComponent(mediaName || 'Media')}&session_id={CHECKOUT_SESSION_ID}`,
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
    }
    catch (e) {
        throw new functions.https.HttpsError('internal', e.message || 'Stripe Fehler');
    }
});
/**
 * Webhook-Handler für Media-Kauf (optional)
 */
exports.mediaCheckoutWebhook = functions
    .region('us-central1')
    .https.onRequest(async (req, res) => {
    var _a;
    const sig = req.headers['stripe-signature'];
    const webhookSecret = (process.env.STRIPE_WEBHOOK_SECRET || ((_a = functions.config().stripe) === null || _a === void 0 ? void 0 : _a.webhook_secret) || '').trim();
    if (!webhookSecret) {
        res.status(500).send('Webhook Secret nicht konfiguriert');
        return;
    }
    const stripe = getStripe();
    try {
        // @ts-ignore
        stripe.webhooks.constructEvent(req.rawBody || req.body, sig, webhookSecret);
    }
    catch (err) {
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
async function handleMediaPurchaseWebhook(session, admin) {
    try {
        const md = session.metadata || {};
        const userId = md.userId;
        if (!userId) {
            console.error('handleMediaPurchaseWebhook: userId fehlt');
            return;
        }
        const amount = session.amount_total || 0; // cents
        const currency = (session.currency || 'eur').toLowerCase();
        // Rechnungsnummer generieren
        const now = Date.now();
        const invoiceNumber = `20${String(now).slice(-6)}-D${String(now).slice(-5)}`;
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
            invoiceNumber,
        }, { merge: true });
        console.log(`✅ Media-Transaktion geschrieben: users/${userId}/transactions/${session.id}`);
        // Zusätzlich: Moment-Dokument anlegen und Datei in Nutzer‑Ordner kopieren (wenn Firebase-URL)
        try {
            const momentsCol = admin.firestore().collection('users').doc(userId).collection('moments');
            const momentId = momentsCol.doc().id;
            const nowMs = Date.now();
            const type = md.mediaType || 'image';
            let storedUrl = md.mediaUrl || '';
            let originalFileName = md.mediaName || 'Media';
            try {
                const mediaUrl = md.mediaUrl || '';
                const avatarId = md.avatarId || '';
                const m = mediaUrl.match(/\/o\/(.*?)\?/);
                if (m && m[1]) {
                    const srcPath = decodeURIComponent(m[1]);
                    const ts = Date.now();
                    const baseName = originalFileName || srcPath.split('/').pop() || `moment_${ts}`;
                    const destPath = `users/${userId}/moments/${avatarId}/${ts}_${baseName}`;
                    const bucket = admin.storage().bucket();
                    await bucket.file(srcPath).copy(bucket.file(destPath));
                    const [signedUrl] = await bucket.file(destPath).getSignedUrl({
                        action: 'read',
                        expires: Date.now() + 30 * 24 * 3600 * 1000,
                        responseDisposition: `attachment; filename="${baseName}"`,
                    });
                    storedUrl = signedUrl;
                    originalFileName = baseName;
                }
            }
            catch (copyErr) {
                console.error('⚠️ Storage-Kopie im Webhook fehlgeschlagen, verwende Original-URL:', copyErr);
            }
            await momentsCol.doc(momentId).set({
                id: momentId,
                userId,
                avatarId: md.avatarId || '',
                type,
                originalUrl: md.mediaUrl || '',
                storedUrl,
                originalFileName,
                acquiredAt: nowMs, // als Zahl, kompatibel zum Client
                price: (amount || 0) / 100.0,
                currency: currency === 'usd' ? '$' : '€',
                receiptId: null,
                tags: [],
            });
            console.log(`✅ Moment erstellt: users/${userId}/moments/${momentId}`);
        }
        catch (e) {
            console.error('⚠️ Moment anlegen im Webhook fehlgeschlagen:', e);
        }
        // PDF-Rechnung erzeugen
        try {
            const ensureInvoiceFiles = require('./invoicing').ensureInvoiceFiles;
            const result = await ensureInvoiceFiles({ transactionId: String(session.id) }, { auth: { uid: userId } });
            if ((result === null || result === void 0 ? void 0 : result.invoicePdfUrl) || (result === null || result === void 0 ? void 0 : result.invoiceNumber)) {
                await txRef.set({
                    ...(result.invoicePdfUrl && { invoicePdfUrl: result.invoicePdfUrl }),
                    ...(result.invoiceNumber && { invoiceNumber: result.invoiceNumber }),
                }, { merge: true });
                console.log(`✅ PDF-Rechnung erzeugt für ${session.id}`);
            }
        }
        catch (e) {
            console.error('⚠️ PDF-Rechnung fehlgeschlagen:', e);
        }
    }
    catch (e) {
        console.error('handleMediaPurchaseWebhook error', e);
    }
}
/**
 * Kopiert eine vorhandene Datei im Firebase Storage in den Moments‑Ordner des Nutzers.
 * Vermeidet Client‑Download/CORS‑Probleme.
 */
exports.copyMediaToMoments = functions
    .region('us-central1')
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Nicht angemeldet');
    }
    const userId = context.auth.uid;
    const mediaUrl = ((data === null || data === void 0 ? void 0 : data.mediaUrl) || '').toString();
    const avatarId = ((data === null || data === void 0 ? void 0 : data.avatarId) || '').toString();
    const fileName = ((data === null || data === void 0 ? void 0 : data.fileName) || '').toString() || undefined;
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
        });
        return { storagePath: destPath, downloadUrl: signedUrl };
    }
    catch (e) {
        throw new functions.https.HttpsError('internal', (e === null || e === void 0 ? void 0 : e.message) || 'Copy fehlgeschlagen');
    }
});
//# sourceMappingURL=mediaCheckout.js.map