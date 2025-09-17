import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class BitHumanService {
  static const String _baseUrl = 'http://localhost:8000'; // Lokales Backend
  static String? _apiKey;

  /// Initialisiert den Service mit API-Key aus .env
  static Future<void> initialize() async {
    try {
      await dotenv.load();
      _apiKey = dotenv.env['BITHUMAN_API_KEY'];

      if (_apiKey == null || _apiKey!.isEmpty) {
        print('⚠️ BitHuman API Key nicht in .env gefunden - Demo-Modus');
        _apiKey = 'demo_key';
      } else {
        print('✅ BitHuman Service initialisiert');
      }
    } catch (e) {
      print('❌ BitHuman Initialisierung fehlgeschlagen: $e');
      _apiKey = 'demo_key';
    }
  }

  /// Erstellt einen Avatar mit Audio-Input über offizielles Backend
  static Future<String?> createAvatarWithAudio({
    required String imagePath,
    required String audioPath,
    String? avatarId,
  }) async {
    try {
      print('🎬 BitHuman: Starte Avatar-Generierung');
      print('🖼️ Bild: $imagePath');
      print('🎵 Audio: $audioPath');

      // Demo-Modus
      if (_apiKey == 'demo_key') {
        return _createDemoVideo(imagePath, audioPath);
      }

      // Offizielles Backend verwenden
      final videoPath = await _generateAvatarWithBackend(imagePath, audioPath);
      return videoPath;
    } catch (e) {
      print('BitHuman Service Error: $e');
      return null;
    }
  }

  /// Lädt .imx Avatar-Modell hoch
  static Future<String?> uploadImxFile(String imxPath) async {
    try {
      print('📤 BitHuman: Lade .imx Avatar hoch');

      final file = File(imxPath);
      if (!await file.exists()) {
        print('❌ .imx Datei nicht gefunden: $imxPath');
        return null;
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/upload_imx'),
      );

      request.files.add(await http.MultipartFile.fromPath('file', imxPath));

      final response = await request.send();

      if (response.statusCode == 200) {
        final responseBody = await response.stream.bytesToString();
        final data = jsonDecode(responseBody);
        print('✅ Avatar hochgeladen: ${data['filename']}');
        return data['filename'];
      } else {
        print('❌ Upload Fehler: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Upload Error: $e');
      return null;
    }
  }

  /// Startet Avatar-Sprechen mit Text
  static Future<bool> speakText(String text, String imxFileName) async {
    try {
      print('🗣️ BitHuman: Starte Avatar-Sprechen');
      print('📝 Text: $text');
      print('🎭 Avatar: $imxFileName');

      final response = await http.post(
        Uri.parse('$_baseUrl/speak'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text, 'imx': imxFileName}),
      );

      if (response.statusCode == 200) {
        print('✅ Avatar spricht jetzt!');
        return true;
      } else {
        print('❌ Speak Fehler: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ Speak Error: $e');
      return false;
    }
  }

  /// Generiert Avatar über offizielles BitHuman Backend
  static Future<String?> _generateAvatarWithBackend(
    String imagePath,
    String audioPath,
  ) async {
    try {
      // Multipart Request an Backend
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/generate-avatar'),
      );

      // Dateien anhängen
      request.files.add(await http.MultipartFile.fromPath('image', imagePath));
      request.files.add(await http.MultipartFile.fromPath('audio', audioPath));

      print('📤 Sende Anfrage an BitHuman Backend...');
      final response = await request.send();

      if (response.statusCode == 200) {
        // Video-Datei in temporärem Verzeichnis speichern
        final tempDir = await getTemporaryDirectory();
        final videoPath =
            '${tempDir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.mp4';
        final videoFile = File(videoPath);

        // Video-Daten speichern
        await response.stream.pipe(videoFile.openWrite());

        print('✅ Avatar-Video erstellt: $videoPath');
        return videoPath;
      } else {
        print('❌ Backend Fehler: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Backend Request Error: $e');
      return null;
    }
  }

  /// Erstellt Demo-Video für Entwicklung
  static Future<String?> _createDemoVideo(
    String imagePath,
    String audioPath,
  ) async {
    try {
      print('🎬 Demo-Modus: Simuliere Avatar-Animation');
      print('🖼️ Bild: $imagePath');
      print('🎵 Audio: $audioPath');

      // Simuliere Verarbeitungszeit
      await Future.delayed(Duration(seconds: 2));

      // Für Demo: Verwende das ursprüngliche Bild als "Video"
      return imagePath;
    } catch (e) {
      print('Demo Video Error: $e');
      return null;
    }
  }

  // Alte API-Methoden entfernt - verwende jetzt offizielles Backend
}
