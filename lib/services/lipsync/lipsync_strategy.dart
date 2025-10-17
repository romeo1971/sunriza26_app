import 'dart:async';

/// Lipsync Strategy Interface
abstract class LipsyncStrategy {
  Future<void> speak(String text, String voiceId);
  void stop();
  void dispose();
  Stream<VisemeEvent>? get visemeStream => null;
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

