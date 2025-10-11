/// Video Stream Service für Live-Video-Wiedergabe
/// Stand: 04.09.2025 - Optimiert für Echtzeit-Streaming
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';

class VideoStreamService {
  static final VideoStreamService _instance = VideoStreamService._internal();
  factory VideoStreamService() => _instance;
  VideoStreamService._internal();

  VideoPlayerController? _controller;
  StreamSubscription<Uint8List>? _streamSubscription;
  final List<Uint8List> _videoBuffer = [];
  bool _isStreaming = false;
  String? _tempVideoPath;

  // Stream Controller für UI-Updates
  final StreamController<VideoStreamState> _stateController =
      StreamController<VideoStreamState>.broadcast();

  Stream<VideoStreamState> get stateStream => _stateController.stream;

  /// Startet Video-Streaming von URL
  Future<void> startStreamingFromUrl(
    String videoUrl, {
    Function(String)? onProgress,
    Function(String)? onError,
  }) async {
    try {
      if (_isStreaming) {
        await stopStreaming();
      }

      _isStreaming = true;
      onProgress?.call('Lade Video von URL...');
      _stateController.add(VideoStreamState.initializing);

      // Video-Controller direkt mit URL initialisieren
      await _initializeVideoController(videoUrl);

      onProgress?.call('Video geladen');
      _stateController.add(VideoStreamState.streaming);
    } catch (e) {
      onError?.call('URL-Stream-Fehler: $e');
      _stateController.add(VideoStreamState.error);
    }
  }

  /// Startet Live-Video-Streaming
  Future<void> startStreaming(
    Stream<Uint8List> videoStream, {
    Function(String)? onProgress,
    Function(String)? onError,
  }) async {
    try {
      if (_isStreaming) {
        await stopStreaming();
      }

      _isStreaming = true;
      _videoBuffer.clear();

      onProgress?.call('Initialisiere Video-Stream...');
      _stateController.add(VideoStreamState.initializing);

      // Temporäre Datei für Video-Stream erstellen
      final directory = await getTemporaryDirectory();
      _tempVideoPath =
          '${directory.path}/live_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final tempFile = File(_tempVideoPath!);

      // Stream-Daten sammeln und in Datei schreiben
      int bytesWritten = 0;
      const int initThresholdBytes =
          64 * 1024; // ~64KB, früher initialisieren für schnellere Anzeige
      _streamSubscription = videoStream.listen(
        (chunk) async {
          _videoBuffer.add(chunk);
          await tempFile.writeAsBytes(chunk, mode: FileMode.append);
          bytesWritten += chunk.length;

          // Controller erst initialisieren, wenn genügend Daten vorhanden sind
          if (_controller == null && bytesWritten >= initThresholdBytes) {
            await _initializeVideoController(tempFile.path);
          }
        },
        onError: (error) {
          onError?.call('Stream-Fehler: $error');
          _stateController.add(VideoStreamState.error);
        },
        onDone: () async {
          // Falls noch nicht initialisiert, final versuchen
          try {
            if (_controller == null) {
              await _initializeVideoController(tempFile.path);
            }
          } catch (_) {}
          onProgress?.call('Video-Stream abgeschlossen');
          _stateController.add(VideoStreamState.completed);
        },
      );
    } catch (e) {
      onError?.call('Fehler beim Starten des Video-Streams: $e');
      _stateController.add(VideoStreamState.error);
    }
  }

  /// Initialisiert Video-Controller für Wiedergabe
  Future<void> _initializeVideoController(String videoPath) async {
    try {
      // Quelle erkennen: Datei vs. Netzwerk-URL
      final Uri? uri = Uri.tryParse(videoPath);
      final bool isHttp =
          uri != null && (uri.isScheme('http') || uri.isScheme('https'));

      if (isHttp) {
        _controller = VideoPlayerController.networkUrl(Uri.parse(videoPath));
      } else {
        _controller = VideoPlayerController.file(File(videoPath));
      }

      await _controller!.initialize();
      // Direkt Ready melden (Listener kann auf einigen Plattformen verzögert feuern)
      _stateController.add(VideoStreamState.ready);

      // Event-Listener für Controller-Events
      _controller!.addListener(() {
        if (_controller!.value.isInitialized) {
          _stateController.add(VideoStreamState.ready);
        }
      });

      // Auto-Play starten
      await _controller!.setLooping(true);
      await _controller!.play();
      _stateController.add(VideoStreamState.streaming);
    } catch (e) {
      _stateController.add(VideoStreamState.error);
      throw Exception('Fehler bei Video-Controller Initialisierung: $e');
    }
  }

  /// Stoppt Video-Streaming und bereinigt Ressourcen
  Future<void> stopStreaming() async {
    try {
      _isStreaming = false;

      await _streamSubscription?.cancel();
      _streamSubscription = null;

      await _controller?.dispose();
      _controller = null;

      // Temporäre Datei löschen
      if (_tempVideoPath != null) {
        final tempFile = File(_tempVideoPath!);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        _tempVideoPath = null;
      }

      _videoBuffer.clear();
      _stateController.add(VideoStreamState.stopped);
    } catch (e) {
      debugPrint('Fehler beim Stoppen des Video-Streams: $e');
    }
  }

  /// Gibt Video-Controller für UI zurück
  VideoPlayerController? get controller => _controller;

  /// Prüft ob Video-Stream aktiv ist
  bool get isStreaming => _isStreaming;

  /// Prüft ob Video bereit für Wiedergabe ist
  bool get isReady => _controller?.value.isInitialized ?? false;

  /// Gibt aktuelle Video-Position zurück
  Duration get position => _controller?.value.position ?? Duration.zero;

  /// Gibt Video-Dauer zurück
  Duration get duration => _controller?.value.duration ?? Duration.zero;

  /// Pausiert/Setzt Video fort
  Future<void> togglePlayPause() async {
    if (_controller != null) {
      if (_controller!.value.isPlaying) {
        await _controller!.pause();
      } else {
        await _controller!.play();
      }
    }
  }

  /// Setzt Video-Position
  Future<void> seekTo(Duration position) async {
    if (_controller != null) {
      await _controller!.seekTo(position);
    }
  }

  /// Bereinigt alle Ressourcen
  Future<void> dispose() async {
    await stopStreaming();
    await _stateController.close();
  }
}

/// Video Stream States für UI-Updates
enum VideoStreamState {
  initializing,
  ready,
  streaming,
  completed,
  error,
  stopped,
}
