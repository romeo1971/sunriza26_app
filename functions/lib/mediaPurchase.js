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
exports.purchaseMediaWithCredits = void 0;
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
/**
 * purchaseMediaWithCredits - Serverseitige Transaktion für Media-Kauf mit Credits
 *
 * Führt atomare Firestore-Transaktion durch:
 * 1. Credits vom Käufer abziehen
 * 2. purchased_media für Käufer anlegen
 * 3. Credits dem Verkäufer gutschreiben
 * 4. Transaktionen für beide Seiten anlegen
 */
exports.purchaseMediaWithCredits = functions.https.onCall(async (data, context) => {
    var _a, _b;
    const uid = (_a = context.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }
    const { mediaId, avatarId, price, currency, mediaType, mediaUrl, mediaName } = data || {};
    // Validierung
    if (!mediaId || typeof mediaId !== 'string') {
        throw new functions.https.HttpsError('invalid-argument', 'mediaId is required');
    }
    if (!avatarId || typeof avatarId !== 'string') {
        throw new functions.https.HttpsError('invalid-argument', 'avatarId is required');
    }
    if (typeof price !== 'number' || price < 0) {
        throw new functions.https.HttpsError('invalid-argument', 'price must be a positive number');
    }
    const db = admin.firestore();
    const requiredCredits = Math.round(price / 0.1);
    try {
        // Hole Avatar-Owner (Verkäufer)
        const avatarDoc = await db.collection('avatars').doc(avatarId).get();
        const sellerId = (_b = avatarDoc.data()) === null || _b === void 0 ? void 0 : _b.userId;
        if (!sellerId) {
            throw new functions.https.HttpsError('not-found', 'Avatar owner not found');
        }
        // Führe Transaktion durch
        const result = await db.runTransaction(async (tx) => {
            var _a;
            const buyerRef = db.collection('users').doc(uid);
            const buyerSnap = await tx.get(buyerRef);
            if (!buyerSnap.exists) {
                throw new functions.https.HttpsError('not-found', 'Buyer user not found');
            }
            const buyerData = buyerSnap.data();
            const currentCredits = (_a = buyerData.credits) !== null && _a !== void 0 ? _a : 0;
            // Check: Genug Credits?
            if (currentCredits < requiredCredits) {
                throw new functions.https.HttpsError('failed-precondition', 'NOT_ENOUGH_CREDITS');
            }
            // 1. Credits vom Käufer abziehen
            tx.set(buyerRef, {
                credits: admin.firestore.FieldValue.increment(-requiredCredits),
                creditsSpent: admin.firestore.FieldValue.increment(requiredCredits),
            }, { merge: true });
            // 2. purchased_media für Käufer anlegen
            const purchaseRef = buyerRef.collection('purchased_media').doc(mediaId);
            tx.set(purchaseRef, {
                mediaId,
                avatarId,
                type: mediaType || 'unknown',
                price,
                currency: currency || 'eur',
                credits: requiredCredits,
                purchasedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            // 3. Transaktion für Käufer anlegen
            const now = Date.now();
            const buyerTxRef = buyerRef.collection('transactions').doc();
            const invoiceNumber = `20${now.toString().substring(now.toString().length - 6)}-D${now.toString().substring(now.toString().length - 5)}`;
            tx.set(buyerTxRef, {
                userId: uid,
                type: 'credit_spent',
                credits: requiredCredits,
                amount: Math.round(price * 100),
                currency: currency || 'eur',
                mediaId,
                mediaType: mediaType || 'unknown',
                mediaUrl: mediaUrl || null,
                mediaName: mediaName || 'Media',
                avatarId,
                sellerId,
                status: 'completed',
                invoiceNumber,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            // 4. Verkäufer: Credits gutschreiben
            const sellerRef = db.collection('users').doc(sellerId);
            tx.set(sellerRef, {
                creditsEarned: admin.firestore.FieldValue.increment(requiredCredits),
            }, { merge: true });
            // 5. Transaktion für Verkäufer anlegen
            const sellerTxRef = sellerRef.collection('transactions').doc();
            const sellerInvoiceNumber = `20${now.toString().substring(now.toString().length - 6)}-E${now.toString().substring(now.toString().length - 5)}`;
            tx.set(sellerTxRef, {
                userId: sellerId,
                type: 'credit_earned',
                credits: requiredCredits,
                amount: Math.round(price * 100),
                currency: currency || 'eur',
                mediaId,
                mediaType: mediaType || 'unknown',
                mediaUrl: mediaUrl || null,
                mediaName: mediaName || 'Media',
                avatarId,
                buyerId: uid,
                status: 'completed',
                invoiceNumber: sellerInvoiceNumber,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            return {
                buyerTxId: buyerTxRef.id,
                sellerTxId: sellerTxRef.id,
                remaining: currentCredits - requiredCredits,
            };
        });
        // 6. Moment-Dokument anlegen (außerhalb der Transaktion, nach Credit-Abzug)
        let storedUrl = mediaUrl || '';
        let finalFileName = mediaName || 'Media';
        try {
            const momentsCol = db.collection('users').doc(uid).collection('moments');
            const momentId = momentsCol.doc().id;
            // Wenn Firebase Storage URL: Datei in User-Moments-Ordner kopieren
            if (mediaUrl && mediaUrl.includes('firebasestorage.googleapis.com')) {
                try {
                    const m = mediaUrl.match(/\/o\/(.*?)\?/);
                    if (m && m[1]) {
                        const srcPath = decodeURIComponent(m[1]);
                        const ts = Date.now();
                        const baseName = finalFileName || srcPath.split('/').pop() || `moment_${ts}`;
                        const destPath = `users/${uid}/moments/${avatarId}/${ts}_${baseName}`;
                        const bucket = admin.storage().bucket();
                        await bucket.file(srcPath).copy(bucket.file(destPath));
                        const [signedUrl] = await bucket.file(destPath).getSignedUrl({
                            action: 'read',
                            expires: Date.now() + 30 * 24 * 3600 * 1000,
                            responseDisposition: `attachment; filename="${baseName}"`,
                        });
                        storedUrl = signedUrl;
                        finalFileName = baseName;
                    }
                }
                catch (copyErr) {
                    console.error('⚠️ Storage copy error:', copyErr);
                }
            }
            await momentsCol.doc(momentId).set({
                id: momentId,
                userId: uid,
                avatarId: avatarId || '',
                type: mediaType || 'unknown',
                mediaId: mediaId || null,
                originalUrl: mediaUrl || '',
                storedUrl,
                originalFileName: finalFileName,
                acquiredAt: Date.now(),
                price: price || 0,
                currency: currency || 'eur',
                paymentMethod: 'credits',
                tags: [],
            });
            console.log(`✅ Moment created: ${momentId}`);
        }
        catch (momentErr) {
            console.error('⚠️ Moment creation failed:', momentErr);
            // Nicht werfen – Credit-Abzug ist bereits erfolgt
        }
        return {
            ok: true,
            ...result,
            momentCreated: true,
            downloadUrl: storedUrl,
        };
    }
    catch (error) {
        console.error('purchaseMediaWithCredits error:', error);
        if (error.code) {
            throw error; // Already a HttpsError
        }
        throw new functions.https.HttpsError('internal', error.message || 'Purchase failed');
    }
});
//# sourceMappingURL=mediaPurchase.js.map