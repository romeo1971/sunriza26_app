import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class BitHumanService {
  static const String _baseUrl = 'https://public.api.bithuman.ai';
  static String? _apiSecret;

  /// Initialisiert BitHuman mit API Secret aus .env
  static Future<void> initialize() async {
    try {
      _apiSecret = dotenv.env['BITHUMAN_API_SECRET'];

      if (_apiSecret == null || _apiSecret!.isEmpty) {
        debugPrint('⚠️ BITHUMAN_API_SECRET nicht in .env gefunden');
        debugPrint('   Hole API Secret von: imaginex.bithuman.ai');
      } else {
        final masked = _apiSecret!.length > 8
            ? '${_apiSecret!.substring(0, 4)}***${_apiSecret!.substring(_apiSecret!.length - 4)}'
            : '***';
        debugPrint('✅ BitHuman Service initialisiert (secret=$masked)');
      }
    } catch (e) {
      debugPrint('❌ BitHuman Initialisierung fehlgeschlagen: $e');
    }
  }

  /// Erstellt einen BitHuman Agent via REST API
  /// 
  /// [imageUrl] - URL zum Hero-Image
  /// [audioUrl] - URL zum Hero-Audio
  /// [prompt] - System Prompt für den Agent
  /// [videoUrl] - Optional: Video URL
  /// 
  /// Returns agent_id oder null bei Fehler
  static Future<String?> createAgent({
    String? imageUrl,
    String? audioUrl,
    String? videoUrl,
    String? prompt,
  }) async {
    if (_apiSecret == null || _apiSecret!.isEmpty) {
      debugPrint('❌ BitHuman API Secret fehlt');
      return null;
    }

    try {
      debugPrint('🚀 BitHuman Agent erstellen...');
      debugPrint('   Image: $imageUrl');
      debugPrint('   Audio: $audioUrl');
      debugPrint('   Prompt: $prompt');

      final body = <String, dynamic>{};
      if (prompt != null && prompt.isNotEmpty) body['prompt'] = prompt;
      if (imageUrl != null && imageUrl.isNotEmpty) body['image'] = imageUrl;
      if (videoUrl != null && videoUrl.isNotEmpty) body['video'] = videoUrl;
      if (audioUrl != null && audioUrl.isNotEmpty) body['audio'] = audioUrl;

      final response = await http.post(
        Uri.parse('$_baseUrl/v1/agent/generate'),
        headers: {
          'Content-Type': 'application/json',
          'api-secret': _apiSecret!,
        },
        body: json.encode(body),
      );

      debugPrint('📥 Response Status: ${response.statusCode}');
      debugPrint('📥 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final agentId = data['agent_id'] as String?;
        final status = data['status'] as String?;

        if (agentId != null) {
          debugPrint('✅ Agent erfolgreich erstellt: $agentId (status: $status)');
          return agentId;
        } else {
          debugPrint('⚠️ Keine agent_id in Response gefunden');
          return null;
        }
      } else {
        debugPrint('❌ BitHuman API Fehler: ${response.statusCode}');
        debugPrint('   Body: ${response.body}');
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ BitHuman createAgent Exception: $e');
      debugPrint('   StackTrace: $stackTrace');
      return null;
    }
  }

  /// Prüft Agent Status
  static Future<Map<String, dynamic>?> getAgentStatus(String agentId) async {
    if (_apiSecret == null || _apiSecret!.isEmpty) {
      debugPrint('❌ BitHuman API Secret fehlt');
      return null;
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/v1/agent/status/$agentId'),
        headers: {
          'api-secret': _apiSecret!,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('✅ Agent Status: ${data['data']['status']}');
        return data['data'] as Map<String, dynamic>?;
      } else {
        debugPrint('❌ Status Check Fehler: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ getAgentStatus Exception: $e');
      return null;
    }
  }

  /// Wartet bis Agent ready ist
  static Future<bool> waitForAgent(String agentId, {Duration timeout = const Duration(minutes: 5)}) async {
    final startTime = DateTime.now();
    
    while (DateTime.now().difference(startTime) < timeout) {
      final status = await getAgentStatus(agentId);
      
      if (status != null) {
        final statusStr = status['status'] as String?;
        
        if (statusStr == 'ready') {
          debugPrint('✅ Agent ready: ${status['model_url']}');
          return true;
        } else if (statusStr == 'failed') {
          debugPrint('❌ Agent Generation failed');
          return false;
        }
        
        debugPrint('⏳ Agent Status: $statusStr (waiting...)');
      }
      
      await Future.delayed(const Duration(seconds: 5));
    }
    
    debugPrint('❌ Timeout waiting for agent');
    return false;
  }

}

