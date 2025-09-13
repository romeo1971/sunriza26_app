import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/avatar_data.dart';
import '../services/firebase_storage_service.dart';
import '../services/avatar_service.dart';

class AvatarDetailsScreen extends StatefulWidget {
  const AvatarDetailsScreen({super.key});

  @override
  State<AvatarDetailsScreen> createState() => _AvatarDetailsScreenState();
}

class _AvatarDetailsScreenState extends State<AvatarDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _deathDateController = TextEditingController();

  DateTime? _birthDate;
  DateTime? _deathDate;
  int? _calculatedAge;

  AvatarData? _avatarData;
  final List<String> _imageUrls = [];
  final List<String> _videoUrls = [];
  final List<String> _textFileUrls = [];
  final TextEditingController _textAreaController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final AvatarService _avatarService = AvatarService();
  final List<File> _newImageFiles = [];
  final List<File> _newVideoFiles = [];
  final List<File> _newTextFiles = [];
  String? _profileImageUrl; // Krone
  String? _profileLocalPath; // Krone (lokal, noch nicht hochgeladen)
  bool _isSaving = false;
  final Set<String> _selectedRemoteImages = {};
  final Set<String> _selectedLocalImages = {};

  @override
  void initState() {
    super.initState();
    // Empfange AvatarData von der vorherigen Seite
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is AvatarData) {
        _applyAvatar(args);
        // Frische Daten aus Firestore nachladen, um veraltete Argumente zu ersetzen
        _fetchLatest(args.id);
      }
    });
  }

  Future<void> _fetchLatest(String id) async {
    final latest = await _avatarService.getAvatar(id);
    if (latest != null && mounted) {
      _applyAvatar(latest);
    }
  }

  void _applyAvatar(AvatarData data) {
    setState(() {
      _avatarData = data;
      _firstNameController.text = data.firstName;
      _nicknameController.text = data.nickname ?? '';
      _lastNameController.text = data.lastName ?? '';
      _birthDate = data.birthDate;
      _deathDate = data.deathDate;
      _calculatedAge = data.calculatedAge;

      _birthDateController.text = _birthDate != null
          ? _formatDate(_birthDate!)
          : '';
      _deathDateController.text = _deathDate != null
          ? _formatDate(_deathDate!)
          : '';

      _imageUrls
        ..clear()
        ..addAll(data.imageUrls);
      _videoUrls
        ..clear()
        ..addAll(data.videoUrls);
      _textFileUrls
        ..clear()
        ..addAll(data.textFileUrls);
      _profileImageUrl =
          data.avatarImageUrl ??
          (_imageUrls.isNotEmpty ? _imageUrls.first : null);
      _profileLocalPath = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final backgroundImage = _profileImageUrl ?? _avatarData?.avatarImageUrl;

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: () => Navigator.pop(context),
          child: const Text('Datenwelt schließen'),
        ),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Speichern',
            icon: const Icon(Icons.save),
            onPressed: _saveAvatarDetails,
          ),
        ],
      ),
      body: Container(
        decoration: backgroundImage != null
            ? BoxDecoration(
                image: DecorationImage(
                  image: NetworkImage(backgroundImage),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    Colors.black.withValues(alpha: 0.7),
                    BlendMode.darken,
                  ),
                ),
              )
            : null,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar-Bild oben
                _buildAvatarImage(),
                const SizedBox(height: 12),
                _buildMediaSection(),

                const SizedBox(height: 24),

                // Eingabefelder
                _buildInputFields(),

                const SizedBox(height: 32),

                // Speichern-Button
                _buildSaveButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarImage() {
    return Center(
      child: Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: (_profileImageUrl ?? _avatarData?.avatarImageUrl) != null
            ? ClipOval(
                child: Image.network(
                  (_profileImageUrl ?? _avatarData!.avatarImageUrl!),
                  width: 150,
                  height: 150,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => CircleAvatar(
                    backgroundColor: Colors.deepPurple.shade100,
                    child: const Icon(
                      Icons.person,
                      size: 80,
                      color: Colors.deepPurple,
                    ),
                  ),
                ),
              )
            : CircleAvatar(
                backgroundColor: Colors.deepPurple.shade100,
                child: const Icon(
                  Icons.person,
                  size: 80,
                  color: Colors.deepPurple,
                ),
              ),
      ),
    );
  }

  Widget _buildMediaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        // Große Media-Buttons in einer Reihe
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _bigMediaButton(Icons.photo_library, 'Bilder', _onAddImages),
            _bigMediaButton(Icons.videocam, 'Videos', _onAddVideos),
            _bigMediaButton(Icons.text_snippet, 'Texte', _onAddTexts),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Diese Bilder, Videos und Texte dienen dazu, den Avatar möglichst genau zu trainieren – keine Urlaubsgalerie.',
          style: TextStyle(color: Colors.white60, fontSize: 12),
        ),
        const SizedBox(height: 16),
        if ((_imageUrls.length + _newImageFiles.length) > 0)
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _imageUrls.length + _newImageFiles.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final remoteCount = _imageUrls.length;
                if (index < remoteCount) {
                  final url = _imageUrls[index];
                  final isCrown =
                      _profileImageUrl == url ||
                      (_profileImageUrl == null && index == 0);
                  return _imageThumbNetwork(url, isCrown);
                } else {
                  final file = _newImageFiles[index - remoteCount];
                  final isCrown = false;
                  return _imageThumbFile(file);
                }
              },
            ),
          ),
        if (_selectedRemoteImages.isNotEmpty || _selectedLocalImages.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Möchtest du die ausgewählten Bilder wirklich löschen?',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedRemoteImages.clear();
                      _selectedLocalImages.clear();
                    });
                  },
                  child: const Text('Abbrechen'),
                ),
                ElevatedButton(
                  onPressed: _confirmDeleteSelectedImages,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Löschen'),
                ),
              ],
            ),
          ),

        const SizedBox(height: 16),

        // Unterhalb keine zusätzlichen Buttons – oben sind die großen Icons
        const SizedBox(height: 16),
        // Textarea -> Hinweis .txt
        const Text(
          'Freitext (wird als .txt gespeichert)',
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _textAreaController,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'Schreibe Gedanken/Erinnerungen…',
            hintStyle: const TextStyle(color: Colors.white54),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.deepPurple),
            ),
          ),
          style: const TextStyle(color: Colors.white),
        ),
        // Hinweis: Text wird beim Speichern automatisch als .txt hinzugefügt
      ],
    );
  }

  Widget _buildCrownSelector() {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.emoji_events, color: Colors.amber, size: 28),
            SizedBox(height: 4),
            Text(
              'Profilbild',
              style: TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imageThumbNetwork(String url, bool isCrown) {
    final selected = _selectedRemoteImages.contains(url);
    return GestureDetector(
      onTap: () => setState(() => _profileImageUrl = url),
      onLongPress: () => setState(() {
        if (selected) {
          _selectedRemoteImages.remove(url);
        } else {
          _selectedRemoteImages.add(url);
        }
      }),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(url, width: 96, height: 96, fit: BoxFit.cover),
          ),
          if (isCrown)
            const Positioned(
              top: 4,
              left: 4,
              child: Icon(Icons.emoji_events, color: Colors.amber, size: 18),
            ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: () => setState(() {
                if (selected) {
                  _selectedRemoteImages.remove(url);
                } else {
                  _selectedRemoteImages.add(url);
                }
              }),
              child: Icon(
                selected ? Icons.check_circle : Icons.check_circle_outline,
                color: selected ? Colors.greenAccent : Colors.white70,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageThumbFile(File file) {
    final key = file.path;
    final selected = _selectedLocalImages.contains(key);
    return GestureDetector(
      onTap: () => setState(() => _profileLocalPath = key),
      onLongPress: () => setState(() {
        if (selected) {
          _selectedLocalImages.remove(key);
        } else {
          _selectedLocalImages.add(key);
        }
      }),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(file, width: 96, height: 96, fit: BoxFit.cover),
          ),
          if (_profileLocalPath == key)
            const Positioned(
              top: 4,
              left: 4,
              child: Icon(Icons.emoji_events, color: Colors.amber, size: 18),
            ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: () => setState(() {
                if (selected) {
                  _selectedLocalImages.remove(key);
                } else {
                  _selectedLocalImages.add(key);
                }
              }),
              child: Icon(
                selected ? Icons.check_circle : Icons.check_circle_outline,
                color: selected ? Colors.greenAccent : Colors.white70,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bigMediaButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, color: Colors.white, size: 34),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _onAddImages() async {
    final source = await _chooseSource('Bildquelle wählen');
    if (source == null) return;
    if (source == ImageSource.gallery) {
      final files = await _picker.pickMultiImage(
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
      if (files.isNotEmpty) {
        setState(() {
          _newImageFiles.addAll(files.map((x) => File(x.path)));
          _profileImageUrl ??= (_imageUrls.isNotEmpty)
              ? _imageUrls.first
              : (files.isNotEmpty ? null : _profileImageUrl);
        });
      }
    } else {
      final x = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
      if (x != null) {
        setState(() {
          _newImageFiles.add(File(x.path));
        });
      }
    }
  }

  Future<void> _onAddVideos() async {
    final source = await _chooseSource('Videoquelle wählen');
    if (source == null) return;
    if (source == ImageSource.gallery) {
      final x = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
      if (x != null) setState(() => _newVideoFiles.add(File(x.path)));
    } else {
      final x = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 5),
      );
      if (x != null) setState(() => _newVideoFiles.add(File(x.path)));
    }
  }

  Future<void> _onAddTexts() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'md', 'rtf'],
      allowMultiple: true,
    );
    if (result != null) {
      setState(() {
        for (final f in result.files) {
          if (f.path != null) _newTextFiles.add(File(f.path!));
        }
      });
    }
  }

  Future<ImageSource?> _chooseSource(String title) async {
    return await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galerie'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Kamera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addTextAreaAsFile() async {
    final text = _textAreaController.text.trim();
    if (text.isEmpty) return;
    final tmp = await File(
      '${Directory.systemTemp.path}/user_text_${DateTime.now().millisecondsSinceEpoch}.txt',
    ).create();
    await tmp.writeAsString(text);
    setState(() => _newTextFiles.add(tmp));
    _textAreaController.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Text als .txt hinzugefügt')),
      );
    }
  }

  Widget _buildInputFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Vorname (Pflichtfeld)
        _buildTextField(
          controller: _firstNameController,
          label: 'Vorname *',
          hint: 'Gib den Vornamen ein',
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Vorname ist erforderlich';
            }
            return null;
          },
        ),

        const SizedBox(height: 16),

        // Spitzname (optional)
        _buildTextField(
          controller: _nicknameController,
          label: 'Spitzname',
          hint: 'Gib einen Spitznamen ein (optional)',
        ),

        const SizedBox(height: 16),

        // Nachname (optional)
        _buildTextField(
          controller: _lastNameController,
          label: 'Nachname',
          hint: 'Gib den Nachnamen ein (optional)',
        ),

        const SizedBox(height: 16),

        // Geburtsdatum (optional)
        _buildDateField(
          controller: _birthDateController,
          label: 'Geburtsdatum',
          hint: 'Wähle das Geburtsdatum',
          onTap: () => _selectBirthDate(),
        ),

        const SizedBox(height: 16),

        // Sterbedatum (optional)
        _buildDateField(
          controller: _deathDateController,
          label: 'Sterbedatum',
          hint: 'Wähle das Sterbedatum (optional)',
          onTap: () => _selectDeathDate(),
        ),

        const SizedBox(height: 16),

        // Berechnetes Alter anzeigen
        if (_calculatedAge != null) _buildAgeDisplay(),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.deepPurple,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    controller.text.isEmpty ? hint : controller.text,
                    style: TextStyle(
                      color: controller.text.isEmpty
                          ? Colors.white70
                          : Colors.white,
                    ),
                  ),
                ),
                const Icon(Icons.calendar_today, color: Colors.white70),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAgeDisplay() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.cake, color: Colors.green.shade600),
          const SizedBox(width: 12),
          Text(
            'Berechnetes Alter: $_calculatedAge Jahre',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.green.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _saveAvatarDetails,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Text(
          'Speichern',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Future<void> _selectBirthDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 25)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _birthDate = picked;
        _birthDateController.text = _formatDate(picked);
        _calculateAge();
      });
    }
  }

  Future<void> _selectDeathDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime.now(),
      firstDate: _birthDate ?? DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _deathDate = picked;
        _deathDateController.text = _formatDate(picked);
        _calculateAge();
      });
    }
  }

  void _calculateAge() {
    if (_birthDate != null) {
      final endDate = _deathDate ?? DateTime.now();
      final age = endDate.year - _birthDate!.year;
      final monthDiff = endDate.month - _birthDate!.month;

      if (monthDiff < 0 || (monthDiff == 0 && endDate.day < _birthDate!.day)) {
        _calculatedAge = age - 1;
      } else {
        _calculatedAge = age;
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  void _saveAvatarDetails() {
    if (!_formKey.currentState!.validate() || _avatarData == null) return;
    if (_isSaving) return;
    setState(() => _isSaving = true);

    () async {
      try {
        // 0) Freitext beim Speichern automatisch als .txt hinzufügen
        final freeText = _textAreaController.text.trim();
        if (freeText.isNotEmpty) {
          final tmp = await File(
            '${Directory.systemTemp.path}/user_text_${DateTime.now().millisecondsSinceEpoch}.txt',
          ).create();
          await tmp.writeAsString(freeText);
          _newTextFiles.add(tmp);
          _textAreaController.clear();
        }

        // 1) Upload neue Dateien und URLs sammeln
        final avatarId = _avatarData!.id;
        final allImages = [..._imageUrls];
        final allVideos = [..._videoUrls];
        final allTexts = [..._textFileUrls];

        // Upload Images einzeln
        for (int i = 0; i < _newImageFiles.length; i++) {
          final url = await FirebaseStorageService.uploadImage(
            _newImageFiles[i],
            customPath:
                'avatars/${FirebaseAuth.instance.currentUser!.uid}/$avatarId/images/${DateTime.now().millisecondsSinceEpoch}_$i.jpg',
          );
          if (url != null) allImages.add(url);
        }

        // Upload Videos einzeln
        for (int i = 0; i < _newVideoFiles.length; i++) {
          final url = await FirebaseStorageService.uploadVideo(
            _newVideoFiles[i],
            customPath:
                'avatars/${FirebaseAuth.instance.currentUser!.uid}/$avatarId/videos/${DateTime.now().millisecondsSinceEpoch}_$i.mp4',
          );
          if (url != null) allVideos.add(url);
        }

        // Upload Text Files einzeln
        for (int i = 0; i < _newTextFiles.length; i++) {
          final url = await FirebaseStorageService.uploadTextFile(
            _newTextFiles[i],
            customPath:
                'avatars/${FirebaseAuth.instance.currentUser!.uid}/$avatarId/texts/${DateTime.now().millisecondsSinceEpoch}_$i.txt',
          );
          if (url != null) allTexts.add(url);
        }

        // 3) Profilbild setzen, falls noch nicht gewählt
        String? avatarImageUrl = _profileImageUrl;
        if (avatarImageUrl == null && allImages.isNotEmpty) {
          avatarImageUrl = allImages.first;
        }

        // 3b) Training-Counts aktualisieren
        final totalDocuments =
            allImages.length +
            allVideos.length +
            allTexts.length +
            (_avatarData!.writtenTexts.length);
        final training = {
          'status': 'pending',
          'startedAt': null,
          'finishedAt': null,
          'lastRunAt': null,
          'progress': 0.0,
          'totalDocuments': totalDocuments,
          'totalFiles': {
            'texts': allTexts.length,
            'images': allImages.length,
            'videos': allVideos.length,
            'others': 0,
          },
          'totalChunks': 0,
          'chunkSize': 0,
          'totalTokens': 0,
          'vector': null,
          'lastError': null,
          'jobId': null,
          'needsRetrain': true,
        };

        // 4) Avatar updaten
        final updated = _avatarData!.copyWith(
          firstName: _firstNameController.text.trim(),
          nickname: _nicknameController.text.trim().isEmpty
              ? null
              : _nicknameController.text.trim(),
          lastName: _lastNameController.text.trim().isEmpty
              ? null
              : _lastNameController.text.trim(),
          birthDate: _birthDate,
          deathDate: _deathDate,
          calculatedAge: _calculatedAge,
          updatedAt: DateTime.now(),
          imageUrls: allImages,
          videoUrls: allVideos,
          textFileUrls: allTexts,
          avatarImageUrl: avatarImageUrl,
          training: training,
        );

        final ok = await _avatarService.updateAvatar(updated);
        if (!mounted) return;
        if (ok) {
          if (!mounted) return;
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Erfolgreich gespeichert'),
              content: const Text(
                'Deine Daten wurden erfolgreich gespeichert.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          // Lokale Daten aktualisieren
          _applyAvatar(updated);
          if (!mounted) return;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Speichern fehlgeschlagen')),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }();
  }

  void _showSuccessSnackBar(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Erfolgreich gespeichert'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteSelectedImages() async {
    final total = _selectedRemoteImages.length + _selectedLocalImages.length;
    if (total == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bilder löschen?'),
        content: Text('Möchtest du $total Bild(er) wirklich löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    // Remote löschen
    for (final url in _selectedRemoteImages) {
      await FirebaseStorageService.deleteFile(url);
      _imageUrls.remove(url);
      if (_profileImageUrl == url) {
        _profileImageUrl = _imageUrls.isNotEmpty ? _imageUrls.first : null;
      }
    }
    // Local entfernen
    _newImageFiles.removeWhere((f) => _selectedLocalImages.contains(f.path));
    _selectedRemoteImages.clear();
    _selectedLocalImages.clear();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _nicknameController.dispose();
    _lastNameController.dispose();
    _birthDateController.dispose();
    _deathDateController.dispose();
    super.dispose();
  }
}
