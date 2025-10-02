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
    await _currentPlayer?.stop();
    _currentPlayer?.dispose();
    _currentPlayer = null;
  }

  AudioPlayer? get currentPlayer => _currentPlayer;
}
