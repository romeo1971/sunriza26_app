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
  StreamSubscription? _channelSubscription;
  AudioPlayer? _audioPlayer;
  bool _isConnecting = false;
  StreamingMp3Source? _currentSource;
  int _chunkCount = 0;
  bool _playbackStarted = false;
  int _bytesAccumulated = 0;
  int _activeSeq = 0;

  final StreamController<VisemeEvent> _visemeController =
      StreamController<VisemeEvent>.broadcast();

  @override
  Stream<VisemeEvent> get visemeStream => _visemeController.stream;

  @override
  void Function(bool isPlaying)? onPlaybackStateChanged;

  StreamingStrategy({required String orchestratorUrl})
    : _orchestratorUrl = orchestratorUrl {
    // LAZY: Connection erst beim ersten speak() (spart Ressourcen!)
  }

  Future<void> _connect() async {
    if (_channel != null || _isConnecting) return;
    _isConnecting = true;

    // Alte Subscription canceln (verhindert Doppel-Events!)
    await _channelSubscription?.cancel();
    _channelSubscription = null;

    _audioPlayer = AudioPlayer();

    try {
      final uri = Uri.parse(_orchestratorUrl);
      _channel = WebSocketChannel.connect(uri);

      // ignore: avoid_print
      print('✅ WS connecting: $_orchestratorUrl');

      // Stream-Listener SOFORT!
      _channelSubscription = _channel!.stream.listen(
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
          print('🔌 WS closed (will reconnect on next speak)');
          _channelSubscription?.cancel();
          _channelSubscription = null;
          _channel = null;
          _isConnecting = false;
        },
        onError: (e) {
          // ignore: avoid_print
          print('❌ WS stream error: $e');
          _channelSubscription?.cancel();
          _channelSubscription = null;
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
  Future<void> warmUp() async {
    // Stelle sicher, dass die WS einmal aufgebaut ist (kaltstart vermeiden)
    if (_channel == null && !_isConnecting) {
      await _connect();
    }
  }

  @override
  Future<void> speak(String text, String voiceId) async {
    // Sicherstellen: vorherige Wiedergabe stoppen, sonst startet 2. Audio nicht
    await _audioPlayer?.stop();
    _playbackStarted = false;
    _bytesAccumulated = 0;
    // Lazy connect on focus/input (deine Anweisung!)
    if (_channel == null && !_isConnecting) {
      await _connect();
    }

    while (_isConnecting) {
      await Future.delayed(Duration(milliseconds: 50));
    }

    if (_channel == null) {
      // ignore: avoid_print
      print('❌ WS connection failed');
      return;
    }

    // IMMER neuen Source erstellen (kein reset!)
    // Alten Source loslassen → GC räumt auf
    _currentSource = StreamingMp3Source();
    _chunkCount = 0;

    // ignore: avoid_print
    print('🎵 Starting streaming playback (reset: ${_currentSource != null})');

    // Neue Sequenz-ID vergeben und mitsenden
    _activeSeq += 1;
    final seq = _activeSeq;
    _channel!.sink.add(
      jsonEncode({
        'type': 'speak',
        'text': text,
        'voice_id': voiceId,
        'seq': seq,
      }),
    );
  }

  void _handleAudio(Map<String, dynamic> data) {
    // Nur aktuelle Sequenz verarbeiten (späte Chunks werden ignoriert)
    final int? seq = data['seq'] is int ? data['seq'] as int : null;
    if (seq != null && seq != _activeSeq) {
      return;
    }
    final audioBytes = base64Decode(data['data']);
    _chunkCount++;
    _bytesAccumulated += audioBytes.length;

    // ignore: avoid_print
    print('🔊 Chunk $_chunkCount: ${audioBytes.length} bytes');

    if (_currentSource == null) return;

    // Chunk zum Stream hinzufügen
    _currentSource!.addChunk(audioBytes);

    // Start erst, wenn genügend Daten gepuffert sind (verhindert -11800)
    const int minStartBytes =
        8 * 1024; // ~8 KB – kurze Grüße starten zuverlässig
    if (!_playbackStarted && _bytesAccumulated >= minStartBytes) {
      _playbackStarted = true;
      _startPlayback();
    }
  }

  Future<void> _startPlayback() async {
    if (_currentSource == null || _audioPlayer == null) {
      // ignore: avoid_print
      print(
        '❌ Cannot start playback: source=${_currentSource != null}, player=${_audioPlayer != null}',
      );
      return;
    }

    // Starte nur, wenn mind. 1 Chunk vorliegt
    if (_chunkCount == 0) {
      // ignore: avoid_print
      print('⚠️ Skip start: no chunks yet');
      return;
    }

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
      // Einmaliger Recover: Player neu aufsetzen und erneut versuchen
      try {
        await _audioPlayer?.dispose();
        _audioPlayer = AudioPlayer();
        await _audioPlayer!.setAudioSource(_currentSource!);
        onPlaybackStateChanged?.call(true);
        await _audioPlayer!.play();
        print('✅ Playback recovered and started');
      } catch (e2) {
        print('❌ Playback recover failed: $e2');
        _playbackStarted = false;
        onPlaybackStateChanged?.call(false);
      }
    }
  }

  void _handleViseme(Map<String, dynamic> data) {
    final int? seq = data['seq'] is int ? data['seq'] as int : null;
    if (seq != null && seq != _activeSeq) {
      return;
    }
    _visemeController.add(
      VisemeEvent(
        viseme: data['value'],
        ptsMs: data['pts_ms'],
        durationMs: data['duration_ms'] ?? 100,
      ),
    );
  }

  void _handleDone() {
    // done ohne Seq oder falsche Seq ignorieren
    // (Listener ruft diese Methode nur über Schalter; hier keine Seq verfügbar)
    // ignore: avoid_print
    print('✅ Stream done ($_chunkCount chunks)');

    // Falls noch nicht gestartet (sehr kurz), jetzt einmal anstoßen
    if (!_playbackStarted && _bytesAccumulated > 0) {
      _playbackStarted = true;
      _startPlayback();
    }

    // Stream als komplett markieren
    _currentSource?.complete();

    // Callback: Playback ends!
    onPlaybackStateChanged?.call(false);
    _playbackStarted = false;
    _bytesAccumulated = 0;
  }

  @override
  Future<void> stop() async {
    try {
      _channel?.sink.add(jsonEncode({'type': 'stop'}));
    } catch (_) {}
    try {
      await _audioPlayer?.stop();
    } catch (_) {}
    _currentSource?.complete();
    _chunkCount = 0;
    _bytesAccumulated = 0;
  }

  @override
  void dispose() {
    _channelSubscription?.cancel();
    _channel?.sink.close();
    _audioPlayer?.dispose();
    _currentSource?.complete();
    _visemeController.close();
  }
}
