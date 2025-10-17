import 'dart:convert';
import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'lipsync_strategy.dart';

/// File-Based Strategy (Aktuelles System)
class FileBasedStrategy implements LipsyncStrategy {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> speak(String text, String voiceId) async {
    // Wird vom Chat-Screen mit bereits decodierter Audio-Datei aufgerufen
    // Diese Strategy ist kompatibel mit dem bestehenden Flow
  }

  /// Spielt lokale Audio-Datei ab
  Future<void> playFromPath(String path) async {
    await _player.stop();
    await _player.setFilePath(path);
    await _player.setLoopMode(LoopMode.off);
    await _player.play();
  }

  @override
  void stop() {
    _player.stop();
  }

  @override
  void dispose() {
    _player.dispose();
  }
}
