import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_service.dart';
import '../models/user_profile.dart';
import '../widgets/app_drawer.dart';

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

  final ImagePicker _picker = ImagePicker();
  final UserService _userService = UserService();

  UserProfile? _profile;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
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
      });
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
    } else {
      final user = FirebaseAuth.instance.currentUser;
      _displayNameController.text = user?.displayName ?? '';
      _phoneController.text = user?.phoneNumber ?? '';
    }
  }

  Future<void> _uploadPhoto() async {
    setState(() => _loading = true);
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      final url = await _userService.uploadUserPhoto(File(image.path));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            url != null ? 'Profilbild aktualisiert' : 'Upload fehlgeschlagen',
          ),
        ),
      );
      await _load();
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _deletePhoto() async {
    setState(() => _loading = true);
    try {
      await _userService.deleteUserPhoto();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profilbild entfernt')));
      await _load();
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      // Erweiterte Profildaten speichern
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
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      if (updatedProfile != null) {
        await _userService.updateUserProfile(updatedProfile);
      } else {
        await _userService.upsertCurrentUserProfile(
          displayName: _displayNameController.text.trim(),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profil gespeichert')));
      Navigator.pop(context);
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade900,
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Profil bearbeiten'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          if (!_loading)
            TextButton(
              onPressed: _save,
              child: const Text(
                'Speichern',
                style: TextStyle(color: Colors.white),
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
                  _buildSection('Persönliche Daten', [
                    _buildTextField(_displayNameController, 'Anzeigename'),
                    _buildTextField(_firstNameController, 'Vorname'),
                    _buildTextField(_lastNameController, 'Nachname'),
                    _buildTextField(
                      _phoneController,
                      'Telefonnummer',
                      keyboardType: TextInputType.phone,
                    ),
                  ]),

                  const SizedBox(height: 24),

                  // Adressdaten
                  _buildSection('Adresse', [
                    _buildTextField(_streetController, 'Straße und Hausnummer'),
                    Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: _buildTextField(_postalCodeController, 'PLZ'),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: _buildTextField(_cityController, 'Stadt'),
                        ),
                      ],
                    ),
                    _buildTextField(_countryController, 'Land'),
                  ]),

                  const SizedBox(height: 24),

                  // Zahlungseinstellungen
                  _buildSection('Zahlungseinstellungen', [
                    _buildPaymentSection(),
                  ]),

                  const SizedBox(height: 32),

                  // Aktionen
                  _buildActionButtons(),
                ],
              ),
            ),
    );
  }

  Widget _buildPhotoSection() {
    return Column(
      children: [
        CircleAvatar(
          radius: 60,
          backgroundColor: Colors.deepPurple.shade100,
          backgroundImage:
              (_profile?.photoUrl != null && _profile!.photoUrl!.isNotEmpty)
              ? NetworkImage(_profile!.photoUrl!)
              : null,
          child: (_profile?.photoUrl == null || _profile!.photoUrl!.isEmpty)
              ? const Icon(Icons.person, size: 48, color: Colors.deepPurple)
              : null,
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: _uploadPhoto,
              icon: const Icon(Icons.photo_camera),
              label: const Text('Foto ändern'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(width: 16),
            if (_profile?.photoUrl != null && _profile!.photoUrl!.isNotEmpty)
              TextButton.icon(
                onPressed: _deletePhoto,
                icon: const Icon(Icons.delete, color: Colors.red),
                label: const Text(
                  'Entfernen',
                  style: TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ],
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

  Widget _buildPaymentSection() {
    return Column(
      children: [
        Row(
          children: [
            const Icon(Icons.credit_card, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _profile?.stripeCustomerId != null
                    ? 'Zahlungsmethoden konfiguriert'
                    : 'Keine Zahlungsmethoden hinterlegt',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            TextButton(
              onPressed: () {
                // TODO: Stripe-Integration
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Stripe-Integration wird implementiert'),
                  ),
                );
              },
              child: const Text('Verwalten'),
            ),
          ],
        ),
        if (_profile?.phoneNumber != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                _profile!.phoneVerified ? Icons.verified : Icons.warning,
                color: _profile!.phoneVerified ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 12),
              Text(
                _profile!.phoneVerified
                    ? 'Telefonnummer verifiziert'
                    : 'Telefonnummer nicht verifiziert',
                style: const TextStyle(color: Colors.white),
              ),
              if (!_profile!.phoneVerified) ...[
                const Spacer(),
                TextButton(
                  onPressed: () {
                    // TODO: Telefon-Verifikation
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Telefon-Verifikation wird implementiert',
                        ),
                      ),
                    );
                  },
                  child: const Text('Verifizieren'),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Profil speichern'),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
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
