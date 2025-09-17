import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class BitHumanService {
  static const String _baseUrl = 'http://localhost:8000'; // Lokales Backend
  static String? _apiKey;

  /// Initialisiert den Service mit API-Key
  static void initialize(String apiKey) {
    _apiKey = apiKey;
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
