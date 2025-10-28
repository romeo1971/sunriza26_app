import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'lipsync_strategy.dart';
import 'package:sunriza26/config.dart';
import 'package:sunriza26/services/env_service.dart';
import 'package:http/http.dart' as http;
import 'package:sunriza26/services/livekit_service.dart';

/// MP3 Stream Audio Source für just_audio
/// Spielt ersten Chunk SOFORT, weitere Chunks werden nachgestreamt
class StreamingMp3Source extends StreamAudioSource {
  final StreamController<List<int>> _controller =
      StreamController<List<int>>.broadcast();
  final List<List<int>> _buffer = [];
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

    // just_audio crasht bei sourceLength == null auf einigen Plattformen
    // → 0 verwenden (unbekannt), Content-Length weiterhin null (chunked)
    return StreamAudioResponse(
      sourceLength: 0,
      contentLength: null, // verhindert Content-Length-Mismatch
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
  bool _useHttpStream = false; // neuer Modus: Audio via HTTP setUrl()
  final bool _clientPlaysAudio =
      true; // Sofortiges Client‑Audio aktiv (parallel zu LiveKit)

  Future<String?> _awaitRoomName({
    Duration timeout = const Duration(milliseconds: 400),
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
    _currentSource = StreamingMp3Source();

    try {
      final uri = Uri.parse(_orchestratorUrl);
      _channel = WebSocketChannel.connect(uri);

      debugPrint('✅ WS connecting: $_orchestratorUrl');

      // Stream-Listener SOFORT!
      if (_channel == null) {
        _isConnecting = false;
        return;
      }
      _channelSubscription = _channel!.stream.listen(
        (message) {
          debugPrint('📩 WS msg (${message.toString().length} chars)');
          try {
            final data = jsonDecode(message);
            debugPrint('📩 Type: ${data['type']}');
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
          debugPrint('🔌 WS closed (will reconnect on next speak)');
          _channelSubscription?.cancel();
          _channelSubscription = null;
          _channel = null;
          _isConnecting = false;
        },
        onError: (e) {
          debugPrint('❌ WS stream error: $e');
          _channelSubscription?.cancel();
          _channelSubscription = null;
          _channel = null;
          _isConnecting = false;
        },
      );

      _isConnecting = false;
    } catch (e) {
      debugPrint('❌ WS connect failed: $e');
      _channel = null;
      _isConnecting = false;
      rethrow;
    }
  }

  @override
  Future<void> warmUp() async {
    // Einmaliger Warmup-Ping gegen /health (kein permanentes Warmhalten)
    try {
      if (!EnvService.orchestratorWarmupEnabled()) return;
      final httpBase = AppConfig.orchestratorUrl
          .replaceFirst('wss://', 'https://')
          .replaceFirst('ws://', 'http://');
      final url = httpBase.endsWith('/')
          ? '${httpBase}health'
          : '$httpBase/health';
      // 1 Ping, kurze Timeout → verhindert Hängenbleiben
      await http.get(Uri.parse(url)).timeout(const Duration(seconds: 3));
    } catch (_) {
      // Ignorieren – Warmup ist Best-Effort
    }
  }

  @override
  Future<void> speak(String text, String voiceId) async {
    // Kein lokales Playback – nur Steuersignal und PCM-Forwarding
    try {
      await _audioPlayer?.stop();
    } catch (_) {}
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
      debugPrint('❌ WS connection failed');
      return;
    }

    // Sicherstellen, dass eine Audioquelle vorhanden ist
    _currentSource ??= StreamingMp3Source();

    // REMOVED: PCM-Forwarding vom Client zu MuseTalk
    // → Orchestrator sendet PCM direkt an MuseTalk (effizienter, vermeidet permanente Client-WS)

    // WS: Steuersignal SOFORT senden (nicht blockieren!)
    _activeSeq += 1;
    final seq = _activeSeq;

    // Parallel: HTTP Audio starten (nicht warten!)
    _startHttpAudio(text, voiceId);

    // WS für LiveKit/MuseTalk (erhöhtes Timeout für Cold Start!)
    final String? lkRoom = await _awaitRoomName(
      timeout: const Duration(milliseconds: 2000),
    );
    if (_channel == null) {
      debugPrint('❌ WS not connected');
      return;
    }
    final msg = {
      'type': 'speak',
      'text': text,
      'voice_id': voiceId,
      'seq': seq,
      'mp3': false,
      if (lkRoom != null && lkRoom.isNotEmpty) 'room': lkRoom,
      if (lkRoom != null && lkRoom.isNotEmpty) 'pcm': true,
    };
    debugPrint('📤 Sending WS speak: ${jsonEncode(msg)}');
    _channel!.sink.add(jsonEncode(msg));

    return;
  }

  void _startHttpAudio(String text, String voiceId) {
    // Async - blockiert speak() NICHT!
    () async {
      try {
        final httpBase = AppConfig.orchestratorUrl
            .replaceFirst('wss://', 'https://')
            .replaceFirst('ws://', 'http://');
        final playUrl = httpBase.endsWith('/')
            ? '${httpBase}tts/stream?voice_id=$voiceId&text=${Uri.encodeComponent(text)}'
            : '$httpBase/tts/stream?voice_id=$voiceId&text=${Uri.encodeComponent(text)}';
        debugPrint('🎵 HTTP Audio starting: ${playUrl.substring(0, 80)}...');
        await _audioPlayer?.stop();
        _audioPlayer ??= AudioPlayer();
        await _audioPlayer!.setUrl(playUrl);
        await _audioPlayer!.play();
        debugPrint('✅ HTTP Audio PLAYING (300-700ms)');
        onPlaybackStateChanged?.call(true);

        // Zusätzlich Orchestrator /speak triggern (BitHuman Lipsync)
        try {
          final speakUrl = httpBase.endsWith('/') ? '${httpBase}speak' : '$httpBase/speak';
          final String? room = await _awaitRoomName(timeout: const Duration(milliseconds: 500));
          final payload = <String, dynamic>{'text': text, if (room != null && room.isNotEmpty) 'room': room};
          // Fire-and-forget
          // ignore: unawaited_futures
          http.post(Uri.parse(speakUrl), headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload)).timeout(const Duration(seconds: 2));
        } catch (_) {}
      } catch (e) {
        debugPrint('❌ HTTP Audio failed: $e');
      }
    }();
  }

  void _handleAudio(Map<String, dynamic> data) {
    if (!_clientPlaysAudio) {
      return; // Lokales Audio deaktiviert – LiveKit spielt ab
    }
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

    _currentSource ??= StreamingMp3Source();

    // Chunk zum Stream hinzufügen
    _currentSource!.addChunk(audioBytes);

    // Start erst, wenn genügend Daten gepuffert sind (verhindert -11800)
    const int minStartBytes = 8 * 1024; // ~8 KB – schnellere Startzeit
    if (!_playbackStarted && _bytesAccumulated >= minStartBytes) {
      _playbackStarted = true;
      _startPlayback();
    }
  }

  Future<void> _startPlayback() async {
    // Nur WS‑Modus wird genutzt
    if (_currentSource == null || _audioPlayer == null) {
      debugPrint(
        '❌ Cannot start playback: source=${_currentSource != null}, player=${_audioPlayer != null}',
      );
      return;
    }

    // Starte nur, wenn mind. 1 Chunk vorliegt
    if (_chunkCount == 0) {
      debugPrint('⚠️ Skip start: no chunks yet');
      return;
    }

    try {
      debugPrint('▶️ Starting playback with first chunk!');

      // iOS: Audio-Session für Playback aktivieren
      try {
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.speech());
      } catch (e) {
        debugPrint('⚠️ Audio session config failed: $e');
      }

      if (_currentSource == null || _audioPlayer == null) {
        debugPrint('❌ Source/Player null beim Start');
        return;
      }

      try {
        await _audioPlayer!.setAudioSource(_currentSource!, preload: false);
      } catch (e) {
        debugPrint('❌ setAudioSource failed: $e - continuing anyway');
        // Continue - Publisher soll trotzdem starten
      }

      // Callback: Playback starts! (auch wenn setAudioSource crashed)
      // WICHTIG: Für MuseTalk Publisher
      onPlaybackStateChanged?.call(true);

      try {
        await _audioPlayer!.play();
      } catch (e) {
        debugPrint('❌ play() failed: $e');
      }

      // Nach Playback-Ende Callback setzen und Source schließen
      // Die Source bleibt offen, bis explizit stop()/dispose() aufgerufen wird
      StreamSubscription? psSub;
      psSub = _audioPlayer!.playerStateStream.listen(
        (s) {
          if (s.processingState == ProcessingState.completed) {
            onPlaybackStateChanged?.call(false);
            try {
              _currentSource?.complete();
            } catch (_) {}
            psSub?.cancel();
          }
        },
        onError: (e) {
          // ignore: avoid_print
          print('⚠️ Player state stream error: $e');
        },
      );

      debugPrint('✅ Playback started (streaming continues)');
    } catch (e) {
      debugPrint('❌ Playback start error: $e');
      // Einmaliger Recover: Player neu aufsetzen und erneut versuchen
      try {
        await _audioPlayer?.dispose();
        _audioPlayer = AudioPlayer();
        await _audioPlayer!.setAudioSource(_currentSource!);
        onPlaybackStateChanged?.call(true);
        await _audioPlayer!.play();
        debugPrint('✅ Playback recovered and started');
      } catch (e2) {
        debugPrint('❌ Playback recover failed: $e2');
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
    debugPrint('✅ Stream done ($_chunkCount chunks)');

    // Falls noch nicht gestartet (sehr kurz), jetzt einmal anstoßen
    if (!_playbackStarted && _bytesAccumulated > 0) {
      _playbackStarted = true;
      _startPlayback();
    }

    // Source NICHT hier schließen – warten bis der Player completed meldet

    // Nicht sofort complete/callback – warte auf tatsächliches Player-Ende
    _playbackStarted = false;
    _bytesAccumulated = 0;

    // Dem Orchestrator explizit signalisieren, dass die Session beendet ist
    try {
      _channel?.sink.add(jsonEncode({'type': 'stop'}));
    } catch (_) {}
    // WebSocket schließen nach done → Container kann scale-down
    _closeWebSocket();
  }

  void _closeWebSocket() {
    try {
      _channelSubscription?.cancel();
      _channelSubscription = null;
      _channel?.sink.close();
      _channel = null;
      _isConnecting = false;
      debugPrint('🔌 WS closed (scale-down enabled)');
    } catch (e) {
      debugPrint('⚠️ WS close error: $e');
    }
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
    // WebSocket schließen
    _closeWebSocket();
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
    _pcmController.close();
  }
}
