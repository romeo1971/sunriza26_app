import 'dart:async';
import 'dart:convert';
import 'package:just_audio/just_audio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'lipsync_strategy.dart';

/// MP3 Stream Audio Source für just_audio
/// Spielt ersten Chunk SOFORT, weitere Chunks werden nachgestreamt
class StreamingMp3Source extends StreamAudioSource {
  StreamController<List<int>> _controller =
      StreamController<List<int>>.broadcast();
  final List<List<int>> _buffer = [];
  bool _isComplete = false;

  void reset() {
    _isComplete = false;
    _buffer.clear();
    if (!_controller.isClosed) {
      _controller.close();
    }
    _controller = StreamController<List<int>>.broadcast();
  }

  void addChunk(List<int> bytes) {
    _buffer.add(bytes);
    if (!_controller.isClosed) {
      _controller.add(bytes);
    }
  }

  void complete() {
    _isComplete = true;
    if (!_controller.isClosed) {
      _controller.close();
    }
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final controller = StreamController<List<int>>();

    // Bereits gepufferte Daten SOFORT senden
    for (final chunk in _buffer) {
      controller.add(chunk);
    }

    // Neue Chunks weiterleiten
    final sub = _controller.stream.listen(
      (data) {
        if (!controller.isClosed) {
          controller.add(data);
        }
      },
      onDone: () {
        if (!controller.isClosed) {
          controller.close();
        }
      },
    );

    controller.onCancel = () => sub.cancel();

    // Geschätzte Länge basierend auf aktuellem Buffer
    final bufferSize = _buffer.fold<int>(0, (sum, chunk) => sum + chunk.length);

    return StreamAudioResponse(
      sourceLength: _isComplete ? bufferSize : null,
      contentLength: _isComplete ? bufferSize : null,
      contentType: 'audio/mpeg',
      stream: controller.stream,
      offset: start ?? 0,
      rangeRequestsSupported: false,
    );
  }
}

/// Streaming Strategy (WebSocket-basiert)
/// ECHTES STREAMING: Spielt ersten Chunk nach ~200ms!
class StreamingStrategy implements LipsyncStrategy {
  final String _orchestratorUrl;
  WebSocketChannel? _channel;
  AudioPlayer? _audioPlayer;
  bool _isConnecting = false;
  StreamingMp3Source? _currentSource;
  int _chunkCount = 0;

  final StreamController<VisemeEvent> _visemeController =
      StreamController<VisemeEvent>.broadcast();

  @override
  Stream<VisemeEvent> get visemeStream => _visemeController.stream;
  
  @override
  void Function(bool isPlaying)? onPlaybackStateChanged;

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

    // Stop previous playback
    await _audioPlayer?.stop();

    // Reset existing source ODER neue erstellen
    if (_currentSource != null) {
      _currentSource!.reset();
    } else {
      _currentSource = StreamingMp3Source();
    }

    _chunkCount = 0;

    // ignore: avoid_print
    print('🎵 Starting streaming playback (reset: ${_currentSource != null})');

    _channel!.sink.add(
      jsonEncode({'type': 'speak', 'text': text, 'voice_id': voiceId}),
    );
  }

  void _handleAudio(Map<String, dynamic> data) {
    final audioBytes = base64Decode(data['data']);
    _chunkCount++;

    // ignore: avoid_print
    print('🔊 Chunk $_chunkCount: ${audioBytes.length} bytes');

    if (_currentSource == null) return;

    // Chunk zum Stream hinzufügen
    _currentSource!.addChunk(audioBytes);

    // ERSTER Chunk → SOFORT abspielen!
    if (_chunkCount == 1) {
      _startPlayback();
    }
  }

  Future<void> _startPlayback() async {
    if (_currentSource == null || _audioPlayer == null) return;

    try {
      // ignore: avoid_print
      print('▶️ Starting playback with first chunk!');

      await _audioPlayer!.setAudioSource(_currentSource!);

      // Callback: Playback starts!
      onPlaybackStateChanged?.call(true);

      await _audioPlayer!.play();

      // ignore: avoid_print
      print('✅ Playback started (streaming continues)');
    } catch (e) {
      // ignore: avoid_print
      print('❌ Playback start error: $e');
      onPlaybackStateChanged?.call(false);
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

  void _handleDone() {
    // ignore: avoid_print
    print('✅ Stream done ($_chunkCount chunks)');

    // Stream als komplett markieren
    _currentSource?.complete();

    // Callback: Playback ends!
    onPlaybackStateChanged?.call(false);
  }

  @override
  void stop() {
    _channel?.sink.add(jsonEncode({'type': 'stop'}));
    _audioPlayer?.stop();
    _currentSource?.complete();
    _chunkCount = 0;
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _audioPlayer?.dispose();
    _currentSource?.complete();
    _visemeController.close();
  }
}
