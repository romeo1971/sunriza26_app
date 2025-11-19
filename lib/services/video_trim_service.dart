import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_theme.dart';
import 'firebase_storage_service.dart';
import 'env_service.dart';
import 'package:path/path.dart' as p;

/// Service für Video-Trimming mit Firebase Function
class VideoTrimService {
  static String _firebaseFunctionUrl() {
    return '${EnvService.cloudFunctionsBaseUrl()}/trimVideo';
  }
  // Globaler Fortschritt für Trim+Upload (0–100), für alle Plattformen
  static final ValueNotifier<int> trimProgress = ValueNotifier<int>(0);

  /// Zeigt Trim-Dialog und trimmt Video
  /// Gibt die neue Video-URL zurück oder null bei Abbruch/Fehler
  static Future<String?> showTrimDialogAndTrim({
    required BuildContext context,
    required String videoUrl,
    required String avatarId,
    double? maxDuration,
  }) async {
    // Verwende lokalen Messenger statt BuildContext nach async Gaps
    final messenger = ScaffoldMessenger.maybeOf(context);

    // Bereits getrimmte Videos (Dateiname enthält _trim) nur einmal erlauben
    if (videoUrl.contains('_trim')) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Dieses Video wurde bereits getrimmt. Bitte das Original erneut hochladen, um es weiter anzupassen.',
          ),
        ),
      );
      return null;
    }
    // 1. Lade Video-Dauer
    double videoDuration = 0;
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      await controller.initialize();
      videoDuration = controller.value.duration.inSeconds.toDouble();
      controller.dispose();
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text('❌ Fehler beim Laden des Videos: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }

    // 2. Zeige Trim-Dialog (reine Bereichsauswahl, ohne Progress)
    if (!context.mounted) return null;

    final result = await showDialog<Map<String, double>>(
      context: context,
      builder: (ctx) => _TrimDialog(
        videoDuration: videoDuration,
        maxDuration: maxDuration ?? videoDuration,
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
    // BuildContext nicht über async Gaps verwenden → vorab Handles sichern
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);

    try {
      // Progress zurücksetzen und Loading Dialog anzeigen
      trimProgress.value = 0;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('⏳ Video wird getrimmt...'),
              const SizedBox(height: 8),
              const Text(
                'Dies kann 10–30 Sekunden dauern.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<int>(
                valueListenable: trimProgress,
                builder: (context, value, _) {
                  final safe = value.clamp(0, 100);
                  return Column(
                    children: [
                      LinearProgressIndicator(
                        value: safe / 100.0,
                        backgroundColor: Colors.grey.shade800,
                        color: AppColors.lightBlue,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$safe %',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      );

      // Firebase Function aufrufen
      final trimResponse = await http
          .post(
            Uri.parse(_firebaseFunctionUrl()),
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

      // Getrimmtes Video direkt aus Bytes zu Firebase hochladen (plattformunabhängig, auch Web)
      final trimmedBytes = trimResponse.bodyBytes;
      debugPrint(
        '💾 Getrimmtes Video-Bytes erhalten: ${trimmedBytes.lengthInBytes} bytes',
      );

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storagePath = 'avatars/$avatarId/videos/${timestamp}_trimmed.mp4';

      // Upload-Fortschritt an globalen Trim-Dialog melden
      newVideoUrl = await FirebaseStorageService.uploadVideoBytes(
        trimmedBytes,
        fileName: 'trimmed_$timestamp.mp4',
        customPath: storagePath,
        onProgress: (p) {
          VideoTrimService.trimProgress.value =
              (p * 100).clamp(0, 100).round();
        },
      );

      if (newVideoUrl == null) {
        throw Exception('Upload fehlgeschlagen');
      }

      // Erstelle Firestore Video-Dokument für Thumbnail-Generierung
      try {
        final mediaId = 'trimmed_${DateTime.now().millisecondsSinceEpoch}';

        // Versuche Original-Video-Dokument zu finden, um originalFileName zu übernehmen
        String? trimmedOriginalFileName;
        double? originalAspectRatio;
        try {
          final qs = await FirebaseFirestore.instance
              .collection('avatars')
              .doc(avatarId)
              .collection('videos')
              .where('url', isEqualTo: videoUrl)
              .limit(1)
              .get();
          if (qs.docs.isNotEmpty) {
            final data = qs.docs.first.data();
            final origName = (data['originalFileName'] as String?) ?? '';
            originalAspectRatio =
                (data['aspectRatio'] as num?)?.toDouble();
            if (origName.isNotEmpty) {
              final dot = origName.lastIndexOf('.');
              if (dot > 0) {
                final base = origName.substring(0, dot);
                final ext = origName.substring(dot);
                trimmedOriginalFileName = '${base}_trimmed$ext';
              } else {
                trimmedOriginalFileName = '${origName}_trimmed';
              }
            }
          }
        } catch (e) {
          debugPrint('⚠️ Konnte originalFileName für Trim nicht ermitteln: $e');
        }

        final Map<String, dynamic> docData = {
          'id': mediaId,
          'avatarId': avatarId,
          'url': newVideoUrl,
          'type': 'video',
          'createdAt': FieldValue.serverTimestamp(),
          // Übernimm Aspect Ratio des Originalvideos, damit Portrait/Landscape erhalten bleibt
          'aspectRatio': originalAspectRatio ?? 16 / 9,
          'durationMs': null,
        };
        if (trimmedOriginalFileName != null) {
          docData['originalFileName'] = trimmedOriginalFileName;
        }

        final docRef = FirebaseFirestore.instance
            .collection('avatars')
            .doc(avatarId)
            .collection('videos')
            .doc(mediaId);
        await docRef.set(docData);
        debugPrint(
          '✅ Firestore Video-Dokument erstellt für Thumbnail-Generierung',
        );

        // Warte (max. ~30s) darauf, dass die Cloud Function thumbUrl gesetzt hat,
        // damit der „Video wird getrimmt…“-Dialog erst verschwindet, wenn die Kachel fertig ist.
        try {
          const maxTries = 60;
          for (var i = 0; i < maxTries; i++) {
            await Future.delayed(const Duration(milliseconds: 500));
            final snap = await docRef.get();
            final data = snap.data();
            final thumb = (data?['thumbUrl'] as String?) ?? '';
            if (thumb.isNotEmpty) {
              debugPrint(
                '🎬 trimVideo: thumbUrl gefunden, Dialog kann geschlossen werden.',
              );
              break;
            }
          }
        } catch (e) {
          debugPrint('⚠️ trimVideo: Fehler beim Warten auf thumbUrl (ignoriert): $e');
        }
      } catch (e) {
        debugPrint('⚠️ Fehler beim Erstellen Video-Dokument: $e');
      }

      // Close loading dialog
      navigator.pop();

      messenger?.showSnackBar(
        const SnackBar(
          content: Text('✅ Video getrimmt!'),
          backgroundColor: Colors.green,
        ),
      );

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
      navigator.maybePop();

      messenger?.showSnackBar(
        SnackBar(
          content: Text('❌ Fehler beim Trimmen: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );

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
    _end = widget.videoDuration;
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
            'Video-Länge: ${widget.videoDuration.toStringAsFixed(1)}s',
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 6),
          const Text(
            'Hinweis: Jedes Original-Video kann nur einmal getrimmt werden. '
            'Für weitere Anpassungen bitte erneut das Original hochladen.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
            textAlign: TextAlign.center,
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
              color: Colors.green.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Dauer: ${duration.toStringAsFixed(1)}s',
              style: TextStyle(
                color: Colors.green,
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
          onPressed: () =>
              Navigator.of(context).pop({'start': _start, 'end': _end}),
          child: const Text('Trimmen'),
        ),
      ],
    );
  }
}
