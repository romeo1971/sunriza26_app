import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/elevenlabs_service.dart';
import '../services/bithuman_service.dart';

class AvatarEditorScreen extends StatefulWidget {
  const AvatarEditorScreen({Key? key}) : super(key: key);

  @override
  State<AvatarEditorScreen> createState() => _AvatarEditorScreenState();
}

class _AvatarEditorScreenState extends State<AvatarEditorScreen> {
  String? _uploadedImxFileName;
  String _inputText = "";
  bool _isUploading = false;
  bool _isSpeaking = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  /// Initialisiert alle Services
  Future<void> _initializeServices() async {
    try {
      await dotenv.load();
      await ElevenLabsService.initialize();
      await BitHumanService.initialize();

      setState(() {
        _isInitialized = true;
      });

      print('✅ Alle Services initialisiert');
    } catch (e) {
      print('❌ Service-Initialisierung fehlgeschlagen: $e');
      _showErrorSnackBar('Service-Initialisierung fehlgeschlagen');
    }
  }

  /// Lädt .imx Avatar-Modell hoch
  Future<void> _uploadImxFile() async {
    if (!_isInitialized) {
      _showErrorSnackBar('Services noch nicht initialisiert');
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['imx'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final filePath = file.path;

        if (filePath != null) {
          final fileName = await BitHumanService.uploadImxFile(filePath);

          if (fileName != null) {
            setState(() {
              _uploadedImxFileName = fileName;
            });
            _showSuccessSnackBar('Avatar erfolgreich hochgeladen: $fileName');
          } else {
            _showErrorSnackBar('Upload fehlgeschlagen');
          }
        }
      }
    } catch (e) {
      print('❌ Upload Fehler: $e');
      _showErrorSnackBar('Upload Fehler: $e');
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  /// Startet Avatar-Sprechen
  Future<void> _speak() async {
    if (!_isInitialized) {
      _showErrorSnackBar('Services noch nicht initialisiert');
      return;
    }

    if (_inputText.isEmpty) {
      _showErrorSnackBar('Bitte Text eingeben');
      return;
    }

    if (_uploadedImxFileName == null) {
      _showErrorSnackBar('Bitte Avatar hochladen');
      return;
    }

    setState(() {
      _isSpeaking = true;
    });

    try {
      // Direkt über Backend sprechen lassen
      final success = await BitHumanService.speakText(
        _inputText,
        _uploadedImxFileName!,
      );

      if (success) {
        _showSuccessSnackBar('Avatar spricht jetzt!');
      } else {
        _showErrorSnackBar('Avatar-Sprechen fehlgeschlagen');
      }
    } catch (e) {
      print('❌ Speak Fehler: $e');
      _showErrorSnackBar('Speak Fehler: $e');
    } finally {
      setState(() {
        _isSpeaking = false;
      });
    }
  }

  /// Zeigt Erfolgs-SnackBar
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Zeigt Fehler-SnackBar
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Avatar Editor'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
      ),
      body: _isInitialized
          ? _buildMainContent()
          : const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Initialisiere Services...'),
                ],
              ),
            ),
    );
  }

  Widget _buildMainContent() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Upload Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Avatar Upload',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('Lade ein .imx Avatar-Modell hoch'),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isUploading ? null : _uploadImxFile,
                    icon: _isUploading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file),
                    label: Text(
                      _isUploading ? 'Lädt hoch...' : 'Avatar (.imx) hochladen',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                  if (_uploadedImxFileName != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Colors.green.shade600,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Avatar: $_uploadedImxFileName',
                              style: TextStyle(color: Colors.green.shade800),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Text Input Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Text zum Sprechen',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('Gib den Text ein, den der Avatar sprechen soll'),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (value) => setState(() => _inputText = value),
                    decoration: const InputDecoration(
                      labelText: 'Text eingeben...',
                      border: OutlineInputBorder(),
                      hintText: 'Hallo! Ich bin dein Avatar.',
                    ),
                    maxLines: 3,
                    minLines: 1,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Speak Button
          ElevatedButton.icon(
            onPressed:
                (_isSpeaking ||
                    _inputText.isEmpty ||
                    _uploadedImxFileName == null)
                ? null
                : _speak,
            icon: _isSpeaking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.record_voice_over),
            label: Text(
              _isSpeaking ? 'Avatar spricht...' : 'Avatar sprechen lassen',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Status Info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info, color: Colors.blue.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Stelle sicher, dass das Backend läuft (localhost:8000)',
                    style: TextStyle(color: Colors.blue.shade800),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
