import * as functions from 'firebase-functions/v1';
import PDFDocument from 'pdfkit';
import { Storage } from '@google-cloud/storage';

const storage = new Storage();

interface InvoiceData {
  invoiceNumber: string;
  date: Date;
  userId: string;
  userEmail: string;
  userName: string;
  userAddress?: {
    street?: string;
    city?: string;
    postalCode?: string;
    country?: string;
  };
  items: {
    description: string;
    quantity: number;
    unitPrice: number;
    total: number;
  }[];
  subtotal: number;
  tax: number;
  total: number;
  currency: string;
  paymentMethod: string;
}

export const generateInvoice = functions
  .region('us-central1')
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Nicht angemeldet');
    }
    try {
      const payload = data as InvoiceData;
      if (!payload || !payload.invoiceNumber || !payload.userId || !payload.items) {
        throw new functions.https.HttpsError('invalid-argument', 'Ungültige Rechnungsdaten');
      }

      const bucketName = process.env.INVOICE_BUCKET || `${process.env.GCLOUD_PROJECT || 'sunriza26'}.appspot.com`;
      const filePath = `invoices/${payload.userId}/${payload.invoiceNumber}.pdf`;
      const bucket = storage.bucket(bucketName);
      const file = bucket.file(filePath);

      const doc = new PDFDocument({ size: 'A4', margin: 50 });
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
    } catch (error: any) {
      console.error('Invoice Error:', error);
      throw new functions.https.HttpsError('internal', error.message || 'Rechnungsfehler');
    }
  });

