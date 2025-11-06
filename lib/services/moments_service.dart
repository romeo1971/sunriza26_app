import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../models/moment.dart';
import '../models/media_models.dart';

/// Moments Service - Speichert gekaufte/angenommene Timeline Items als Originaldateien
class MomentsService {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _storage = FirebaseStorage.instance;

  /// Moment Collection für User
  CollectionReference<Map<String, dynamic>> _momentsCol(String userId) {
    return _fs.collection('users').doc(userId).collection('moments');
  }

  /// Receipts Collection für User
  CollectionReference<Map<String, dynamic>> _receiptsCol(String userId) {
    return _fs.collection('users').doc(userId).collection('receipts');
  }

  /// Speichert Timeline Item als Moment (kopiert Originaldatei)
  Future<Moment> saveMoment({
    required AvatarMedia media,
    required double price,
    required String paymentMethod, // 'free', 'credits', 'stripe'
    String? stripePaymentIntentId,
  }) async {
    debugPrint('🔵 [MomentsService] START saveMoment: mediaId=${media.id}, price=$price, method=$paymentMethod');
    
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      debugPrint('🔴 [MomentsService] User nicht authentifiziert');
      throw Exception('User not authenticated');
    }
    debugPrint('🔵 [MomentsService] User ID: $uid');

    // 1-3. Versuche Kopie ins Nutzer-Moments-Storage, fallback auf Original-URL
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    String storedUrl;
    try {
      debugPrint('🔵 [MomentsService] Download File von: ${media.url}');
      // 1. Download Original File
      final fileBytes = await _downloadFile(media.url);
      debugPrint('✅ [MomentsService] File geladen: ${fileBytes.length} bytes');

      // 2. Determine File Extension
      final ext = _getExtensionFromUrl(media.url) ?? _getExtensionFromType(media.type);
      debugPrint('🔵 [MomentsService] Extension: $ext');

      // 3. Upload to Moments Storage
      final storagePath = 'users/$uid/moments/${media.avatarId}/$timestamp$ext';
      debugPrint('🔵 [MomentsService] Upload zu: $storagePath');
      final ref = _storage.ref().child(storagePath);

      await ref.putData(
        fileBytes,
        SettableMetadata(
          contentType: _getContentType(media.type),
          contentDisposition: 'attachment; filename="${media.originalFileName ?? 'moment$ext'}"',
        ),
      );

      storedUrl = await ref.getDownloadURL();
      debugPrint('✅ [MomentsService] Upload erfolgreich: $storedUrl');
    } catch (e, stackTrace) {
      // Fallback: Speichere ohne Kopie, referenziere Original-URL
      debugPrint('⚠️ [MomentsService] Copy to moments failed, using originalUrl. Error: $e');
      debugPrint('⚠️ [MomentsService] StackTrace: $stackTrace');
      storedUrl = media.url;
    }

    // 4. Optional: Copy Thumbnail
    String? storedThumbUrl;
    if (media.thumbUrl != null && media.thumbUrl!.isNotEmpty) {
      try {
        final thumbBytes = await _downloadFile(media.thumbUrl!);
        final thumbPath = 'users/$uid/moments/${media.avatarId}/${timestamp}_thumb.jpg';
        final thumbRef = _storage.ref().child(thumbPath);
        await thumbRef.putData(
          thumbBytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        storedThumbUrl = await thumbRef.getDownloadURL();
      } catch (e) {
        // Thumbnail optional - Fehler ignorieren
        debugPrint('⚠️ Thumbnail copy failed: $e');
      }
    }

    // 5. Create Moment
    final momentId = _momentsCol(uid).doc().id;
    final moment = Moment(
      id: momentId,
      userId: uid,
      avatarId: media.avatarId,
      type: _typeToString(media.type),
      originalUrl: media.url,
      storedUrl: storedUrl,
      thumbUrl: storedThumbUrl,
      originalFileName: media.originalFileName,
      acquiredAt: timestamp,
      price: price,
      currency: media.currency ?? '€',
      receiptId: null, // Wird später gesetzt wenn Receipt erstellt wird
      tags: media.tags,
    );

    // 6. Save to Firestore
    await _momentsCol(uid).doc(momentId).set(moment.toMap());

    // 7. Receipt (falls Preis > 0) und Transaktionseintrag (immer)
    String? receiptId;
    if (price > 0.0) {
      final receipt = await _createReceipt(
        momentId: momentId,
        avatarId: media.avatarId,
        price: price,
        currency: media.currency ?? '€',
        paymentMethod: paymentMethod,
        stripePaymentIntentId: stripePaymentIntentId,
        metadata: {
          'mediaId': media.id,
          'originalFileName': media.originalFileName,
          'type': _typeToString(media.type),
        },
      );
      receiptId = receipt.id;
      await _momentsCol(uid).doc(momentId).update({'receiptId': receipt.id});
    }

    // Zusätzlich: Transaktions-Dokument für UI (users/{uid}/transactions) – IMMER anlegen
    try {
      final transactionsCol = _fs.collection('users').doc(uid).collection('transactions');
      final txRef = transactionsCol.doc();
      final rawCurrency = (media.currency ?? 'eur').toLowerCase();
      final currencyCode = (rawCurrency.contains('usd') || rawCurrency.contains('\$') || rawCurrency.contains('\u000024'))
          ? 'usd'
          : 'eur';
      await txRef.set({
        'userId': uid,
        'type': 'media_purchase',
        'amount': (price * 100).round(), // 0 bei kostenlos
        'currency': currencyCode,
        'status': 'completed',
        'createdAt': FieldValue.serverTimestamp(),
        'mediaId': media.id,
        'mediaType': _typeToString(media.type),
        'mediaUrl': media.url,
        'mediaName': media.originalFileName ?? 'Media',
        'avatarId': media.avatarId,
        if (stripePaymentIntentId != null) 'stripeSessionId': stripePaymentIntentId,
        if (receiptId != null) 'receiptId': receiptId,
      });
      debugPrint('✅ [MomentsService] UI-Transaction gespeichert: ${txRef.id}');

      // Versuche direkt Rechnung/PDF zu erzeugen, damit die UI einen Download-Link hat
      try {
        final fns = FirebaseFunctions.instanceFor(region: 'us-central1');
        final ensure = fns.httpsCallable('ensureInvoiceFiles');
        final res = await ensure.call({ 'transactionId': txRef.id });
        final data = Map<String, dynamic>.from(res.data as Map? ?? {});
        final pdf = data['invoicePdfUrl'] as String?;
        final nr = data['invoiceNumber'] as String?;
        if ((pdf != null && pdf.isNotEmpty) || (nr != null && nr.isNotEmpty)) {
          await txRef.set({
            if (pdf != null && pdf.isNotEmpty) 'invoicePdfUrl': pdf,
            if (nr != null && nr.isNotEmpty) 'invoiceNumber': nr,
          }, SetOptions(merge: true));
          debugPrint('✅ [MomentsService] Rechnung gespeichert (nr=${nr ?? '-'}).');
        }
      } catch (e) {
        debugPrint('⚠️ [MomentsService] ensureInvoiceFiles fehlgeschlagen: $e');
      }
    } catch (e) {
      debugPrint('⚠️ Transaction create failed: $e');
    }

    debugPrint('✅ Moment saved: $momentId ($storedUrl)');
    return moment;
  }

  /// Erstellt eine Rechnung
  Future<Receipt> _createReceipt({
    required String momentId,
    required String avatarId,
    required double price,
    required String currency,
    required String paymentMethod,
    String? stripePaymentIntentId,
    Map<String, dynamic>? metadata,
  }) async {
    debugPrint('🔵 [MomentsService] START _createReceipt');
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      debugPrint('🔴 [MomentsService] Receipt: User nicht authentifiziert');
      throw Exception('User not authenticated');
    }

    final receiptId = _receiptsCol(uid).doc().id;
    debugPrint('🔵 [MomentsService] Receipt ID: $receiptId');
    final receipt = Receipt(
      id: receiptId,
      userId: uid,
      avatarId: avatarId,
      momentId: momentId,
      price: price,
      currency: currency,
      paymentMethod: paymentMethod,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      stripePaymentIntentId: stripePaymentIntentId,
      metadata: metadata,
    );

    debugPrint('🔵 [MomentsService] Speichere Receipt...');
    await _receiptsCol(uid).doc(receiptId).set(receipt.toMap());
    debugPrint('✅ [MomentsService] Receipt created: $receiptId');
    return receipt;
  }

  /// Download File from URL
  Future<Uint8List> _downloadFile(String url) async {
    final response = await http.get(Uri.parse(url)).timeout(
      const Duration(seconds: 30),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to download file: ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  /// Get File Extension from URL
  String? _getExtensionFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      final ext = p.extension(path);
      if (ext.isNotEmpty) return ext;
    } catch (_) {}
    return null;
  }

  /// Get File Extension from Media Type
  String _getExtensionFromType(AvatarMediaType type) {
    switch (type) {
      case AvatarMediaType.image:
        return '.jpg';
      case AvatarMediaType.video:
        return '.mp4';
      case AvatarMediaType.audio:
        return '.mp3';
      case AvatarMediaType.document:
        return '.pdf';
    }
  }

  /// Get Content Type from Media Type
  String _getContentType(AvatarMediaType type) {
    switch (type) {
      case AvatarMediaType.image:
        return 'image/jpeg';
      case AvatarMediaType.video:
        return 'video/mp4';
      case AvatarMediaType.audio:
        return 'audio/mpeg';
      case AvatarMediaType.document:
        return 'application/pdf';
    }
  }

  /// Convert Media Type to String
  String _typeToString(AvatarMediaType type) {
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

  /// Liste alle Moments für User
  Future<List<Moment>> listMoments({String? avatarId}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return [];

    Query<Map<String, dynamic>> query = _momentsCol(uid);
    
    if (avatarId != null) {
      query = query.where('avatarId', isEqualTo: avatarId);
    }

    final snapshot = await query
        .orderBy('acquiredAt', descending: true)
        .limit(500)
        .get();

    List<Moment> items = snapshot.docs.map((d) => Moment.fromMap(d.data())).toList();
    // Fallback: Falls (noch) keine Moments vorhanden, versuche aus purchased_media
    if (items.isEmpty) {
      try {
        Query<Map<String, dynamic>> p = _fs.collection('users').doc(uid).collection('purchased_media');
        if (avatarId != null) p = p.where('avatarId', isEqualTo: avatarId);
        final ps = await p.orderBy('purchasedAt', descending: true).limit(500).get();
        if (ps.docs.isNotEmpty) {
          items = ps.docs.map((d) {
            final m = d.data();
            final type = (m['type'] as String?) ?? 'image';
            return Moment(
              id: d.id,
              userId: uid,
              avatarId: (m['avatarId'] as String?) ?? '',
              type: type,
              originalUrl: (m['mediaUrl'] as String?) ?? '',
              storedUrl: (m['mediaUrl'] as String?) ?? '',
              thumbUrl: null,
              originalFileName: (m['mediaName'] as String?) ?? 'Media',
              acquiredAt: ((m['purchasedAt'] as Timestamp?)?.millisecondsSinceEpoch) ?? DateTime.now().millisecondsSinceEpoch,
              price: (m['price'] as num?)?.toDouble(),
              currency: (m['currency'] as String?) ?? '€',
              receiptId: null,
              tags: const [],
            );
          }).toList();
        }
      } catch (_) {}
    }
    debugPrint('🔵 [MomentsService] listMoments: ${items.length} items');
    return items;
  }

  /// Liste alle Receipts für User
  Future<List<Receipt>> listReceipts({String? avatarId}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return [];

    Query<Map<String, dynamic>> query = _receiptsCol(uid);
    
    if (avatarId != null) {
      query = query.where('avatarId', isEqualTo: avatarId);
    }

    final snapshot = await query
        .orderBy('createdAt', descending: true)
        .limit(500)
        .get();

    return snapshot.docs.map((d) => Receipt.fromMap(d.data())).toList();
  }

  /// Lösche Moment
  Future<void> deleteMoment(String momentId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    // Hole Moment für Storage-Pfad
    final doc = await _momentsCol(uid).doc(momentId).get();
    if (!doc.exists) return;

    final moment = Moment.fromMap(doc.data()!);

    // Lösche Storage File
    try {
      final ref = _storage.refFromURL(moment.storedUrl);
      await ref.delete();
    } catch (e) {
      debugPrint('⚠️ Storage delete failed: $e');
    }

    // Lösche Thumbnail
    if (moment.thumbUrl != null) {
      try {
        final thumbRef = _storage.refFromURL(moment.thumbUrl!);
        await thumbRef.delete();
      } catch (e) {
        debugPrint('⚠️ Thumbnail delete failed: $e');
      }
    }

    // Lösche Firestore Doc
    await _momentsCol(uid).doc(momentId).delete();
    debugPrint('✅ Moment deleted: $momentId');
  }

  void debugPrint(String message) {
    // ignore: avoid_print
    print(message);
  }
}

