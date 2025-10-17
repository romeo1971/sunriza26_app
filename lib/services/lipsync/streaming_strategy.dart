import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'lipsync_strategy.dart';

/// Streaming Strategy (WebSocket-basiert)
class StreamingStrategy implements LipsyncStrategy {
  final String _orchestratorUrl;
  WebSocketChannel? _channel;
  AudioPlayer? _audioPlayer;

  final StreamController<VisemeEvent> _visemeController =
      StreamController<VisemeEvent>.broadcast();

  @override
  Stream<VisemeEvent> get visemeStream => _visemeController.stream;

  StreamingStrategy({required String orchestratorUrl})
      : _orchestratorUrl = orchestratorUrl;

  Future<void> _connect() async {
    if (_channel != null) return;

    _channel = WebSocketChannel.connect(Uri.parse(_orchestratorUrl));
    _audioPlayer = AudioPlayer();

    _channel!.stream.listen((message) {
      final data = jsonDecode(message);

      switch (data['type']) {
        case 'audio':
          _handleAudio(data);
          break;
        case 'viseme':
          _handleViseme(data);
          break;
      }
    });
  }

  @override
  Future<void> speak(String text, String voiceId) async {
    await _connect();

    _channel!.sink.add(jsonEncode({
      'type': 'speak',
      'text': text,
      'voice_id': voiceId,
    }));
  }

  void _handleAudio(Map<String, dynamic> data) {
    final audioBytes = base64Decode(data['data']);
    _audioPlayer?.play(BytesSource(audioBytes));
  }

  void _handleViseme(Map<String, dynamic> data) {
    _visemeController.add(VisemeEvent(
      viseme: data['value'],
      ptsMs: data['pts_ms'],
      durationMs: data['duration_ms'] ?? 100,
    ));
  }

  @override
  void stop() {
    _channel?.sink.add(jsonEncode({'type': 'stop'}));
    _audioPlayer?.stop();
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _audioPlayer?.dispose();
    _visemeController.close();
  }
}

