import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Modal.com Dynamics Service
/// GPU-basierte LivePortrait Avatar-Animation
class DynamicsServiceModal {
  // Modal.com Backend URL (deployed)
  static const String BACKEND_URL =
      'https://romeo1971--sunriza-dynamics-api-generate-dynamics.modal.run';

  /// Generiert Dynamics-Video für einen Avatar
  ///
  /// [avatarId] - Firestore Avatar Document ID
  /// [dynamicsId] - Name der Dynamics (z.B. 'basic', 'lachen', 'sprechen')
  /// [parameters] - Optional: Custom Parameter für LivePortrait
  ///
  /// Returns: Video URL in Firebase Storage
  ///
  /// Throws: Exception bei Fehler
  static Future<String> generateDynamics({
    required String avatarId,
    String dynamicsId = 'basic',
    Map<String, dynamic>? parameters,
  }) async {
    debugPrint('🎭 Starte Dynamics-Generierung für Avatar: $avatarId');

    final defaultParameters = {
      'driving_multiplier': 0.41,
      'scale': 1.7,
      'source_max_dim': 1600,
      'animation_region': 'all',
    };

    final finalParameters = parameters ?? defaultParameters;

    final response = await http
        .post(
          Uri.parse(BACKEND_URL),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'avatar_id': avatarId,
            'dynamics_id': dynamicsId,
            'parameters': finalParameters,
          }),
        )
        .timeout(
          const Duration(minutes: 10),
          onTimeout: () {
            throw Exception('Dynamics-Generierung Timeout (10 Min)');
          },
        );

    if (response.statusCode != 200) {
      throw Exception(
        'Dynamics-Generierung fehlgeschlagen: ${response.statusCode} - ${response.body}',
      );
    }

    final data = jsonDecode(response.body);

    if (data['status'] == 'success') {
      final videoUrl = data['video_url'] as String;
      debugPrint('✅ Dynamics-Video erstellt: $videoUrl');
      return videoUrl;
    } else {
      throw Exception('Dynamics-Generierung fehlgeschlagen: ${data['error']}');
    }
  }

  /// Health Check - prüft ob Backend erreichbar ist
  static Future<bool> healthCheck() async {
    try {
      final healthUrl = BACKEND_URL.replaceAll(
        'api-generate-dynamics',
        'health',
      );

      final response = await http
          .get(Uri.parse(healthUrl))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['status'] == 'healthy';
      }
      return false;
    } catch (e) {
      debugPrint('⚠️ Health Check fehlgeschlagen: $e');
      return false;
    }
  }

  /// Geschätzte Generierungszeit in Sekunden
  /// Mit GPU: ~30-60 Sekunden
  static int estimatedDuration({int sourceMaxDim = 1600}) {
    // GPU: Sehr schnell!
    if (sourceMaxDim <= 512) return 20;
    if (sourceMaxDim <= 1024) return 30;
    if (sourceMaxDim <= 1600) return 45;
    return 60; // 2048+
  }
}
