import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/avatar_data.dart';
import '../theme/app_theme.dart';
import 'package:video_player/video_player.dart';
import 'home_navigation_screen.dart';

/// Entdecken Screen - Öffentliche Avatare im Feed-Style
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Set<String> _favoriteIds = {};

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('favorites')
          .get();

      setState(() {
        _favoriteIds = snapshot.docs.map((doc) => doc.id).toSet();
      });
    } catch (e) {
      debugPrint('Fehler beim Laden der Favoriten: $e');
    }
  }

  Future<void> _toggleFavorite(String avatarId) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      final favRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('favorites')
          .doc(avatarId);

      if (_favoriteIds.contains(avatarId)) {
        // Entfernen
        await favRef.delete();
        setState(() => _favoriteIds.remove(avatarId));
      } else {
        // Hinzufügen
        await favRef.set({
          'avatarId': avatarId,
          'addedAt': FieldValue.serverTimestamp(),
        });
        setState(() => _favoriteIds.add(avatarId));
      }
    } catch (e) {
      debugPrint('Fehler beim Favoriten-Toggle: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showSearch() {
    showSearch(
      context: context,
      delegate: AvatarSearchDelegate(_favoriteIds, _toggleFavorite),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('avatars')
          .where('isPublic', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: Text('Fehler: ${snapshot.error}')),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final avatars = snapshot.data!.docs
            .map(
              (doc) => AvatarData.fromMap(doc.data() as Map<String, dynamic>),
            )
            .toList();

        if (avatars.isEmpty) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.explore_off,
                    size: 64,
                    color: Colors.white.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Noch keine öffentlichen Avatare',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return PageView.builder(
          scrollDirection: Axis.vertical,
          itemCount: avatars.length,
          onPageChanged: (index) {
            setState(() {
              // Aktuellen Avatar Index speichern
            });
          },
          itemBuilder: (context, index) {
            return _buildFullscreenAvatarPage(avatars[index]);
          },
        );
      },
    );
  }

  Widget _buildFullscreenAvatarPage(AvatarData avatar) {
    // isPublic Namen sammeln
    final nameParts = <String>[];
    if (avatar.firstNamePublic == true) {
      nameParts.add(avatar.firstName);
    }
    if (avatar.nicknamePublic == true && avatar.nickname != null) {
      nameParts.add('"${avatar.nickname}"');
    }
    if (avatar.lastNamePublic == true && avatar.lastName != null) {
      nameParts.add(avatar.lastName!);
    }
    final displayName = nameParts.isEmpty ? 'Avatar' : nameParts.join(' ');

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          displayName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: _showSearch,
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          image: avatar.avatarImageUrl != null
              ? DecorationImage(
                  image: NetworkImage(avatar.avatarImageUrl!),
                  fit: BoxFit.cover,
                )
              : null,
          color: avatar.avatarImageUrl == null ? Colors.grey.shade800 : null,
        ),
        child: Stack(
          children: [
            // Unten: Conversation starten Button (schwarz)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: ElevatedButton.icon(
                onPressed: () {
                  final homeNav = context
                      .findAncestorStateOfType<HomeNavigationScreenState>();
                  if (homeNav != null) {
                    homeNav.openChat(avatar.id);
                  } else {
                    Navigator.pushNamed(
                      context,
                      '/avatar-chat',
                      arguments: {'avatarId': avatar.id},
                    );
                  }
                },
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Conversation starten'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black.withOpacity(0.7),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview(String url) {
    return Image.network(
      url,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          height: 300,
          color: Colors.grey.shade800,
          child: const Center(
            child: Icon(Icons.image_not_supported, color: Colors.white54),
          ),
        );
      },
    );
  }

  Widget _buildVideoPreview(String url) {
    return Container(
      width: double.infinity,
      color: Colors.grey.shade800,
      child: const Center(
        child: Icon(Icons.play_circle_outline, color: Colors.white, size: 64),
      ),
    );
  }
}

/// Search Delegate für Avatar-Suche
class AvatarSearchDelegate extends SearchDelegate<String> {
  final Set<String> favoriteIds;
  final Function(String) toggleFavorite;

  AvatarSearchDelegate(this.favoriteIds, this.toggleFavorite);

  @override
  String get searchFieldLabel => 'Avatar suchen...';

  @override
  ThemeData appBarTheme(BuildContext context) {
    return ThemeData(
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: Colors.white, fontSize: 18),
      ),
    );
  }

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      // Kreuz löscht nur den Text, schließt NICHT die Suche
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear, color: Colors.white),
          onPressed: () {
            query = '';
          },
        ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    // Return-Arrow nur sichtbar wenn KEIN Text eingegeben
    if (query.isEmpty) {
      return IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => close(context, ''),
      );
    }
    // Sonst: Lupe-Icon
    return const Padding(
      padding: EdgeInsets.all(12.0),
      child: Icon(Icons.search, color: Colors.white),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSearchResults();
  }

  Widget _buildSearchResults() {
    if (query.isEmpty) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Text(
            'Avatar-Namen eingeben...',
            style: TextStyle(color: Colors.white.withOpacity(0.5)),
          ),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('avatars')
            .where('isPublic', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final avatars = snapshot.data!.docs
              .map(
                (doc) => AvatarData.fromMap(doc.data() as Map<String, dynamic>),
              )
              .where((avatar) {
                final name =
                    '${avatar.firstName} ${avatar.lastName ?? ''} ${avatar.nickname ?? ''}'
                        .toLowerCase();
                return name.contains(query.toLowerCase());
              })
              .toList();

          if (avatars.isEmpty) {
            return Center(
              child: Text(
                'Keine Avatare gefunden',
                style: TextStyle(color: Colors.white.withOpacity(0.6)),
              ),
            );
          }

          return ListView.builder(
            itemCount: avatars.length,
            itemBuilder: (context, index) {
              final avatar = avatars[index];
              final isFavorite = favoriteIds.contains(avatar.id);

              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: avatar.avatarImageUrl != null
                      ? NetworkImage(avatar.avatarImageUrl!)
                      : null,
                  child: avatar.avatarImageUrl == null
                      ? Text(avatar.firstName[0].toUpperCase())
                      : null,
                ),
                title: Text(
                  '${avatar.firstName} ${avatar.lastName ?? ''}',
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: avatar.role != null
                    ? Text(
                        avatar.role!,
                        style: TextStyle(color: Colors.white.withOpacity(0.6)),
                      )
                    : null,
                trailing: IconButton(
                  icon: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: isFavorite ? Colors.red : Colors.white,
                  ),
                  onPressed: () => toggleFavorite(avatar.id),
                ),
                onTap: () {
                  close(context, '');
                  final homeNav = context
                      .findAncestorStateOfType<HomeNavigationScreenState>();
                  if (homeNav != null) {
                    homeNav.openChat(avatar.id);
                  } else {
                    Navigator.pushNamed(
                      context,
                      '/avatar-chat',
                      arguments: {'avatarId': avatar.id},
                    );
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
