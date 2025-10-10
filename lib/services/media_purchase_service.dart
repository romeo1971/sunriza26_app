import 'package:cloud_firestore/cloud_firestore.dart';
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
    final price = media.price ?? 0.0;
    final currency = media.currency ?? '€';

    // Preis in Credits umrechnen (1 Credit = 0,1 €)
    final requiredCredits = (price / 0.1).round();

    // Prüfen ob genug Credits vorhanden
    final hasCredits = await hasEnoughCredits(userId, requiredCredits);
    if (!hasCredits) return false;

    try {
      final userRef = _firestore.collection('users').doc(userId);

      // Batch-Operation für Atomarität
      final batch = _firestore.batch();

      // 1. Credits abziehen
      batch.update(userRef, {
        'credits': FieldValue.increment(-requiredCredits),
        'creditsSpent': FieldValue.increment(requiredCredits),
      });

      // 2. Transaktion anlegen
      final transactionRef = userRef.collection('transactions').doc();
      batch.set(transactionRef, {
        'userId': userId,
        'type': 'credit_spent',
        'credits': requiredCredits,
        'mediaId': media.id,
        'mediaType': _getMediaTypeString(media.type),
        'mediaUrl': media.url,
        'mediaName': media.originalFileName ?? 'Media',
        'avatarId': media.avatarId,
        'status': 'completed',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 3. Media als gekauft markieren
      final purchaseRef = userRef.collection('purchased_media').doc(media.id);
      batch.set(purchaseRef, {
        'mediaId': media.id,
        'avatarId': media.avatarId,
        'type': _getMediaTypeString(media.type),
        'price': price,
        'currency': currency,
        'credits': requiredCredits,
        'purchasedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      return true;
    } catch (e) {
      print('Fehler beim Media-Kauf: $e');
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
      });

      return result.data['url'] as String?;
    } catch (e) {
      print('Fehler beim Stripe-Checkout: $e');
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
      batch.update(userRef, {
        'credits': FieldValue.increment(-requiredCredits),
        'creditsSpent': FieldValue.increment(requiredCredits),
      });

      // 2. Transaktion anlegen (Bundle)
      final transactionRef = userRef.collection('transactions').doc();
      batch.set(transactionRef, {
        'userId': userId,
        'type': 'credit_spent',
        'credits': requiredCredits,
        'mediaIds': mediaList.map((m) => m.id).toList(),
        'mediaType': 'bundle',
        'mediaName': 'Bundle (${mediaList.length} Medien)',
        'status': 'completed',
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
      return true;
    } catch (e) {
      print('Fehler beim Bundle-Kauf: $e');
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
