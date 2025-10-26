import 'dart:typed_data';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;
import '../models/media_models.dart';

/// Service für Audio Cover Images Management
/// - Upload mit Crop (9:16 oder 16:9)
/// - Thumbnail Generation
/// - Firebase Storage: audio/{audioId}/coverImages/cover_{index}.jpg
class AudioCoverService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Upload Cover Image für Audio Asset
  Future<AudioCoverImage> uploadCoverImage({
    required String avatarId,
    required String audioId,
    required Uint8List imageBytes,
    required int index, // 0-4
    required double aspectRatio, // 9:16 oder 16:9
  }) async {
    if (index < 0 || index > 4) {
      throw ArgumentError('Index must be between 0 and 4');
    }

    // 1. Thumbnail generieren (200x300 für 9:16 oder 300x200 für 16:9)
    final thumbBytes = await _generateThumbnail(imageBytes, aspectRatio);

    // 2. Storage Paths (neues Schema)
    final oneBased = index + 1; // 1..5
    final storagePath = 'avatars/$avatarId/audio/$audioId/coverImages/image$oneBased.jpg';
    final thumbStoragePath = 'avatars/$avatarId/audio/$audioId/coverImages/thumbs/thumb$oneBased.jpg';

    // 3. Upload Full Image (direkt aus Bytes)
    final ref = _storage.ref().child(storagePath);
    await ref.putData(
      imageBytes,
      SettableMetadata(
        contentType: 'image/jpeg',
        contentDisposition: 'attachment; filename="image$oneBased.jpg"',
        customMetadata: {
          'aspectRatio': aspectRatio.toString(),
        },
      ),
    );
    final url = await ref.getDownloadURL();

    // 4. Upload Thumbnail (direkt aus Bytes)
    final thumbRef = _storage.ref().child(thumbStoragePath);
    await thumbRef.putData(
      thumbBytes,
      SettableMetadata(
        contentType: 'image/jpeg',
        contentDisposition: 'attachment; filename="thumb$oneBased.jpg"',
        customMetadata: {
          'aspectRatio': aspectRatio.toString(),
        },
      ),
    );
    final thumbUrl = await thumbRef.getDownloadURL();

    // 5. Return AudioCoverImage Object
    return AudioCoverImage(
      url: url,
      thumbUrl: thumbUrl,
      aspectRatio: aspectRatio,
      index: index,
    );
  }

  /// Thumbnail generieren (200x300 oder 300x200)
  Future<Uint8List> _generateThumbnail(Uint8List imageBytes, double aspectRatio) async {
    final image = img.decodeImage(imageBytes);
    if (image == null) throw Exception('Invalid image data');

    final isPortrait = aspectRatio < 1.0; // 9:16
    final targetWidth = isPortrait ? 200 : 300;
    final targetHeight = isPortrait ? 300 : 200;

    final thumbnail = img.copyResize(
      image,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.linear,
    );

    return Uint8List.fromList(img.encodeJpg(thumbnail, quality: 85));
  }

  /// Delete Cover Image
  Future<void> deleteCoverImage({
    required String avatarId,
    required String audioId,
    required int index,
    String? audioUrl, // optional für Timestamp-Pfad
  }) async {
    final oneBased = index + 1;

    // Versuche in drei Varianten zu löschen: Timestamp, audioId, Old-Path
    // 1) Timestamp (aus URL extrahieren)
    String? timestamp;
    if (audioUrl != null) {
      final m = RegExp(r'/audio/(\d+)').firstMatch(audioUrl);
      if (m != null) timestamp = m.group(1);
    }

    Future<void> _tryDelete(String path) async {
      final ref = _storage.ref().child(path);
      try {
        await ref.delete();
      } catch (_) {}
    }

    if (timestamp != null) {
      await _tryDelete('avatars/$avatarId/audio/$timestamp/coverImages/image$oneBased.jpg');
      await _tryDelete('avatars/$avatarId/audio/$timestamp/coverImages/thumbs/thumb$oneBased.jpg');
    }

    // 2) Neuer Pfad (audioId)
    await _tryDelete('avatars/$avatarId/audio/$audioId/coverImages/image$oneBased.jpg');
    await _tryDelete('avatars/$avatarId/audio/$audioId/coverImages/thumbs/thumb$oneBased.jpg');

    // 3) Alter Pfad ohne avatarId
    await _tryDelete('audio/$audioId/coverImages/image$oneBased.jpg');
    await _tryDelete('audio/$audioId/coverImages/thumbs/thumb$oneBased.jpg');
  }

  /// Lädt Cover Images aus Firebase Storage
  /// Sucht in mehreren möglichen Pfaden (neues Schema, altes Schema, timestamp-basiert)
  Future<List<AudioCoverImage>> getCoverImages({
    required String avatarId,
    required String audioId,
    String? audioUrl, // Optional: Audio-URL um Timestamp zu extrahieren
  }) async {
    final List<AudioCoverImage> coverImages = [];
    
    try {
      debugPrint('🔍 getCoverImages from Storage: avatarId=$avatarId, audioId=$audioId');
      if (audioUrl != null) debugPrint('🔍 audioUrl: $audioUrl');
      
      // Extrahiere Timestamp aus Audio-URL (falls vorhanden)
      String? timestamp;
      if (audioUrl != null) {
        final match = RegExp(r'/audio/(\d+)').firstMatch(audioUrl);
        if (match != null) {
          timestamp = match.group(1);
          debugPrint('🔍 Extracted timestamp from audioUrl: $timestamp');
        }
      }
      
      // Prüfe alle 5 möglichen Slots (1-5)
      for (int i = 1; i <= 5; i++) {
        try {
          String? imageUrl;
          String? thumbUrl;
          Reference? imageRef;
          
          // Versuch 1: Timestamp-basierter Pfad (aus audioUrl extrahiert)
          if (timestamp != null) {
            try {
              final imagePath = 'avatars/$avatarId/audio/$timestamp/coverImages/image$i.jpg';
              final thumbPath = 'avatars/$avatarId/audio/$timestamp/coverImages/thumbs/thumb$i.jpg';
              
              imageRef = _storage.ref().child(imagePath);
              final thumbRef = _storage.ref().child(thumbPath);
              
              imageUrl = await imageRef.getDownloadURL();
              thumbUrl = await thumbRef.getDownloadURL();
              debugPrint('✅ Found at TIMESTAMP path: $imagePath');
            } catch (e) {
              debugPrint('⚠️ Not found at timestamp path ($timestamp)');
            }
          }
          
          // Versuch 2: Neuer Pfad mit audioId
          if (imageUrl == null) {
            try {
              final imagePath = 'avatars/$avatarId/audio/$audioId/coverImages/image$i.jpg';
              final thumbPath = 'avatars/$avatarId/audio/$audioId/coverImages/thumbs/thumb$i.jpg';
              
              imageRef = _storage.ref().child(imagePath);
              final thumbRef = _storage.ref().child(thumbPath);
              
              imageUrl = await imageRef.getDownloadURL();
              thumbUrl = await thumbRef.getDownloadURL();
              debugPrint('✅ Found at AUDIO_ID path: $imagePath');
            } catch (e) {
              debugPrint('⚠️ Not found at audioId path');
            }
          }
          
          // Versuch 3: Alter Pfad ohne avatarId
          if (imageUrl == null) {
            try {
              final imagePath = 'audio/$audioId/coverImages/image$i.jpg';
              final thumbPath = 'audio/$audioId/coverImages/thumbs/thumb$i.jpg';
              
              imageRef = _storage.ref().child(imagePath);
              final thumbRef = _storage.ref().child(thumbPath);
              
              imageUrl = await imageRef.getDownloadURL();
              thumbUrl = await thumbRef.getDownloadURL();
              debugPrint('✅ Found at OLD path: $imagePath');
            } catch (e) {
              debugPrint('⚪ Not found at any path for slot $i');
            }
          }
          
          // Wenn gefunden, füge zur Liste hinzu
          if (imageUrl != null && thumbUrl != null && imageRef != null) {
            // Hole Metadata für Aspect Ratio (falls gespeichert)
            final metadata = await imageRef.getMetadata();
            double aspectRatio = 16 / 9; // Default
            
            if (metadata.customMetadata != null && metadata.customMetadata!.containsKey('aspectRatio')) {
              aspectRatio = double.tryParse(metadata.customMetadata!['aspectRatio'] ?? '1.777') ?? 16 / 9;
            }
            
            coverImages.add(AudioCoverImage(
              url: imageUrl,
              thumbUrl: thumbUrl,
              aspectRatio: aspectRatio,
              index: i - 1, // 0-based index
            ));
            
            debugPrint('✅ Loaded cover image at slot $i (index ${i - 1})');
          }
        } catch (e) {
          debugPrint('❌ Error loading slot $i: $e');
        }
      }
      
      debugPrint('📸 Loaded ${coverImages.length} cover images from Storage');
      return coverImages;
    } catch (e) {
      debugPrint('❌ Error loading cover images from Storage: $e');
      return [];
    }
  }

  /// Update Audio Media mit Cover Images Array
  Future<void> updateAudioCoverImages({
    required String avatarId,
    required String audioId,
    required List<AudioCoverImage> coverImages,
  }) async {
    try {
      await _firestore
          .collection('avatars')
          .doc(avatarId)
          .collection('media')
          .doc(audioId)
          .set({
        'coverImages': coverImages.map((e) => e.toMap()).toList(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('⚠️ Firestore update failed (permission or doc missing): $e');
      // Ignoriere Firestore-Fehler, Storage ist die Source of Truth
    }
  }

  /// Entferne Cover Image aus Array und lösche aus Storage
  Future<void> removeCoverImage({
    required String avatarId,
    required String audioId,
    required AvatarMedia audioMedia,
    required int index,
  }) async {
    // 1. Delete from Storage
    await deleteCoverImage(
      avatarId: avatarId,
      audioId: audioId,
      index: index,
    );

    // 2. Remove from Array und reindex
    final updatedImages = <AudioCoverImage>[];
    if (audioMedia.coverImages != null) {
      for (var img in audioMedia.coverImages!) {
        if (img.index != index) {
          // Reindex: Wenn index > removed index, dann index--
          final newIndex = img.index > index ? img.index - 1 : img.index;
          updatedImages.add(AudioCoverImage(
            url: img.url,
            thumbUrl: img.thumbUrl,
            aspectRatio: img.aspectRatio,
            index: newIndex,
          ));
        }
      }
    }

    // 3. Update Firestore
    await updateAudioCoverImages(
      avatarId: avatarId,
      audioId: audioId,
      coverImages: updatedImages,
    );
  }

  void debugPrint(String message) {
    // ignore: avoid_print
    print(message);
  }
}

