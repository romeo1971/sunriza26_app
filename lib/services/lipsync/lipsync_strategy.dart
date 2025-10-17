import 'dart:async';

/// Lipsync Strategy Interface
abstract class LipsyncStrategy {
  Future<void> speak(String text, String voiceId);
  Future<void> stop();
  Future<void> warmUp() async {}
  void dispose();
  Stream<VisemeEvent>? get visemeStream => null;

  // Callback für Playback-Status
  void Function(bool isPlaying)? onPlaybackStateChanged;
}

/// Viseme Event
class VisemeEvent {
  final String viseme;
  final int ptsMs;
  final int durationMs;

  VisemeEvent({
    required this.viseme,
    required this.ptsMs,
    required this.durationMs,
  });
}
