/// Media Upload Widget für Veo 3 Training
/// Stand: 04.09.2025 - Upload von Bildern und Videos für AI-Training

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/media_upload_service.dart';

class MediaUploadWidget extends StatefulWidget {
  final UploadType uploadType;
  final Function(UploadResult)? onUploadComplete;
  final Function(double)? onProgress;

  const MediaUploadWidget({
    super.key,
    required this.uploadType,
    this.onUploadComplete,
    this.onProgress,
  });

  @override
  State<MediaUploadWidget> createState() => _MediaUploadWidgetState();
}

class _MediaUploadWidgetState extends State<MediaUploadWidget> {
  final MediaUploadService _uploadService = MediaUploadService();
  UploadStatus _status = UploadStatus.idle;
  double _progress = 0.0;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                _getIconForType(widget.uploadType),
                color: Theme.of(context).colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _getTitleForType(widget.uploadType),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_status == UploadStatus.uploading)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: _progress,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Beschreibung
          Text(
            _getDescriptionForType(widget.uploadType),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 16),

          // Upload-Buttons
          if (_status == UploadStatus.idle) ...[
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _uploadImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Bild auswählen'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _uploadImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Foto aufnehmen'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.secondary,
                      foregroundColor: Theme.of(
                        context,
                      ).colorScheme.onSecondary,
                    ),
                  ),
                ),
              ],
            ),

            if (_supportsVideo(widget.uploadType)) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _uploadVideo(ImageSource.gallery),
                      icon: const Icon(Icons.video_library),
                      label: const Text('Video auswählen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _uploadVideo(ImageSource.camera),
                      icon: const Icon(Icons.videocam),
                      label: const Text('Video aufnehmen'),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _uploadMultipleFiles,
                icon: const Icon(Icons.upload_file),
                label: const Text('Mehrere Dateien hochladen'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],

          // Progress-Anzeige
          if (_status == UploadStatus.uploading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _progress,
              backgroundColor: Theme.of(context).colorScheme.surface,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Upload: ${(_progress * 100).toInt()}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],

          // Fehler-Anzeige
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red[700], fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Erfolg-Anzeige
          if (_status == UploadStatus.completed) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Upload erfolgreich abgeschlossen!',
                      style: TextStyle(
                        color: Colors.green[700],
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Upload-Bild
  Future<void> _uploadImage(ImageSource source) async {
    setState(() {
      _status = UploadStatus.uploading;
      _progress = 0.0;
      _errorMessage = null;
    });

    try {
      final result = await _uploadService.uploadImage(
        type: widget.uploadType,
        source: source,
        onProgress: (progress) {
          setState(() {
            _progress = progress;
          });
          widget.onProgress?.call(progress);
        },
      );

      setState(() {
        _status = result.success ? UploadStatus.completed : UploadStatus.error;
        _errorMessage = result.error;
      });

      widget.onUploadComplete?.call(result);
    } catch (e) {
      setState(() {
        _status = UploadStatus.error;
        _errorMessage = 'Upload fehlgeschlagen: $e';
      });
    }
  }

  /// Upload-Video
  Future<void> _uploadVideo(ImageSource source) async {
    setState(() {
      _status = UploadStatus.uploading;
      _progress = 0.0;
      _errorMessage = null;
    });

    try {
      final result = await _uploadService.uploadVideo(
        type: widget.uploadType,
        source: source,
        onProgress: (progress) {
          setState(() {
            _progress = progress;
          });
          widget.onProgress?.call(progress);
        },
      );

      setState(() {
        _status = result.success ? UploadStatus.completed : UploadStatus.error;
        _errorMessage = result.error;
      });

      widget.onUploadComplete?.call(result);
    } catch (e) {
      setState(() {
        _status = UploadStatus.error;
        _errorMessage = 'Upload fehlgeschlagen: $e';
      });
    }
  }

  /// Upload mehrerer Dateien
  Future<void> _uploadMultipleFiles() async {
    setState(() {
      _status = UploadStatus.uploading;
      _progress = 0.0;
      _errorMessage = null;
    });

    try {
      final results = await _uploadService.uploadMultipleFiles(
        type: widget.uploadType,
        onProgress: (progress) {
          setState(() {
            _progress = progress;
          });
          widget.onProgress?.call(progress);
        },
      );

      final successCount = results.where((r) => r.success).length;
      final errorCount = results.where((r) => !r.success).length;

      setState(() {
        _status = UploadStatus.completed;
        _errorMessage = errorCount > 0
            ? '$successCount erfolgreich, $errorCount Fehler'
            : null;
      });

      // Erste erfolgreiche Upload-Result weiterleiten
      final firstSuccess = results.firstWhere(
        (r) => r.success,
        orElse: () => results.first,
      );
      widget.onUploadComplete?.call(firstSuccess);
    } catch (e) {
      setState(() {
        _status = UploadStatus.error;
        _errorMessage = 'Multi-Upload fehlgeschlagen: $e';
      });
    }
  }

  /// Prüft ob Video-Upload unterstützt wird
  bool _supportsVideo(UploadType type) {
    return type == UploadType.referenceVideo ||
        type == UploadType.trainingVideos;
  }

  /// Icon für Upload-Typ
  IconData _getIconForType(UploadType type) {
    switch (type) {
      case UploadType.referenceVideo:
        return Icons.video_camera_back;
      case UploadType.trainingImages:
        return Icons.photo_library;
      case UploadType.trainingVideos:
        return Icons.movie;
      case UploadType.customVoice:
        return Icons.mic;
    }
  }

  /// Titel für Upload-Typ
  String _getTitleForType(UploadType type) {
    switch (type) {
      case UploadType.referenceVideo:
        return 'Referenzvideo';
      case UploadType.trainingImages:
        return 'Training-Bilder';
      case UploadType.trainingVideos:
        return 'Training-Videos';
      case UploadType.customVoice:
        return 'Voice-Training';
    }
  }

  /// Beschreibung für Upload-Typ
  String _getDescriptionForType(UploadType type) {
    switch (type) {
      case UploadType.referenceVideo:
        return 'Laden Sie ein Referenzvideo hoch, das für die Lippen-Synchronisation verwendet wird. Empfohlen: 3-5 Minuten, HD-Qualität.';
      case UploadType.trainingImages:
        return 'Laden Sie Bilder hoch, um Veo 3 zu trainieren. Empfohlen: Hochauflösende Bilder (512x512px), verschiedene Perspektiven.';
      case UploadType.trainingVideos:
        return 'Laden Sie Videos hoch, um Veo 3 zu trainieren. Empfohlen: Kurze Clips (1-3 Minuten), stabile Aufnahmen.';
      case UploadType.customVoice:
        return 'Laden Sie Audio-Aufnahmen hoch, um Ihre Custom Voice zu trainieren. Empfohlen: 30+ Minuten klare Sprache.';
    }
  }
}
