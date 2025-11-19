import 'services/lipsync/lipsync_factory.dart';

class AppConfig {
  // Lipsync Mode
  static const lipsyncMode =
      LipsyncMode.streaming; // Live Lipsync via Orchestrator

  // Backend URLs (Prod Hauau – Dev wird über .env / EnvService konfiguriert)
  static const backendUrl = 'https://us-central1-hauau-prod.cloudfunctions.net';
  static const memoryApiBaseUrl = backendUrl; // Memory API als Cloud Function (Fallback)
  static const orchestratorUrl =
      'wss://romeo1971--lipsync-orchestrator-asgi.modal.run/';
  // LivePortrait Streaming WS (Modal)
  static const livePortraitWsUrl =
      'wss://romeo1971--liveportrait-ws-asgi.modal.run/stream';
  // BitHuman Agent Join URL (Modal)
  static const bithumanAgentUrl =
      'https://romeo1971--bithuman-complete-agent-join.modal.run';
}
