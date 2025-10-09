import 'package:audioplayers/audioplayers.dart';

/// Singleton Service für globales Audio-Player Management
/// Ermöglicht das Stoppen von Audio-Playern bei Hot-Reload/Restart
class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._internal();

  factory AudioPlayerService() => _instance;

  AudioPlayerService._internal();

  AudioPlayer? _currentPlayer;

  void setCurrentPlayer(AudioPlayer player) {
    _currentPlayer = player;
  }

  Future<void> stopAll() async {
    final p = _currentPlayer;
    _currentPlayer = null; // Guard: entferne Referenz vor dem Dispose
    if (p != null) {
      try {
        await p.stop();
      } catch (_) {}
      try {
        await p.dispose();
      } catch (_) {}
    }
  }

  AudioPlayer? get currentPlayer => _currentPlayer;
}
