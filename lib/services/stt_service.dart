import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Speech-to-Text Service für Web & Mobile.
/// Mobile: nutzt File-Upload direkt an OpenAI Whisper API.
/// Web: nutzt Web Audio Blob Upload an Backend /stt/whisper oder direkt OpenAI.
class SttService {
  /// Transkribiert eine Audio-Datei (Mobile) via OpenAI Whisper.
  static Future<String?> transcribeFile(File audioFile) async {
    if (kIsWeb) {
      throw UnsupportedError('transcribeFile ist nur auf Mobile verfügbar. Nutze transcribeWebBlob für Web.');
    }
    try {
      final key = dotenv.env['OPENAI_API_KEY']?.trim();
      if (key == null || key.isEmpty) {
        debugPrint('[SttService] OPENAI_API_KEY fehlt in .env');
        return null;
      }
      final uri = Uri.parse('https://api.openai.com/v1/audio/transcriptions');
      final req = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $key'
        ..fields['model'] = 'whisper-1'
        ..files.add(
          await http.MultipartFile.fromPath(
            'file',
            audioFile.path,
            contentType: MediaType('audio', 'wav'),
          ),
        );
      final resp = await req.send().timeout(const Duration(seconds: 30));
      final body = await resp.stream.bytesToString();
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        return (data['text'] as String?)?.trim();
      } else {
        debugPrint('[SttService] Whisper-Fehler: ${resp.statusCode} $body');
        return null;
      }
    } catch (e) {
      debugPrint('[SttService] transcribeFile Fehler: $e');
      return null;
    }
  }

  /// Transkribiert ein Web Audio Blob (Uint8List) via OpenAI Whisper.
  /// Für Web: empfängt bytes direkt aus MediaRecorder.
  static Future<String?> transcribeWebBlob(Uint8List audioBytes, {String? filename}) async {
    if (!kIsWeb) {
      throw UnsupportedError('transcribeWebBlob ist nur auf Web verfügbar. Nutze transcribeFile für Mobile.');
    }
    try {
      final key = dotenv.env['OPENAI_API_KEY']?.trim();
      if (key == null || key.isEmpty) {
        debugPrint('[SttService] OPENAI_API_KEY fehlt in .env');
        return null;
      }
      final uri = Uri.parse('https://api.openai.com/v1/audio/transcriptions');
      final req = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $key'
        ..fields['model'] = 'whisper-1'
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            audioBytes,
            filename: filename ?? 'audio.webm',
            contentType: MediaType('audio', 'webm'),
          ),
        );
      final resp = await req.send().timeout(const Duration(seconds: 30));
      final body = await resp.stream.bytesToString();
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        return (data['text'] as String?)?.trim();
      } else {
        debugPrint('[SttService] Whisper-Fehler: ${resp.statusCode} $body');
        return null;
      }
    } catch (e) {
      debugPrint('[SttService] transcribeWebBlob Fehler: $e');
      return null;
    }
  }
}

