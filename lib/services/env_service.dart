import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../config.dart';

class EnvService {
  EnvService._();

  static String _safeEnv(String key) {
    try {
      if (dotenv.isInitialized) {
        return (dotenv.env[key] ?? '').trim();
      }
    } catch (_) {}
    return '';
  }

  static String _normalizeBase(String url) {
    if (url.isEmpty) return url;
    try {
      final uri = Uri.parse(url);
      final host = uri.host;
      // Android-Emulator kann 127.0.0.1/localhost nicht erreichen → 10.0.2.2
      if (defaultTargetPlatform == TargetPlatform.android &&
          (host == '127.0.0.1' || host == 'localhost')) {
        return uri.replace(host: '10.0.2.2').toString();
      }
      return url;
    } catch (_) {
      // Fallback auf rohe Substitution
      if (defaultTargetPlatform == TargetPlatform.android) {
        return url
            .replaceFirst('http://localhost', 'http://10.0.2.2')
            .replaceFirst('https://localhost', 'https://10.0.2.2')
            .replaceFirst('http://127.0.0.1', 'http://10.0.2.2')
            .replaceFirst('https://127.0.0.1', 'https://10.0.2.2');
      }
      return url;
    }
  }

  static String memoryApiBaseUrl() {
    const fromDefine = String.fromEnvironment(
      'MEMORY_API_BASE_URL',
      defaultValue: '',
    );
    if (fromDefine.isNotEmpty) return _normalizeBase(fromDefine.trim());

    final fromEnv = _safeEnv('MEMORY_API_BASE_URL');
    if (fromEnv.isNotEmpty) return _normalizeBase(fromEnv);

    // Optional: spezielle LAN‑URL für physische Geräte
    const lanDefine = String.fromEnvironment('LAN_BASE_URL', defaultValue: '');
    if (lanDefine.isNotEmpty) return _normalizeBase(lanDefine.trim());
    final lanEnv = _safeEnv('LAN_BASE_URL');
    if (lanEnv.isNotEmpty) return _normalizeBase(lanEnv);

    // Production: Cloud Functions als Fallback
    return AppConfig.memoryApiBaseUrl;
  }

  static String pineconeApiBaseUrl() {
    const fromDefine = String.fromEnvironment(
      'PINECONE_API_BASE_URL',
      defaultValue: '',
    );
    if (fromDefine.isNotEmpty) return _normalizeBase(fromDefine.trim());

    final fromEnv = _safeEnv('PINECONE_API_BASE_URL');
    if (fromEnv.isNotEmpty) return _normalizeBase(fromEnv);

    // Optional: spezielle LAN‑URL für physische Geräte
    const lanDefine = String.fromEnvironment('LAN_BASE_URL', defaultValue: '');
    if (lanDefine.isNotEmpty) return _normalizeBase(lanDefine.trim());
    final lanEnv = _safeEnv('LAN_BASE_URL');
    if (lanEnv.isNotEmpty) return _normalizeBase(lanEnv);

    // Production: Cloud Functions als Fallback
    return AppConfig.backendUrl;
  }

  /// Basis-URL für TTS-/ElevenLabs-Backend (z. B. FastAPI oder Cloud Function Proxy)
  /// Reihenfolge:
  /// - Compile-time define: ELEVENLABS_API_BASE_URL oder TTS_API_BASE_URL
  /// - .env: ELEVENLABS_API_BASE_URL oder TTS_API_BASE_URL
  /// - Fallback: memoryApiBaseUrl() → bestehendes Verhalten
  static String ttsApiBaseUrl() {
    // Defines haben Vorrang (CI/Release)
    const fromDefine1 = String.fromEnvironment('ELEVENLABS_API_BASE_URL', defaultValue: '');
    if (fromDefine1.isNotEmpty) return _normalizeBase(fromDefine1.trim());
    const fromDefine2 = String.fromEnvironment('TTS_API_BASE_URL', defaultValue: '');
    if (fromDefine2.isNotEmpty) return _normalizeBase(fromDefine2.trim());

    // .env
    final fromEnv1 = _safeEnv('ELEVENLABS_API_BASE_URL');
    if (fromEnv1.isNotEmpty) return _normalizeBase(fromEnv1);
    final fromEnv2 = _safeEnv('TTS_API_BASE_URL');
    if (fromEnv2.isNotEmpty) return _normalizeBase(fromEnv2);

    // Fallback auf bisherige Logik
    final mem = memoryApiBaseUrl();
    if (mem.isNotEmpty) return mem;
    return AppConfig.backendUrl;
  }

  /// Basis-URL für generische Cloud Functions (Thumbs, Social Embeds, etc.)
  /// DEV/PROD werden primär über .env gesteuert (CLOUDFUNCTIONS_BASE_URL).
  static String cloudFunctionsBaseUrl() {
    const fromDefine = String.fromEnvironment(
      'CLOUDFUNCTIONS_BASE_URL',
      defaultValue: '',
    );
    if (fromDefine.isNotEmpty) return _normalizeBase(fromDefine.trim());

    final fromEnv = _safeEnv('CLOUDFUNCTIONS_BASE_URL');
    if (fromEnv.isNotEmpty) return _normalizeBase(fromEnv);

    // Fallback: Prod-Backend-URL
    return AppConfig.backendUrl;
  }

  /// Erkennt, ob die TTS‑Basis Cloud Functions ist (liefert /testTTS als Bytes)
  static bool ttsIsCloudFunctions(String baseUrl) {
    try {
      final host = Uri.parse(baseUrl).host;
      return host.contains('cloudfunctions.net');
    } catch (_) {
      return baseUrl.contains('cloudfunctions.net');
    }
  }

  /// Liefert den Pfad für TTS je nach Backend
  static String ttsEndpointPath(String baseUrl) {
    return ttsIsCloudFunctions(baseUrl) ? '/testTTS' : '/avatar/tts';
  }

  /// Basis-URL für Orchestrator-/LiveKit-Hilfsendpunkte (z. B. /livekit/token, /avatar/info)
  /// Reihenfolge:
  /// - Compile-time: LIVEKIT_API_BASE_URL oder ORCHESTRATOR_API_BASE_URL
  /// - .env: LIVEKIT_API_BASE_URL oder ORCHESTRATOR_API_BASE_URL
  /// - Fallback: memoryApiBaseUrl() (für Abwärtskompatibilität)
  static String livekitApiBaseUrl() {
    const fromDefine1 = String.fromEnvironment('LIVEKIT_API_BASE_URL', defaultValue: '');
    if (fromDefine1.isNotEmpty) return _normalizeBase(fromDefine1.trim());
    const fromDefine2 = String.fromEnvironment('ORCHESTRATOR_API_BASE_URL', defaultValue: '');
    if (fromDefine2.isNotEmpty) return _normalizeBase(fromDefine2.trim());

    final fromEnv1 = _safeEnv('LIVEKIT_API_BASE_URL');
    if (fromEnv1.isNotEmpty) return _normalizeBase(fromEnv1);
    final fromEnv2 = _safeEnv('ORCHESTRATOR_API_BASE_URL');
    if (fromEnv2.isNotEmpty) return _normalizeBase(fromEnv2);

    // Rückfall
    return memoryApiBaseUrl();
  }

  // Feature-Flags für Orchestrator
  static bool orchestratorEnabled() {
    final v = _safeEnv('ORCHESTRATOR_ENABLED');
    if (v.isEmpty) return true; // Default: an
    return !(v == '0' || v.toLowerCase() == 'false');
  }

  static bool orchestratorWarmupEnabled() {
    final v = _safeEnv('ORCHESTRATOR_WARMUP');
    if (v.isEmpty) return true; // Default: an
    return !(v == '0' || v.toLowerCase() == 'false');
  }
}
