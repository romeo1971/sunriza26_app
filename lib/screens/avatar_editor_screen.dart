import 'package:flutter/material.dart';
import 'package:sunriza26/services/bithuman_service.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;

class AvatarEditorScreen extends StatefulWidget {
  final String avatarId;
  final String avatarName;
  final String? avatarImageUrl;

  const AvatarEditorScreen({
    super.key,
    required this.avatarId,
    required this.avatarName,
    this.avatarImageUrl,
  });

  @override
  State<AvatarEditorScreen> createState() => _AvatarEditorScreenState();
}

class _AvatarEditorScreenState extends State<AvatarEditorScreen> {
  String? _generatedAgentId;
  File? _selectedImage;
  bool _isGenerating = false;
  bool _isInitialized = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      await BitHumanService.initialize();

      setState(() {
        _isInitialized = true;
      });

      print('✅ BitHuman Service initialisiert');
    } catch (e) {
      _showErrorSnackBar('Fehler bei der Initialisierung: $e');
    }
  }

  Future<void> _selectImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      _showErrorSnackBar('Fehler beim Auswählen des Bildes: $e');
    }
  }

  Future<File> _downloadAvatarImageToTemp(String url) async {
    final uri = Uri.parse(url);
    final resp = await http.get(uri);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final tmpPath =
          '${Directory.systemTemp.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final f = File(tmpPath);
      await f.writeAsBytes(resp.bodyBytes);
      return f;
    }
    throw Exception('Bild-Download fehlgeschlagen (${resp.statusCode})');
  }

  Future<void> _generateAgent() async {
    if (!_isInitialized) {
      _showErrorSnackBar('Service ist noch nicht initialisiert.');
      return;
    }

    // Wenn kein lokales Bild existiert, versuche das Krone-Bild zu laden
    if (_selectedImage == null &&
        (widget.avatarImageUrl?.isNotEmpty ?? false)) {
      try {
        final file = await _downloadAvatarImageToTemp(widget.avatarImageUrl!);
        setState(() => _selectedImage = file);
      } catch (e) {
        _showErrorSnackBar('Konnte Krone-Bild nicht laden: $e');
        return;
      }
    }

    if (_selectedImage == null) {
      _showErrorSnackBar('Kein Bild vorhanden.');
      return;
    }

    setState(() {
      _isGenerating = true;
    });

    try {
      final agentId = await BitHumanService.generateAgentFromImage(
        _selectedImage!,
        widget.avatarName,
      );

      if (agentId != null) {
        setState(() {
          _generatedAgentId = agentId;
        });
        _showSuccessSnackBar(
          '🎭 Avatar Agent für "${widget.avatarName}" erfolgreich generiert!\n\nAgent ID: $agentId',
        );
      } else {
        _showErrorSnackBar('Agent-Generierung fehlgeschlagen.');
      }
    } catch (e) {
      _showErrorSnackBar('Fehler bei der Agent-Generierung: $e');
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Avatar Editor - ${widget.avatarName}'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Avatar Generation Section
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      // KRONE-BILD (füllt den Bereich)
                      GestureDetector(
                        onTap: _selectImage,
                        child: Container(
                          height: 300,
                          width: 200,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey.shade100,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: _selectedImage != null
                                ? Image.file(_selectedImage!, fit: BoxFit.cover)
                                : (widget.avatarImageUrl != null &&
                                      widget.avatarImageUrl!.isNotEmpty)
                                ? Image.network(
                                    widget.avatarImageUrl!,
                                    fit: BoxFit.cover,
                                  )
                                : const Icon(
                                    Icons.person,
                                    size: 80,
                                    color: Colors.grey,
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Generate Button (CI-Farbe)
                      ElevatedButton(
                        onPressed: _isGenerating ? null : _generateAgent,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _isGenerating
                              ? 'Generiere Avatar...'
                              : 'Avatar generieren',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),

                      if (_generatedAgentId != null) ...[
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Colors.green.shade600,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Avatar Agent generiert!',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Agent ID: $_generatedAgentId',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.green.shade600,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ],
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

              // Info Card
              Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                padding: const EdgeInsets.all(16.0),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.white70),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'BitHuman generiert automatisch einen lebensechten Avatar aus deinem Bild. Der Avatar spricht mit ElevenLabs TTS und dem definierten Begrüßungstext.',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Status Info
              if (!_isInitialized)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 16),
                      Text('Initialisiere BitHuman Service...'),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
