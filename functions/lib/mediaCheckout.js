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
    }
    catch (error) {
        console.error('Fehler beim Media-Kauf verarbeiten:', error);
    }
}
//# sourceMappingURL=mediaCheckout.js.map