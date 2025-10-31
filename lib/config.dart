import 'services/lipsync/lipsync_factory.dart';

class AppConfig {
  // Lipsync Mode
  static const lipsyncMode =
      LipsyncMode.streaming; // Live Lipsync via Orchestrator

  // Backend URLs
  static const backendUrl = 'https://us-central1-sunriza26.cloudfunctions.net';
  static const orchestratorUrl =
      'wss://romeo1971--lipsync-orchestrator-asgi.modal.run/';
  // LivePortrait Streaming WS (Modal)
  static const livePortraitWsUrl =
      'wss://romeo1971--liveportrait-ws-asgi.modal.run/stream';
  // BitHuman Agent Join URL (Modal)
  static const bithumanAgentUrl =
      'https://romeo1971--bithuman-complete-agent-join.modal.run';
}
