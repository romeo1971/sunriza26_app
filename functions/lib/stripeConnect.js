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
Object.defineProperty(exports, "__esModule", { value: true });
exports.createSellerDashboardLink = exports.processCreditsPayment = exports.stripeConnectWebhook = exports.createConnectedAccount = void 0;
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
// Stripe nur initialisieren wenn Secret Key vorhanden
const getStripe = () => {
    var _a;
    const secretKey = (process.env.STRIPE_SECRET_KEY || ((_a = functions.config().stripe) === null || _a === void 0 ? void 0 : _a.secret_key) || '').trim();
    if (!secretKey) {
        throw new functions.https.HttpsError('failed-precondition', 'Stripe Secret Key nicht konfiguriert');
    }
    const Stripe = require('stripe');
    return new Stripe(secretKey);
};
/**
 * Erstellt Stripe Connected Account für Verkäufer (Seller Onboarding)
 */
exports.createConnectedAccount = functions
    .region('us-central1')
    .https.onCall(async (data, context) => {
    var _a, _b, _c;
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Nutzer muss angemeldet sein');
    }
    const userId = context.auth.uid;
    const { country, email, businessType } = data || {};
    if (!country || !email) {
        throw new functions.https.HttpsError('invalid-argument', 'Country und Email erforderlich');
    }
    try {
        const stripe = getStripe();
        const userDoc = await admin.firestore().collection('users').doc(userId).get();
        if (!userDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'User nicht gefunden');
        }
        const userData = userDoc.data();
        if (userData.stripeConnectAccountId) {
            const account = await stripe.accounts.retrieve(userData.stripeConnectAccountId);
            if (!account.charges_enabled || !account.payouts_enabled) {
                const appUrl = process.env.APP_URL || ((_a = functions.config().app) === null || _a === void 0 ? void 0 : _a.url) || 'http://localhost:4202';
                const accountLink = await stripe.accountLinks.create({
                    account: userData.stripeConnectAccountId,
                    refresh_url: `${appUrl}/seller/onboarding?refresh=true`,
                    return_url: `${appUrl}/seller/onboarding?success=true`,
                    type: 'account_onboarding',
                });
                return {
                    accountId: userData.stripeConnectAccountId,
                    url: accountLink.url,
                    status: account.charges_enabled && account.payouts_enabled ? 'active' : 'pending',
                };
            }
            return { accountId: userData.stripeConnectAccountId, status: 'active' };
        }
        const account = await stripe.accounts.create({
            type: 'express',
            country: String(country).toUpperCase(),
            email,
            business_type: businessType || 'individual',
            capabilities: { card_payments: { requested: true }, transfers: { requested: true } },
            settings: { payouts: { schedule: { interval: 'monthly', monthly_anchor: 28 } } },
        });
        const appUrl = process.env.APP_URL || ((_b = functions.config().app) === null || _b === void 0 ? void 0 : _b.url) || 'http://localhost:4202';
        const accountLink = await stripe.accountLinks.create({
            account: account.id,
            refresh_url: `${appUrl}/seller/onboarding?refresh=true`,
            return_url: `${appUrl}/seller/onboarding?success=true`,
            type: 'account_onboarding',
        });
        await admin.firestore().collection('users').doc(userId).update({
            isSeller: true,
            stripeConnectAccountId: account.id,
            stripeConnectStatus: 'pending',
            payoutsEnabled: false,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return { accountId: account.id, url: accountLink.url, status: 'pending' };
    }
    catch (error) {
        // Ausführliches Stripe-Fehlerlogging für schnelle Diagnose
        try {
            console.error('Fehler beim Erstellen des Connected Accounts:', {
                message: error === null || error === void 0 ? void 0 : error.message,
                type: error === null || error === void 0 ? void 0 : error.type,
                code: error === null || error === void 0 ? void 0 : error.code,
                param: error === null || error === void 0 ? void 0 : error.param,
                requestId: (error === null || error === void 0 ? void 0 : error.requestId) || ((_c = error === null || error === void 0 ? void 0 : error.raw) === null || _c === void 0 ? void 0 : _c.requestId),
                raw: error === null || error === void 0 ? void 0 : error.raw,
                stack: error === null || error === void 0 ? void 0 : error.stack,
            });
        }
        catch (_) {
            console.error('Fehler beim Erstellen des Connected Accounts (fallback):', error);
        }
        throw new functions.https.HttpsError('internal', error.message);
    }
});
exports.stripeConnectWebhook = functions
    .region('us-central1')
    .https.onRequest(async (req, res) => {
    var _a;
    const sig = req.headers['stripe-signature'];
    // Eigener Secret für CONNECT‑Webhook, damit Checkout und Connect getrennte Secrets nutzen können
    const webhookSecret = (process.env.STRIPE_CONNECT_WEBHOOK_SECRET
        || ((_a = functions.config().stripe) === null || _a === void 0 ? void 0 : _a.connect_webhook_secret)
        || '').trim();
    if (!webhookSecret) {
        res.status(500).send('Webhook Secret nicht konfiguriert');
        return;
    }
    const stripe = getStripe();
    let event;
    try {
        // @ts-ignore rawBody bei v1 vorhanden, in Emulator aufsetzen
        event = stripe.webhooks.constructEvent(req.rawBody || req.raw || req.body, sig, webhookSecret);
    }
    catch (err) {
        res.status(400).send(`Webhook Error: ${err.message}`);
        return;
    }
    try {
        const t = String(event.type || '');
        if (t === 'account.updated' ||
            t.startsWith('v2.core.account.updated') ||
            t.startsWith('v2.core.account[') // includes requirements/configuration.* updates
        ) {
            await handleAccountUpdated(event.data.object);
        }
        else if (t === 'account.application.deauthorized' || t === 'v2.core.account.closed') {
            await handleAccountDeauthorized(event.data.object);
        }
        else {
            // ignore other v2 events like account_person.*
        }
        res.json({ received: true });
    }
    catch (error) {
        res.status(500).send('Webhook Processing Error');
    }
});
/**
 * Account Updated - KYC Status, Payouts etc.
 */
async function handleAccountUpdated(account) {
    var _a;
    const accountId = account.id;
    console.log(`Account Updated: ${accountId}`);
    // User mit diesem Account finden
    const usersSnapshot = await admin
        .firestore()
        .collection('users')
        .where('stripeConnectAccountId', '==', accountId)
        .limit(1)
        .get();
    if (usersSnapshot.empty) {
        console.log(`Kein User mit Account ${accountId} gefunden`);
        return;
    }
    const userDoc = usersSnapshot.docs[0];
    const userId = userDoc.id;
    // Status ermitteln
    let status = 'pending';
    if (account.details_submitted && account.charges_enabled && account.payouts_enabled) {
        status = 'active';
    }
    else if ((_a = account.requirements) === null || _a === void 0 ? void 0 : _a.disabled_reason) {
        status = 'restricted';
    }
    // Firestore aktualisieren
    await admin.firestore().collection('users').doc(userId).update({
        stripeConnectStatus: status,
        payoutsEnabled: account.payouts_enabled || false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`User ${userId} Account Status aktualisiert: ${status}`);
}
/**
 * Account Deauthorized - User hat Zugriff widerrufen
 */
async function handleAccountDeauthorized(account) {
    const accountId = account.id;
    console.log(`Account Deauthorized: ${accountId}`);
    // User mit diesem Account finden
    const usersSnapshot = await admin
        .firestore()
        .collection('users')
        .where('stripeConnectAccountId', '==', accountId)
        .limit(1)
        .get();
    if (usersSnapshot.empty) {
        return;
    }
    const userDoc = usersSnapshot.docs[0];
    const userId = userDoc.id;
    // Account entfernen
    await admin.firestore().collection('users').doc(userId).update({
        isSeller: false,
        stripeConnectAccountId: null,
        stripeConnectStatus: 'disabled',
        payoutsEnabled: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`User ${userId} Account deaktiviert`);
}
exports.processCreditsPayment = functions
    .region('us-central1')
    .https.onCall(async (data, context) => {
    var _a, _b, _c, _d;
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Nicht angemeldet');
    }
    const buyerId = context.auth.uid;
    const { mediaId, credits, sellerId, platformFeePercent } = data || {};
    if (!mediaId || !credits || !sellerId) {
        throw new functions.https.HttpsError('invalid-argument', 'Fehlende Parameter');
    }
    try {
        const stripe = getStripe();
        const salesFeePercent = parseFloat(process.env.SALES_FEE_PERCENT || ((_a = functions.config().platform) === null || _a === void 0 ? void 0 : _a.sales_fee_percent) || '20');
        const feePercent = platformFeePercent || salesFeePercent;
        const amountInCents = credits * 10;
        const platformFee = Math.round(amountInCents * (feePercent / 100));
        const sellerAmount = amountInCents - platformFee;
        const sellerDoc = await admin.firestore().collection('users').doc(sellerId).get();
        if (!sellerDoc.exists || !((_b = sellerDoc.data()) === null || _b === void 0 ? void 0 : _b.stripeConnectAccountId)) {
            throw new functions.https.HttpsError('not-found', 'Verkäufer Account nicht gefunden');
        }
        const sellerAccountId = sellerDoc.data().stripeConnectAccountId;
        const mediaDoc = await admin.firestore().collection('avatars').doc(sellerId).collection('media').doc(mediaId).get();
        const avatarId = mediaDoc.exists ? (_c = mediaDoc.data()) === null || _c === void 0 ? void 0 : _c.avatarId : null;
        const mediaName = mediaDoc.exists ? (_d = mediaDoc.data()) === null || _d === void 0 ? void 0 : _d.originalFileName : null;
        await stripe.transfers.create({ amount: sellerAmount, currency: 'eur', destination: sellerAccountId, metadata: { mediaId, buyerId, sellerId, avatarId } });
        await admin.firestore().collection('users').doc(sellerId).collection('sales').add({
            sellerId, avatarId, mediaId, mediaName, buyerId, credits,
            amount: amountInCents / 100,
            platformFee: platformFee / 100,
            sellerEarnings: sellerAmount / 100,
            status: 'completed',
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await admin.firestore().collection('users').doc(sellerId).update({
            pendingEarnings: admin.firestore.FieldValue.increment(sellerAmount / 100),
            totalEarnings: admin.firestore.FieldValue.increment(sellerAmount / 100),
        });
        return { success: true };
    }
    catch (error) {
        console.error('Credits Payment Error:', error);
        throw new functions.https.HttpsError('internal', error.message);
    }
});
exports.createSellerDashboardLink = functions
    .region('us-central1')
    .https.onCall(async (_data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Nutzer muss angemeldet sein');
    }
    const userId = context.auth.uid;
    try {
        const stripe = getStripe();
        const userDoc = await admin.firestore().collection('users').doc(userId).get();
        if (!userDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'User nicht gefunden');
        }
        const userData = userDoc.data();
        if (!userData.stripeConnectAccountId) {
            throw new functions.https.HttpsError('failed-precondition', 'Kein Connected Account vorhanden');
        }
        const loginLink = await stripe.accounts.createLoginLink(userData.stripeConnectAccountId);
        return { url: loginLink.url };
    }
    catch (error) {
        console.error('Fehler beim Erstellen des Dashboard Links:', error);
        throw new functions.https.HttpsError('internal', error.message);
    }
});
//# sourceMappingURL=stripeConnect.js.map