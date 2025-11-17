import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../screens/avatar_chat_screen.dart';

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
          // Direkt den Avatar-Chat in Vollbild öffnen (ähnlich Explore → Chat)
          return AvatarChatScreen(
            avatarId: avatarId,
          );
        },
      ),
    );
  }
}


