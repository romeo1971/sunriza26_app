import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_player/video_player.dart';
import 'firebase_storage_service.dart';
import 'package:path/path.dart' as p;

/// Service für Video-Trimming mit Firebase Function
class VideoTrimService {
  static const String _firebaseFunctionUrl =
      'https://us-central1-sunriza26.cloudfunctions.net/trimVideo';

  /// Zeigt Trim-Dialog und trimmt Video
  /// Gibt die neue Video-URL zurück oder null bei Abbruch/Fehler
  static Future<String?> showTrimDialogAndTrim({
    required BuildContext context,
    required String videoUrl,
    required String avatarId,
    double? maxDuration,
  }) async {
    // 1. Lade Video-Dauer
    double videoDuration = 0;
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      await controller.initialize();
      videoDuration = controller.value.duration.inSeconds.toDouble();
      controller.dispose();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Fehler beim Laden des Videos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }

    // 2. Zeige Trim-Dialog
    final result = await showDialog<Map<String, double>>(
      context: context,
      builder: (ctx) => _TrimDialog(
        videoDuration: videoDuration,
        maxDuration: maxDuration ?? 10.0,
      ),
    );

    if (result == null) return null; // Abbruch

    final start = result['start']!;
    final end = result['end']!;

    // 3. Trimme Video
    return await trimVideo(
      context: context,
      videoUrl: videoUrl,
      avatarId: avatarId,
      start: start,
      end: end,
    );
  }

  /// Trimmt ein Video und lädt es zu Firebase hoch
  static Future<String?> trimVideo({
    required BuildContext context,
    required String videoUrl,
    required String avatarId,
    required double start,
    required double end,
  }) async {
    String? newVideoUrl;

    try {
      // Loading Dialog anzeigen
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('⏳ Video wird getrimmt...'),
                SizedBox(height: 8),
                Text(
                  'Dies kann 10-30 Sekunden dauern',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      }

      // Firebase Function aufrufen
      final trimResponse = await http
          .post(
            Uri.parse(_firebaseFunctionUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'video_url': videoUrl,
              'start_time': start,
              'end_time': end,
            }),
          )
          .timeout(const Duration(seconds: 240));

      if (trimResponse.statusCode != 200) {
        String errorMessage = 'Backend-Fehler';
        try {
          final errorData = jsonDecode(trimResponse.body);
          errorMessage = errorData['detail'] ?? 'Backend-Fehler';
        } catch (e) {
          errorMessage = 'Backend-Fehler: ${trimResponse.statusCode}';
        }
        throw Exception(errorMessage);
      }

      debugPrint('✅ Video getrimmt, speichere...');

      // Temporäre Datei erstellen
      final tempDir = await getTemporaryDirectory();
      final outputFile = File(
        '${tempDir.path}/trimmed_${DateTime.now().millisecondsSinceEpoch}.mp4',
      );

      await outputFile.writeAsBytes(trimResponse.bodyBytes);
      debugPrint('💾 Video gespeichert: ${outputFile.path}');

      // Getrimmtes Video zu Firebase hochladen
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storagePath = 'avatars/$avatarId/videos/${timestamp}_trimmed.mp4';

      newVideoUrl = await FirebaseStorageService.uploadVideo(
        outputFile,
        customPath: storagePath,
      );

      if (newVideoUrl == null) {
        throw Exception('Upload fehlgeschlagen');
      }

      // Erstelle Firestore Video-Dokument für Thumbnail-Generierung
      try {
        final mediaId = 'trimmed_${DateTime.now().millisecondsSinceEpoch}';
        await FirebaseFirestore.instance
            .collection('avatars')
            .doc(avatarId)
            .collection('videos')
            .doc(mediaId)
            .set({
              'url': newVideoUrl,
              'type': 'video',
              'createdAt': FieldValue.serverTimestamp(),
              'aspectRatio': 16 / 9,
            });
        debugPrint(
          '✅ Firestore Video-Dokument erstellt für Thumbnail-Generierung',
        );
      } catch (e) {
        debugPrint('⚠️ Fehler beim Erstellen Video-Dokument: $e');
      }

      // Cleanup temp file
      try {
        await outputFile.delete();
      } catch (_) {}

      // Close loading dialog
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Video getrimmt!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      return newVideoUrl;
    } catch (e) {
      debugPrint('❌ Trim Fehler: $e');

      // CLEANUP bei Fehler
      if (newVideoUrl != null) {
        try {
          debugPrint('🧹 ROLLBACK: Lösche neues Video wegen Fehler');
          await FirebaseStorageService.deleteFile(newVideoUrl);

          // Lösche Firestore Video-Dokument falls erstellt
          final qs = await FirebaseFirestore.instance
              .collection('avatars')
              .doc(avatarId)
              .collection('videos')
              .where('url', isEqualTo: newVideoUrl)
              .get();
          for (final d in qs.docs) {
            await d.reference.delete();
            debugPrint('🧹 ROLLBACK: Firestore Video-Doc gelöscht: ${d.id}');
          }

          debugPrint('✅ ROLLBACK komplett');
        } catch (cleanupError) {
          debugPrint('⚠️ ROLLBACK Fehler: $cleanupError');
        }
      }

      // Close loading dialog
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Fehler beim Trimmen: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }

      return null;
    }
  }

  /// Löscht ein Video komplett (Storage + Thumbnails + Firestore)
  static Future<void> deleteVideo({
    required String videoUrl,
    required String avatarId,
  }) async {
    try {
      debugPrint('🗑️ Lösche Video: $videoUrl');
      await FirebaseStorageService.deleteFile(videoUrl);

      // Lösche Video-Thumbnails
      final originalPath = FirebaseStorageService.pathFromUrl(videoUrl);
      if (originalPath.isNotEmpty) {
        final dir = p.dirname(originalPath);
        final base = p.basenameWithoutExtension(originalPath);
        final prefix = '$dir/thumbs/${base}_';
        debugPrint('🗑️ Lösche Video-Thumbs: $prefix');
        await FirebaseStorageService.deleteByPrefix(prefix);
      }

      // Lösche Firestore Video-Dokument
      final qs = await FirebaseFirestore.instance
          .collection('avatars')
          .doc(avatarId)
          .collection('videos')
          .where('url', isEqualTo: videoUrl)
          .get();
      for (final d in qs.docs) {
        await d.reference.delete();
        debugPrint('🗑️ Firestore Video-Doc gelöscht: ${d.id}');
      }

      debugPrint('✅ Video komplett gelöscht');
    } catch (e) {
      debugPrint('⚠️ Fehler beim Löschen des Videos: $e');
      rethrow;
    }
  }
}

/// Dialog für Video-Trimming
class _TrimDialog extends StatefulWidget {
  final double videoDuration;
  final double maxDuration;

  const _TrimDialog({required this.videoDuration, required this.maxDuration});

  @override
  State<_TrimDialog> createState() => _TrimDialogState();
}

class _TrimDialogState extends State<_TrimDialog> {
  late double _start;
  late double _end;

  @override
  void initState() {
    super.initState();
    _start = 0;
    _end = widget.videoDuration.clamp(0, widget.maxDuration);
  }

  @override
  Widget build(BuildContext context) {
    final duration = _end - _start;

    return AlertDialog(
      title: const Text('⏱️ Video trimmen'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Video-Länge: ${widget.videoDuration.toStringAsFixed(1)}s\n'
            'Max. erlaubt: ${widget.maxDuration.toStringAsFixed(1)}s',
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          Text('Start: ${_start.toStringAsFixed(1)}s'),
          Slider(
            value: _start,
            min: 0,
            max: widget.videoDuration - 0.1,
            divisions: (widget.videoDuration * 10).toInt(),
            onChanged: (value) {
              setState(() {
                _start = value;
                if (_end - _start > widget.maxDuration) {
                  _end = (_start + widget.maxDuration).clamp(
                    0,
                    widget.videoDuration,
                  );
                }
                if (_end <= _start) {
                  _end = (_start + 0.1).clamp(0, widget.videoDuration);
                }
              });
            },
          ),
          const SizedBox(height: 8),
          Text('Ende: ${_end.toStringAsFixed(1)}s'),
          Slider(
            value: _end,
            min: 0.1,
            max: widget.videoDuration,
            divisions: (widget.videoDuration * 10).toInt(),
            onChanged: (value) {
              setState(() {
                _end = value;
                if (_end - _start > widget.maxDuration) {
                  _start = (_end - widget.maxDuration).clamp(
                    0,
                    widget.videoDuration,
                  );
                }
                if (_end <= _start) {
                  _start = (_end - 0.1).clamp(0, widget.videoDuration);
                }
              });
            },
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: duration <= widget.maxDuration
                  ? Colors.green.withValues(alpha: 0.2)
                  : Colors.orange.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Dauer: ${duration.toStringAsFixed(1)}s / ${widget.maxDuration.toStringAsFixed(1)}s',
              style: TextStyle(
                color: duration <= widget.maxDuration
                    ? Colors.green
                    : Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton(
          onPressed: duration <= widget.maxDuration
              ? () => Navigator.of(context).pop({'start': _start, 'end': _end})
              : null,
          child: const Text('Trimmen'),
        ),
      ],
    );
  }
}
