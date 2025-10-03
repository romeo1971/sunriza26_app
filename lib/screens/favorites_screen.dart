import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/avatar_data.dart';
import '../theme/app_theme.dart';
import 'home_navigation_screen.dart';

/// Favoriten Screen - Gespeicherte Lieblings-Avatare
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'Nicht angemeldet',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Favoriten'),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Fehler: ${snapshot.error}',
                style: const TextStyle(color: Colors.white),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data?.data() as Map<String, dynamic>?;
          final favoriteIds =
              (data?['favoriteAvatarIds'] as List<dynamic>?)
                  ?.map((e) => e as String)
                  .toList() ??
              [];

          if (favoriteIds.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.favorite_border,
                    size: 64,
                    color: Colors.white.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Noch keine Favoriten',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Markiere Avatare mit ❤️ beim Entdecken',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            );
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('avatars')
                .where(
                  FieldPath.documentId,
                  whereIn: favoriteIds.take(10).toList(),
                )
                .snapshots(),
            builder: (context, avatarSnapshot) {
              if (!avatarSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final avatars = avatarSnapshot.data!.docs
                  .map(
                    (doc) =>
                        AvatarData.fromMap(doc.data() as Map<String, dynamic>),
                  )
                  .toList();

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: avatars.length,
                itemBuilder: (context, index) {
                  return _buildFavoriteCard(avatars[index]);
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildFavoriteCard(AvatarData avatar) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _startConversation(avatar),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Avatar Bild 9:16
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: avatar.avatarImageUrl != null
                      ? Image.network(
                          avatar.avatarImageUrl!,
                          width: 54,
                          height: 96,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: 54,
                          height: 96,
                          color: Colors.grey.shade800,
                          child: Center(
                            child: Text(
                              avatar.firstName[0].toUpperCase(),
                              style: const TextStyle(fontSize: 24),
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 16),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${avatar.firstName} ${avatar.nickname != null ? '"${avatar.nickname}"' : ''} ${avatar.lastName ?? ''}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (avatar.role != null)
                        Text(
                          avatar.role!,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 13,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          border: Border.all(color: Colors.white, width: 1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Conversation starten',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Entfernen Button - Herz mit GMBC Gradient
                GestureDetector(
                  onTap: () => _removeFavorite(avatar.id),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFE91E63), // Magenta
                          AppColors.lightBlue, // Blue
                          Color(0xFF00E5FF), // Cyan
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: const Icon(
                      Icons.favorite,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startConversation(AvatarData avatar) async {
    // Direkt zum Chat - KEINE Dialoge!
    final homeNav = context
        .findAncestorStateOfType<HomeNavigationScreenState>();

    if (homeNav != null) {
      homeNav.openChat(avatar.id);
    } else if (mounted) {
      Navigator.pushNamed(context, '/avatar-chat', arguments: avatar);
    }
  }

  Future<void> _removeFavorite(String avatarId) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'favoriteAvatarIds': FieldValue.arrayRemove([avatarId]),
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Aus Favoriten entfernt')));
      }
    } catch (e) {
      debugPrint('Fehler beim Entfernen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
