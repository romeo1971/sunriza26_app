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
const functions = __importStar(require("firebase-functions/v1"));
const pdfkit_1 = __importDefault(require("pdfkit"));
const storage_1 = require("@google-cloud/storage");
const storage = new storage_1.Storage();
exports.generateInvoice = functions
    .region('us-central1')
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Nicht angemeldet');
    }
    try {
        const payload = data;
        if (!payload || !payload.invoiceNumber || !payload.userId || !payload.items) {
            throw new functions.https.HttpsError('invalid-argument', 'Ungültige Rechnungsdaten');
        }
        const bucketName = process.env.INVOICE_BUCKET || `${process.env.GCLOUD_PROJECT || 'sunriza26'}.appspot.com`;
        const filePath = `invoices/${payload.userId}/${payload.invoiceNumber}.pdf`;
        const bucket = storage.bucket(bucketName);
        const file = bucket.file(filePath);
        const doc = new pdfkit_1.default({ size: 'A4', margin: 50 });
        const stream = doc.pipe(file.createWriteStream({ contentType: 'application/pdf' }));
        doc.fontSize(18).text('Rechnung', { align: 'right' });
        doc.moveDown();
        doc.fontSize(12).text(`Rechnungsnummer: ${payload.invoiceNumber}`);
        doc.text(`Datum: ${new Date(payload.date).toLocaleDateString('de-DE')}`);
        doc.moveDown();
        doc.text(`Kunde: ${payload.userName}`);
        if (payload.userAddress) {
            doc.text(payload.userAddress.street || '');
            doc.text(`${payload.userAddress.postalCode || ''} ${payload.userAddress.city || ''}`);
            doc.text(payload.userAddress.country || '');
        }
        doc.moveDown();
        doc.text('Positionen:');
        payload.items.forEach((it) => {
            doc.text(`${it.description}  x${it.quantity}  ${it.total.toFixed(2)} ${payload.currency}`);
        });
        doc.moveDown();
        doc.text(`Zwischensumme: ${payload.subtotal.toFixed(2)} ${payload.currency}`);
        doc.text(`Steuer: ${payload.tax.toFixed(2)} ${payload.currency}`);
        doc.text(`Gesamt: ${payload.total.toFixed(2)} ${payload.currency}`, { underline: true });
        doc.end();
        await new Promise((resolve, reject) => {
            stream.on('finish', resolve);
            stream.on('error', reject);
        });
        const [signedUrl] = await file.getSignedUrl({ action: 'read', expires: Date.now() + 1000 * 60 * 60 });
        return { url: signedUrl, path: filePath };
    }
    catch (error) {
        console.error('Invoice Error:', error);
        throw new functions.https.HttpsError('internal', error.message || 'Rechnungsfehler');
    }
});
//# sourceMappingURL=invoiceGenerator.js.map