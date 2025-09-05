/// Media Upload Service für Veo 3 Training
/// Stand: 04.09.2025 - Upload von Bildern und Videos für AI-Training

import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:image/image.dart' as img;

/// Upload-Typen für verschiedene AI-Modelle
enum UploadType {
  referenceVideo, // Referenzvideo für Lippen-Synchronisation
  trainingImages, // Bilder für Veo 3 Training
  trainingVideos, // Videos für Veo 3 Training
  customVoice, // Audio für Custom Voice Training
}

/// Upload-Status
enum UploadStatus { idle, selecting, uploading, processing, completed, error }

/// Upload-Resultat
class UploadResult {
  final bool success;
  final String? downloadUrl;
  final String? filePath;
  final String? error;
  final Map<String, dynamic>? metadata;

  UploadResult({
    required this.success,
    this.downloadUrl,
    this.filePath,
    this.error,
    this.metadata,
  });
}

class MediaUploadService {
  static final MediaUploadService _instance = MediaUploadService._internal();
  factory MediaUploadService() => _instance;
  MediaUploadService._internal();

  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _imagePicker = ImagePicker();

  /// Wählt und lädt ein Bild hoch
  Future<UploadResult> uploadImage({
    required UploadType type,
    ImageSource source = ImageSource.gallery,
    Function(double)? onProgress,
  }) async {
    try {
      onProgress?.call(0.1);

      // Bild auswählen
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 90,
      );

      if (image == null) {
        return UploadResult(success: false, error: 'Kein Bild ausgewählt');
      }

      onProgress?.call(0.3);

      // Bild verarbeiten
      final processedImage = await _processImage(File(image.path));
      onProgress?.call(0.5);

      // Upload-Pfad generieren
      final uploadPath = _generateUploadPath(type, 'image', image.name);

      // Upload zu Firebase Storage
      final ref = _storage.ref().child(uploadPath);
      final uploadTask = ref.putFile(processedImage);

      // Progress-Listener
      uploadTask.snapshotEvents.listen((snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        onProgress?.call(0.5 + (progress * 0.4));
      });

      // Upload abschließen
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      onProgress?.call(0.9);

      // Metadaten sammeln
      final metadata = await _generateImageMetadata(processedImage);

      onProgress?.call(1.0);

      return UploadResult(
        success: true,
        downloadUrl: downloadUrl,
        filePath: uploadPath,
        metadata: metadata,
      );
    } catch (e) {
      return UploadResult(
        success: false,
        error: 'Bild-Upload fehlgeschlagen: $e',
      );
    }
  }

  /// Wählt und lädt ein Video hoch
  Future<UploadResult> uploadVideo({
    required UploadType type,
    ImageSource source = ImageSource.gallery,
    Function(double)? onProgress,
  }) async {
    try {
      onProgress?.call(0.1);

      // Video auswählen
      final XFile? video = await _imagePicker.pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 10), // Max 10 Minuten für Training
      );

      if (video == null) {
        return UploadResult(success: false, error: 'Kein Video ausgewählt');
      }

      onProgress?.call(0.2);

      // Video-Thumbnail generieren
      final thumbnail = await _generateVideoThumbnail(video.path);
      onProgress?.call(0.3);

      // Upload-Pfad generieren
      final uploadPath = _generateUploadPath(type, 'video', video.name);

      // Upload zu Firebase Storage
      final ref = _storage.ref().child(uploadPath);
      final uploadTask = ref.putFile(File(video.path));

      // Progress-Listener
      uploadTask.snapshotEvents.listen((snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        onProgress?.call(0.3 + (progress * 0.5));
      });

      // Upload abschließen
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      onProgress?.call(0.8);

      // Metadaten sammeln
      final metadata = await _generateVideoMetadata(
        File(video.path),
        thumbnail,
      );

      onProgress?.call(1.0);

      return UploadResult(
        success: true,
        downloadUrl: downloadUrl,
        filePath: uploadPath,
        metadata: metadata,
      );
    } catch (e) {
      return UploadResult(
        success: false,
        error: 'Video-Upload fehlgeschlagen: $e',
      );
    }
  }

  /// Lädt mehrere Dateien gleichzeitig hoch
  Future<List<UploadResult>> uploadMultipleFiles({
    required UploadType type,
    Function(double)? onProgress,
  }) async {
    try {
      // Dateien auswählen
      final filePickerResult = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'mp4', 'mov', 'avi'],
      );

      if (filePickerResult == null || filePickerResult.files.isEmpty) {
        return [
          UploadResult(success: false, error: 'Keine Dateien ausgewählt'),
        ];
      }

      final results = <UploadResult>[];
      final totalFiles = filePickerResult.files.length;

      for (int i = 0; i < totalFiles; i++) {
        final file = filePickerResult.files[i];
        final filePath = file.path;

        if (filePath == null) continue;

        // Progress für diese Datei
        final fileProgress = (i / totalFiles) + (1 / totalFiles);
        onProgress?.call(fileProgress * 0.8);

        // Datei-Typ bestimmen
        final isVideo =
            file.extension?.toLowerCase() == 'mp4' ||
            file.extension?.toLowerCase() == 'mov' ||
            file.extension?.toLowerCase() == 'avi';

        UploadResult result;
        if (isVideo) {
          result = await _uploadVideoFile(File(filePath), type);
        } else {
          result = await _uploadImageFile(File(filePath), type);
        }

        results.add(result);
      }

      onProgress?.call(1.0);
      return results;
    } catch (e) {
      return [
        UploadResult(success: false, error: 'Multi-Upload fehlgeschlagen: $e'),
      ];
    }
  }

  /// Verarbeitet Bild für AI-Training
  Future<File> _processImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final image = img.decodeImage(bytes);

    if (image == null) throw Exception('Bild konnte nicht verarbeitet werden');

    // Bild für AI-Training optimieren
    final processed = img.copyResize(
      image,
      width: 512, // Veo 3 Standard-Auflösung
      height: 512,
      interpolation: img.Interpolation.cubic,
    );

    // Qualität optimieren
    final processedBytes = img.encodeJpg(processed, quality: 95);

    // Temporäre Datei erstellen
    final tempFile = File('${imageFile.path}_processed.jpg');
    await tempFile.writeAsBytes(processedBytes);

    return tempFile;
  }

  /// Generiert Video-Thumbnail
  Future<Uint8List?> _generateVideoThumbnail(String videoPath) async {
    try {
      return await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 512,
        quality: 75,
      );
    } catch (e) {
      print('Thumbnail-Generierung fehlgeschlagen: $e');
      return null;
    }
  }

  /// Generiert Upload-Pfad
  String _generateUploadPath(
    UploadType type,
    String fileType,
    String fileName,
  ) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final folder = _getFolderForType(type);
    return '$folder/${timestamp}_$fileName';
  }

  /// Ordner für Upload-Typ
  String _getFolderForType(UploadType type) {
    switch (type) {
      case UploadType.referenceVideo:
        return 'reference-videos';
      case UploadType.trainingImages:
        return 'training/images';
      case UploadType.trainingVideos:
        return 'training/videos';
      case UploadType.customVoice:
        return 'voice-training';
    }
  }

  /// Generiert Bild-Metadaten
  Future<Map<String, dynamic>> _generateImageMetadata(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final image = img.decodeImage(bytes);

    return {
      'type': 'image',
      'width': image?.width ?? 0,
      'height': image?.height ?? 0,
      'size': bytes.length,
      'format': 'jpg',
      'uploadedAt': DateTime.now().toIso8601String(),
    };
  }

  /// Generiert Video-Metadaten
  Future<Map<String, dynamic>> _generateVideoMetadata(
    File videoFile,
    Uint8List? thumbnail,
  ) async {
    final stat = await videoFile.stat();

    return {
      'type': 'video',
      'size': stat.size,
      'format': 'mp4',
      'hasThumbnail': thumbnail != null,
      'uploadedAt': DateTime.now().toIso8601String(),
    };
  }

  /// Upload einzelner Datei (Helper)
  Future<UploadResult> _uploadImageFile(File file, UploadType type) async {
    try {
      final processedImage = await _processImage(file);
      final uploadPath = _generateUploadPath(
        type,
        'image',
        file.path.split('/').last,
      );

      final ref = _storage.ref().child(uploadPath);
      final snapshot = await ref.putFile(processedImage);
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return UploadResult(
        success: true,
        downloadUrl: downloadUrl,
        filePath: uploadPath,
      );
    } catch (e) {
      return UploadResult(success: false, error: e.toString());
    }
  }

  /// Upload einzelner Video-Datei (Helper)
  Future<UploadResult> _uploadVideoFile(File file, UploadType type) async {
    try {
      final uploadPath = _generateUploadPath(
        type,
        'video',
        file.path.split('/').last,
      );

      final ref = _storage.ref().child(uploadPath);
      final snapshot = await ref.putFile(file);
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return UploadResult(
        success: true,
        downloadUrl: downloadUrl,
        filePath: uploadPath,
      );
    } catch (e) {
      return UploadResult(success: false, error: e.toString());
    }
  }
}
