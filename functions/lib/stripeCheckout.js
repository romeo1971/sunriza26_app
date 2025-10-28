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
exports.stripeWebhook = exports.createCreditsCheckoutSession = void 0;
const https_1 = require("firebase-functions/v2/https");
const stripe_1 = __importDefault(require("stripe"));
const admin = __importStar(require("firebase-admin"));
// Stripe nur initialisieren wenn Secret Key vorhanden (env)
const getStripe = () => {
    const secretKey = process.env.STRIPE_SECRET_KEY || '';
    if (!secretKey) {
        throw new https_1.HttpsError('failed-precondition', 'Stripe Secret Key nicht konfiguriert');
    }
    return new stripe_1.default(secretKey, { apiVersion: '2025-09-30.clover' });
};
exports.createCreditsCheckoutSession = (0, https_1.onCall)({ region: 'us-central1' }, async (req) => {
    const auth = req.auth;
    const data = req.data || {};
    if (!auth)
        throw new https_1.HttpsError('unauthenticated', 'Nutzer muss angemeldet sein');
    const userId = auth.uid;
    const { euroAmount, amount, currency, exchangeRate, credits } = data;
    if (!amount || !currency || !credits || !euroAmount) {
        throw new https_1.HttpsError('invalid-argument', 'Fehlende Parameter: amount, currency, credits, euroAmount erforderlich');
    }
    if (currency !== 'eur' && currency !== 'usd') {
        throw new https_1.HttpsError('invalid-argument', 'Währung muss eur oder usd sein');
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
    }
    catch (error) {
        if (error.type === 'StripeAuthenticationError')
            throw new https_1.HttpsError('failed-precondition', 'Stripe API Key ungültig oder nicht konfiguriert');
        throw new https_1.HttpsError('internal', `Stripe Error: ${error.message || 'Unbekannter Fehler'}`);
    }
});
exports.stripeWebhook = (0, https_1.onRequest)({ region: 'us-central1' }, async (req, res) => {
    const sig = req.headers['stripe-signature'];
    const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET || '';
    if (!webhookSecret) {
        res.status(500).send('Webhook Secret nicht konfiguriert');
        return;
    }
    const stripe = getStripe();
    let event;
    try {
        // @ts-ignore
        event = stripe.webhooks.constructEvent(req.rawBody || req.body, sig, webhookSecret);
    }
    catch (err) {
        res.status(400).send(`Webhook Error: ${err.message}`);
        return;
    }
    if (event.type === 'checkout.session.completed') {
        const session = event.data.object;
        const md = session.metadata || {};
        if (md.type === 'media_purchase') {
            try {
                const path = './mediaCheckout';
                const mod = await Promise.resolve(`${path}`).then(s => __importStar(require(s)));
                if (mod && typeof mod.handleMediaPurchaseWebhook === 'function') {
                    await mod.handleMediaPurchaseWebhook(session, admin);
                }
            }
            catch (_) { }
            res.json({ received: true });
            return;
        }
        const { userId, credits, euroAmount, exchangeRate } = md;
        if (!userId || !credits) {
            res.status(400).send('Fehlende Metadata');
            return;
        }
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
        }
        catch (e) {
            res.status(500).send('Interner Fehler');
            return;
        }
    }
    res.json({ received: true });
});
//# sourceMappingURL=stripeCheckout.js.map