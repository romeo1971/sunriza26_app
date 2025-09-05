import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_service.dart';
import '../models/user_profile.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
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
    setState(() {
      _loading = true;
    });
    try {
      // Stelle sicher, dass ein Basisprofil existiert
      await _userService.upsertCurrentUserProfile();
      final p = await _userService.getCurrentUserProfile();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _nameController.text =
            p?.displayName ??
            (FirebaseAuth.instance.currentUser?.displayName ?? '');
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _pickPhoto() async {
    final x = await _picker.pickImage(source: ImageSource.gallery);
    if (x == null) return;
    setState(() {
      _loading = true;
    });
    try {
      final url = await _userService.uploadUserPhoto(File(x.path));
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
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _deletePhoto() async {
    setState(() {
      _loading = true;
    });
    try {
      await _userService.deleteUserPhoto();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profilbild entfernt')));
      await _load();
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _loading = true;
    });
    try {
      await _userService.upsertCurrentUserProfile(
        displayName: _nameController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profil gespeichert')));
      Navigator.pop(context);
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil bearbeiten'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 12),
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.deepPurple.shade100,
                    backgroundImage:
                        (_profile?.photoUrl != null &&
                            _profile!.photoUrl!.isNotEmpty)
                        ? NetworkImage(_profile!.photoUrl!)
                        : null,
                    child:
                        (_profile?.photoUrl == null ||
                            _profile!.photoUrl!.isEmpty)
                        ? const Icon(
                            Icons.person,
                            size: 48,
                            color: Colors.deepPurple,
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _pickPhoto,
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Foto wählen'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _deletePhoto,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Foto löschen'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Anzeigename',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.deepPurple.shade300,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Name anzeigen...',
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Speichern'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}
