import 'file_based_strategy.dart';
// import 'streaming_strategy.dart'; // Direkter Import nicht mehr nötig
import 'auto_strategy.dart';
import 'lipsync_strategy.dart';

enum LipsyncMode { fileBased, streaming }

class LipsyncFactory {
  static LipsyncStrategy create({
    required LipsyncMode mode,
    required String backendUrl,
    String? orchestratorUrl,
  }) {
    switch (mode) {
      case LipsyncMode.fileBased:
        return FileBasedStrategy();

      case LipsyncMode.streaming:
        if (orchestratorUrl == null) {
          throw ArgumentError('orchestratorUrl required for streaming mode');
        }
        // Automatische Umschaltung: Streaming wenn verfügbar, sonst FileBased
        return AutoLipsyncStrategy(orchestratorUrl: orchestratorUrl);
    }
  }
}
