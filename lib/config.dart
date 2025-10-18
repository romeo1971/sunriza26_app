import 'services/lipsync/lipsync_factory.dart';

class AppConfig {
  // Lipsync Mode
  static const lipsyncMode = LipsyncMode.streaming;

  // Backend URLs
  static const backendUrl = 'https://backend.sunriza26.com';
  static const orchestratorUrl =
      'wss://romeo1971--lipsync-orchestrator-asgi.modal.run/';
  // LivePortrait Streaming WS (Modal)
  static const livePortraitWsUrl =
      'wss://romeo1971--liveportrait-ws-asgi.modal.run/stream';
}
