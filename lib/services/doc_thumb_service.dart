import 'dart:ui' as ui;
import 'package:archive/archive.dart' as zip;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdf_render/pdf_render.dart' as pdf;
import '../models/media_models.dart';

class DocThumbService {
  /// Generiert NUR Thumbnail, OHNE Firestore zu ändern
  static Future<Map<String, dynamic>?> generateThumbOnly(
    String avatarId,
    AvatarMedia media,
  ) async {
    try {
      if (kDebugMode) {
        print('DocThumbService.generateThumbOnly: START für ${media.id}');
      }
      if (media.type != AvatarMediaType.document) {
        if (kDebugMode) {
          print('DocThumbService.generateThumbOnly: SKIP - kein Dokument');
        }
        return null;
      }

      final bytes = await _loadPreviewBytes(media);
      if (bytes == null) {
        if (kDebugMode) {
          print(
            'DocThumbService.generateThumbOnly: FAIL - keine Preview-Bytes',
          );
        }
        return null;
      }

      // decode
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final src = frame.image;
      final srcW = src.width.toDouble();
      final srcH = src.height.toDouble();
      final srcAR = srcW / srcH;
      final bool wantPortrait = srcAR < 1.0;
      final double targetAR = wantPortrait ? (9 / 16) : (16 / 9);

      // crop cover
      double cropW, cropH;
      if (srcAR > targetAR) {
        cropH = srcH;
        cropW = cropH * targetAR;
      } else {
        cropW = srcW;
        cropH = cropW / targetAR;
      }
      final cropLeft = ((srcW - cropW) / 2).clamp(0, srcW);
      final cropTop = ((srcH - cropH) / 2).clamp(0, srcH);

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final dstRect = ui.Rect.fromLTWH(
        0,
        0,
        cropW.toDouble(),
        cropH.toDouble(),
      );
      final srcRect = ui.Rect.fromLTWH(
        cropLeft.toDouble(),
        cropTop.toDouble(),
        cropW.toDouble(),
        cropH.toDouble(),
      );
      final paint = ui.Paint();
      canvas.drawImageRect(src, srcRect, dstRect, paint);
      final cropped = await recorder.endRecording().toImage(
        cropW.toInt(),
        cropH.toInt(),
      );
      final byteData = await cropped.toByteData(format: ui.ImageByteFormat.png);
      final out = byteData!.buffer.asUint8List();
      src.dispose();
      cropped.dispose();

      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance.ref().child(
        'avatars/$avatarId/documents/thumbs/${media.id}_$ts.png',
      );
      final task = await ref.putData(
        out,
        SettableMetadata(contentType: 'image/png'),
      );
      final thumbUrl = await task.ref.getDownloadURL();
      if (kDebugMode) {
        print(
          'DocThumbService.generateThumbOnly: Thumb hochgeladen: $thumbUrl',
        );
      }

      // NUR thumbUrl und aspectRatio zurückgeben, KEIN Firestore-Update!
      return {'thumbUrl': thumbUrl, 'aspectRatio': targetAR};
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('DocThumbService.generateThumbOnly error: $e');
        print('Stack: $stackTrace');
      }
      return null;
    }
  }

  /// Generiert Thumbnail UND updated Firestore mit DELETE+SET
  static Future<Map<String, dynamic>?> generateAndStoreThumb(
    String avatarId,
    AvatarMedia media,
  ) async {
    try {
      if (kDebugMode) {
        print('DocThumbService: START für ${media.id}');
      }
      if (media.type != AvatarMediaType.document) {
        if (kDebugMode) {
          print('DocThumbService: SKIP - kein Dokument');
        }
        return null;
      }

      final bytes = await _loadPreviewBytes(media);
      if (bytes == null) {
        if (kDebugMode) {
          print('DocThumbService: FAIL - keine Preview-Bytes');
        }
        return null;
      }
      if (kDebugMode) {
        print('DocThumbService: Preview-Bytes geladen: ${bytes.length}');
      }

      // decode
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final src = frame.image;
      final srcW = src.width.toDouble();
      final srcH = src.height.toDouble();
      final srcAR = srcW / srcH;
      final bool wantPortrait = srcAR < 1.0;
      final double targetAR = wantPortrait ? (9 / 16) : (16 / 9);

      // crop cover
      double cropW, cropH;
      if (srcAR > targetAR) {
        cropH = srcH;
        cropW = cropH * targetAR;
      } else {
        cropW = srcW;
        cropH = cropW / targetAR;
      }
      final cropLeft = ((srcW - cropW) / 2).clamp(0, srcW);
      final cropTop = ((srcH - cropH) / 2).clamp(0, srcH);

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final dstRect = ui.Rect.fromLTWH(
        0,
        0,
        cropW.toDouble(),
        cropH.toDouble(),
      );
      final srcRect = ui.Rect.fromLTWH(
        cropLeft.toDouble(),
        cropTop.toDouble(),
        cropW.toDouble(),
        cropH.toDouble(),
      );
      final paint = ui.Paint();
      canvas.drawImageRect(src, srcRect, dstRect, paint);
      final cropped = await recorder.endRecording().toImage(
        cropW.toInt(),
        cropH.toInt(),
      );
      final byteData = await cropped.toByteData(format: ui.ImageByteFormat.png);
      final out = byteData!.buffer.asUint8List();
      src.dispose();
      cropped.dispose();

      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance.ref().child(
        'avatars/$avatarId/documents/thumbs/${media.id}_$ts.png',
      );
      final task = await ref.putData(
        out,
        SettableMetadata(contentType: 'image/png'),
      );
      final thumbUrl = await task.ref.getDownloadURL();
      if (kDebugMode) {
        print('DocThumbService: Thumb hochgeladen: $thumbUrl');
      }

      // DELETE + SET (verhindert Cloud Function onCreate-Trigger!)
      final docRef = FirebaseFirestore.instance
          .collection('avatars')
          .doc(avatarId)
          .collection('documents')
          .doc(media.id);

      // Hole alte Daten
      final oldDoc = await docRef.get();
      final oldData = oldDoc.data() ?? {};

      // DELETE
      try {
        await docRef.delete();
      } catch (_) {}

      // SET mit allen Feldern + thumbUrl + aspectRatio
      await docRef.set({
        'id': media.id,
        'avatarId': avatarId,
        'type': 'document',
        'url': oldData['url'] ?? media.url,
        'thumbUrl': thumbUrl,
        'createdAt': oldData['createdAt'] ?? media.createdAt,
        'aspectRatio': targetAR,
        if (oldData['tags'] != null) 'tags': oldData['tags'],
        if (oldData['originalFileName'] != null)
          'originalFileName': oldData['originalFileName'],
        if (oldData['isFree'] != null) 'isFree': oldData['isFree'],
        if (oldData['price'] != null) 'price': oldData['price'],
        if (oldData['currency'] != null) 'currency': oldData['currency'],
      });

      if (kDebugMode) {
        print('DocThumbService: SUCCESS - Firestore aktualisiert');
      }
      return {'thumbUrl': thumbUrl, 'aspectRatio': targetAR};
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('DocThumbService error: $e');
        print('Stack: $stackTrace');
      }
      return null;
    }
  }

  static Future<Uint8List?> _loadPreviewBytes(AvatarMedia media) async {
    try {
      final lower = (media.originalFileName ?? media.url).toLowerCase();
      if (lower.endsWith('.pdf')) {
        return _fetchPdfPreviewBytes(media.url);
      } else if (lower.endsWith('.pptx')) {
        return _fetchPptxPreviewBytes(media.url);
      } else if (lower.endsWith('.docx')) {
        return _fetchDocxPreviewBytes(media.url);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _fetchPdfPreviewBytes(String url) async {
    try {
      // Lade PDF-Bytes
      final r = await http.get(Uri.parse(url));
      if (r.statusCode != 200) return null;

      // Rendere erste Seite als Bild
      final doc = await pdf.PdfDocument.openData(r.bodyBytes);
      final page = await doc.getPage(1);
      final pageImage = await page.render(
        width: page.width.toInt(),
        height: page.height.toInt(),
      );
      await pageImage.createImageIfNotAvailable();
      final image = pageImage.imageIfAvailable!;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      await doc.dispose();

      return bytes;
    } catch (e) {
      if (kDebugMode) {
        print('_fetchPdfPreviewBytes error: $e');
      }
      return null;
    }
  }

  static Future<Uint8List?> _fetchPptxPreviewBytes(String url) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) return null;
      final archive = zip.ZipDecoder().decodeBytes(
        res.bodyBytes,
        verify: false,
      );
      final candidates = [
        'ppt/media/image1.jpeg',
        'ppt/media/image1.jpg',
        'ppt/media/image1.png',
      ];
      for (final name in candidates) {
        final f = archive.files.firstWhere(
          (af) => af.name == name,
          orElse: () => zip.ArchiveFile('', 0, null),
        );
        if (f.isFile && f.content is List<int>) {
          return Uint8List.fromList(f.content as List<int>);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _fetchDocxPreviewBytes(String url) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) return null;
      final archive = zip.ZipDecoder().decodeBytes(
        res.bodyBytes,
        verify: false,
      );
      final candidates = [
        'word/media/image1.jpeg',
        'word/media/image1.jpg',
        'word/media/image1.png',
        'word/media/image2.jpeg',
        'word/media/image2.jpg',
        'word/media/image2.png',
      ];
      for (final name in candidates) {
        final f = archive.files.firstWhere(
          (af) => af.name == name,
          orElse: () => zip.ArchiveFile('', 0, null),
        );
        if (f.isFile && f.content is List<int>) {
          return Uint8List.fromList(f.content as List<int>);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
