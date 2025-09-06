import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/avatar_service.dart';
import '../widgets/primary_button.dart';

class AvatarCreationScreen extends StatefulWidget {
  const AvatarCreationScreen({super.key});

  @override
  State<AvatarCreationScreen> createState() => _AvatarCreationScreenState();
}

class _AvatarCreationScreenState extends State<AvatarCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _deathDateController = TextEditingController();
  final _writtenTextsController = TextEditingController();

  final AvatarService _avatarService = AvatarService();
  final ImagePicker _imagePicker = ImagePicker();

  File? _avatarImage;
  final List<File> _images = [];
  final List<File> _videos = [];
  final List<File> _textFiles = [];
  DateTime? _birthDate;
  DateTime? _deathDate;
  bool _isLoading = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _nicknameController.dispose();
    _lastNameController.dispose();
    _birthDateController.dispose();
    _deathDateController.dispose();
    _writtenTextsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Avatar erstellen'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAvatarImageSection(),
                    const SizedBox(height: 24),
                    _buildBasicInfoSection(),
                    const SizedBox(height: 24),
                    _buildDateSection(),
                    const SizedBox(height: 24),
                    _buildMediaSection(),
                    const SizedBox(height: 24),
                    _buildWrittenTextsSection(),
                    const SizedBox(height: 32),
                    _buildCreateButton(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildAvatarImageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Avatar-Bild',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Center(
          child: GestureDetector(
            onTap: _pickAvatarImage,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.deepPurple, width: 2),
                color: Colors.deepPurple.shade50,
              ),
              child: _avatarImage != null
                  ? ClipOval(
                      child: Image.file(_avatarImage!, fit: BoxFit.cover),
                    )
                  : const Icon(
                      Icons.person_add,
                      size: 40,
                      color: Colors.deepPurple,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: _pickAvatarImage,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Bild auswählen'),
          ),
        ),
      ],
    );
  }

  Widget _buildBasicInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Grunddaten',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _firstNameController,
          decoration: const InputDecoration(
            labelText: 'Vorname *',
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Vorname ist erforderlich';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _nicknameController,
          decoration: const InputDecoration(
            labelText: 'Spitzname',
            border: OutlineInputBorder(),
            hintText: 'z.B. Oma, Opa, Mama',
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _lastNameController,
          decoration: const InputDecoration(
            labelText: 'Nachname',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildDateSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Lebensdaten',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _birthDateController,
          decoration: const InputDecoration(
            labelText: 'Geburtsdatum',
            border: OutlineInputBorder(),
            suffixIcon: Icon(Icons.calendar_today),
          ),
          readOnly: true,
          onTap: () => _selectDate(context, true),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _deathDateController,
          decoration: const InputDecoration(
            labelText: 'Todesdatum (optional)',
            border: OutlineInputBorder(),
            suffixIcon: Icon(Icons.calendar_today),
          ),
          readOnly: true,
          onTap: () => _selectDate(context, false),
        ),
      ],
    );
  }

  Widget _buildMediaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Medien',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _pickImages,
                icon: const Icon(Icons.photo_library),
                label: Text('Bilder (${_images.length})'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _pickVideos,
                icon: const Icon(Icons.video_library),
                label: Text('Videos (${_videos.length})'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _pickTextFiles,
          icon: const Icon(Icons.text_snippet),
          label: Text('Textdateien (${_textFiles.length})'),
        ),
      ],
    );
  }

  Widget _buildWrittenTextsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Geschriebene Texte',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _writtenTextsController,
          decoration: const InputDecoration(
            labelText: 'Texte (ein Text pro Zeile)',
            border: OutlineInputBorder(),
            hintText:
                'Erzähl mir von deiner Kindheit...\nWas war dein Lieblingsessen?...',
          ),
          maxLines: 5,
        ),
      ],
    );
  }

  Widget _buildCreateButton() {
    return SizedBox(
      width: double.infinity,
      child: PrimaryButton(
        text: 'Avatar erstellen',
        onPressed: _isLoading ? null : _createAvatar,
        isLoading: _isLoading,
      ),
    );
  }

  Future<void> _pickAvatarImage() async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (image != null) {
      setState(() {
        _avatarImage = File(image.path);
      });
    }
  }

  Future<void> _pickImages() async {
    final List<XFile> images = await _imagePicker.pickMultiImage(
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (images.isNotEmpty) {
      setState(() {
        _images.addAll(images.map((image) => File(image.path)));
      });
    }
  }

  Future<void> _pickVideos() async {
    final XFile? video = await _imagePicker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 5),
    );
    if (video != null) {
      setState(() {
        _videos.add(File(video.path));
      });
    }
  }

  Future<void> _pickTextFiles() async {
    // Hier würde normalerweise ein File Picker verwendet werden
    // Für Demo-Zwecke simulieren wir das
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Textdateien-Upload wird implementiert')),
    );
  }

  Future<void> _selectDate(BuildContext context, bool isBirthDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isBirthDate
          ? DateTime.now().subtract(const Duration(days: 365 * 30))
          : DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isBirthDate) {
          _birthDate = picked;
          _birthDateController.text =
              '${picked.day}.${picked.month}.${picked.year}';
        } else {
          _deathDate = picked;
          _deathDateController.text =
              '${picked.day}.${picked.month}.${picked.year}';
        }
      });
    }
  }

  Future<void> _createAvatar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final writtenTexts = _writtenTextsController.text
          .split('\n')
          .where((text) => text.trim().isNotEmpty)
          .toList();

      final avatar = await _avatarService.createAvatar(
        firstName: _firstNameController.text.trim(),
        nickname: _nicknameController.text.trim().isEmpty
            ? null
            : _nicknameController.text.trim(),
        lastName: _lastNameController.text.trim().isEmpty
            ? null
            : _lastNameController.text.trim(),
        birthDate: _birthDate,
        deathDate: _deathDate,
        avatarImage: _avatarImage,
        images: _images.isNotEmpty ? _images : null,
        videos: _videos.isNotEmpty ? _videos : null,
        textFiles: _textFiles.isNotEmpty ? _textFiles : null,
        writtenTexts: writtenTexts.isNotEmpty ? writtenTexts : null,
      );

      if (avatar != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Avatar erfolgreich erstellt!')),
          );
          Navigator.pop(context, avatar);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fehler beim Erstellen des Avatars')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
