import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ElevenLabsService {
  static const String _baseUrl = 'https://api.elevenlabs.io/v1';
  static String? _apiKey;
  static String? _voiceId;

  /// Initialisiert ElevenLabs mit API Key aus .env
  static Future<void> initialize() async {
    try {
      // .env wird bereits in main.dart geladen – hier nur lesen
      // Unterstütze beide Schreibweisen: ELEVENLABS_API_KEY und ELEVENLABS_API_KEY
      _apiKey ??=
          (dotenv.env['ELEVENLABS_API_KEY'] ??
          dotenv.env['ELEVENLABS_API_KEY']);
      // Fallback: falls zur Laufzeit nicht geladen, versuche einmal zu laden
      if (_apiKey == null || _apiKey!.isEmpty) {
        try {
          await dotenv.load(fileName: '.env');
          _apiKey =
              dotenv.env['ELEVENLABS_API_KEY'] ??
              dotenv.env['ELEVENLABS_API_KEY'];
        } catch (_) {}
      }
      _voiceId ??=
          dotenv.env['ELEVENLABS_VOICE_ID'] ??
          'pNInz6obpgDQGcFmaJgB'; // Default Voice

      if (_apiKey == null || _apiKey!.isEmpty) {
        final keys = dotenv.env.keys.toList();
        print('⚠️ ElevenLabs API Key nicht in .env gefunden (Keys: $keys)');
      } else {
        final masked = _apiKey!.length > 6
            ? '${_apiKey!.substring(0, 3)}***${_apiKey!.substring(_apiKey!.length - 3)}'
            : '***';
        print('✅ ElevenLabs Service initialisiert (key=$masked)');
      }
    } catch (e) {
      print('❌ ElevenLabs Initialisierung fehlgeschlagen: $e');
    }
  }

  /// Generiert TTS Audio von Text
  static Future<String?> generateSpeech(String text) async {
    if (_apiKey == null) {
      print('❌ ElevenLabs API Key nicht gesetzt');
      return null;
    }

    try {
      print('🎵 ElevenLabs: Generiere TTS für Text');

      final response = await http.post(
        Uri.parse('$_baseUrl/text-to-speech/$_voiceId'),
        headers: {'xi-api-key': _apiKey!, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'text': text,
          'voice_settings': {
            'stability': 0.4,
            'similarity_boost': 0.75,
            'style': 0.0,
            'use_speaker_boost': true,
          },
        }),
      );

      if (response.statusCode == 200) {
        // Audio in temporärem Verzeichnis speichern
        final tempDir = await getTemporaryDirectory();
        final audioPath =
            '${tempDir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.wav';
        final audioFile = File(audioPath);

        await audioFile.writeAsBytes(response.bodyBytes);

        print('✅ ElevenLabs TTS Audio erstellt: $audioPath');
        return audioPath;
      } else {
        print('❌ ElevenLabs Fehler: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ ElevenLabs TTS Fehler: $e');
      return null;
    }
  }

  /// Holt verfügbare Voices
  static Future<List<Map<String, dynamic>>?> getVoices() async {
    if (_apiKey == null) return null;

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/voices'),
        headers: {'xi-api-key': _apiKey!, 'accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['voices']);
      } else {
        print(
          '❌ ElevenLabs Voices HTTP ${response.statusCode}: ${response.body}',
        );
      }
      return null;
    } catch (e) {
      print('❌ ElevenLabs Voices Fehler: $e');
      return null;
    }
  }
}
