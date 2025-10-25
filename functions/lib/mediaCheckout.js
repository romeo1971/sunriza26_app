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
exports.createMediaCheckoutSession = void 0;
exports.handleMediaPurchaseWebhook = handleMediaPurchaseWebhook;
const functions = __importStar(require("firebase-functions"));
const stripe_1 = __importDefault(require("stripe"));
// Stripe nur initialisieren wenn Secret Key vorhanden
const getStripe = () => {
    var _a;
    const secretKey = ((_a = functions.config().stripe) === null || _a === void 0 ? void 0 : _a.secret_key) || process.env.STRIPE_SECRET_KEY || '';
    if (!secretKey) {
        throw new functions.https.HttpsError('failed-precondition', 'Stripe Secret Key nicht konfiguriert');
    }
    return new stripe_1.default(secretKey, {
        apiVersion: '2025-09-30.clover',
    });
};
/**
 * Cloud Function: Stripe Checkout Session für Media-Kauf
 */
exports.createMediaCheckoutSession = functions
    .region('us-central1')
    .https.onCall(async (data, context) => {
    var _a;
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Nutzer muss angemeldet sein');
    }
    const { mediaId, avatarId, amount, currency, mediaName, mediaType, } = data;
    if (!mediaId || !amount || !currency) {
        throw new functions.https.HttpsError('invalid-argument', 'Fehlende Parameter');
    }
    // Preis-Check: Mindestens 2€
    const minAmount = currency === 'eur' ? 200 : 220; // 2€ bzw. 2.20$
    if (amount < minAmount) {
        throw new functions.https.HttpsError('invalid-argument', 'Zahlungen unter 2€ nur mit Credits möglich');
    }
    try {
        const userId = context.auth.uid;
        const appUrl = ((_a = functions.config().app) === null || _a === void 0 ? void 0 : _a.url) || 'http://localhost:4202';
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
    }
    catch (error) {
        console.error('Stripe Checkout Error:', error);
        throw new functions.https.HttpsError('internal', error.message);
    }
});
/**
 * Webhook: Media-Kauf abschließen nach erfolgreicher Zahlung
 * (wird vom stripeWebhook in stripeCheckout.ts aufgerufen)
 */
async function handleMediaPurchaseWebhook(session, admin) {
    const metadata = session.metadata;
    if (!metadata || metadata.type !== 'media_purchase')
        return;
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
        const firestore = admin.firestore();
        const storage = admin.storage();
        // 1. Lade Media Asset Details
        const mediaDoc = await firestore
            .collection('avatars')
            .doc(avatarId)
            .collection('media')
            .doc(mediaId)
            .get();
        if (!mediaDoc.exists) {
            console.error(`Media ${mediaId} nicht gefunden`);
            return;
        }
        const mediaData = mediaDoc.data();
        const originalUrl = mediaData.url;
        const originalFileName = mediaData.originalFileName || 'media';
        const thumbUrl = mediaData.thumbUrl;
        // 2. Kopiere Original-Datei in user/moments Storage
        const timestamp = Date.now();
        const fileExt = getFileExtension(originalUrl) || getExtForType(mediaType);
        const storagePath = `users/${userId}/moments/${avatarId}/${timestamp}${fileExt}`;
        // Download und Re-Upload (Firebase Storage)
        const bucket = storage.bucket();
        const sourceFile = bucket.file(getStoragePathFromUrl(originalUrl));
        const destFile = bucket.file(storagePath);
        await sourceFile.copy(destFile);
        // Get Download URL
        const [storedUrl] = await destFile.getSignedUrl({
            action: 'read',
            expires: '01-01-2100', // Permanent
        });
        // 3. Optional: Copy Thumbnail
        let storedThumbUrl = null;
        if (thumbUrl) {
            try {
                const thumbStoragePath = `users/${userId}/moments/${avatarId}/${timestamp}_thumb.jpg`;
                const sourceThumb = bucket.file(getStoragePathFromUrl(thumbUrl));
                const destThumb = bucket.file(thumbStoragePath);
                await sourceThumb.copy(destThumb);
                [storedThumbUrl] = await destThumb.getSignedUrl({
                    action: 'read',
                    expires: '01-01-2100',
                });
            }
            catch (error) {
                console.warn('Thumbnail copy failed:', error.message);
            }
        }
        // 4. Create Moment
        const momentId = firestore.collection('users').doc(userId).collection('moments').doc().id;
        const price = session.amount_total ? session.amount_total / 100 : 0;
        const currency = session.currency === 'usd' ? '$' : '€';
        await userRef.collection('moments').doc(momentId).set({
            id: momentId,
            userId,
            avatarId,
            type: mediaType,
            originalUrl,
            storedUrl,
            thumbUrl: storedThumbUrl,
            originalFileName,
            acquiredAt: timestamp,
            price,
            currency,
            receiptId: null, // Wird gleich gesetzt
        });
        // 5. Create Receipt
        const receiptId = firestore.collection('users').doc(userId).collection('receipts').doc().id;
        await userRef.collection('receipts').doc(receiptId).set({
            id: receiptId,
            userId,
            avatarId,
            momentId,
            price,
            currency,
            paymentMethod: 'stripe',
            createdAt: timestamp,
            stripePaymentIntentId: String(session.payment_intent || ''),
            metadata: {
                mediaId,
                mediaType,
                stripeSessionId: session.id,
            },
        });
        // Update Moment with Receipt ID
        await userRef.collection('moments').doc(momentId).update({
            receiptId,
        });
        // 6. Transaktion anlegen
        await userRef.collection('transactions').add({
            userId,
            type: 'media_purchase',
            mediaId,
            avatarId,
            mediaType,
            amount: price,
            currency: session.currency || 'eur',
            stripeSessionId: session.id,
            paymentIntent: session.payment_intent,
            status: 'completed',
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        // 7. Media als gekauft markieren
        await userRef.collection('purchased_media').doc(mediaId).set({
            mediaId,
            avatarId,
            type: mediaType,
            price,
            currency,
            purchasedAt: timestamp,
        });
        console.log(`✅ Media-Kauf erfolgreich: User ${userId} - Media ${mediaId} → Moment ${momentId}`);
    }
    catch (error) {
        console.error('❌ Fehler beim Media-Kauf verarbeiten:', error);
    }
}
/**
 * Helper: Extrahiere Storage-Pfad aus Firebase Download URL
 */
function getStoragePathFromUrl(url) {
    try {
        // Firebase Storage URL Format: /v0/b/{bucket}/o/{path}
        const pathMatch = url.match(/\/o\/([^?]+)/);
        if (pathMatch) {
            return decodeURIComponent(pathMatch[1]);
        }
    }
    catch (e) {
        console.warn('Failed to parse storage URL:', url);
    }
    return url;
}
/**
 * Helper: Dateiendung aus URL extrahieren
 */
function getFileExtension(url) {
    try {
        const urlObj = new URL(url);
        const pathname = urlObj.pathname;
        const match = pathname.match(/\.([a-zA-Z0-9]+)(\?|$)/);
        return match ? `.${match[1]}` : null;
    }
    catch (e) {
        return null;
    }
}
/**
 * Helper: Default Extension für Media Type
 */
function getExtForType(type) {
    switch (type) {
        case 'image': return '.jpg';
        case 'video': return '.mp4';
        case 'audio': return '.mp3';
        case 'document': return '.pdf';
        default: return '';
    }
}
//# sourceMappingURL=mediaCheckout.js.map