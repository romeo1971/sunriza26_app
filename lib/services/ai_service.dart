/// AI Service für Live-Video-Generierung
/// Stand: 04.09.2025 - Integration mit Firebase Cloud Functions
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  // Hinweis: Cloud Functions Client aktuell ungenutzt

  // ComfyUI URLs (Cloud Run)
  static const String _comfyuiBaseUrl =
      'https://comfyui-sonic-xxxxx-uc.a.run.app';
  static const String _generateLiveVideoUrl = '$_comfyuiBaseUrl/prompt';
  static const String _healthCheckUrl = '$_comfyuiBaseUrl/system_stats';
  static const String _testTtsUrl = '$_comfyuiBaseUrl/tts';

  /// Generiert Live-Video mit ComfyUI_Sonic
  /// Basiert auf dem Workflow aus dem Bild
  Future<Stream<Uint8List>> generateLiveVideo({
    required String text,
    required String imageUrl,
    required String audioUrl,
    Function(String)? onProgress,
    Function(String)? onError,
  }) async {
    try {
      onProgress?.call('Starte ComfyUI Sonic Video-Generierung...');

      // ComfyUI Sonic Workflow (basierend auf dem Bild)
      final workflow = {
        "1": {
          "inputs": {"ckpt_name": "svd_xt.safetensors"},
          "class_type": "CheckpointLoaderSimple",
          "_meta": {"title": "Image Only Checkpoint Loader (img2vid model)"},
        },
        "2": {
          "inputs": {"audio": audioUrl},
          "class_type": "LoadAudio",
          "_meta": {"title": "LoadAudio"},
        },
        "3": {
          "inputs": {"image": imageUrl},
          "class_type": "LoadImage",
          "_meta": {"title": "Load Image"},
        },
        "4": {
          "inputs": {
            "model": ["1", 0],
            "dtype": "fp16",
          },
          "class_type": "SONICTLoader",
          "_meta": {"title": "Sonic"},
        },
        "5": {
          "inputs": {
            "clip_vision": ["1", 1],
            "vae": ["1", 2],
            "audio": ["2", 0],
            "image": ["3", 0],
            "weight_dtype": "fp16",
            "min_resolution": 512,
            "duration": 5.0,
            "expand_ratio": 0.5,
          },
          "class_type": "SONIC_PreData",
          "_meta": {"title": "Sonic"},
        },
        "6": {
          "inputs": {
            "model": ["4", 0],
            "data_dict": ["5", 0],
            "fps": 24.0,
            "seed": 1537071674,
            "control_after_generate": "randomize",
            "inference_steps": 25,
            "dynamic_scale": 1.0,
          },
          "class_type": "SONICSampler",
          "_meta": {"title": "Sonic"},
        },
        "7": {
          "inputs": {
            "images": ["6", 0],
            "audio": ["2", 0],
            "vae": ["1", 2],
            "frame_rate": 8,
            "loop_count": 0,
            "filename_prefix": "sonic_lipsync",
            "format": "video/h264-mp4",
            "pix_fmt": "yuv420p",
            "crf": 19,
            "save_metadata": true,
            "trim_to_audio": true,
            "pingpong": false,
            "save_output": true,
          },
          "class_type": "VideoCombine",
          "_meta": {"title": "Video Combine"},
        },
      };

      onProgress?.call('Verbinde mit ComfyUI...');

      // HTTP Request an ComfyUI
      final request = http.Request('POST', Uri.parse(_generateLiveVideoUrl));
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      });
      request.body = jsonEncode({"prompt": workflow});

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode != 200) {
        throw Exception(
          'ComfyUI-Fehler: ${response.statusCode} - $responseBody',
        );
      }

      onProgress?.call('ComfyUI verarbeitet Video...');

      // Warte auf Video-Generierung und hole das Ergebnis
      final result = await _waitForComfyUIResult(responseBody);

      if (result != null) {
        onProgress?.call('Video erfolgreich generiert!');
        return Stream.value(result);
      } else {
        throw Exception('Video-Generierung fehlgeschlagen');
      }
    } catch (e) {
      onError?.call('Fehler bei ComfyUI Video-Generierung: $e');
      rethrow;
    }
  }

  /// Testet Text-to-Speech ohne Video-Generierung
  /// Nützlich für Debugging und schnelle Tests
  Future<Uint8List> testTextToSpeech(String text) async {
    try {
      final request = http.Request('POST', Uri.parse(_testTtsUrl));
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'audio/mpeg',
      });
      request.body = '{"text": "${_escapeJson(text)}"}';

      final streamedResponse = await request.send();

      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        throw Exception(
          'TTS-Fehler: ${streamedResponse.statusCode} - $errorBody',
        );
      }

      // Audio-Daten sammeln
      final audioBytes = <int>[];
      await for (final chunk in streamedResponse.stream) {
        audioBytes.addAll(chunk);
      }

      return Uint8List.fromList(audioBytes);
    } catch (e) {
      throw Exception('TTS-Test fehlgeschlagen: $e');
    }
  }

  /// Überprüft den Status der AI-Services
  Future<Map<String, dynamic>> checkHealth() async {
    try {
      final response = await http.get(
        Uri.parse(_healthCheckUrl),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        return {'status': 'healthy', 'data': response.body};
      } else {
        return {'status': 'unhealthy', 'error': 'HTTP ${response.statusCode}'};
      }
    } catch (e) {
      return {'status': 'unhealthy', 'error': e.toString()};
    }
  }

  /// Speichert Audio-Daten temporär für Tests
  Future<String> saveAudioToFile(Uint8List audioData) async {
    try {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/test_audio.mp3');
      await file.writeAsBytes(audioData);
      return file.path;
    } catch (e) {
      throw Exception('Fehler beim Speichern der Audio-Datei: $e');
    }
  }

  /// Validiert Text für AI-Verarbeitung
  bool validateText(String text) {
    if (text.trim().isEmpty) return false;
    if (text.length > 5000) return false; // Google TTS Limit
    return true;
  }

  /// Wartet auf ComfyUI Video-Generierung und lädt das Ergebnis
  Future<Uint8List?> _waitForComfyUIResult(String responseBody) async {
    try {
      final responseData = jsonDecode(responseBody);
      final promptId = responseData['prompt_id'];

      if (promptId == null) return null;

      // Polling bis Video fertig ist
      for (int i = 0; i < 60; i++) {
        // Max 5 Minuten warten
        await Future.delayed(Duration(seconds: 5));

        final historyResponse = await http.get(
          Uri.parse('$_comfyuiBaseUrl/history/$promptId'),
          headers: {'Accept': 'application/json'},
        );

        if (historyResponse.statusCode == 200) {
          final historyData = jsonDecode(historyResponse.body);
          final status = historyData[promptId.toString()];

          if (status != null && status['status'] != null) {
            final statusInfo = status['status'];
            if (statusInfo['status_str'] == 'success') {
              // Video ist fertig - hole die Ausgabedatei
              final outputs = status['outputs'];
              if (outputs != null && outputs['7'] != null) {
                final videoInfo = outputs['7'];
                if (videoInfo['videos'] != null &&
                    videoInfo['videos'].isNotEmpty) {
                  final videoPath = videoInfo['videos'][0]['filename'];
                  return await _downloadVideoFromComfyUI(videoPath);
                }
              }
            } else if (statusInfo['status_str'] == 'error') {
              throw Exception(
                'ComfyUI Fehler: ${statusInfo.get('message', 'Unbekannter Fehler')}',
              );
            }
          }
        }
      }

      throw Exception('Video-Generierung Timeout');
    } catch (e) {
      throw Exception('Fehler beim Warten auf Video: $e');
    }
  }

  /// Lädt Video von ComfyUI herunter
  Future<Uint8List> _downloadVideoFromComfyUI(String videoPath) async {
    try {
      final response = await http.get(
        Uri.parse('$_comfyuiBaseUrl/view?filename=$videoPath'),
        headers: {'Accept': 'video/mp4'},
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        throw Exception('Video Download Fehler: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Fehler beim Video Download: $e');
    }
  }

  /// Escaped JSON-String für sichere Übertragung
  String _escapeJson(String text) {
    return text
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }
}
