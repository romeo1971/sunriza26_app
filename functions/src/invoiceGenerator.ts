import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
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

/**
 * Generiert eine eRechnung (PDF) für eine Transaktion
 */
export const generateInvoice = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Nutzer muss angemeldet sein',
      );
    }

    const { transactionId } = data;
    if (!transactionId) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'transactionId fehlt',
      );
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
        throw new functions.https.HttpsError(
          'not-found',
          'Transaktion nicht gefunden',
        );
      }

      const transaction = transactionDoc.data()!;

      // User-Daten laden
      const userDoc = await admin.firestore().collection('users').doc(userId).get();
      const userData = userDoc.data()!;

      // Rechnungsnummer generieren (falls noch nicht vorhanden)
      let invoiceNumber = transaction.invoiceNumber;
      if (!invoiceNumber) {
        invoiceNumber = await generateInvoiceNumber();
      }

      // Invoice-Daten vorbereiten
      const invoiceData: InvoiceData = {
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
            description:
              transaction.type === 'credit_purchase'
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
      const bucket = storage.bucket(functions.config().firebase?.storageBucket);
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
    } catch (error: any) {
      console.error('Invoice Generation Error:', error);
      throw new functions.https.HttpsError(
        'internal',
        `Fehler: ${error.message}`,
      );
    }
  });

/**
 * Generiert eine eindeutige Rechnungsnummer
 */
async function generateInvoiceNumber(): Promise<string> {
  const year = new Date().getFullYear();
  const counterDoc = admin
    .firestore()
    .collection('counters')
    .doc('invoiceNumber');

  const newNumber = await admin.firestore().runTransaction(async (transaction) => {
    const doc = await transaction.get(counterDoc);
    let current = 0;
    let lastYear = year;

    if (doc.exists) {
      current = doc.data()?.current || 0;
      lastYear = doc.data()?.year || year;
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
async function createInvoicePDF(data: InvoiceData): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'A4', margin: 50 });
    const buffers: Buffer[] = [];

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

    if (data.userAddress?.street) {
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

function formatDate(date: Date): string {
  return new Intl.DateTimeFormat('de-DE').format(date);
}

function formatCurrency(amount: number, currency: string): string {
  return new Intl.NumberFormat('de-DE', {
    style: 'currency',
    currency: currency,
  }).format(amount);
}

