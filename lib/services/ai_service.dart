/// AI Service für Live-Video-Generierung
/// Stand: 04.09.2025 - Integration mit Firebase Cloud Functions

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // Cloud Function URLs (nach Deployment)
  static const String _generateLiveVideoUrl =
      'https://us-central1-sunriza26.cloudfunctions.net/generateLiveVideo';
  static const String _healthCheckUrl =
      'https://us-central1-sunriza26.cloudfunctions.net/healthCheck';
  static const String _testTtsUrl =
      'https://us-central1-sunriza26.cloudfunctions.net/testTTS';

  /**
   * Generiert Live-Video mit geklonter Stimme und Lippen-Synchronisation
   * Gibt einen Stream zurück für Echtzeit-Wiedergabe
   */
  Future<Stream<Uint8List>> generateLiveVideo({
    required String text,
    Function(String)? onProgress,
    Function(String)? onError,
  }) async {
    try {
      onProgress?.call('Starte Video-Generierung...');

      // HTTP Request für Live-Streaming
      final request = http.Request('POST', Uri.parse(_generateLiveVideoUrl));
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'video/mp4',
        'Cache-Control': 'no-cache',
      });
      request.body = '{"text": "${_escapeJson(text)}"}';

      onProgress?.call('Verbinde mit AI-Service...');

      // Streamed Response
      final streamedResponse = await request.send();

      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        throw Exception(
          'Server-Fehler: ${streamedResponse.statusCode} - $errorBody',
        );
      }

      onProgress?.call('Empfange Video-Stream...');

      // Video-Metadaten aus Headers extrahieren
      final contentType =
          streamedResponse.headers['content-type'] ?? 'video/mp4';
      final metadataHeader = streamedResponse.headers['x-video-metadata'];

      if (metadataHeader != null) {
        onProgress?.call('Video-Metadaten: $metadataHeader');
      }

      // Stream in Uint8List Chunks umwandeln
      return streamedResponse.stream.map((chunk) => Uint8List.fromList(chunk));
    } catch (e) {
      onError?.call('Fehler bei Video-Generierung: $e');
      rethrow;
    }
  }

  /**
   * Testet Text-to-Speech ohne Video-Generierung
   * Nützlich für Debugging und schnelle Tests
   */
  Future<Uint8List> testTextToSpeech(String text) async {
    try {
      final request = http.Request('POST', Uri.parse(_testTtsUrl));
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'audio/wav',
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

  /**
   * Überprüft den Status der AI-Services
   */
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

  /**
   * Speichert Audio-Daten temporär für Tests
   */
  Future<String> saveAudioToFile(Uint8List audioData) async {
    try {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/test_audio.wav');
      await file.writeAsBytes(audioData);
      return file.path;
    } catch (e) {
      throw Exception('Fehler beim Speichern der Audio-Datei: $e');
    }
  }

  /**
   * Validiert Text für AI-Verarbeitung
   */
  bool validateText(String text) {
    if (text.trim().isEmpty) return false;
    if (text.length > 5000) return false; // Google TTS Limit
    return true;
  }

  /**
   * Escaped JSON-String für sichere Übertragung
   */
  String _escapeJson(String text) {
    return text
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }
}
