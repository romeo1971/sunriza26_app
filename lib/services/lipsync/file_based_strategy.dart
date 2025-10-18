import 'package:just_audio/just_audio.dart';
import 'lipsync_strategy.dart';

/// File-Based Strategy (Aktuelles System)
class FileBasedStrategy implements LipsyncStrategy {
  final AudioPlayer _player = AudioPlayer();

  @override
  Stream<VisemeEvent>? get visemeStream => null;

  @override
  // File-basiert: Es gibt keinen PCM-Stream. Dieser Getter erfüllt nur den Interface‑Kontrakt,
  // damit der Build stabil bleibt, wenn das Interface erweitert wurde.
  Stream<PcmChunkEvent>? get pcmStream => null;

  @override
  void Function(bool isPlaying)? onPlaybackStateChanged;

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
  Future<void> stop() async {
    await _player.stop();
  }

  @override
  Future<void> warmUp() async {
    // File-basiert: kein Warm-up nötig
  }

  @override
  void dispose() {
    _player.dispose();
  }
}
