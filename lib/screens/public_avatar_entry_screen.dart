import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../screens/explore_screen.dart';

/// Öffentlicher Einstiegspunkt für Avatar-URLs wie:
/// https://www.hauau.de/#/avatar/<slug>
///
/// - Lädt den Avatar anhand des Slugs aus Firestore
/// - Öffnet dann direkt den Avatar-Chat in der "Explore"-Ansicht (ohne Login-Zwang)
class PublicAvatarEntryScreen extends StatelessWidget {
  final String slug;
  const PublicAvatarEntryScreen({super.key, required this.slug});

  Future<String?> _resolveAvatarId() async {
    try {
      // 1) Primär: slugs-Collection (slug -> avatarId), wie in deiner DB-Struktur
      final slugDoc = await FirebaseFirestore.instance
          .collection('slugs')
          .doc(slug)
          .get();
      if (slugDoc.exists) {
        final data = slugDoc.data();
        final avatarId = data?['avatarId'] as String?;
        if (avatarId != null && avatarId.isNotEmpty) {
          return avatarId;
        }
      }

      // 2) Fallback: direkt im Avatar-Dokument (falls slug dort gespeichert ist)
      final snap = await FirebaseFirestore.instance
          .collection('avatars')
          .where('slug', isEqualTo: slug)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return snap.docs.first.id;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<String?>(
        future: _resolveAvatarId(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00FF94)),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(
              child: Text(
                'Avatar nicht gefunden',
                style: TextStyle(color: Colors.white),
              ),
            );
          }

          final avatarId = snapshot.data!;
          // Explore-View für GENAU diesen Avatar, ohne Scrollen
          return ExploreScreen(
            initialAvatarId: avatarId,
            publicEntry: true,
          );
        },
      ),
    );
  }
}


