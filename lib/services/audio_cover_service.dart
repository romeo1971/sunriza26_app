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

    // 1. Temp-Datei erstellen
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempPath = p.join(dir.path, 'audio_cover_${timestamp}_$index.jpg');
    final tempFile = File(tempPath);
    await tempFile.writeAsBytes(imageBytes, flush: true);

    // 2. Thumbnail generieren (200x300 für 9:16 oder 300x200 für 16:9)
    final thumbBytes = await _generateThumbnail(imageBytes, aspectRatio);
    final thumbPath = p.join(dir.path, 'audio_cover_${timestamp}_${index}_thumb.jpg');
    final thumbFile = File(thumbPath);
    await thumbFile.writeAsBytes(thumbBytes, flush: true);

    // 3. Storage Paths
    final storagePath = 'avatars/$avatarId/audio/$audioId/coverImages/cover_$index.jpg';
    final thumbStoragePath = 'avatars/$avatarId/audio/$audioId/coverImages/cover_${index}_thumb.jpg';

    // 4. Upload Full Image
    final ref = _storage.ref().child(storagePath);
    await ref.putFile(
      tempFile,
      SettableMetadata(
        contentType: 'image/jpeg',
        contentDisposition: 'attachment; filename="cover_$index.jpg"',
      ),
    );
    final url = await ref.getDownloadURL();

    // 5. Upload Thumbnail
    final thumbRef = _storage.ref().child(thumbStoragePath);
    await thumbRef.putFile(
      thumbFile,
      SettableMetadata(
        contentType: 'image/jpeg',
        contentDisposition: 'attachment; filename="cover_${index}_thumb.jpg"',
      ),
    );
    final thumbUrl = await thumbRef.getDownloadURL();

    // 6. Cleanup Temp Files
    try {
      await tempFile.delete();
      await thumbFile.delete();
    } catch (_) {}

    // 7. Return AudioCoverImage Object
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
  }) async {
    // Delete Full Image
    final storagePath = 'avatars/$avatarId/audio/$audioId/coverImages/cover_$index.jpg';
    final ref = _storage.ref().child(storagePath);
    try {
      await ref.delete();
    } catch (e) {
      // Ignore if file doesn't exist
      debugPrint('Failed to delete cover image: $e');
    }

    // Delete Thumbnail
    final thumbStoragePath = 'avatars/$avatarId/audio/$audioId/coverImages/cover_${index}_thumb.jpg';
    final thumbRef = _storage.ref().child(thumbStoragePath);
    try {
      await thumbRef.delete();
    } catch (e) {
      // Ignore if file doesn't exist
      debugPrint('Failed to delete cover thumbnail: $e');
    }
  }

  /// Update Audio Media mit Cover Images Array
  Future<void> updateAudioCoverImages({
    required String avatarId,
    required String audioId,
    required List<AudioCoverImage> coverImages,
  }) async {
    await _firestore
        .collection('avatars')
        .doc(avatarId)
        .collection('media')
        .doc(audioId)
        .update({
      'coverImages': coverImages.map((e) => e.toMap()).toList(),
    });
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

