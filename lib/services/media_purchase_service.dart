import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/media_models.dart';

/// Service für Media-Käufe (Credits oder Stripe)
class MediaPurchaseService {
  final _firestore = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instance;

  /// Prüft ob User genug Credits hat (direkt über das `credits` Feld im User-Dokument).
  Future<bool> hasEnoughCredits(String userId, int requiredCredits) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) return false;
      final data = userDoc.data() ?? <String, dynamic>{};
      final currentCredits = (data['credits'] as num?)?.toInt() ?? 0;
      debugPrint(
        '🔍 [PurchaseService] hasEnoughCredits: user=$userId credits=$currentCredits required=$requiredCredits',
      );
      return currentCredits >= requiredCredits;
    } catch (e) {
      debugPrint('⚠️ [PurchaseService] hasEnoughCredits Fehler: $e');
      return false;
    }
  }

  /// Prüft, ob der Avatar‑Owner alle notwendigen Verkäuferdaten bereitgestellt hat
  /// (Name/Firma + Adresse + aktiver Payout bei Stripe Connect)
  Future<bool> isSellerCompliant(String avatarId) async {
    try {
      final avatarDoc = await _firestore.collection('avatars').doc(avatarId).get();
      final ownerId = (avatarDoc.data() ?? const {})['userId'] as String?;
      if (ownerId == null || ownerId.isEmpty) return false;
      final userDoc = await _firestore.collection('users').doc(ownerId).get();
      if (!userDoc.exists) return false;
      final u = userDoc.data() ?? const {};
      final name = ((u['companyName'] ?? u['displayName'] ?? u['name']) as String?)?.trim();
      final addr = (u['address'] as Map<String, dynamic>?) ?? const {};
      final street = (addr['street'] ?? u['street']) as String?;
      final postal = (addr['postalCode'] ?? u['postalCode']) as String?;
      final city = (addr['city'] ?? u['city']) as String?;
      final country = (addr['country'] ?? u['country']) as String?;
      final payoutsEnabled = (u['payoutsEnabled'] == true);
      final hasName = (name != null && name.isNotEmpty);
      final hasAddr = [street, postal, city, country].every((v) => v is String && v.trim().isNotEmpty);
      return hasName && hasAddr && payoutsEnabled;
    } catch (_) {
      return false;
    }
  }

  /// Prüft ob User Media bereits gekauft hat
  Future<bool> hasMediaAccess(String userId, String mediaId) async {
    final purchaseDoc = await _firestore
        .collection('users')
        .doc(userId)
        .collection('purchased_media')
        .doc(mediaId)
        .get();

    return purchaseDoc.exists;
  }

  /// Kauft Media mit Credits (serverseitig via Cloud Function)
  /// Gibt die Download-URL zurück oder null bei Fehler
  Future<String?> purchaseMediaWithCredits({
    required String userId,
    required AvatarMedia media,
  }) async {
    debugPrint('🔵 [PurchaseService] START purchaseMediaWithCredits: userId=$userId, mediaId=${media.id}');
    
    final price = media.price ?? 0.0;
    final currency = media.currency ?? '€';

    try {
      final callable = _functions.httpsCallable('purchaseMediaWithCredits');
      final result = await callable.call({
        'mediaId': media.id,
        'avatarId': media.avatarId,
        'price': price,
        'currency': currency == '\$' ? 'usd' : 'eur',
        'mediaType': _getMediaTypeString(media.type),
        'mediaUrl': media.url,
        'mediaName': media.originalFileName ?? 'Media',
      });

      final data = result.data as Map?;
      final ok = data?['ok'] == true;
      final downloadUrl = data?['downloadUrl'] as String?;
      
      if (ok) {
        debugPrint('✅ [PurchaseService] Media-Kauf erfolgreich, downloadUrl=$downloadUrl');
        return downloadUrl ?? media.url; // Fallback auf Original-URL
      } else {
        debugPrint('🔴 [PurchaseService] Media-Kauf fehlgeschlagen (ok=false)');
        return null;
      }
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'failed-precondition') {
        debugPrint('🔴 [PurchaseService] Nicht genug Credits');
      } else {
        debugPrint('🔴 [PurchaseService] Function error: ${e.code} ${e.message}');
      }
      return null;
    } catch (e, stackTrace) {
      debugPrint('🔴 [PurchaseService] Fehler beim Media-Kauf: $e');
      debugPrint('🔴 [PurchaseService] StackTrace: $stackTrace');
      return null;
    }
  }

  /// Kauft Media mit Stripe (Direktzahlung)
  Future<String?> purchaseMediaWithStripe({
    required String userId,
    required AvatarMedia media,
  }) async {
    final price = media.price ?? 0.0;
    final currency = media.currency ?? '€';

    // Nur bei Preisen >= 2€ erlaubt
    if (price < 2.0) {
      throw Exception('Zahlungen unter 2€ nur mit Credits möglich');
    }

    try {
      final callable = _functions.httpsCallable('createMediaCheckoutSession');

      final result = await callable.call({
        'mediaId': media.id,
        'avatarId': media.avatarId,
        'amount': (price * 100).toInt(), // in Cents
        'currency': currency == '\$' ? 'usd' : 'eur',
        'mediaName': media.originalFileName ?? 'Media',
        'mediaType': _getMediaTypeString(media.type),
        'mediaUrl': media.url,
      });

      return result.data['url'] as String?;
    } catch (e) {
      debugPrint('Fehler beim Stripe-Checkout: $e');
      return null;
    }
  }

  /// Kauft mehrere Medien als Bundle
  Future<bool> purchaseMediaBundle({
    required String userId,
    required List<AvatarMedia> mediaList,
  }) async {
    // Gesamtpreis berechnen
    double totalPrice = 0.0;
    for (final media in mediaList) {
      totalPrice += media.price ?? 0.0;
    }

    final requiredCredits = (totalPrice / 0.1).round();

    // Prüfen ob genug Credits vorhanden
    final hasCredits = await hasEnoughCredits(userId, requiredCredits);
    if (!hasCredits) return false;

    try {
      final userRef = _firestore.collection('users').doc(userId);
      final batch = _firestore.batch();

      // 1. Credits abziehen
      batch.set(userRef, {
        'credits': FieldValue.increment(-requiredCredits),
        'creditsSpent': FieldValue.increment(requiredCredits),
      }, SetOptions(merge: true));

      // 2. Transaktion anlegen (Bundle)
      final transactionRef = userRef.collection('transactions').doc();
      final now = DateTime.now().millisecondsSinceEpoch;
      final invoiceNumber = '20${now.toString().substring(now.toString().length - 6)}-D${now.toString().substring(now.toString().length - 5)}';
      batch.set(transactionRef, {
        'userId': userId,
        'type': 'credit_spent',
        'credits': requiredCredits,
        'amount': (totalPrice * 100).round(),
        'currency': 'eur',
        'mediaIds': mediaList.map((m) => m.id).toList(),
        'mediaType': 'bundle',
        'mediaName': 'Bundle (${mediaList.length} Medien)',
        'status': 'completed',
        'invoiceNumber': invoiceNumber,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 3. Alle Medien als gekauft markieren
      for (final media in mediaList) {
        final purchaseRef = userRef.collection('purchased_media').doc(media.id);
        batch.set(purchaseRef, {
          'mediaId': media.id,
          'avatarId': media.avatarId,
          'type': _getMediaTypeString(media.type),
          'price': media.price,
          'currency': media.currency,
          'credits': ((media.price ?? 0.0) / 0.1).round(),
          'purchasedAt': FieldValue.serverTimestamp(),
          'bundleTransactionId': transactionRef.id,
        });
      }

      await batch.commit();
      
      // PDF-Rechnung erzeugen
      try {
        debugPrint('🔵 [PurchaseService] Erzeuge Bundle-Rechnung...');
        final fns = FirebaseFunctions.instanceFor(region: 'us-central1');
        final ensure = fns.httpsCallable('ensureInvoiceFiles');
        final res = await ensure.call({'transactionId': transactionRef.id});
        final data = Map<String, dynamic>.from(res.data as Map? ?? {});
        final pdf = data['invoicePdfUrl'] as String?;
        final nr = data['invoiceNumber'] as String?;
        if ((pdf != null && pdf.isNotEmpty) || (nr != null && nr.isNotEmpty)) {
          await transactionRef.set({
            if (pdf != null && pdf.isNotEmpty) 'invoicePdfUrl': pdf,
            if (nr != null && nr.isNotEmpty) 'invoiceNumber': nr,
          }, SetOptions(merge: true));
          debugPrint('✅ [PurchaseService] Bundle-Rechnung gespeichert.');
        }
      } catch (e) {
        debugPrint('⚠️ [PurchaseService] ensureInvoiceFiles (Bundle) fehlgeschlagen: $e');
      }
      
      return true;
    } catch (e) {
      debugPrint('Fehler beim Bundle-Kauf: $e');
      return false;
    }
  }

  String _getMediaTypeString(AvatarMediaType type) {
    switch (type) {
      case AvatarMediaType.image:
        return 'image';
      case AvatarMediaType.video:
        return 'video';
      case AvatarMediaType.audio:
        return 'audio';
      case AvatarMediaType.document:
        return 'document';
    }
  }
}
