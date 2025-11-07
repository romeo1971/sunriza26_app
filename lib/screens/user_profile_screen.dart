import 'dart:io';
import 'package:flutter/foundation.dart';
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
import '../widgets/custom_text_field.dart';
import '../widgets/custom_date_field.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

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

  void _markChanged() {
    setState(() => _hasChanges = true);
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
      if (mounted) {
        setState(() => _loading = false);
      }
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
        debugPrint('⚠️ Error loading DOB: $e');
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
      if (!mounted) return null;

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
                          try {
                            final dynamic any = cropped; // API-kompatibel
                            if (any is Uint8List) {
                              result = any;
                            } else if (any is cyi.CropSuccess) {
                              result = any.croppedImage as Uint8List?;
                            } else if (any?.bytes is Uint8List) {
                              result = any.bytes as Uint8List?;
                            }
                          } catch (_) {}
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

  Future<ImageSource?> _chooseImageSource() async {
    return await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white),
              title: const Text('Aus Galerie wählen', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: Colors.white),
              title: const Text('Mit Kamera aufnehmen', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
      backgroundColor: const Color(0xFF1A1A1A),
    );
  }

  Future<void> _uploadPhoto() async {
    final source = await _chooseImageSource();
    if (source == null) return;

    // Berechtigungen anfragen
    if (source == ImageSource.camera) {
      final st = await Permission.camera.status;
      if (st.isDenied || st.isRestricted) {
        final req = await Permission.camera.request();
        if (!req.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kamera-Zugriff verweigert')));
          }
          return;
        }
      }
    } else {
      // iOS: Fotos, Android: Speicher – nur bei Bedarf anfragen
      if (!kIsWeb && Platform.isIOS) {
        final pst = await Permission.photos.status;
        if (pst.isDenied || pst.isRestricted) {
          await Permission.photos.request();
        }
      } else if (!kIsWeb && Platform.isAndroid) {
        final sst = await Permission.storage.status;
        if (sst.isDenied || sst.isRestricted) {
          await Permission.storage.request();
        }
      }
    }

    File? file;
    if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      // Desktop: FilePicker
      final res = await FilePicker.platform.pickFiles(type: FileType.image);
      final path = res?.files.single.path;
      if (path != null) file = File(path);
    } else {
      // Mobile/Web: ImagePicker
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: source, imageQuality: 90);
      if (pickedFile != null) file = File(pickedFile.path);
    }

    if (file == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Keine Datei ausgewählt')));
      }
      return;
    }

    File f = file;
    debugPrint('🖼️ Original file: ${f.path}');

    final cropped = await _cropToPortrait916(f);
    if (cropped == null) {
      debugPrint('❌ Cropping cancelled or failed');
      return;
    }

    f = cropped;
    debugPrint('✅ Using cropped file: ${f.path}');

    setState(() => _uploadingPhoto = true);

    try {
      debugPrint('📤 Uploading to Firebase...');
      final url = await _userService.uploadProfileImage(f);
      debugPrint('✅ Upload complete: $url');

      if (!mounted) return;

      // WICHTIG: Sofort in Firestore speichern (nur erlaubte Felder)
      if (url != null) {
        await _userService.updateCurrentUserProfileImageUrl(url);
        debugPrint('✅ ProfileImageUrl saved to Firestore: $url');
        if (_profile != null) {
          _profile = _profile!.copyWith(
            profileImageUrl: url,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          );
        }
      }

      setState(() {
        _profileImageUrl = url;
        _uploadingPhoto = false;
        _hasChanges = false; // Wurde bereits gespeichert
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.read<LocalizationService>().t('profile.photoUpdated'),
          ),
        ),
      );
    } catch (e) {
      debugPrint('❌ Upload error: $e');
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
        debugPrint(
          '✅ Saving profile: dob=${updatedProfile.dob}, profileImageUrl=${updatedProfile.profileImageUrl}',
        );
        await _userService.updateUserProfile(updatedProfile);
        debugPrint('✅ Profile saved successfully');
      } else {
        debugPrint('⚠️ No profile to update, creating new one');
        await _userService.upsertCurrentUserProfile(
          displayName: _displayNameController.text.trim(),
        );
      }

      if (!mounted) return;

      // WICHTIG: Nur _hasChanges zurücksetzen, NICHT _profileImageUrl ändern!
      setState(() => _hasChanges = false);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.read<LocalizationService>().t('profile.saved')),
        ),
      );
    } catch (e) {
      debugPrint('❌ Save error: $e');
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
      backgroundColor: Colors.black, // Schwarz wie im Details Screen
      appBar: AppBar(
        title: const Text('Profildaten'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          style: IconButton.styleFrom(
            overlayColor: Colors.white.withValues(alpha: 0.1),
          ),
        ),
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
                  const SizedBox(height: 6),

                  // Persönliche Daten - ExpansionTile wie im Details Screen
                  _buildExpandableSection(
                    context.read<LocalizationService>().t(
                      'profile.personalData',
                    ),
                    [
                      CustomTextField(
                        label: context.read<LocalizationService>().t(
                          'profile.displayName',
                        ),
                        controller: _displayNameController,
                        onChanged: (_) => _markChanged(),
                      ),
                      const SizedBox(height: 16),
                      CustomTextField(
                        label: context.read<LocalizationService>().t(
                          'avatars.details.firstNameLabel',
                        ),
                        controller: _firstNameController,
                        onChanged: (_) => _markChanged(),
                      ),
                      const SizedBox(height: 16),
                      CustomTextField(
                        label: context.read<LocalizationService>().t(
                          'avatars.details.lastNameLabel',
                        ),
                        controller: _lastNameController,
                        onChanged: (_) => _markChanged(),
                      ),
                      const SizedBox(height: 16),
                      CustomDateField(
                        label: context.read<LocalizationService>().t(
                          'profile.dateOfBirth',
                        ),
                        selectedDate: _selectedDob,
                        onDateSelected: (date) {
                          setState(() {
                            _selectedDob = date;
                            _hasChanges = true;
                          });
                        },
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // Adressdaten - ExpansionTile wie im Details Screen
                  _buildExpandableSection(
                    context.read<LocalizationService>().t('profile.address'),
                    [
                      CustomTextField(
                        label: context.read<LocalizationService>().t(
                          'profile.streetAndNumber',
                        ),
                        controller: _streetController,
                        onChanged: (_) => _markChanged(),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: CustomTextField(
                              label: context.read<LocalizationService>().t(
                                'profile.postalCode',
                              ),
                              controller: _postalCodeController,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => _markChanged(),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: CustomTextField(
                              label: context.read<LocalizationService>().t(
                                'profile.city',
                              ),
                              controller: _cityController,
                              onChanged: (_) => _markChanged(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      CustomTextField(
                        label: context.read<LocalizationService>().t(
                          'profile.country',
                        ),
                        controller: _countryController,
                        onChanged: (_) => _markChanged(),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // Telefonnummer - ExpansionTile wie im Details Screen
                  _buildExpandableSection('Telefonnummer', [
                    CustomTextField(
                      label: 'Telefonnummer',
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      onChanged: (_) => _markChanged(),
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
                              Colors.white.withValues(alpha: 0.1),
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

                  const SizedBox(height: 6),

                  // Zahlungsmoethoden - ExpansionTile wie im Details Screen
                  _buildExpandableSection('Zahlungsmoethoden', [
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
          color: Colors.white.withValues(
            alpha: 0.04,
          ), // Konsistent mit ExpansionTile
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(
              alpha: 0.2,
            ), // Subtiler weißer Border
            width: 1,
          ),
        ),
        child: _uploadingPhoto
            ? const Center(child: CircularProgressIndicator())
            : _profileImageUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Image.network(
                  _profileImageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    // Fallback bei 404/Token-Fehlern
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() => _profileImageUrl = null);
                    });
                    return const Center(
                      child: Icon(
                        Icons.add_photo_alternate,
                        size: 40,
                        color: Colors.white54,
                      ),
                    );
                  },
                ),
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

  Widget _buildExpandableSection(String title, List<Widget> children) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: ExpansionTile(
        initiallyExpanded: false,
        collapsedBackgroundColor: Colors.white.withValues(alpha: 0.04),
        backgroundColor: Colors.white.withValues(alpha: 0.06),
        collapsedIconColor: AppColors.magenta, // GMBC Arrow collapsed
        iconColor: AppColors.lightBlue, // GMBC Arrow expanded
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
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
          onPressed: _manageStripeConnect,
          style:
              ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ).copyWith(
                backgroundColor: WidgetStateProperty.all(Colors.transparent),
                overlayColor: WidgetStateProperty.all(
                  Colors.white.withValues(alpha: 0.1),
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
        if (_profile?.stripeConnectAccountId != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _openStripeDashboard,
            icon: const Icon(Icons.open_in_new, color: Colors.white70),
            label: const Text('Stripe Dashboard öffnen', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ],
    );
  }

  Future<void> _manageStripeConnect() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final countryRaw = _countryController.text.trim();
      final country = (countryRaw.isNotEmpty ? countryRaw : (_profile?.country ?? 'DE')).toUpperCase();
      final email = user.email ?? _profile?.email ?? '';

      final fns = FirebaseFunctions.instanceFor(region: 'us-central1');
      final fn = fns.httpsCallable('createConnectedAccount');

      final res = await fn.call({
        'country': country,
        'email': email,
        'businessType': 'individual',
      });

      final data = Map<String, dynamic>.from(res.data as Map);
      final url = data['url'] as String?;
      if (url == null || url.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kein Onboarding-Link erhalten')));
        }
        return;
      }

      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kann Link nicht öffnen: $url')));
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Future<void> _openStripeDashboard() async {
    try {
      final fns = FirebaseFunctions.instanceFor(region: 'us-central1');
      final fn = fns.httpsCallable('createSellerDashboardLink');
      final res = await fn.call();
      final data = Map<String, dynamic>.from(res.data as Map);
      final url = data['url'] as String?;
      if (url == null || url.isEmpty) return;
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dashboard-Link fehlgeschlagen: $e')));
    }
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
