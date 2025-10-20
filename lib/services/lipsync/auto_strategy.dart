import 'dart:async';
import 'package:http/http.dart' as http;

import 'lipsync_strategy.dart';
import 'file_based_strategy.dart';
import 'streaming_strategy.dart';
import 'package:sunriza26/config.dart';

/// Automatische Umschaltung zwischen Streaming (Modal) und FileBased
/// - Wenn Modal down → FileBased nutzen
/// - Sobald Modal wieder erreichbar → automatisch zurück zu Streaming
class AutoLipsyncStrategy implements LipsyncStrategy {
  final StreamingStrategy _streaming;
  final FileBasedStrategy _fileBased;

  LipsyncStrategy _active;
  Timer? _probeTimer;

  AutoLipsyncStrategy({required String orchestratorUrl})
    : _streaming = StreamingStrategy(orchestratorUrl: orchestratorUrl),
      _fileBased = FileBasedStrategy(),
      _active = FileBasedStrategy() {
    // Initial schnell prüfen; nicht blockierend
    _probeAvailability();
    // Periodisch prüfen, ob Streaming wieder verfügbar ist (wenn FileBased aktiv ist)
    _probeTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_active is FileBasedStrategy) {
        _probeAvailability();
      }
    });
  }

  // Extern gesetzter Callback wird an die aktive Strategy weitergereicht
  @override
  void Function(bool isPlaying)? onPlaybackStateChanged;

  @override
  Stream<VisemeEvent>? get visemeStream => _streaming.visemeStream;

  @override
  Stream<PcmChunkEvent>? get pcmStream => _streaming.pcmStream;

  Future<void> _switchTo(LipsyncStrategy next) async {
    if (identical(_active, next)) return;
    _active = next;
    // Callback auch auf Sub-Strategien setzen
    _streaming.onPlaybackStateChanged = onPlaybackStateChanged;
    _fileBased.onPlaybackStateChanged = onPlaybackStateChanged;
  }

  Future<void> _probeAvailability() async {
    final bool ok = await _checkModalHealth();
    if (ok) {
      await _switchTo(_streaming);
      // Warm-up schadet nicht (vermeidet Kaltstart beim nächsten speak)
      try {
        await _streaming.warmUp();
      } catch (_) {}
    } else {
      await _switchTo(_fileBased);
    }
  }

  Future<bool> _checkModalHealth() async {
    try {
      // Aus WS-URL eine HTTP Health-URL bauen
      final httpBase = AppConfig.orchestratorUrl
          .replaceFirst('wss://', 'https://')
          .replaceFirst('ws://', 'http://');
      final url = httpBase.endsWith('/')
          ? '${httpBase}health'
          : '$httpBase/health';
      final resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(milliseconds: 1200));
      if (resp.statusCode == 200) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> speak(String text, String voiceId) async {
    // Vor jedem Speak kurz prüfen; nicht zu teuer
    await _probeAvailability();
    // Callback sicher weiterreichen
    _streaming.onPlaybackStateChanged = onPlaybackStateChanged;
    _fileBased.onPlaybackStateChanged = onPlaybackStateChanged;
    await _active.speak(text, voiceId);
  }

  @override
  Future<void> stop() async {
    try {
      await _streaming.stop();
    } catch (_) {}
    try {
      await _fileBased.stop();
    } catch (_) {}
  }

  @override
  Future<void> warmUp() async {
    // Warm-up bevorzugt Streaming; FileBased braucht kein Warm-up
    await _probeAvailability();
  }

  @override
  void dispose() {
    try {
      _probeTimer?.cancel();
    } catch (_) {}
    try {
      _streaming.dispose();
    } catch (_) {}
    try {
      _fileBased.dispose();
    } catch (_) {}
  }
}
