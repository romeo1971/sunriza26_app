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
exports.createPaymentIntentWithCard = exports.setDefaultPaymentMethod = exports.deletePaymentMethod = exports.getPaymentMethods = exports.createSetupIntent = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
/**
 * Payment Methods Management
 * - Karten speichern (Setup Intent)
 * - Karten abrufen
 * - Karten löschen
 * - Standard-Karte setzen
 */
// Stripe initialisieren (conditional)
function getStripe() {
    var _a;
    const secretKey = ((_a = functions.config().stripe) === null || _a === void 0 ? void 0 : _a.secret_key) || process.env.STRIPE_SECRET_KEY;
    if (!secretKey) {
        throw new functions.https.HttpsError('failed-precondition', 'Stripe Secret Key nicht konfiguriert');
    }
    const stripe = require('stripe')(secretKey, { apiVersion: '2025-09-30.clover' });
    return stripe;
}
/**
 * Stripe Customer ID holen oder erstellen
 */
async function getOrCreateCustomer(userId) {
    const stripe = getStripe();
    // UserProfile laden
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    if (!userDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'User nicht gefunden');
    }
    const userData = userDoc.data();
    // Bereits vorhanden?
    if (userData.stripeCustomerId) {
        return userData.stripeCustomerId;
    }
    // Neu erstellen
    const customer = await stripe.customers.create({
        metadata: { userId },
    });
    // In Firestore speichern
    await admin.firestore().collection('users').doc(userId).update({
        stripeCustomerId: customer.id,
    });
    return customer.id;
}
/**
 * Setup Intent erstellen (Karte hinzufügen)
 */
exports.createSetupIntent = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Nicht angemeldet');
    }
    try {
        const stripe = getStripe();
        const userId = context.auth.uid;
        const customerId = await getOrCreateCustomer(userId);
        // Setup Intent erstellen
        const setupIntent = await stripe.setupIntents.create({
            customer: customerId,
            payment_method_types: ['card'],
        });
        return {
            clientSecret: setupIntent.client_secret,
            customerId,
        };
    }
    catch (error) {
        console.error('Setup Intent Error:', error);
        throw new functions.https.HttpsError('internal', error.message);
    }
});
/**
 * Gespeicherte Zahlungsmethoden abrufen
 */
exports.getPaymentMethods = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Nicht angemeldet');
    }
    try {
        const stripe = getStripe();
        const userId = context.auth.uid;
        // UserProfile laden
        const userDoc = await admin.firestore().collection('users').doc(userId).get();
        if (!userDoc.exists) {
            return { paymentMethods: [] };
        }
        const customerId = userDoc.data().stripeCustomerId;
        if (!customerId) {
            return { paymentMethods: [] };
        }
        // Zahlungsmethoden von Stripe laden
        const paymentMethods = await stripe.paymentMethods.list({
            customer: customerId,
            type: 'card',
        });
        // Customer laden um default zu erkennen
        const customer = await stripe.customers.retrieve(customerId);
        return {
            paymentMethods: paymentMethods.data.map((pm) => {
                var _a;
                return ({
                    id: pm.id,
                    brand: pm.card.brand,
                    last4: pm.card.last4,
                    expMonth: pm.card.exp_month,
                    expYear: pm.card.exp_year,
                    isDefault: pm.id === ((_a = customer.invoice_settings) === null || _a === void 0 ? void 0 : _a.default_payment_method),
                });
            }),
        };
    }
    catch (error) {
        console.error('Get Payment Methods Error:', error);
        throw new functions.https.HttpsError('internal', error.message);
    }
});
/**
 * Zahlungsmethode löschen
 */
exports.deletePaymentMethod = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Nicht angemeldet');
    }
    const { paymentMethodId } = data;
    if (!paymentMethodId) {
        throw new functions.https.HttpsError('invalid-argument', 'paymentMethodId fehlt');
    }
    try {
        const stripe = getStripe();
        await stripe.paymentMethods.detach(paymentMethodId);
        return { success: true };
    }
    catch (error) {
        console.error('Delete Payment Method Error:', error);
        throw new functions.https.HttpsError('internal', error.message);
    }
});
/**
 * Standard-Zahlungsmethode setzen
 */
exports.setDefaultPaymentMethod = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Nicht angemeldet');
    }
    const { paymentMethodId } = data;
    if (!paymentMethodId) {
        throw new functions.https.HttpsError('invalid-argument', 'paymentMethodId fehlt');
    }
    try {
        const stripe = getStripe();
        const userId = context.auth.uid;
        // UserProfile laden
        const userDoc = await admin.firestore().collection('users').doc(userId).get();
        if (!userDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'User nicht gefunden');
        }
        const customerId = userDoc.data().stripeCustomerId;
        if (!customerId) {
            throw new functions.https.HttpsError('failed-precondition', 'Kein Stripe Customer');
        }
        // Standard setzen
        await stripe.customers.update(customerId, {
            invoice_settings: {
                default_payment_method: paymentMethodId,
            },
        });
        return { success: true };
    }
    catch (error) {
        console.error('Set Default Payment Method Error:', error);
        throw new functions.https.HttpsError('internal', error.message);
    }
});
/**
 * Payment Intent mit gespeicherter Karte erstellen
 * Für: Credits kaufen, Media kaufen (≥2€)
 */
exports.createPaymentIntentWithCard = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Nicht angemeldet');
    }
    const { amount, currency, paymentMethodId, metadata } = data;
    if (!amount || !currency) {
        throw new functions.https.HttpsError('invalid-argument', 'amount und currency erforderlich');
    }
    try {
        const stripe = getStripe();
        const userId = context.auth.uid;
        // UserProfile laden
        const userDoc = await admin.firestore().collection('users').doc(userId).get();
        if (!userDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'User nicht gefunden');
        }
        const customerId = userDoc.data().stripeCustomerId;
        if (!customerId) {
            throw new functions.https.HttpsError('failed-precondition', 'Kein Stripe Customer');
        }
        // Payment Intent erstellen
        const paymentIntent = await stripe.paymentIntents.create({
            amount, // in Cents
            currency: currency.toLowerCase(),
            customer: customerId,
            payment_method: paymentMethodId || undefined,
            confirm: paymentMethodId ? true : false, // Auto-confirm wenn Karte angegeben
            automatic_payment_methods: paymentMethodId ? undefined : { enabled: true },
            metadata: {
                userId,
                ...metadata,
            },
        });
        // Bei erfolgreicher Zahlung: Webhook verarbeitet den Rest
        return {
            clientSecret: paymentIntent.client_secret,
            status: paymentIntent.status,
            paymentIntentId: paymentIntent.id,
        };
    }
    catch (error) {
        console.error('Create Payment Intent Error:', error);
        throw new functions.https.HttpsError('internal', error.message);
    }
});
//# sourceMappingURL=paymentMethods.js.map