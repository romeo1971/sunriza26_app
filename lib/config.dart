import 'services/lipsync/lipsync_factory.dart';

class AppConfig {
  // Lipsync Mode
  static const lipsyncMode = LipsyncMode.fileBased; // Default: Aktuell

  // Backend URLs
  static const backendUrl = 'https://backend.sunriza26.com';
  static const orchestratorUrl = 'wss://orchestrator.sunriza26.com/lipsync';
}
