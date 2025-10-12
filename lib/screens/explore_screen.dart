import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/avatar_data.dart';
import 'home_navigation_screen.dart';

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

  // PageController für persistente Scroll-Position
  late PageController _pageController;
  int _currentPageIndex = 0;

  // Explorer Timeline State
  Timer? _explorerTimer;
  final Map<String, List<String>> _explorerImages =
      {}; // avatarId -> eye-active images
  final Map<String, int> _currentIndex = {}; // avatarId -> current index
  final Map<String, String?> _currentImage =
      {}; // avatarId -> current image URL

  // LRU Cache: Behalte letzte 5 Avatare im Speicher
  static const int _maxCachedAvatars = 5;
  final List<String> _cachedAvatarIds =
      []; // Queue: Ältester = [0], Neuester = [last]

  // Firestore Listener für aktuellen Avatar (Live-Updates bei Änderungen)
  StreamSubscription<DocumentSnapshot>? _currentAvatarSub;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentPageIndex);
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
    _pageController.dispose();
    _explorerTimer?.cancel();
    _currentAvatarSub?.cancel();

    // Cleanup: Alle gecachten Avatare entfernen
    for (final avatarId in _cachedAvatarIds) {
      final images = _explorerImages[avatarId];
      if (images != null) {
        for (final url in images) {
          NetworkImage(url).evict();
        }
      }
    }
    debugPrint(
      '🗑️ Explorer Screen dispose: ${_cachedAvatarIds.length} Avatare aus Cache entfernt',
    );

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

  // Explorer Timeline: Lade eye-active Images
  Future<void> _loadExplorerImages(String avatarId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('avatars')
          .doc(avatarId)
          .get();

      if (!doc.exists) return;

      final data = doc.data()!;
      final allImages =
          (data['imageUrls'] as List<dynamic>?)?.cast<String>() ?? [];

      if (allImages.isEmpty) {
        _explorerImages[avatarId] = [];
        _currentImage[avatarId] = null;
        return;
      }

      // Timeline-Daten laden
      final timeline = data['imageTimeline'] as Map<String, dynamic>?;
      final explorerVisible =
          timeline?['explorerVisible'] as Map<String, dynamic>?;

      // WICHTIG: Hero-Image (Index 0) ist IMMER sichtbar im Explorer
      final heroImage = allImages[0];

      // Filtere eye-active Images (OHNE Hero, da immer dabei)
      final activeImages = allImages.skip(1).where((url) {
        return explorerVisible?[url] == true;
      }).toList();

      // Hero-Image IMMER an Index 0, dann active Images
      final explorerImagesList = [heroImage, ...activeImages];

      _explorerImages[avatarId] = explorerImagesList;
      _currentIndex[avatarId] = 0;
      _currentImage[avatarId] = heroImage;

      // Preload Hero-Image
      if (mounted) {
        precacheImage(NetworkImage(heroImage), context);
      }
    } catch (e) {
      debugPrint('❌ Explorer Images Fehler: $e');
    }
  }

  // Firestore Listener für Live-Updates des aktuellen Avatars
  void _startAvatarListener(String avatarId) {
    _currentAvatarSub?.cancel();
    _currentAvatarSub = FirebaseFirestore.instance
        .collection('avatars')
        .doc(avatarId)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists && mounted && _currentAvatarId == avatarId) {
            // Bei Änderungen: Bilder NEU LADEN (gelöscht/verschoben/etc.)
            debugPrint('🔄 Explorer: Avatar-Daten geändert, lade Bilder neu');
            _loadExplorerImages(avatarId).then((_) {
              _startExplorerTimer(avatarId);
              if (mounted) setState(() {});
            });
          }
        });
  }

  // LRU Cache Management: Füge Avatar hinzu und lösche ältesten wenn Limit erreicht
  void _manageLRUCache(String newAvatarId) {
    // Entferne Avatar aus Liste wenn bereits vorhanden (wird neu hinzugefügt am Ende)
    _cachedAvatarIds.remove(newAvatarId);

    // Füge aktuellen Avatar am Ende hinzu (= zuletzt verwendet)
    _cachedAvatarIds.add(newAvatarId);

    // Wenn Limit überschritten: Lösche ÄLTESTEN Avatar (Index 0)
    if (_cachedAvatarIds.length > _maxCachedAvatars) {
      final oldestAvatarId = _cachedAvatarIds.removeAt(0);

      // Cleanup für ältesten Avatar
      final oldImages = _explorerImages[oldestAvatarId];
      if (oldImages != null) {
        for (final url in oldImages) {
          NetworkImage(url).evict();
        }
        debugPrint(
          '🗑️ LRU Cache bereinigt: $oldestAvatarId (${oldImages.length} Bilder) | Cache: ${_cachedAvatarIds.length}/$_maxCachedAvatars',
        );

        // Entferne aus Maps
        _explorerImages.remove(oldestAvatarId);
        _currentIndex.remove(oldestAvatarId);
        _currentImage.remove(oldestAvatarId);
      }
    } else {
      debugPrint(
        '✅ LRU Cache: $newAvatarId hinzugefügt | Cache: ${_cachedAvatarIds.length}/$_maxCachedAvatars',
      );
    }
  }

  // Explorer Timeline: Starte 2-Sekunden-Loop
  void _startExplorerTimer(String avatarId) {
    _explorerTimer?.cancel();

    final images = _explorerImages[avatarId];
    if (images == null || images.length <= 1) return;

    _explorerTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted || _currentAvatarId != avatarId) {
        timer.cancel();
        return;
      }

      final idx = _currentIndex[avatarId] ?? 0;
      final nextIdx = (idx + 1) % images.length; // IMMER LOOP

      setState(() {
        _currentIndex[avatarId] = nextIdx;
        _currentImage[avatarId] = images[nextIdx];
      });

      // Preload next (KEIN BLACK SCREEN)
      final preloadIdx = (nextIdx + 1) % images.length;
      precacheImage(NetworkImage(images[preloadIdx]), context);
    });
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
              controller: _pageController,
              scrollDirection: Axis.vertical,
              itemCount: _cachedAvatars.length,
              onPageChanged: (index) async {
                _currentPageIndex = index; // Position speichern
                final avatarId = _cachedAvatars[index].id;
                _currentAvatarId = avatarId;
                widget.onCurrentAvatarChanged?.call(avatarId);

                // LRU Cache Management
                _manageLRUCache(avatarId);

                // Timeline laden & starten (nur wenn noch nicht geladen)
                if (!_explorerImages.containsKey(avatarId)) {
                  await _loadExplorerImages(avatarId);
                }
                _startExplorerTimer(avatarId);

                // Starte Listener für Live-Updates
                _startAvatarListener(avatarId);

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
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Noch keine öffentlichen Avatare',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          itemCount: _cachedAvatars.length,
          onPageChanged: (index) async {
            _currentPageIndex = index; // Position speichern
            final avatarId = _cachedAvatars[index].id;
            _currentAvatarId = avatarId;
            widget.onCurrentAvatarChanged?.call(avatarId);

            // LRU Cache Management
            _manageLRUCache(avatarId);

            // Timeline laden & starten (nur wenn noch nicht geladen)
            if (!_explorerImages.containsKey(avatarId)) {
              await _loadExplorerImages(avatarId);
            }
            _startExplorerTimer(avatarId);

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

    // Timeline-Bild oder Fallback
    final imageUrl = _currentImage[avatar.id] ?? avatar.avatarImageUrl;

    // Bild SOFORT in den Cache laden (unsichtbar)
    if (imageUrl != null) {
      precacheImage(NetworkImage(imageUrl), context);
    }

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
      body: Container(
        decoration: BoxDecoration(
          image: imageUrl != null
              ? DecorationImage(
                  image: NetworkImage(imageUrl),
                  fit: BoxFit.cover,
                )
              : null,
          color: imageUrl == null ? Colors.grey.shade800 : null,
        ),
        child: Stack(
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
                              Shadow(offset: Offset(1, 0), color: Colors.white),
                              Shadow(
                                offset: Offset(-1, 0),
                                color: Colors.white,
                              ),
                              Shadow(offset: Offset(0, 1), color: Colors.white),
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
                  backgroundColor: Colors.black.withValues(alpha: 0.7),
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
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
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
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
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
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
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
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
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
