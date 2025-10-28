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
exports.mediaCheckoutWebhook = exports.createMediaCheckoutSession = void 0;
const functions = __importStar(require("firebase-functions/v1"));
const stripe_1 = __importDefault(require("stripe"));
// Stripe nur initialisieren wenn Secret Key vorhanden
const getStripe = () => {
    var _a;
    const secretKey = process.env.STRIPE_SECRET_KEY || ((_a = functions.config().stripe) === null || _a === void 0 ? void 0 : _a.secret_key) || '';
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
    const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET || ((_a = functions.config().stripe) === null || _a === void 0 ? void 0 : _a.webhook_secret) || '';
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
//# sourceMappingURL=mediaCheckout.js.map