import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'lipsync_strategy.dart';

/// Streaming Strategy (WebSocket-basiert)
/// Sammelt MP3-Chunks und spielt sie als komplette Datei ab
class StreamingStrategy implements LipsyncStrategy {
  final String _orchestratorUrl;
  WebSocketChannel? _channel;
  AudioPlayer? _audioPlayer;
  bool _isConnecting = false;
  final List<List<int>> _audioChunks = [];
  bool _isCollecting = false;

  final StreamController<VisemeEvent> _visemeController =
      StreamController<VisemeEvent>.broadcast();

  @override
  Stream<VisemeEvent> get visemeStream => _visemeController.stream;

  StreamingStrategy({required String orchestratorUrl})
    : _orchestratorUrl = orchestratorUrl {
    // Connect SOFORT beim Init!
    _connect();
  }

  Future<void> _connect() async {
    if (_channel != null || _isConnecting) return;
    _isConnecting = true;

    _audioPlayer = AudioPlayer();

    try {
      final uri = Uri.parse(_orchestratorUrl);
      _channel = WebSocketChannel.connect(uri);

      // ignore: avoid_print
      print('✅ WS connecting: $_orchestratorUrl');

      // Stream-Listener SOFORT!
      _channel!.stream.listen(
        (message) {
          // ignore: avoid_print
          print('📩 WS msg (${message.toString().length} chars)');
          try {
            final data = jsonDecode(message);
            // ignore: avoid_print
            print('📩 Type: ${data['type']}');
            switch (data['type']) {
              case 'audio':
                _handleAudio(data);
                break;
              case 'viseme':
                _handleViseme(data);
                break;
              case 'done':
                // Stream fertig
                _handleDone();
                break;
              case 'error':
                // ignore: avoid_print
                print('❌ Orchestrator error: ${data['message']}');
                break;
            }
          } catch (e) {
            // ignore: avoid_print
            print('❌ JSON parse error: $e');
          }
        },
        onDone: () {
          // ignore: avoid_print
          print('🔌 WS closed');
          _channel = null;
          _isConnecting = false;
        },
        onError: (e) {
          // ignore: avoid_print
          print('❌ WS stream error: $e');
          _channel = null;
          _isConnecting = false;
        },
      );

      _isConnecting = false;
    } catch (e) {
      // ignore: avoid_print
      print('❌ WS connect failed: $e');
      _channel = null;
      _isConnecting = false;
      rethrow;
    }
  }

  @override
  Future<void> speak(String text, String voiceId) async {
    // Warte bis Connection ready
    while (_isConnecting) {
      await Future.delayed(Duration(milliseconds: 50));
    }

    if (_channel == null) {
      // ignore: avoid_print
      print('❌ No WS connection for speak');
      return;
    }

    // Reset
    await _audioPlayer?.stop();
    _audioChunks.clear();
    _isCollecting = true;

    _channel!.sink.add(
      jsonEncode({'type': 'speak', 'text': text, 'voice_id': voiceId}),
    );
  }

  void _handleAudio(Map<String, dynamic> data) {
    final audioBytes = base64Decode(data['data']);
    // ignore: avoid_print
    print('🔊 audio ${audioBytes.length} bytes');

    if (_isCollecting) {
      _audioChunks.add(audioBytes);
    }
  }

  void _handleViseme(Map<String, dynamic> data) {
    _visemeController.add(
      VisemeEvent(
        viseme: data['value'],
        ptsMs: data['pts_ms'],
        durationMs: data['duration_ms'] ?? 100,
      ),
    );
  }

  Future<void> _handleDone() async {
    // ignore: avoid_print
    print('✅ Stream done, playing ${_audioChunks.length} chunks');
    _isCollecting = false;

    if (_audioChunks.isEmpty) return;

    // Alle Chunks zu einer MP3-Datei zusammenfügen
    final allBytes = _audioChunks.expand((c) => c).toList();

    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.mp3',
      );
      await tempFile.writeAsBytes(allBytes);

      // ignore: avoid_print
      print('🎵 Playing MP3: ${tempFile.path} (${allBytes.length} bytes)');

      await _audioPlayer?.setFilePath(tempFile.path);
      await _audioPlayer?.play();

      // File nach 10 Sek löschen
      Future.delayed(Duration(seconds: 10), () {
        try {
          tempFile.deleteSync();
        } catch (_) {}
      });
    } catch (e) {
      // ignore: avoid_print
      print('❌ Audio play error: $e');
    }

    _audioChunks.clear();
  }

  @override
  void stop() {
    _channel?.sink.add(jsonEncode({'type': 'stop'}));
    _audioPlayer?.stop();
    _isCollecting = false;
    _audioChunks.clear();
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _audioPlayer?.dispose();
    _visemeController.close();
  }
}
