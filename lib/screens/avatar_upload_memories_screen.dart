import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../theme/app_theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import '../services/firebase_storage_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/avatar_data.dart';
import '../widgets/custom_text_field.dart';

class _LocalImage {
  final File? file;
  final Uint8List? bytes;
  final String? name;

  _LocalImage.file(this.file)
      : bytes = null,
        name = null;

  _LocalImage.bytes(this.bytes, {this.name}) : file = null;
}

class AvatarUploadMemoriesScreen extends StatefulWidget {
  const AvatarUploadMemoriesScreen({super.key});

  @override
  State<AvatarUploadMemoriesScreen> createState() =>
      _AvatarUploadMemoriesScreenState();
}

class _AvatarUploadMemoriesScreenState
    extends State<AvatarUploadMemoriesScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _textController = TextEditingController();

  final List<_LocalImage> _uploadedImages = [];
  final List<File> _uploadedVideos = [];
  final List<File> _uploadedTextFiles = [];
  final List<String> _writtenTexts = [];

  int? _selectedAvatarImageIndex;

  // Firebase Storage URLs
  List<String> _uploadedImageUrls = [];
  List<String> _uploadedVideoUrls = [];
  List<String> _uploadedTextFileUrls = [];

  bool _isUploading = false;
  double _uploadProgress = 0.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Avatar erstellen'),
        backgroundColor: AppColors.accentGreenDark,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Frage oben
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                color: const Color(0x1400DFA8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.accentGreenDark.withValues(alpha: 0.3),
                ),
              ),
              child: const Text(
                'Bitte lade Bilder, Videos oder Texte hoch – oder verfasse etwas Persönliches.',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: AppColors.accentGreenDark,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 24),

            // Vier Upload-Optionen
            _buildUploadOptions(),

            const SizedBox(height: 24),

            // Avatar-Bild-Auswahl
            if (_uploadedImages.isNotEmpty) _buildAvatarImageSelection(),

            const SizedBox(height: 24),

            // Hochgeladene Inhalte anzeigen
            _buildUploadedContent(),

            const SizedBox(height: 32),

            // Upload-Status
            if (_isUploading) _buildUploadProgress(),

            // Weiter-Button
            _buildContinueButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadOptions() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildUploadCard(
                'Bild',
                Icons.image,
                Colors.blue,
                _pickImage,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildUploadCard(
                'Video',
                Icons.videocam,
                Colors.red,
                _pickVideo,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildUploadCard(
                'Textdatei',
                Icons.description,
                Colors.green,
                _pickTextFile,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildUploadCard(
                'Text schreiben',
                Icons.edit,
                Colors.orange,
                _showTextInput,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUploadCard(
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarImageSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Wähle ein Avatar-Bild:',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _uploadedImages.length,
              itemBuilder: (context, index) {
                final isSelected = _selectedAvatarImageIndex == index;
                final img = _uploadedImages[index];
                Widget imageWidget;
                if (img.file != null) {
                  imageWidget = Image.file(
                    img.file!,
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                  );
                } else if (img.bytes != null) {
                  imageWidget = Image.memory(
                    img.bytes!,
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                  );
                } else {
                  imageWidget = const SizedBox.shrink();
                }

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedAvatarImageIndex = index;
                    });
                  },
                  child: Container(
                    width: 100,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.accentGreenDark
                            : Colors.grey.shade300,
                        width: isSelected ? 3 : 1,
                      ),
                    ),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: imageWidget,
                        ),
                        if (isSelected)
                          const Positioned(
                            top: 4,
                            right: 4,
                            child: Icon(
                              Icons.workspace_premium,
                              color: Colors.amber,
                              size: 24,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildUploadedContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_uploadedImages.isNotEmpty) ...[
          const Text(
            'Bilder:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _uploadedImages.length,
              itemBuilder: (context, index) {
                final img = _uploadedImages[index];
                Widget imageWidget;
                if (img.file != null) {
                  imageWidget = Image.file(
                    img.file!,
                    fit: BoxFit.cover,
                  );
                } else if (img.bytes != null) {
                  imageWidget = Image.memory(
                    img.bytes!,
                    fit: BoxFit.cover,
                  );
                } else {
                  imageWidget = const SizedBox.shrink();
                }

                return Container(
                  width: 80,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: imageWidget,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (_uploadedVideos.isNotEmpty) ...[
          const Text(
            'Videos:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _uploadedVideos.length,
              itemBuilder: (context, index) {
                return Container(
                  width: 80,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: const Icon(
                    Icons.play_circle_outline,
                    size: 40,
                    color: Colors.red,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (_uploadedTextFiles.isNotEmpty) ...[
          const Text(
            'Textdateien:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ..._uploadedTextFiles.map(
            (file) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.description, size: 20, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(child: Text(file.path.split('/').last)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (_writtenTexts.isNotEmpty) ...[
          const Text(
            'Geschriebene Texte:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ..._writtenTexts.map(
            (text) => Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Text(text),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildUploadProgress() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: _uploadProgress,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Lade Inhalte hoch... ${(_uploadProgress * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _uploadProgress,
            backgroundColor: Colors.blue.shade100,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueButton() {
    final hasContent =
        _uploadedImages.isNotEmpty ||
        _uploadedVideos.isNotEmpty ||
        _uploadedTextFiles.isNotEmpty ||
        _writtenTexts.isNotEmpty;
    final hasAvatarSelected =
        _uploadedImages.isNotEmpty && _selectedAvatarImageIndex != null;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: (hasContent && hasAvatarSelected && !_isUploading)
            ? _uploadAndContinue
            : () {
                if (!hasAvatarSelected) {
                  _showErrorSnackBar(
                    'Bitte wähle ein Avatar-Bild (Hero-Image) aus.',
                  );
                }
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: ShaderMask(
          shaderCallback: (bounds) => Theme.of(
            context,
          ).extension<AppGradients>()!.magentaBlue.createShader(bounds),
          child: Text(
            _isUploading
                ? 'Wird hochgeladen...'
                : (hasAvatarSelected
                      ? 'Avatar jetzt anlegen'
                      : 'Avatar-Bild wählen'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );
      if (image != null) {
        if (kIsWeb) {
          // Web: arbeite mit Bytes, kein dart:io File
          final bytes = await image.readAsBytes();
          setState(() {
            _uploadedImages.add(
              _LocalImage.bytes(
                bytes,
                name: image.name,
              ),
            );
          });
        } else {
          // Mobile/Desktop: wie bisher mit File arbeiten
          setState(() {
            _uploadedImages.add(_LocalImage.file(File(image.path)));
          });
        }
      }
    } catch (e) {
      _showErrorSnackBar('Fehler beim Auswählen des Bildes: $e');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
      );
      if (video != null) {
        setState(() {
          _uploadedVideos.add(File(video.path));
        });
      }
    } catch (e) {
      _showErrorSnackBar('Fehler beim Auswählen des Videos: $e');
    }
  }

  Future<void> _pickTextFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'docx', 'pdf'],
      );

      if (result != null) {
        setState(() {
          _uploadedTextFiles.add(File(result.files.single.path!));
        });
      }
    } catch (e) {
      _showErrorSnackBar('Fehler beim Auswählen der Textdatei: $e');
    }
  }

  void _showTextInput() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Text schreiben'),
        content: SizedBox(
          width: double.maxFinite,
          child: CustomTextField(
            label: '',
            controller: _textController,
            hintText: 'Schreibe hier deinen persönlichen Text...',
            maxLines: 5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_textController.text.isNotEmpty) {
                setState(() {
                  _writtenTexts.add(_textController.text);
                  _textController.clear();
                });
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.white,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppColors.magenta, AppColors.lightBlue],
              ).createShader(bounds),
              child: const Text(
                'Hinzufügen',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadAndContinue() async {
    if (_isUploading) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    try {
      int totalFiles =
          _uploadedImages.length +
          _uploadedVideos.length +
          _uploadedTextFiles.length;
      int uploadedFiles = 0;

      // Upload Bilder
      if (_uploadedImages.isNotEmpty) {
        if (kIsWeb) {
          final bytesList = _uploadedImages
              .map((img) => img.bytes)
              .whereType<Uint8List>()
              .toList();
          final names = _uploadedImages
              .map((img) => img.name ?? 'image.jpg')
              .toList();
          _uploadedImageUrls =
              await FirebaseStorageService.uploadMultipleImagesBytes(
            bytesList,
            fileNames: names,
          );
        } else {
          final files = _uploadedImages
              .map((img) => img.file)
              .whereType<File>()
              .toList();
          _uploadedImageUrls =
              await FirebaseStorageService.uploadMultipleImages(files);
        }

        uploadedFiles += _uploadedImages.length;
        if (!mounted) return;
        setState(() {
          _uploadProgress = uploadedFiles / totalFiles;
        });
      }

      // Upload Videos
      if (_uploadedVideos.isNotEmpty) {
        _uploadedVideoUrls = await FirebaseStorageService.uploadMultipleVideos(
          _uploadedVideos,
        );
        uploadedFiles += _uploadedVideos.length;
        if (!mounted) return;
        setState(() {
          _uploadProgress = uploadedFiles / totalFiles;
        });
      }

      // Upload Textdateien
      if (_uploadedTextFiles.isNotEmpty) {
        _uploadedTextFileUrls =
            await FirebaseStorageService.uploadMultipleTextFiles(
              _uploadedTextFiles,
            );
        uploadedFiles += _uploadedTextFiles.length;
        if (!mounted) return;
        setState(() {
          _uploadProgress = uploadedFiles / totalFiles;
        });
      }

      if (!mounted) return;
      setState(() {
        _uploadProgress = 1.0;
      });

      // Kurz warten, damit der Benutzer den 100% Fortschritt sieht
      await Future.delayed(const Duration(milliseconds: 500));

      // Erstelle AvatarData mit den hochgeladenen URLs
      final userId = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
      final avatarData = AvatarData(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        userId: userId,
        firstName: '',
        imageUrls: _uploadedImageUrls,
        videoUrls: _uploadedVideoUrls,
        textFileUrls: _uploadedTextFileUrls,
        writtenTexts: _writtenTexts,
        avatarImageUrl: _selectedAvatarImageIndex != null
            ? _uploadedImageUrls[_selectedAvatarImageIndex!]
            : null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Navigate to Avatar Details Page with data
      if (!mounted) return;
      Navigator.pushNamed(context, '/avatar-details', arguments: avatarData);
    } catch (e) {
      _showErrorSnackBar('Fehler beim Upload: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0.0;
        });
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }
}
