import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:crop_your_image/crop_your_image.dart' as cyi;
import 'package:path_provider/path_provider.dart';
import '../services/user_service.dart';
import '../models/user_profile.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _postalCodeController = TextEditingController();
  final TextEditingController _countryController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  final UserService _userService = UserService();

  UserProfile? _profile;
  bool _loading = false;
  bool _hasChanges = false;
  bool _listenersAttached = false;
  DateTime? _selectedDob;
  bool _uploadingPhoto = false;
  String? _profileImageUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _attachListeners() {
    if (_listenersAttached) return; // Nur einmal anhängen!
    _listenersAttached = true;

    // Listener für TextField-Änderungen - NACH dem initialen Laden
    _displayNameController.addListener(
      () => setState(() => _hasChanges = true),
    );
    _firstNameController.addListener(() => setState(() => _hasChanges = true));
    _lastNameController.addListener(() => setState(() => _hasChanges = true));
    _streetController.addListener(() => setState(() => _hasChanges = true));
    _cityController.addListener(() => setState(() => _hasChanges = true));
    _postalCodeController.addListener(() => setState(() => _hasChanges = true));
    _countryController.addListener(() => setState(() => _hasChanges = true));
    _phoneController.addListener(() => setState(() => _hasChanges = true));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await _userService.upsertCurrentUserProfile();
      final p = await _userService.getCurrentUserProfile();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _fillControllers();
        _hasChanges = false; // WICHTIG: Nach dem Laden keine Änderungen
      });
      // Listener NACH dem initialen Setzen der Werte anhängen
      _attachListeners();
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _fillControllers() {
    if (_profile != null) {
      _displayNameController.text = _profile!.displayName ?? '';
      _firstNameController.text = _profile!.firstName ?? '';
      _lastNameController.text = _profile!.lastName ?? '';
      _streetController.text = _profile!.street ?? '';
      _cityController.text = _profile!.city ?? '';
      _postalCodeController.text = _profile!.postalCode ?? '';
      _countryController.text = _profile!.country ?? '';
      _phoneController.text = _profile!.phoneNumber ?? '';

      // DOB kann null sein, wenn das Feld noch nicht existiert
      try {
        _selectedDob = _profile!.dob != null
            ? DateTime.fromMillisecondsSinceEpoch(_profile!.dob!)
            : null;
      } catch (e) {
        print('⚠️ Error loading DOB: $e');
        _selectedDob = null;
      }

      // WICHTIG: profileImageUrl direkt verwenden, KEIN Cache-Busting beim Laden
      _profileImageUrl = _profile!.profileImageUrl;
    } else {
      final user = FirebaseAuth.instance.currentUser;
      _displayNameController.text = user?.displayName ?? '';
      _phoneController.text = user?.phoneNumber ?? '';
    }
  }

  Future<File?> _cropToPortrait916(File input) async {
    try {
      final bytes = await input.readAsBytes();
      final cropController = cyi.CropController();
      Uint8List? result;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          backgroundColor: Colors.black,
          clipBehavior: Clip.hardEdge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: LayoutBuilder(
            builder: (dCtx, _) {
              final sz = MediaQuery.of(dCtx).size;
              final double dlgW = (sz.width * 0.9).clamp(320.0, 900.0);
              final double dlgH = (sz.height * 0.9).clamp(480.0, 1200.0);
              return SizedBox(
                width: dlgW,
                height: dlgH,
                child: Column(
                  children: [
                    Expanded(
                      child: cyi.Crop(
                        controller: cropController,
                        image: bytes,
                        aspectRatio: 9 / 16,
                        withCircleUi: false,
                        baseColor: Colors.black,
                        maskColor: Colors.black38,
                        onCropped: (cropped) {
                          result = cropped;
                          Navigator.pop(ctx);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                result = null;
                                Navigator.pop(ctx);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Ink(
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade800,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  child: Center(
                                    child: Text(
                                      'Abbrechen',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => cropController.crop(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Ink(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFE91E63),
                                      AppColors.lightBlue,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  child: Center(
                                    child: Text(
                                      'Zuschneiden',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

      if (result == null) return null;
      final dir = await getTemporaryDirectory();
      final tmp = await File(
        '${dir.path}/crop_${DateTime.now().millisecondsSinceEpoch}.png',
      ).create(recursive: true);
      await tmp.writeAsBytes(result!, flush: true);
      return tmp;
    } catch (_) {
      return null;
    }
  }

  Future<void> _uploadPhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    File f = File(pickedFile.path);
    print('🖼️ Original file: ${f.path}');

    final cropped = await _cropToPortrait916(f);
    if (cropped == null) {
      print('❌ Cropping cancelled or failed');
      return;
    }

    f = cropped;
    print('✅ Using cropped file: ${f.path}');

    setState(() => _uploadingPhoto = true);

    try {
      print('📤 Uploading to Firebase...');
      final url = await _userService.uploadProfileImage(f);
      print('✅ Upload complete: $url');

      if (!mounted) return;

      // WICHTIG: Sofort in Firestore speichern
      if (_profile != null && url != null) {
        final updatedProfile = _profile!.copyWith(
          profileImageUrl: url,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        await _userService.updateUserProfile(updatedProfile);
        print('✅ ProfileImageUrl saved to Firestore: $url');

        // Profile neu laden
        _profile = updatedProfile;
      }

      setState(() {
        _profileImageUrl = url;
        _uploadingPhoto = false;
        _hasChanges = false; // Wurde bereits gespeichert
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.read<LocalizationService>().t('profile.photoUpdated'),
          ),
        ),
      );
    } catch (e) {
      print('❌ Upload error: $e');
      setState(() => _uploadingPhoto = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler beim Upload: $e')));
      }
    }
  }

  Future<void> _save() async {
    try {
      // Erweiterte Profildaten speichern
      final cleanImageUrl = _profileImageUrl;

      final updatedProfile = _profile?.copyWith(
        displayName: _displayNameController.text.trim().isEmpty
            ? null
            : _displayNameController.text.trim(),
        firstName: _firstNameController.text.trim().isEmpty
            ? null
            : _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim().isEmpty
            ? null
            : _lastNameController.text.trim(),
        street: _streetController.text.trim().isEmpty
            ? null
            : _streetController.text.trim(),
        city: _cityController.text.trim().isEmpty
            ? null
            : _cityController.text.trim(),
        postalCode: _postalCodeController.text.trim().isEmpty
            ? null
            : _postalCodeController.text.trim(),
        country: _countryController.text.trim().isEmpty
            ? null
            : _countryController.text.trim(),
        phoneNumber: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        profileImageUrl: cleanImageUrl,
        dob: _selectedDob?.millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      if (updatedProfile != null) {
        print(
          '✅ Saving profile: dob=${updatedProfile.dob}, profileImageUrl=${updatedProfile.profileImageUrl}',
        );
        await _userService.updateUserProfile(updatedProfile);
        print('✅ Profile saved successfully');
      } else {
        print('⚠️ No profile to update, creating new one');
        await _userService.upsertCurrentUserProfile(
          displayName: _displayNameController.text.trim(),
        );
      }

      if (!mounted) return;

      // WICHTIG: Nur _hasChanges zurücksetzen, NICHT _profileImageUrl ändern!
      setState(() => _hasChanges = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.read<LocalizationService>().t('profile.saved')),
        ),
      );
    } catch (e) {
      print('❌ Save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler beim Speichern: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade900,
      appBar: AppBar(
        title: const Text('Profildaten'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (_hasChanges)
            IconButton(
              onPressed: _save,
              icon: const Icon(
                Icons.save_outlined,
                color: Colors.white,
                size: 28,
              ),
              tooltip: context.read<LocalizationService>().t(
                'avatars.details.saveTooltip',
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Profilbild-Sektion
                  _buildPhotoSection(),
                  const SizedBox(height: 32),

                  // Persönliche Daten
                  _buildSection(
                    context.read<LocalizationService>().t(
                      'profile.personalData',
                    ),
                    [
                      _buildTextField(
                        _displayNameController,
                        context.read<LocalizationService>().t(
                          'profile.displayName',
                        ),
                      ),
                      _buildTextField(
                        _firstNameController,
                        context.read<LocalizationService>().t(
                          'avatars.details.firstNameLabel',
                        ),
                      ),
                      _buildTextField(
                        _lastNameController,
                        context.read<LocalizationService>().t(
                          'avatars.details.lastNameLabel',
                        ),
                      ),
                      _buildDobField(),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Adressdaten
                  _buildSection(
                    context.read<LocalizationService>().t('profile.address'),
                    [
                      _buildTextField(
                        _streetController,
                        context.read<LocalizationService>().t(
                          'profile.streetAndNumber',
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: _buildTextField(
                              _postalCodeController,
                              context.read<LocalizationService>().t(
                                'profile.postalCode',
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: _buildTextField(
                              _cityController,
                              context.read<LocalizationService>().t(
                                'profile.city',
                              ),
                            ),
                          ),
                        ],
                      ),
                      _buildTextField(
                        _countryController,
                        context.read<LocalizationService>().t(
                          'profile.country',
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Telefonnummer
                  _buildSection('Telefonnummer', [
                    _buildTextField(
                      _phoneController,
                      'Telefonnummer',
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.warning,
                          color: Colors.orange,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Telefonnummer nicht verifiziert',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () {},
                      style:
                          ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ).copyWith(
                            backgroundColor: WidgetStateProperty.all(
                              Colors.transparent,
                            ),
                            overlayColor: WidgetStateProperty.all(
                              Colors.white.withOpacity(0.1),
                            ),
                          ),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: const Center(
                          child: Text(
                            'Verifizieren',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]),

                  const SizedBox(height: 24),

                  // Zahlungseinstellungen
                  _buildSection('Zahlungseinstellungen', [
                    _buildPaymentSection(),
                  ]),

                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildPhotoSection() {
    return GestureDetector(
      onTap: _uploadingPhoto ? null : _uploadPhoto,
      child: Container(
        width: 120,
        height: 213, // 9:16 aspect ratio
        decoration: BoxDecoration(
          color: Colors.grey.shade800,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade600),
        ),
        child: _uploadingPhoto
            ? const Center(child: CircularProgressIndicator())
            : _profileImageUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(_profileImageUrl!, fit: BoxFit.cover),
              )
            : const Center(
                child: Icon(
                  Icons.add_photo_alternate,
                  size: 40,
                  color: Colors.white54,
                ),
              ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          ...children.map(
            (child) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      readOnly: readOnly,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade400),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.grey.shade600),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.grey.shade600),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.deepPurple),
        ),
        filled: true,
        fillColor: Colors.grey.shade700,
      ),
    );
  }

  Widget _buildDobField() {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _selectedDob ?? DateTime(1990),
          firstDate: DateTime(1900),
          lastDate: DateTime.now(),
        );
        if (picked != null) {
          setState(() {
            _selectedDob = picked;
            _hasChanges = true;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.grey.shade700,
          border: Border.all(color: Colors.grey.shade600),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _selectedDob != null
                  ? '${_selectedDob!.day}.${_selectedDob!.month}.${_selectedDob!.year}'
                  : 'Geburtsdatum',
              style: TextStyle(
                color: _selectedDob != null
                    ? Colors.white
                    : Colors.grey.shade400,
                fontSize: 16,
              ),
            ),
            const Icon(Icons.calendar_today, color: Colors.white70, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.credit_card, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _profile?.stripeCustomerId != null
                    ? context.read<LocalizationService>().t(
                        'profile.paymentsConfigured',
                      )
                    : context.read<LocalizationService>().t(
                        'profile.noPayments',
                      ),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.read<LocalizationService>().t('profile.stripeTodo'),
                ),
              ),
            );
          },
          style:
              ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ).copyWith(
                backgroundColor: WidgetStateProperty.all(Colors.transparent),
                overlayColor: WidgetStateProperty.all(
                  Colors.white.withOpacity(0.1),
                ),
              ),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: const Center(
              child: Text(
                'Verwalten',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _streetController.dispose();
    _cityController.dispose();
    _postalCodeController.dispose();
    _countryController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}
