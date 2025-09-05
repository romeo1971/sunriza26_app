/// AI Assistant Screen - Haupt-UI für Live-Video-Generierung
/// Stand: 04.09.2025 - Mit geklonter Stimme und Echtzeit-Lippensynchronisation
library;

import 'package:flutter/material.dart';
import '../services/ai_service.dart';
import '../services/video_stream_service.dart';
import '../services/media_upload_service.dart';
import '../widgets/video_player_widget.dart';
import '../widgets/text_input_widget.dart';
import '../widgets/status_widget.dart';
import '../widgets/media_upload_widget.dart';

class AIAssistantScreen extends StatefulWidget {
  const AIAssistantScreen({super.key});

  @override
  State<AIAssistantScreen> createState() => _AIAssistantScreenState();
}

class _AIAssistantScreenState extends State<AIAssistantScreen> {
  final TextEditingController _textController = TextEditingController();
  final AIService _aiService = AIService();
  final VideoStreamService _videoService = VideoStreamService();
  final MediaUploadService _uploadService = MediaUploadService();

  bool _isGenerating = false;
  String _statusMessage = 'Bereit für Texteingabe';
  String? _errorMessage;
  String? _referenceVideoUrl;
  List<String> _trainingMediaUrls = [];

  @override
  void initState() {
    super.initState();
    _checkServiceHealth();
    _setupVideoStreamListener();
  }

  @override
  void dispose() {
    _textController.dispose();
    _videoService.dispose();
    super.dispose();
  }

  /// Überprüft den Status der AI-Services
  Future<void> _checkServiceHealth() async {
    try {
      final health = await _aiService.checkHealth();
      if (health['status'] == 'healthy') {
        setState(() {
          _statusMessage = 'AI-Services sind bereit';
        });
      } else {
        setState(() {
          _statusMessage = 'AI-Services nicht verfügbar';
          _errorMessage = health['error'];
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Fehler beim Verbinden mit AI-Services';
        _errorMessage = e.toString();
      });
    }
  }

  /// Setzt Video-Stream Listener auf
  void _setupVideoStreamListener() {
    _videoService.stateStream.listen((state) {
      setState(() {
        switch (state) {
          case VideoStreamState.initializing:
            _statusMessage = 'Initialisiere Video-Stream...';
            break;
          case VideoStreamState.ready:
            _statusMessage = 'Video bereit für Wiedergabe';
            break;
          case VideoStreamState.streaming:
            _statusMessage = 'Video wird gestreamt...';
            break;
          case VideoStreamState.completed:
            _statusMessage = 'Video-Generierung abgeschlossen';
            _isGenerating = false;
            break;
          case VideoStreamState.error:
            _statusMessage = 'Fehler beim Video-Streaming';
            _isGenerating = false;
            break;
          case VideoStreamState.stopped:
            _statusMessage = 'Video-Stream gestoppt';
            _isGenerating = false;
            break;
        }
      });
    });
  }

  /// Startet Live-Video-Generierung
  Future<void> _generateVideo() async {
    final text = _textController.text.trim();

    if (!_aiService.validateText(text)) {
      _showErrorDialog(
        'Bitte geben Sie einen gültigen Text ein (1-5000 Zeichen)',
      );
      return;
    }

    setState(() {
      _isGenerating = true;
      _statusMessage = 'Starte Video-Generierung...';
      _errorMessage = null;
    });

    try {
      // Live-Video-Stream starten
      final videoStream = await _aiService.generateLiveVideo(
        text: text,
        onProgress: (progress) {
          setState(() {
            _statusMessage = progress;
          });
        },
        onError: (error) {
          setState(() {
            _errorMessage = error;
            _isGenerating = false;
          });
        },
      );

      // Video-Streaming starten
      await _videoService.startStreaming(
        videoStream,
        onProgress: (progress) {
          setState(() {
            _statusMessage = progress;
          });
        },
        onError: (error) {
          setState(() {
            _errorMessage = error;
            _isGenerating = false;
          });
        },
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Fehler bei der Video-Generierung: $e';
        _isGenerating = false;
      });
    }
  }

  /// Stoppt Video-Generierung
  Future<void> _stopGeneration() async {
    await _videoService.stopStreaming();
    setState(() {
      _isGenerating = false;
      _statusMessage = 'Video-Generierung gestoppt';
    });
  }

  /// Testet Text-to-Speech ohne Video
  Future<void> _testTTS() async {
    final text = _textController.text.trim();

    if (!_aiService.validateText(text)) {
      _showErrorDialog('Bitte geben Sie einen gültigen Text ein');
      return;
    }

    setState(() {
      _statusMessage = 'Teste Text-to-Speech...';
    });

    try {
      final audioData = await _aiService.testTextToSpeech(text);
      final audioPath = await _aiService.saveAudioToFile(audioData);

      _showSuccessDialog(
        'TTS-Test erfolgreich! Audio gespeichert unter: $audioPath',
      );
    } catch (e) {
      _showErrorDialog('TTS-Test fehlgeschlagen: $e');
    }
  }

  /// Zeigt Fehler-Dialog
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fehler'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Zeigt Erfolgs-Dialog
  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Erfolg'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sunriza26 - Live AI Assistant'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.health_and_safety),
            onPressed: _checkServiceHealth,
            tooltip: 'Service-Status prüfen',
          ),
        ],
      ),
      body: Column(
        children: [
          // Status-Widget
          StatusWidget(
            message: _statusMessage,
            isGenerating: _isGenerating,
            errorMessage: _errorMessage,
          ),

          // Video-Player Bereich
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _videoService.isReady
                    ? VideoPlayerWidget(controller: _videoService.controller!)
                    : const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.videocam_outlined,
                              size: 64,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Video wird hier angezeigt',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),

          // Media Upload Bereich
          Expanded(
            flex: 1,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // Referenzvideo Upload
                  MediaUploadWidget(
                    uploadType: UploadType.referenceVideo,
                    onUploadComplete: (result) {
                      if (result?.success == true) {
                        setState(() {
                          _referenceVideoUrl = result!.downloadUrl;
                          _statusMessage = 'Referenzvideo hochgeladen';
                        });
                      }
                    },
                  ),

                  const SizedBox(height: 16),

                  // Training Media Upload
                  MediaUploadWidget(
                    uploadType: UploadType.trainingImages,
                    onUploadComplete: (result) {
                      if (result?.success == true) {
                        setState(() {
                          _trainingMediaUrls.add(result!.downloadUrl!);
                          _statusMessage = 'Training-Bilder hochgeladen';
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

          // Text-Eingabe Bereich
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextInputWidget(
                    controller: _textController,
                    enabled: !_isGenerating,
                    hintText:
                        'Geben Sie hier den Text ein, der gesprochen werden soll...',
                    maxLines: 4,
                  ),

                  const SizedBox(height: 16),

                  // Aktions-Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isGenerating ? null : _generateVideo,
                          icon: _isGenerating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.play_arrow),
                          label: Text(
                            _isGenerating ? 'Generiere...' : 'Video generieren',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      if (_isGenerating)
                        ElevatedButton.icon(
                          onPressed: _stopGeneration,
                          icon: const Icon(Icons.stop),
                          label: const Text('Stoppen'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // TTS-Test Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isGenerating ? null : _testTTS,
                      icon: const Icon(Icons.volume_up),
                      label: const Text('TTS-Test (nur Audio)'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
