import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/avatar_data.dart';
import 'home_navigation_screen.dart';
import '../widgets/safe_network_image.dart';

/// Entdecken Screen - Öffentliche Avatare im Feed-Style
class ExploreScreen extends StatefulWidget {
  final Function(String avatarId)? onCurrentAvatarChanged;

  const ExploreScreen({super.key, this.onCurrentAvatarChanged});

  @override
  State<ExploreScreen> createState() => ExploreScreenState();
}

class ExploreScreenState extends State<ExploreScreen> {
  final _searchController = TextEditingController();
  Set<String> _favoriteIds = {};
  String? _currentAvatarId;
  List<AvatarData> _cachedAvatars = [];
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  String? getCurrentAvatarId() => _currentAvatarId;

  bool isAvatarFavorite(String? avatarId) {
    if (avatarId == null) return false;
    return _favoriteIds.contains(avatarId);
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
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data();
        final favs =
            (data?['favoriteAvatarIds'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [];
        setState(() {
          _favoriteIds = favs.toSet();
        });
      }
    } catch (e) {
      debugPrint('Fehler beim Laden der Favoriten: $e');
    }
  }

  Future<void> _toggleFavorite(String avatarId) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId);

      if (_favoriteIds.contains(avatarId)) {
        // Entfernen
        await userRef.update({
          'favoriteAvatarIds': FieldValue.arrayRemove([avatarId]),
        });
        setState(() => _favoriteIds.remove(avatarId));
      } else {
        // Hinzufügen
        await userRef.update({
          'favoriteAvatarIds': FieldValue.arrayUnion([avatarId]),
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

        // WICHTIG: Beim ersten Ladezustand den Cache rendern, um Flackern
        // beim Tab-Wechsel zu vermeiden. Spinner nur wenn kein Cache existiert.
        if (snapshot.connectionState == ConnectionState.waiting) {
          if (_cachedAvatars.isNotEmpty) {
            return PageView.builder(
              scrollDirection: Axis.vertical,
              itemCount: _cachedAvatars.length,
              onPageChanged: (index) {
                _currentAvatarId = _cachedAvatars[index].id;
                widget.onCurrentAvatarChanged?.call(_cachedAvatars[index].id);
                if (mounted) setState(() {});
              },
              itemBuilder: (context, index) {
                return _buildFullscreenAvatarPage(_cachedAvatars[index]);
              },
            );
          }
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

        // Cache nur beim ersten Mal oder wenn sich die Anzahl ändert
        if (!_isInitialized || _cachedAvatars.length != avatars.length) {
          _cachedAvatars = avatars;
          _isInitialized = true;

          // Erste Avatar ID setzen wenn noch nicht gesetzt
          if (_currentAvatarId == null && avatars.isNotEmpty) {
            _currentAvatarId = avatars[0].id;
          }
        }

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
          itemCount: _cachedAvatars.length,
          onPageChanged: (index) {
            _currentAvatarId = _cachedAvatars[index].id;
            widget.onCurrentAvatarChanged?.call(_cachedAvatars[index].id);
            // Nur setState für das Herz-Icon, nicht den ganzen PageView
            if (mounted) setState(() {});
          },
          itemBuilder: (context, index) {
            return _buildFullscreenAvatarPage(_cachedAvatars[index]);
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
        toolbarHeight: 56,
        titleSpacing: 0,
        title: Transform.translate(
          offset: const Offset(0, 3),
          child: Text(
            displayName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w300,
              height: 1.0,
              shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: _showSearch,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Hintergrundbild sicher laden (mit Fallback)
          Positioned.fill(
            child: SafeNetworkImage(
              url: avatar.avatarImageUrl,
              fit: BoxFit.cover,
            ),
          ),
          // Overlay-UI
          Stack(
            children: [
              // Rechts Mitte: Favoriten-Herz (TikTok-Style)
              Positioned(
                right: 16,
                top: MediaQuery.of(context).size.height * 0.4,
                child: GestureDetector(
                  onTap: () => _toggleFavorite(avatar.id),
                  child: _favoriteIds.contains(avatar.id)
                      ? Stack(
                          children: [
                            Icon(
                              Icons.favorite,
                              color: Colors.white,
                              size: 28,
                              shadows: [
                                Shadow(
                                  offset: Offset(1, 0),
                                  color: Colors.white,
                                ),
                                Shadow(
                                  offset: Offset(-1, 0),
                                  color: Colors.white,
                                ),
                                Shadow(
                                  offset: Offset(0, 1),
                                  color: Colors.white,
                                ),
                                Shadow(
                                  offset: Offset(0, -1),
                                  color: Colors.white,
                                ),
                              ],
                            ),
                            ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [
                                  Color(0xFFE91E63), // Magenta
                                  Color(0xFF2196F3), // Blue
                                  Color(0xFF00E5FF), // Cyan
                                ],
                              ).createShader(bounds),
                              child: const Icon(
                                Icons.favorite,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ],
                        )
                      : const Icon(
                          Icons.favorite_border,
                          color: Colors.white,
                          size: 28,
                        ),
                ),
              ),

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
                        arguments: avatar,
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
        ],
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
