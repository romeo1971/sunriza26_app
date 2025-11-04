import * as functions from 'firebase-functions/v1';
import PDFDocument from 'pdfkit';
import * as admin from 'firebase-admin';

// OTS entfernt – keine Service-URL nötig

function generateInvoiceNumber(): string {
  const now = new Date();
  const y = now.getUTCFullYear();
  const m = String(now.getUTCMonth() + 1).padStart(2, '0');
  const d = String(now.getUTCDate()).padStart(2, '0');
  const rand = Math.random().toString(16).slice(2, 8).toUpperCase();
  return `${y}${m}${d}-${rand}`;
}

function getCompanyImprint() {
  return {
    name: (process.env.INVOICE_COMPANY_NAME || 'Hauau UG (haftungsbeschränkt)').trim(),
    street: (process.env.INVOICE_COMPANY_STREET || 'Musterstraße 1').trim(),
    postalCode: (process.env.INVOICE_COMPANY_POSTAL || '12345').trim(),
    city: (process.env.INVOICE_COMPANY_CITY || 'Musterstadt').trim(),
    country: (process.env.INVOICE_COMPANY_COUNTRY || 'DE').trim(),
    vatId: (process.env.INVOICE_COMPANY_VATID || 'DE123456789').trim(),
  } as { name: string; street?: string; postalCode?: string; city?: string; country?: string; vatId?: string };
}



async function tryDownloadBufferFromStorage(storagePath: string): Promise<Buffer | null> {
  try {
    const bucket = admin.storage().bucket();
    const f = bucket.file(storagePath);
    const [exists] = await f.exists();
    if (!exists) return null;
    const [buf] = await f.download();
    return Buffer.from(buf);
  } catch {
    return null;
  }
}

async function getLogoBuffer(): Promise<Buffer | null> {
  const pathFromEnv = (process.env.INVOICE_LOGO_GS_PATH || '').trim();
  if (pathFromEnv) {
    const b = await tryDownloadBufferFromStorage(pathFromEnv);
    if (b) return b;
  }
  // Fallback: Branding-Standardpfad im Default-Bucket
  return await tryDownloadBufferFromStorage('branding/hauau_logo.png');
}

async function getMediaThumbBuffer(tx: any): Promise<Buffer | null> {
  try {
    const avatarId: string | undefined = tx.avatarId;
    const mediaId: string | undefined = tx.mediaId;
    const mediaType: string | undefined = tx.mediaType;
    if (!avatarId || !mediaId || !mediaType) return null;
    const bucket = admin.storage().bucket();
    let prefix: string | null = null;
    if (mediaType === 'image') prefix = `avatars/${avatarId}/images/thumbs/${mediaId}_`;
    else if (mediaType === 'video') prefix = `avatars/${avatarId}/videos/thumbs/${mediaId}`;
    else if (mediaType === 'audio') prefix = `avatars/${avatarId}/audio/thumbs/${mediaId}`; // png
    if (!prefix) return null;
    const [files] = await bucket.getFiles({ prefix });
    if (!files || files.length === 0) return null;
    // wähle die aktuellste Datei
    let latest = files[0];
    for (const f of files) {
      const a = new Date((latest.metadata as any)?.updated || (latest.metadata as any)?.timeCreated || 0).getTime();
      const b = new Date((f.metadata as any)?.updated || (f.metadata as any)?.timeCreated || 0).getTime();
      if (b > a) latest = f;
    }
    const [buf] = await latest.download();
    return Buffer.from(buf);
  } catch {
    return null;
  }
}

// OTS entfernt

// Zentrales Rendering für ein konsistentes, schönes PDF-Layout
async function renderStyledInvoice(doc: any, args: {
  invoiceNumber: string;
  date: Date;
  seller: { name: string; street?: string; postalCode?: string; city?: string; country?: string; vatId?: string };
  buyer: { name: string; email?: string };
  items: Array<{ description: string; quantity: number; unitPrice: number; total: number }>;
  currency: string;
  mediaThumb?: Buffer | null;
  rbr?: string | null;
}) {
  const left = 50;
  const right = 545;

  // Headerband
  doc.save();
  const grad = doc.linearGradient(left, 110, right, 40); // bottom-left -> top-right
  grad.stop(0, '#6B7280'); // deutlich dunkler unten (HOWAREU gut lesbar)
  grad.stop(1, '#F7F7F9'); // sehr hell oben
  doc.rect(left, 40, right - left, 70).fill(grad);
  doc.fillColor('#000');
  try {
    const logo = await getLogoBuffer();
    if (logo) doc.image(logo, left + 10, 50, { fit: [150, 50] });
  } catch {}
  doc.font('Helvetica-Bold').fontSize(20).text('Rechnung', left, 60, { width: (right - left) - 20, align: 'right' });
  doc.restore();

  // Infozeile (Rechnungsnr./Datum) rechts, Seller links
  const infoY = 130;
  doc.font('Helvetica').fontSize(11);
  doc.text('Verkäufer', left, infoY, { continued: false });
  doc.font('Helvetica-Bold').text(args.seller.name);
  doc.font('Helvetica');
  if (args.seller.street) doc.text(args.seller.street);
  const cityLine = `${args.seller.postalCode || ''} ${args.seller.city || ''}`.trim();
  if (cityLine) doc.text(cityLine);
  if (args.seller.country) doc.text(args.seller.country);
  if (args.seller.vatId) doc.text(`USt-IdNr.: ${args.seller.vatId}`);

  doc.font('Helvetica').fontSize(11);
  const rightColX = 360;
  doc.text(`Rechnungsnummer: ${args.invoiceNumber}`, rightColX, infoY);
  if (args.rbr && args.rbr.length > 0) {
    doc.text(`RBR: ${args.rbr}`);
  }
  doc.text(`Datum: ${args.date.toLocaleDateString('de-DE')}`);

  // Buyer Block
  const buyerY = 210;
  doc.font('Helvetica').text('Kunde', left, buyerY);
  doc.font('Helvetica-Bold').text(args.buyer.name);
  doc.font('Helvetica');
  if (args.buyer.email) doc.text(args.buyer.email);

  // Optionales Media-Thumb rechts
  if (args.mediaThumb) {
    try {
      doc.image(args.mediaThumb, rightColX, buyerY - 10, { fit: [170, 120] });
    } catch {}
  }

  // Tabellen-Header
  const tableY = 280;
  doc.save();
  doc.rect(left, tableY, right - left, 24).fill('#EEF0F4');
  doc.fillColor('#000').font('Helvetica-Bold').fontSize(11);
  // Spaltengeometrie so, dass Beträge rechts bündig bei numericRight enden
  const gap = 20; // weiter nach links schieben
  const numericRight = right - 10; // 535
  const totalW = 90;
  const totalX = numericRight - totalW; // 445
  const unitW = 85;
  const unitRight = totalX - gap; // 435
  const unitX = unitRight - unitW; // 350
  const qtyW = 50;
  const qtyRight = unitX - gap; // 340
  const qtyX = qtyRight - qtyW; // 290
  const descX = left + 10; // 60
  const descW = qtyX - descX - gap; // Platz bis Menge

  doc.text('Beschreibung', descX, tableY + 6, { width: descW, align: 'left' });
  doc.text('Menge', qtyX, tableY + 6, { width: qtyW, align: 'left' });
  doc.text('Einzelpreis', unitX, tableY + 6, { width: unitW, align: 'left' });
  // Header "Gesamt" näher an die Werte: rechtsbündig an numericRight
  doc.text('Gesamt', totalX, tableY + 6, { width: totalW, align: 'right' });
  doc.restore();

  // Tabellenzeilen
  let rowY = tableY + 30;
  doc.font('Helvetica').fontSize(11);
  for (const it of args.items) {
    doc.text(it.description, descX, rowY, { width: descW });
    doc.text(String(it.quantity), qtyX, rowY, { width: qtyW, align: 'left' });
    // Einzelpreis linksbündig
    doc.text(`${it.unitPrice.toFixed(2)} ${args.currency.toUpperCase()}`, unitX, rowY, { width: unitW, align: 'left' });
    doc.text(`${it.total.toFixed(2)} ${args.currency.toUpperCase()}`, totalX, rowY, { width: totalW, align: 'right' });
    rowY += 20;
    doc.moveTo(left, rowY + 2).lineTo(right, rowY + 2).lineWidth(0.5).opacity(0.08).stroke().opacity(1);
  }

  // Totals Box rechts
  const totalsY = rowY + 20;
  // Box so platzieren, dass linke Kante mit "Einzelpreis" (unitX) bündig ist
  const boxX = unitX - 12; // kleine Innenabstände
  const boxWidth = (numericRight - boxX) + 6;
  doc.save();
  doc.roundedRect(boxX, totalsY, boxWidth - 6, 86, 6).fill('#F8F9FB');
  doc.fillColor('#000').font('Helvetica').fontSize(11);
  const subtotal = args.items.reduce((a, b) => a + b.total, 0);
  const vatRate = (args.seller.country || '').toUpperCase() === 'DE' ? 0.19 : 0.0;
  const vatLabel = vatRate > 0 ? `MwSt (${(vatRate * 100).toFixed(0)}%)` : 'MwSt';
  const vatAmount = +(subtotal * vatRate).toFixed(2);
  const grandTotal = +(subtotal + vatAmount).toFixed(2);
  const labelLeft = unitX; // exakt linksbündig mit "Einzelpreis"
  const valueWidth = numericRight - labelLeft;
  doc.text('Zwischensumme', labelLeft, totalsY + 10);
  doc.text(`${subtotal.toFixed(2)} ${args.currency.toUpperCase()}`, labelLeft, totalsY + 10, { width: valueWidth, align: 'right' });
  doc.text(vatLabel, labelLeft, totalsY + 30);
  doc.text(`${vatAmount.toFixed(2)} ${args.currency.toUpperCase()}`, labelLeft, totalsY + 30, { width: valueWidth, align: 'right' });
  doc.font('Helvetica-Bold');
  doc.text('Gesamt', labelLeft, totalsY + 52);
  doc.text(`${grandTotal.toFixed(2)} ${args.currency.toUpperCase()}`, labelLeft, totalsY + 52, { width: valueWidth, align: 'right' });
  doc.restore();
}

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

      const bucket = admin.storage().bucket();
      const filePath = `invoices/${payload.userId}/${payload.invoiceNumber}.pdf`;
      const file = bucket.file(filePath);

      const doc = new PDFDocument({ size: 'A4', margin: 50 });
      const stream = doc.pipe(file.createWriteStream({ contentType: 'application/pdf' }));

      await renderStyledInvoice(doc, {
        invoiceNumber: payload.invoiceNumber,
        date: new Date(payload.date),
        seller: getCompanyImprint(),
        buyer: { name: payload.userName, email: payload.userEmail },
        items: payload.items.map((i) => ({ description: i.description, quantity: i.quantity, unitPrice: i.unitPrice, total: i.total })),
        currency: payload.currency,
        mediaThumb: null,
        rbr: null,
      });
      doc.end();

      await new Promise((resolve, reject) => {
        stream.on('finish', resolve);
        stream.on('error', reject);
      });

      const [signedUrl] = await file.getSignedUrl({
        action: 'read',
        expires: Date.now() + 1000 * 60 * 60,
        responseDisposition: `attachment; filename=\"${payload.invoiceNumber}.pdf\"`,
      } as any);
      return { url: signedUrl, path: filePath };
    } catch (error: any) {
      console.error('Invoice Error:', error);
      throw new functions.https.HttpsError('internal', error.message || 'Rechnungsfehler');
    }
  });

// Schreibe Anker-Infos direkt in die Transaktion (keine invoiceAnchors-Collection)
// ensureInvoiceForTransaction entfernt

// getInvoiceAnchorStatus entfernt

// Upgrade pending OTS proofs periodically and mark as stamped when attestations included
// upgradeInvoiceAnchors entfernt

// Sofort-Upgrade per Button/Klick für EINE Transaktion
// upgradeInvoiceForTransaction entfernt

// Nur PDF/XML sicherstellen und Download-URL liefern – KEIN Anchor/Status
export const ensureInvoiceFiles = functions
  .region('us-central1')
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Nicht angemeldet');
    const userId = context.auth.uid;
    const txId = (data?.transactionId as string || '').trim();
    if (!txId) throw new functions.https.HttpsError('invalid-argument', 'transactionId fehlt');
    const db = admin.firestore();
    const txRef = db.collection('users').doc(userId).collection('transactions').doc(txId);
    const txSnap = await txRef.get();
    if (!txSnap.exists) throw new functions.https.HttpsError('not-found', 'Transaktion nicht gefunden');
    const tx: any = txSnap.data() || {};

    let invoiceNumber: string | undefined = tx.invoiceNumber;
    if (!invoiceNumber) {
      invoiceNumber = generateInvoiceNumber();
      await txRef.set({ invoiceNumber }, { merge: true });
    }

    const bucket = admin.storage().bucket();
    const pdfPath = `invoices/${userId}/${invoiceNumber}.pdf`;
    const xmlPath = `invoices/${userId}/${invoiceNumber}.xml`;

    // Existenz prüfen, ggf. erzeugen – identisch zur Logik oben, aber ohne Anchor-Updates
    const pdfFile = bucket.file(pdfPath);
    const xmlFile = bucket.file(xmlPath);
    const [pdfExists] = await pdfFile.exists();
    const [xmlExists] = await xmlFile.exists();
    if (!pdfExists || !xmlExists) {
      const items = [
        {
          description: tx.credits ? `${tx.credits} Credits` : (tx.mediaName || 'Kauf'),
          quantity: 1,
          unitPrice: ((tx.amount || 0) / 100) || 0,
          total: ((tx.amount || 0) / 100) || 0,
        },
      ];
      // Verkäufer ermitteln (soft – mit Fallback auf Firma)
      let seller: { name: string; street?: string; postalCode?: string; city?: string; country?: string; vatId?: string } = getCompanyImprint();
      try {
        const txType = String(tx.type || '').toLowerCase();
        if (txType === 'media_purchase' && tx.avatarId) {
          const avatarSnap = await db.collection('avatars').doc(String(tx.avatarId)).get();
          const ownerUserId = (avatarSnap.data() as any)?.userId as string | undefined;
          if (ownerUserId) {
            const userSnap = await db.collection('users').doc(ownerUserId).get();
            if (userSnap.exists) {
              const u = (userSnap.data() || {}) as any;
              const name = (u.companyName || u.displayName || u.name || '').toString().trim();
              if (name) {
                seller = {
                  name,
                  street: u.address?.street || u.street,
                  postalCode: u.address?.postalCode || u.postalCode,
                  city: u.address?.city || u.city,
                  country: u.address?.country || u.country,
                  vatId: u.vatId || u.taxId,
                };
              }
            }
          }
        }
      } catch {}
      let buyer: { name: string; email?: string } = { name: tx.userName || userId };
      try {
        const userSnap = await db.collection('users').doc(userId).get();
        const u = (userSnap.data() || {}) as any;
        buyer = { name: u.displayName || u.name || userId, email: u.email };
      } catch {}

      const doc = new PDFDocument({ size: 'A4', margin: 50 });
      const pdfStream = doc.pipe(pdfFile.createWriteStream({ contentType: 'application/pdf' }));
      const createdAt = tx.createdAt && tx.createdAt.toDate ? tx.createdAt.toDate() : new Date();
      const mediaThumb = (String(tx.type || '').toLowerCase() === 'media_purchase') ? await getMediaThumbBuffer(tx) : null;
      await renderStyledInvoice(doc, {
        invoiceNumber,
        date: createdAt,
        seller,
        buyer,
        items,
        currency: (tx.currency || 'EUR').toString(),
        mediaThumb,
        rbr: (tx.rbr as string | undefined) || `RBR-${invoiceNumber}`,
      });
      doc.end();
      await new Promise((resolve, reject) => { pdfStream.on('finish', resolve); pdfStream.on('error', reject); });

      const xml = `<?xml version="1.0" encoding="UTF-8"?>\n`+
        `<Invoice>`+
        `<ID>${invoiceNumber}</ID>`+
        `<Seller><Name>${seller.name}</Name>${seller.vatId ? `<VAT>${seller.vatId}</VAT>` : ''}</Seller>`+
        `<Buyer><Name>${buyer.name}</Name>${buyer.email ? `<Email>${buyer.email}</Email>` : ''}</Buyer>`+
        `<Total>${items[0].total.toFixed(2)}</Total>`+
        `<Currency>${(tx.currency || 'EUR').toString().toUpperCase()}</Currency>`+
        `</Invoice>`;
      await xmlFile.save(Buffer.from(xml, 'utf-8'), { contentType: 'application/xml' });
    }

    const [freshUrl] = await bucket.file(pdfPath).getSignedUrl({ action: 'read', expires: Date.now() + 30*24*3600*1000, responseDisposition: `attachment; filename="${invoiceNumber}.pdf"` } as any);
    await txRef.set({ invoicePdfUrl: freshUrl }, { merge: true });
    return { invoiceNumber, invoicePdfUrl: freshUrl, invoiceXmlUrl: null, status: 'ready' };
  });

