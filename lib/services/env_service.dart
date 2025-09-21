import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kDebugMode;
import 'package:flutter_dotenv/flutter_dotenv.dart';

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

    if (kDebugMode) {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return 'http://10.0.2.2:8000';
      }
      return 'http://127.0.0.1:8000';
    }
    return '';
  }
}
