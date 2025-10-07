import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:archive/archive.dart' as zip;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/media_models.dart';

class DocThumbService {
  static Future<String?> generateAndStoreThumb(
    String avatarId,
    AvatarMedia media,
  ) async {
    try {
      if (media.type != AvatarMediaType.document) return null;

      final bytes = await _loadPreviewBytes(media);
      if (bytes == null) return null;

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

      await FirebaseFirestore.instance
          .collection('avatars')
          .doc(avatarId)
          .collection('media')
          .doc(media.id)
          .set({
            'thumbUrl': thumbUrl,
            'aspectRatio': targetAR,
          }, SetOptions(merge: true));

      return thumbUrl;
    } catch (e) {
      if (kDebugMode) {
        print('DocThumbService error: $e');
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
      final r = await http.get(Uri.parse(url));
      if (r.statusCode != 200) return null;
      // einfache PDF preview: viele Hosts liefern bereits eine Bildvorschau (z. B. wenn url bereits zu png führt)
      return r.bodyBytes;
    } catch (_) {
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
