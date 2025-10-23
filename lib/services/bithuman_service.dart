import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class BitHumanService {
  static const String _baseUrl = 'https://api.bithuman.ai/v1';
  static String? _apiKey;
  static String? _apiSecret;

  /// Initialisiert BitHuman mit API Credentials aus .env
  static Future<void> initialize() async {
    try {
      _apiKey = dotenv.env['BITHUMAN_API_KEY'];
      _apiSecret = dotenv.env['BITHUMAN_API_SECRET'];

      if (_apiKey == null || _apiKey!.isEmpty) {
        debugPrint('⚠️ BITHUMAN_API_KEY nicht in .env gefunden');
      }
      if (_apiSecret == null || _apiSecret!.isEmpty) {
        debugPrint('⚠️ BITHUMAN_API_SECRET nicht in .env gefunden');
      }

      if (_apiKey != null && _apiSecret != null) {
        final maskedKey = _apiKey!.length > 6
            ? '${_apiKey!.substring(0, 3)}***${_apiKey!.substring(_apiKey!.length - 3)}'
            : '***';
        debugPrint('✅ BitHuman Service initialisiert (key=$maskedKey)');
      }
    } catch (e) {
      debugPrint('❌ BitHuman Initialisierung fehlgeschlagen: $e');
    }
  }

  /// Erstellt einen BitHuman Agent
  /// 
  /// [imagePath] - Lokaler Pfad zum Hero-Image
  /// [audioPath] - Lokaler Pfad zum Hero-Audio
  /// [model] - 'essence' oder 'expression'
  /// [name] - Optionaler Name des Agents
  /// 
  /// Returns agent_id oder null bei Fehler
  static Future<String?> createAgent({
    required String imagePath,
    required String audioPath,
    required String model,
    String? name,
  }) async {
    if (_apiKey == null || _apiSecret == null) {
      debugPrint('❌ BitHuman API Credentials fehlen');
      return null;
    }

    try {
      debugPrint('🚀 BitHuman Agent erstellen...');
      debugPrint('   Image: $imagePath');
      debugPrint('   Audio: $audioPath');
      debugPrint('   Model: $model');

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/agents'),
      );

      // Headers
      request.headers['X-API-Key'] = _apiKey!;
      request.headers['X-API-Secret'] = _apiSecret!;

      // Files
      request.files.add(await http.MultipartFile.fromPath('image', imagePath));
      request.files.add(await http.MultipartFile.fromPath('audio', audioPath));

      // Fields
      request.fields['model'] = model;
      if (name != null && name.isNotEmpty) {
        request.fields['name'] = name;
      }

      debugPrint('📤 Sende Request an BitHuman API...');
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      debugPrint('📥 Response Status: ${response.statusCode}');
      debugPrint('📥 Response Body: $responseBody');

      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        final agentId = data['agent_id'] as String?;

        if (agentId != null) {
          debugPrint('✅ Agent erfolgreich erstellt: $agentId');
          return agentId;
        } else {
          debugPrint('⚠️ Keine agent_id in Response gefunden');
          return null;
        }
      } else {
        debugPrint('❌ BitHuman API Fehler: ${response.statusCode}');
        debugPrint('   Body: $responseBody');
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ BitHuman createAgent Exception: $e');
      debugPrint('   StackTrace: $stackTrace');
      return null;
    }
  }

  /// Lädt eine Remote-Datei herunter und gibt den lokalen Pfad zurück
  static Future<String?> _downloadFile(String url, String filename) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final tempDir = Directory.systemTemp;
        final file = File('${tempDir.path}/$filename');
        await file.writeAsBytes(response.bodyBytes);
        return file.path;
      }
    } catch (e) {
      debugPrint('❌ Download fehlgeschlagen: $e');
    }
    return null;
  }

  /// Erstellt Agent mit URLs statt lokalen Pfaden
  static Future<String?> createAgentFromUrls({
    required String imageUrl,
    required String audioUrl,
    required String model,
    String? name,
  }) async {
    try {
      debugPrint('📥 Lade Hero-Image herunter...');
      final imagePath = await _downloadFile(imageUrl, 'hero_image.jpg');
      if (imagePath == null) {
        debugPrint('❌ Hero-Image Download fehlgeschlagen');
        return null;
      }

      debugPrint('📥 Lade Hero-Audio herunter...');
      final audioPath = await _downloadFile(audioUrl, 'hero_audio.mp3');
      if (audioPath == null) {
        debugPrint('❌ Hero-Audio Download fehlgeschlagen');
        return null;
      }

      return await createAgent(
        imagePath: imagePath,
        audioPath: audioPath,
        model: model,
        name: name,
      );
    } catch (e) {
      debugPrint('❌ createAgentFromUrls Exception: $e');
      return null;
    }
  }

  /// Fügt Agent zu LiveKit Room hinzu
  static Future<bool> joinAgentToRoom({
    required String agentId,
    required String roomUrl,
    required String roomToken,
    String? participantName,
  }) async {
    if (_apiKey == null || _apiSecret == null) {
      debugPrint('❌ BitHuman API Credentials fehlen');
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/agents/$agentId/join-room'),
        headers: {
          'X-API-Key': _apiKey!,
          'X-API-Secret': _apiSecret!,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'room_url': roomUrl,
          'room_token': roomToken,
          'participant_name': participantName ?? 'BitHuman Agent',
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final success = data['success'] as bool? ?? false;
        if (success) {
          debugPrint('✅ Agent erfolgreich in Room hinzugefügt');
          return true;
        }
      }

      debugPrint('❌ Join Room fehlgeschlagen: ${response.statusCode}');
      return false;
    } catch (e) {
      debugPrint('❌ joinAgentToRoom Exception: $e');
      return false;
    }
  }

  /// Entfernt Agent aus LiveKit Room
  static Future<bool> removeAgentFromRoom(String agentId) async {
    if (_apiKey == null || _apiSecret == null) {
      debugPrint('❌ BitHuman API Credentials fehlen');
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/agents/$agentId/leave-room'),
        headers: {
          'X-API-Key': _apiKey!,
          'X-API-Secret': _apiSecret!,
        },
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Agent erfolgreich aus Room entfernt');
        return true;
      }

      debugPrint('⚠️ Remove from Room: ${response.statusCode}');
      return false;
    } catch (e) {
      debugPrint('❌ removeAgentFromRoom Exception: $e');
      return false;
    }
  }
}

