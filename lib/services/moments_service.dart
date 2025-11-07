import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import '../models/moment.dart';
import '../models/media_models.dart';

/// Moments Service - Speichert gekaufte/angenommene Timeline Items als Originaldateien
class MomentsService {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _storage = FirebaseStorage.instance;

  /// Globaler Refresh-Ticker: UI hört darauf und lädt neu
  static final ValueNotifier<int> refreshTicker = ValueNotifier<int>(0);

  /// Moment Collection für User
  CollectionReference<Map<String, dynamic>> _momentsCol(String userId) {
    return _fs.collection('users').doc(userId).collection('moments');
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
      // Versuche serverseitige Kopie per Cloud Function (robust, kein CORS)
      debugPrint('⚠️ [MomentsService] Client copy failed, try server copy: $e');
      debugPrint('⚠️ [MomentsService] StackTrace: $stackTrace');
      try {
        final fns = FirebaseFunctions.instanceFor(region: 'us-central1');
        final fn = fns.httpsCallable('copyMediaToMoments');
        final res = await fn.call({
          'mediaUrl': media.url,
          'avatarId': media.avatarId,
          'fileName': media.originalFileName,
        });
        final data = Map<String, dynamic>.from(res.data as Map);
        final url = data['downloadUrl'] as String?;
        if (url != null && url.isNotEmpty) {
          storedUrl = url;
          debugPrint('✅ [MomentsService] Server copy success');
        } else {
          storedUrl = media.url; // letzter Fallback
        }
      } catch (e) {
        debugPrint('⚠️ [MomentsService] Server copy failed: $e');
        storedUrl = media.url; // letzter Fallback
      }
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
    debugPrint('🔵 [MomentsService] Create Moment: mediaId=${media.id}');
    final moment = Moment(
      id: momentId,
      userId: uid,
      avatarId: media.avatarId,
      type: _typeToString(media.type),
      mediaId: media.id,
      originalUrl: media.url,
      storedUrl: storedUrl,
      thumbUrl: storedThumbUrl,
      originalFileName: media.originalFileName,
      acquiredAt: timestamp,
      price: price,
      currency: media.currency ?? '€',
      paymentMethod: paymentMethod,
      tags: media.tags,
      downloadCount: 0,
      maxDownloads: 5,
    );

    // 6. Save to Firestore
    debugPrint('🔵 [MomentsService] Save Moment to Firestore...');
    try {
      final momentMap = moment.toMap();
      debugPrint('🔵 [MomentsService] Moment Map: $momentMap');
      await _momentsCol(uid).doc(momentId).set(momentMap);
      debugPrint('🔵 [MomentsService] Moment saved to Firestore');
    } catch (e, stack) {
      debugPrint('❌ [MomentsService] FIRESTORE WRITE FAILED: $e');
      debugPrint('❌ [MomentsService] Stack: $stack');
      rethrow;
    }

    // 7. Moment ist fertig gespeichert
    if (price > 0.0) {
      debugPrint('✅ [MomentsService] Gekaufter Moment angelegt (Transaktion wird separat erstellt)');
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
    // UI benachrichtigen
    try { refreshTicker.value = refreshTicker.value + 1; } catch (_) {}
    return moment;
  }

  /// Inkrementiert den Download-Zähler für einen Moment (max bis `maxDownloads`).
  /// Gibt die verbleibenden Downloads zurück.
  Future<int> incrementDownloadCount(String momentId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return 0;
    final docRef = _momentsCol(uid).doc(momentId);
    return await _fs.runTransaction<int>((tx) async {
      final snap = await tx.get(docRef);
      if (!snap.exists) return 0;
      final data = snap.data() as Map<String, dynamic>;
      final current = (data['downloadCount'] as num?)?.toInt() ?? 0;
      final max = (data['maxDownloads'] as num?)?.toInt() ?? 5;
      if (current >= max) {
        return 0;
      }
      final next = current + 1;
      tx.update(docRef, {'downloadCount': next});
      return (max - next);
    });
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
              mediaId: (m['mediaId'] as String?),
              originalUrl: (m['mediaUrl'] as String?) ?? '',
              storedUrl: (m['mediaUrl'] as String?) ?? '',
              thumbUrl: null,
              originalFileName: (m['mediaName'] as String?) ?? 'Media',
              acquiredAt: ((m['purchasedAt'] as Timestamp?)?.millisecondsSinceEpoch) ?? DateTime.now().millisecondsSinceEpoch,
              price: (m['price'] as num?)?.toDouble(),
              currency: (m['currency'] as String?) ?? '€',
              tags: const [],
            );
          }).toList();
        }
      } catch (_) {}
    }
    debugPrint('🔵 [MomentsService] listMoments: ${items.length} items');
    return items;
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
    // UI benachrichtigen
    try { refreshTicker.value = refreshTicker.value + 1; } catch (_) {}
  }

  void debugPrint(String message) {
    // ignore: avoid_print
    print(message);
  }
}

