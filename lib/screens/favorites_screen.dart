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
        title: const Text(
          '❤️ Favoriten',
          style: TextStyle(color: Colors.white, fontSize: 24),
        ),
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
                // Avatar Bild
                CircleAvatar(
                  radius: 32,
                  backgroundImage: avatar.avatarImageUrl != null
                      ? NetworkImage(avatar.avatarImageUrl!)
                      : null,
                  child: avatar.avatarImageUrl == null
                      ? Text(
                          avatar.firstName[0].toUpperCase(),
                          style: const TextStyle(fontSize: 24),
                        )
                      : null,
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
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFFE91E63),
                              AppColors.lightBlue,
                              Color(0xFF00E5FF),
                            ],
                          ),
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
                // Entfernen Button
                IconButton(
                  onPressed: () => _removeFavorite(avatar.id),
                  icon: const Icon(Icons.favorite, color: Colors.red, size: 28),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startConversation(AvatarData avatar) async {
    // Finde HomeNavigationScreen im Widget-Tree
    final homeNav = context
        .findAncestorStateOfType<HomeNavigationScreenState>();

    // Begrüßungstext abspielen (TODO: Voice abspielen)
    if (avatar.greetingText != null && mounted) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              CircleAvatar(
                backgroundImage: avatar.avatarImageUrl != null
                    ? NetworkImage(avatar.avatarImageUrl!)
                    : null,
                child: avatar.avatarImageUrl == null
                    ? Text(avatar.firstName[0].toUpperCase())
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  avatar.firstName,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          content: Text(
            avatar.greetingText!,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                if (homeNav != null) {
                  homeNav.openChat(avatar.id);
                } else {
                  // Fallback: Normale Navigation mit Avatar-Objekt
                  Navigator.pushNamed(
                    context,
                    '/avatar-chat',
                    arguments: avatar,
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.lightBlue,
              ),
              child: const Text('Chat starten'),
            ),
          ],
        ),
      );
    } else {
      // Direkt zum Chat
      if (homeNav != null) {
        homeNav.openChat(avatar.id);
      } else if (mounted) {
        // Fallback: Normale Navigation mit Avatar-Objekt
        Navigator.pushNamed(context, '/avatar-chat', arguments: avatar);
      }
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
