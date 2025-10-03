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
exports.generateInvoice = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
const pdfkit_1 = __importDefault(require("pdfkit"));
const storage_1 = require("@google-cloud/storage");
const storage = new storage_1.Storage();
/**
 * Generiert eine eRechnung (PDF) für eine Transaktion
 */
exports.generateInvoice = functions
    .region('us-central1')
    .https.onCall(async (data, context) => {
    var _a;
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Nutzer muss angemeldet sein');
    }
    const { transactionId } = data;
    if (!transactionId) {
        throw new functions.https.HttpsError('invalid-argument', 'transactionId fehlt');
    }
    try {
        const userId = context.auth.uid;
        // Transaktion laden
        const transactionDoc = await admin
            .firestore()
            .collection('users')
            .doc(userId)
            .collection('transactions')
            .doc(transactionId)
            .get();
        if (!transactionDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Transaktion nicht gefunden');
        }
        const transaction = transactionDoc.data();
        // User-Daten laden
        const userDoc = await admin.firestore().collection('users').doc(userId).get();
        const userData = userDoc.data();
        // Rechnungsnummer generieren (falls noch nicht vorhanden)
        let invoiceNumber = transaction.invoiceNumber;
        if (!invoiceNumber) {
            invoiceNumber = await generateInvoiceNumber();
        }
        // Invoice-Daten vorbereiten
        const invoiceData = {
            invoiceNumber,
            date: transaction.createdAt.toDate(),
            userId,
            userEmail: userData.email || 'Keine E-Mail',
            userName: userData.displayName || `${userData.firstName} ${userData.lastName}`.trim() || 'Kunde',
            userAddress: {
                street: userData.street,
                city: userData.city,
                postalCode: userData.postalCode,
                country: userData.country,
            },
            items: [
                {
                    description: transaction.type === 'credit_purchase'
                        ? `${transaction.credits} Credits`
                        : transaction.mediaName || 'Media-Kauf',
                    quantity: 1,
                    unitPrice: transaction.amount || 0,
                    total: transaction.amount || 0,
                },
            ],
            subtotal: transaction.amount || 0,
            tax: 0, // TODO: MwSt. berechnen wenn nötig
            total: transaction.amount || 0,
            currency: transaction.currency === 'usd' ? 'USD' : 'EUR',
            paymentMethod: 'Kreditkarte (Stripe)',
        };
        // PDF generieren
        const pdfBuffer = await createInvoicePDF(invoiceData);
        // PDF in Firebase Storage hochladen
        const bucket = storage.bucket((_a = functions.config().firebase) === null || _a === void 0 ? void 0 : _a.storageBucket);
        const fileName = `invoices/${userId}/${invoiceNumber}.pdf`;
        const file = bucket.file(fileName);
        await file.save(pdfBuffer, {
            metadata: {
                contentType: 'application/pdf',
            },
        });
        // Öffentliche URL generieren (7 Tage gültig)
        const [url] = await file.getSignedUrl({
            action: 'read',
            expires: Date.now() + 7 * 24 * 60 * 60 * 1000, // 7 Tage
        });
        // Transaktion mit Rechnungs-Info updaten
        await transactionDoc.ref.update({
            invoiceNumber,
            invoicePdfUrl: url,
        });
        return {
            invoiceNumber,
            pdfUrl: url,
        };
    }
    catch (error) {
        console.error('Invoice Generation Error:', error);
        throw new functions.https.HttpsError('internal', `Fehler: ${error.message}`);
    }
});
/**
 * Generiert eine eindeutige Rechnungsnummer
 */
async function generateInvoiceNumber() {
    const year = new Date().getFullYear();
    const counterDoc = admin
        .firestore()
        .collection('counters')
        .doc('invoiceNumber');
    const newNumber = await admin.firestore().runTransaction(async (transaction) => {
        var _a, _b;
        const doc = await transaction.get(counterDoc);
        let current = 0;
        let lastYear = year;
        if (doc.exists) {
            current = ((_a = doc.data()) === null || _a === void 0 ? void 0 : _a.current) || 0;
            lastYear = ((_b = doc.data()) === null || _b === void 0 ? void 0 : _b.year) || year;
        }
        // Reset counter bei neuem Jahr
        if (lastYear !== year) {
            current = 0;
        }
        const next = current + 1;
        transaction.set(counterDoc, { current: next, year });
        return next;
    });
    // Format: INV-2025-00001
    return `INV-${year}-${newNumber.toString().padStart(5, '0')}`;
}
/**
 * Erstellt PDF-Rechnung mit pdfkit
 */
async function createInvoicePDF(data) {
    return new Promise((resolve, reject) => {
        var _a;
        const doc = new pdfkit_1.default({ size: 'A4', margin: 50 });
        const buffers = [];
        doc.on('data', (buffer) => buffers.push(buffer));
        doc.on('end', () => resolve(Buffer.concat(buffers)));
        doc.on('error', reject);
        // Header
        doc
            .fontSize(20)
            .text('Sunriza GmbH', 50, 50)
            .fontSize(10)
            .text('Musterstraße 123', 50, 75)
            .text('12345 Berlin, Deutschland', 50, 90)
            .text('info@sunriza.com', 50, 105);
        // Rechnungsnummer & Datum
        doc
            .fontSize(10)
            .text(`Rechnung Nr: ${data.invoiceNumber}`, 400, 50, { align: 'right' })
            .text(`Datum: ${formatDate(data.date)}`, 400, 65, { align: 'right' });
        // Kunde
        doc.fontSize(12).text('Rechnung an:', 50, 150);
        doc
            .fontSize(10)
            .text(data.userName, 50, 170)
            .text(data.userEmail, 50, 185);
        if ((_a = data.userAddress) === null || _a === void 0 ? void 0 : _a.street) {
            let y = 200;
            doc.text(data.userAddress.street, 50, y);
            y += 15;
            if (data.userAddress.postalCode && data.userAddress.city) {
                doc.text(`${data.userAddress.postalCode} ${data.userAddress.city}`, 50, y);
                y += 15;
            }
            if (data.userAddress.country) {
                doc.text(data.userAddress.country, 50, y);
            }
        }
        // Tabelle
        const tableTop = 280;
        doc
            .fontSize(10)
            .font('Helvetica-Bold')
            .text('Beschreibung', 50, tableTop)
            .text('Menge', 300, tableTop)
            .text('Preis', 380, tableTop)
            .text('Gesamt', 480, tableTop)
            .font('Helvetica');
        doc
            .moveTo(50, tableTop + 15)
            .lineTo(550, tableTop + 15)
            .stroke();
        let y = tableTop + 25;
        data.items.forEach((item) => {
            doc
                .fontSize(10)
                .text(item.description, 50, y)
                .text(item.quantity.toString(), 300, y)
                .text(formatCurrency(item.unitPrice, data.currency), 380, y)
                .text(formatCurrency(item.total, data.currency), 480, y);
            y += 20;
        });
        // Summen
        y += 20;
        doc
            .moveTo(380, y)
            .lineTo(550, y)
            .stroke();
        y += 10;
        doc
            .fontSize(10)
            .text('Zwischensumme:', 380, y)
            .text(formatCurrency(data.subtotal, data.currency), 480, y);
        if (data.tax > 0) {
            y += 20;
            doc
                .text('MwSt.:', 380, y)
                .text(formatCurrency(data.tax, data.currency), 480, y);
        }
        y += 20;
        doc
            .fontSize(12)
            .font('Helvetica-Bold')
            .text('Gesamt:', 380, y)
            .text(formatCurrency(data.total, data.currency), 480, y)
            .font('Helvetica');
        // Footer
        doc
            .fontSize(9)
            .text('Zahlungsmethode: ' + data.paymentMethod, 50, 700)
            .text('Vielen Dank für Ihren Kauf!', 50, 720);
        doc.end();
    });
}
function formatDate(date) {
    return new Intl.DateTimeFormat('de-DE').format(date);
}
function formatCurrency(amount, currency) {
    return new Intl.NumberFormat('de-DE', {
        style: 'currency',
        currency: currency,
    }).format(amount);
}
//# sourceMappingURL=invoiceGenerator.js.map