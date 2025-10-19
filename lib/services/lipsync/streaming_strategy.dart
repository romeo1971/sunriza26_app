import 'dart:async';
import 'dart:convert';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'lipsync_strategy.dart';
import 'package:sunriza26/config.dart';
import 'package:sunriza26/services/livekit_service.dart';

/// MP3 Stream Audio Source für just_audio
/// Spielt ersten Chunk SOFORT, weitere Chunks werden nachgestreamt
class StreamingMp3Source extends StreamAudioSource {
  final StreamController<List<int>> _controller =
      StreamController<List<int>>.broadcast();
  final List<List<int>> _buffer = [];
  bool _isComplete = false;
  bool _disposed = false;

  void addChunk(List<int> bytes) {
    if (_disposed) return;
    _buffer.add(bytes);
    if (!_controller.isClosed) {
      _controller.add(bytes);
    }
  }

  void complete() {
    if (_disposed) return;
    _isComplete = true;
    if (!_controller.isClosed) {
      _controller.close();
    }
  }

  void dispose() {
    _disposed = true;
    if (!_controller.isClosed) {
      _controller.close();
    }
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    if (_disposed) {
      // Wenn disposed, leeren Stream zurückgeben (verhindert Null-Check Crash)
      return StreamAudioResponse(
        sourceLength: 0,
        contentLength: 0,
        contentType: 'audio/mpeg',
        stream: Stream.empty(),
        offset: 0,
        rangeRequestsSupported: false,
      );
    }

    final controller = StreamController<List<int>>();

    // Bereits gepufferte Daten SOFORT senden
    for (final chunk in _buffer) {
      if (!controller.isClosed && !_disposed) {
        controller.add(chunk);
      }
    }

    // Neue Chunks weiterleiten
    final sub = _controller.stream.listen(
      (data) {
        if (!controller.isClosed && !_disposed) {
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
    // WICHTIG: Für echtes Streaming KEINE Content-Length setzen.
    // Wenn komplett: Länge melden, sonst null (chunked Transfer).
    final int? lengthWhenComplete = _isComplete ? bufferSize : null;

    return StreamAudioResponse(
      sourceLength: lengthWhenComplete,
      contentLength: lengthWhenComplete,
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
  WebSocketChannel? _museTalkChannel; // persistente WS zu MuseTalk
  StreamSubscription? _channelSubscription;
  AudioPlayer? _audioPlayer;
  bool _isConnecting = false;
  StreamingMp3Source? _currentSource;
  int _chunkCount = 0;
  bool _playbackStarted = false;
  int _bytesAccumulated = 0;
  int _activeSeq = 0;
  bool _useHttpStream = false; // neuer Modus: Audio via HTTP setUrl()
  bool _museTalkRoomSent = false; // Raumname nur einmal senden

  Future<String?> _awaitRoomName({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final start = DateTime.now();
    while (true) {
      final rn = LiveKitService().roomName;
      if (rn != null && rn.isNotEmpty) return rn;
      if (DateTime.now().difference(start) >= timeout) return null;
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  final StreamController<VisemeEvent> _visemeController =
      StreamController<VisemeEvent>.broadcast();
  final StreamController<PcmChunkEvent> _pcmController =
      StreamController<PcmChunkEvent>.broadcast();

  @override
  Stream<VisemeEvent> get visemeStream => _visemeController.stream;
  @override
  Stream<PcmChunkEvent> get pcmStream => _pcmController.stream;

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
              case 'pcm':
                _handlePcm(data);
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
    // Sicherstellen: vorherige Wiedergabe stoppen (Player NICHT disposen)
    try {
      await _audioPlayer?.stop();
    } catch (_) {}
    _audioPlayer ??= AudioPlayer();
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

    // Zusätzlich: PCM an MuseTalk-WS weiterleiten (Raumname zuerst)
    try {
      final museTalkWs = AppConfig.museTalkWsUrl;
      final String? roomName = await _awaitRoomName();
      if (roomName == null || roomName.isEmpty) {
        // ignore: avoid_print
        print('⚠️ Kein LiveKit-Raum – PCM-Forwarding übersprungen');
        return;
      }
      _museTalkChannel ??= WebSocketChannel.connect(Uri.parse(museTalkWs));
      // Erste Nachricht: Room als Bytes (Server erwartet receive_bytes für das erste Frame)
      if (!_museTalkRoomSent) {
        _museTalkChannel!.sink.add(utf8.encode(roomName));
        _museTalkRoomSent = true;
      }
      // PCM kommt später aus Orchestrator via _pcmController; hier nur Hook setzen
      _pcmController.stream.listen((evt) {
        try {
          _museTalkChannel!.sink.add(evt.bytes);
        } catch (_) {}
      });
    } catch (e) {
      // ignore: avoid_print
      print('⚠️ MuseTalk WS forward failed: $e');
    }

    // HTTP‑Streaming nutzen (stabiler als WS->StreamAudioSource)
    // Alte Source ggf. später entsorgen
    final oldSource = _currentSource;
    _currentSource = null;
    _useHttpStream = true;
    if (oldSource != null) {
      Future.delayed(const Duration(seconds: 1), () {
        try {
          oldSource.complete();
        } catch (_) {}
        try {
          oldSource.dispose();
        } catch (_) {}
      });
    }
    _chunkCount = 0;

    // ignore: avoid_print
    print('🎵 Starting streaming playback via HTTP source');

    // Neue Sequenz-ID vergeben und mitsenden
    _activeSeq += 1;
    final seq = _activeSeq;
    _channel!.sink.add(
      jsonEncode({
        'type': 'speak',
        'text': text,
        'voice_id': voiceId,
        'seq': seq,
        'mp3': false, // MP3 kommt jetzt über HTTP-Stream
      }),
    );

    // HTTP‑Stream URL vom Orchestrator verwenden
    try {
      final httpBase = _orchestratorUrl
          .replaceFirst('wss://', 'https://')
          .replaceFirst('ws://', 'http://');
      final url = Uri.parse(httpBase.replaceFirst(RegExp(r"/+$"), ''))
          .resolve('/tts/stream')
          .replace(queryParameters: {'voice_id': voiceId, 'text': text})
          .toString();
      // ignore: avoid_print
      print('🎧 HTTP stream URL: $url');

      // iOS: Audio-Session vorbereiten
      try {
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.speech());
      } catch (_) {}

      await _audioPlayer!.setUrl(url);
      onPlaybackStateChanged?.call(true);
      await _audioPlayer!.play();
    } catch (e) {
      // ignore: avoid_print
      print('❌ HTTP audio set/play failed: $e');
    }
  }

  void _handleAudio(Map<String, dynamic> data) {
    if (_useHttpStream) {
      // Im HTTP‑Modus kommt kein 'audio' mehr über WS
      return;
    }
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

    // WICHTIG: Signal an UI dass Audio kommt (für MuseTalk Publisher Start)
    if (_chunkCount == 1) {
      onPlaybackStateChanged?.call(true);
    }

    if (_currentSource == null) return;

    // Chunk zum Stream hinzufügen
    _currentSource!.addChunk(audioBytes);

    // Start erst, wenn genügend Daten gepuffert sind (verhindert -11800)
    const int minStartBytes =
        64 * 1024; // ~64 KB – verhindert frühes Ausgehen bei 2. Audio
    if (!_playbackStarted && _bytesAccumulated >= minStartBytes) {
      _playbackStarted = true;
      _startPlayback();
    }
  }

  Future<void> _startPlayback() async {
    if (_useHttpStream) {
      // HTTP‑Modus steuert Playback direkt über setUrl()/play()
      return;
    }
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

      // iOS: Audio-Session für Playback aktivieren
      try {
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.speech());
      } catch (e) {
        print('⚠️ Audio session config failed: $e');
      }

      if (_currentSource == null || _audioPlayer == null) {
        print('❌ Source/Player null beim Start');
        return;
      }

      try {
        await _audioPlayer!.setAudioSource(_currentSource!);
      } catch (e) {
        print('❌ setAudioSource failed: $e - continuing anyway');
        // Continue - Publisher soll trotzdem starten
      }

      // Callback: Playback starts! (auch wenn setAudioSource crashed)
      // WICHTIG: Für MuseTalk Publisher
      onPlaybackStateChanged?.call(true);

      try {
        await _audioPlayer!.play();
      } catch (e) {
        print('❌ play() failed: $e');
      }

      // Nach Playback-Ende Callback setzen und Source schließen
      // Die Source bleibt offen, bis explizit stop()/dispose() aufgerufen wird
      _audioPlayer!.playerStateStream
          .firstWhere((s) => s.processingState == ProcessingState.completed)
          .then((_) {
            onPlaybackStateChanged?.call(false);
            // Jetzt Source schließen – Player ist fertig
            try {
              _currentSource?.complete();
            } catch (_) {}
          })
          .catchError((e) {
            // ignore: avoid_print
            print('⚠️ Player state stream error: $e');
          });

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

  void _handlePcm(Map<String, dynamic> data) {
    final int pts = data['pts_ms'] ?? 0;
    final String b64 = data['data'] ?? '';
    if (b64.isEmpty) return;
    final bytes = base64Decode(b64);
    _pcmController.add(PcmChunkEvent(bytes: bytes, ptsMs: pts));
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

    // Source NICHT hier schließen – warten bis der Player completed meldet

    // Nicht sofort complete/callback – warte auf tatsächliches Player-Ende
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
    _useHttpStream = false;
    // Source sauber schließen und disposen
    try {
      _currentSource?.complete();
      _currentSource?.dispose();
    } catch (_) {}
    _chunkCount = 0;
    _bytesAccumulated = 0;
  }

  @override
  void dispose() {
    _channelSubscription?.cancel();
    _channel?.sink.close();
    // Source explizit disposen
    try {
      _currentSource?.complete();
    } catch (_) {}
    _currentSource?.dispose();
    _audioPlayer?.dispose();
    _visemeController.close();
  }
}
