import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/media_models.dart';
import '../models/user_profile.dart';

/// Service für Media-Käufe (Credits oder Stripe)
class MediaPurchaseService {
  final _firestore = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instance;

  /// Prüft ob User genug Credits hat
  Future<bool> hasEnoughCredits(String userId, int requiredCredits) async {
    final userDoc = await _firestore.collection('users').doc(userId).get();
    if (!userDoc.exists) return false;

    final profile = UserProfile.fromMap(userDoc.data()!);
    return profile.credits >= requiredCredits;
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

  /// Kauft Media mit Credits
  Future<bool> purchaseMediaWithCredits({
    required String userId,
    required AvatarMedia media,
  }) async {
    debugPrint('🔵 [PurchaseService] START purchaseMediaWithCredits: userId=$userId, mediaId=${media.id}');
    
    final price = media.price ?? 0.0;
    final currency = media.currency ?? '€';

    // Preis in Credits umrechnen (1 Credit = 0,1 €)
    final requiredCredits = (price / 0.1).round();
    debugPrint('🔵 [PurchaseService] Preis: $price, Credits: $requiredCredits');

    // Prüfen ob genug Credits vorhanden
    final hasCredits = await hasEnoughCredits(userId, requiredCredits);
    if (!hasCredits) {
      debugPrint('🔴 [PurchaseService] Nicht genug Credits');
      return false;
    }
    debugPrint('✅ [PurchaseService] Credits verfügbar');

    try {
      // Ermittle Avatar-Owner (Verkäufer)
      String? sellerId;
      try {
        final avatarDoc = await _firestore.collection('avatars').doc(media.avatarId).get();
        sellerId = (avatarDoc.data()?['userId'] as String?);
      } catch (e) {
        debugPrint('⚠️ [PurchaseService] Avatar-Owner konnte nicht geladen werden: $e');
      }
      
      debugPrint('🔵 [PurchaseService] Verkäufer: $sellerId');
      
      final userRef = _firestore.collection('users').doc(userId);

      // Batch-Operation für Atomarität
      final batch = _firestore.batch();

      // 1. Credits abziehen (Käufer)
      debugPrint('🔵 [PurchaseService] Ziehe $requiredCredits Credits ab...');
      batch.set(userRef, {
        'credits': FieldValue.increment(-requiredCredits),
        'creditsSpent': FieldValue.increment(requiredCredits),
      }, SetOptions(merge: true));

      // 2. Transaktion anlegen (Käufer = Ausgabe)
      final transactionRef = userRef.collection('transactions').doc();
      final now = DateTime.now().millisecondsSinceEpoch;
      final invoiceNumber = '20${now.toString().substring(now.toString().length - 6)}-D${now.toString().substring(now.toString().length - 5)}';
      final transactionData = {
        'userId': userId,
        'type': 'credit_spent',
        'credits': requiredCredits,
        'amount': (price * 100).round(),
        'currency': currency == '\$' ? 'usd' : 'eur',
        'mediaId': media.id,
        'mediaType': _getMediaTypeString(media.type),
        'mediaUrl': media.url,
        'mediaName': media.originalFileName ?? 'Media',
        'avatarId': media.avatarId,
        'sellerId': sellerId,
        'status': 'completed',
        'invoiceNumber': invoiceNumber,
        'createdAt': FieldValue.serverTimestamp(),
      };
      debugPrint('🔵 [PurchaseService] Erstelle Transaktion: ${transactionRef.id}');
      debugPrint('🔵 [PurchaseService] Transaction Data: $transactionData');
      batch.set(transactionRef, transactionData);

      // 3. Media als gekauft markieren
      final purchaseRef = userRef.collection('purchased_media').doc(media.id);
      debugPrint('🔵 [PurchaseService] Markiere Media als gekauft: ${media.id}');
      batch.set(purchaseRef, {
        'mediaId': media.id,
        'avatarId': media.avatarId,
        'type': _getMediaTypeString(media.type),
        'price': price,
        'currency': currency,
        'credits': requiredCredits,
        'purchasedAt': FieldValue.serverTimestamp(),
      });

      // 4. Verkäufer Einnahmen gutschreiben (IMMER, auch bei Selbstkauf!)
      String? sellerTxId;
      if (sellerId != null && sellerId.isNotEmpty) {
        debugPrint('🔵 [PurchaseService] Schreibe Einnahmen für Verkäufer $sellerId gut...');
        final sellerRef = _firestore.collection('users').doc(sellerId);
        
        // Gutschrift Einnahmen
        batch.set(sellerRef, {
          'creditsEarned': FieldValue.increment(requiredCredits),
        }, SetOptions(merge: true));
        
        // Transaktion für Verkäufer (Einnahme)
        final sellerTxRef = sellerRef.collection('transactions').doc();
        sellerTxId = sellerTxRef.id; // ID für später speichern
        final sellerInvoiceNumber = '20${now.toString().substring(now.toString().length - 6)}-E${now.toString().substring(now.toString().length - 5)}';
        batch.set(sellerTxRef, {
          'userId': sellerId,
          'type': 'credit_earned',
          'credits': requiredCredits,
          'amount': (price * 100).round(),
          'currency': currency == '\$' ? 'usd' : 'eur',
          'mediaId': media.id,
          'mediaType': _getMediaTypeString(media.type),
          'mediaUrl': media.url,
          'mediaName': media.originalFileName ?? 'Media',
          'avatarId': media.avatarId,
          'buyerId': userId,
          'status': 'completed',
          'invoiceNumber': sellerInvoiceNumber,
          'createdAt': FieldValue.serverTimestamp(),
        });
        debugPrint('✅ [PurchaseService] Verkäufer-Transaktion erstellt (ID: $sellerTxId)');
      } else {
        debugPrint('⚠️ [PurchaseService] Kein Verkäufer gefunden → keine Einnahmen-Gutschrift');
      }

      debugPrint('🔵 [PurchaseService] Committe Batch...');
      await batch.commit();
      debugPrint('✅ [PurchaseService] Batch erfolgreich committed!');
      
      // PDF-Rechnung erzeugen (KÄUFER)
      try {
        debugPrint('🔵 [PurchaseService] Erzeuge PDF-Rechnung für Käufer...');
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
          debugPrint('✅ [PurchaseService] Käufer-Rechnung gespeichert (nr=${nr ?? '-'}).');
        }
      } catch (e) {
        debugPrint('⚠️ [PurchaseService] ensureInvoiceFiles (Käufer) fehlgeschlagen: $e');
      }
      
      // PDF-Rechnung erzeugen (VERKÄUFER)
      if (sellerId != null && sellerId.isNotEmpty && sellerTxId != null) {
        try {
          debugPrint('🔵 [PurchaseService] Erzeuge PDF-Rechnung für Verkäufer...');
          final fns = FirebaseFunctions.instanceFor(region: 'us-central1');
          final ensure = fns.httpsCallable('ensureInvoiceFiles');
          final res = await ensure.call({'transactionId': sellerTxId});
          final data = Map<String, dynamic>.from(res.data as Map? ?? {});
          final pdf = data['invoicePdfUrl'] as String?;
          final nr = data['invoiceNumber'] as String?;
          if ((pdf != null && pdf.isNotEmpty) || (nr != null && nr.isNotEmpty)) {
            await _firestore
                .collection('users')
                .doc(sellerId)
                .collection('transactions')
                .doc(sellerTxId)
                .set({
              if (pdf != null && pdf.isNotEmpty) 'invoicePdfUrl': pdf,
              if (nr != null && nr.isNotEmpty) 'invoiceNumber': nr,
            }, SetOptions(merge: true));
            debugPrint('✅ [PurchaseService] Verkäufer-Rechnung gespeichert (nr=${nr ?? '-'}).');
          }
        } catch (e) {
          debugPrint('⚠️ [PurchaseService] ensureInvoiceFiles (Verkäufer) fehlgeschlagen: $e');
        }
      }
      
      return true;
    } catch (e, stackTrace) {
      debugPrint('🔴 [PurchaseService] Fehler beim Media-Kauf: $e');
      debugPrint('🔴 [PurchaseService] StackTrace: $stackTrace');
      return false;
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
