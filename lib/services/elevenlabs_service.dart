import 'dart:io';
import 'package:flutter/foundation.dart';
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
        debugPrint('⚠️ ElevenLabs API Key nicht in .env gefunden (Keys: $keys)');
      } else {
        final masked = _apiKey!.length > 6
            ? '${_apiKey!.substring(0, 3)}***${_apiKey!.substring(_apiKey!.length - 3)}'
            : '***';
        debugPrint('✅ ElevenLabs Service initialisiert (key=$masked)');
      }
    } catch (e) {
      debugPrint('❌ ElevenLabs Initialisierung fehlgeschlagen: $e');
    }
  }

  /// Generiert TTS Audio von Text
  static Future<String?> generateSpeech(String text) async {
    if (_apiKey == null) {
      debugPrint('❌ ElevenLabs API Key nicht gesetzt');
      return null;
    }

    try {
      debugPrint('🎵 ElevenLabs: Generiere TTS für Text');

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

        debugPrint('✅ ElevenLabs TTS Audio erstellt: $audioPath');
        return audioPath;
      } else {
        debugPrint('❌ ElevenLabs Fehler: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ ElevenLabs TTS Fehler: $e');
      return null;
    }
  }

  /// Holt verfügbare Voices über Backend-Proxy (umgeht Flutter SSL-Problem)
  static Future<List<Map<String, dynamic>>?> getVoices() async {
    try {
      final base = (dotenv.env['MEMORY_API_BASE_URL'] ?? '').trim();
      if (base.isEmpty) {
        debugPrint('❌ Backend URL fehlt: MEMORY_API_BASE_URL');
        return null;
      }
      
      // Nutze neuen Backend-Proxy Endpoint
      final url = '$base/api/elevenlabs/voices';
      debugPrint('🔍 Rufe Backend Proxy auf: $url');
      final r = await http.get(
        Uri.parse(url),
        headers: {'accept': 'application/json'},
      );
      
      if (r.statusCode >= 200 && r.statusCode < 300) {
        final data = jsonDecode(r.body);
        // ElevenLabs API Response Format: {"voices": [...]}
        final list = (data is Map && data['voices'] is List)
            ? List<Map<String, dynamic>>.from(data['voices'])
            : <Map<String, dynamic>>[];
        debugPrint('✅ Backend Voices: ${list.length} verfügbar');
        return list;
      } else {
        debugPrint('❌ Backend Voices HTTP ${r.statusCode}: ${r.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Backend Voices Fehler: $e');
      return null;
    }
  }
}
