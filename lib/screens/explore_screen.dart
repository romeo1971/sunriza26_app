import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/avatar_data.dart';
import '../widgets/app_drawer.dart';
import 'home_navigation_screen.dart';
// app_theme not needed here after extraction
// removed unused service/model/purchase imports after extracting widget
import '../widgets/timeline_items_sheet.dart';

//

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
  String? _socialOverlayUrl; // aktives iFrame

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
                  Image.asset(
                    'assets/logo/logo_hauau.png',
                    width: 240,
                    height: 240,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Dein Avatar in 2 Minuten',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Text(
                      'Upload Dein Foto und Deine Stimmprobe und los geht\'s',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 16,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Noch keine öffentlichen Avatare',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
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
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 56,
        titleSpacing: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
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
          // Hero-Widget für nahtlosen Übergang zum Chat!
          Hero(
            tag: 'avatar-${avatar.id}',
            child: Container(
              decoration: BoxDecoration(
                image: imageUrl != null
                    ? DecorationImage(
                        image: NetworkImage(imageUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
                color: imageUrl == null ? Colors.grey.shade800 : null,
              ),
            ),
          ),
          Stack(
            children: [
              // Social iFrame Overlay (unter AppBar, über Hintergrund; Buttons bleiben oben)
              if (_socialOverlayUrl != null)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 56 + 8,
                  left: 0,
                  right: 0,
                  bottom: 88,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: InAppWebView(
                      initialSettings: InAppWebViewSettings(javaScriptEnabled: true),
                      initialUrlRequest: URLRequest(url: WebUri(_socialOverlayUrl!)),
                    ),
                  ),
                ),
              if (_socialOverlayUrl != null)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 56 + 12,
                  right: 12,
                  child: GestureDetector(
                    onTap: () => setState(() => _socialOverlayUrl = null),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 20),
                    ),
                  ),
                ),
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

              // Unten: Conversation starten Button + Timeline + Social Dropup
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    // Einheitliche Höhe für alle drei Buttons (hier 56)
                    // Chat starten (Button, weißer Text)
                    Expanded(
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
                        label: const Text('Chat starten'),
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
                    const SizedBox(width: 10),
                    // Timeline-Button
                    SizedBox(
                      width: 56,
                      height: 40,
                      child: ElevatedButton(
                        onPressed: () => _openTimelineOverlay(avatar.id),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.7),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        child: const Icon(Icons.timeline, size: 22),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Social Dropup (öffnet Menü nach oben)
                    _buildSocialDropupButton(avatar.id, height: 40),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openTimelineOverlay(String avatarId) async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => TimelineItemsSheet(avatarId: avatarId),
    );
  }

  Widget _buildSocialDropupButton(String avatarId, {double height = 48}) {
    final GlobalKey openerKey = GlobalKey();
    return SizedBox(
      width: 56,
      height: height,
      child: ElevatedButton(
        key: openerKey,
        onPressed: () => _openSocialMenu(openerKey, avatarId),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black.withValues(alpha: 0.7),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: EdgeInsets.zero,
        ),
        child: const FaIcon(FontAwesomeIcons.globe, size: 20, color: Colors.white),
      ),
    );
  }

  void _openSocialMenu(GlobalKey openerKey, String avatarId) async {
    // Lade verbundene Social Accounts (connected==true)
    final links = await _fetchConnectedSocials(avatarId);
    // Basis-Provider immer anbieten
    final Set<String> present = links.map((e) => (e['provider'] ?? '').toLowerCase()).toSet();
    if (!present.contains('facebook')) links.insert(0, {'provider': 'Facebook', 'url': ''});
    if (!present.contains('instagram')) links.insert(0, {'provider': 'Instagram', 'url': ''});

    await showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (_) {
        return Stack(
          children: [
            // Schließen bei Tap außerhalb
            Positioned.fill(
              child: GestureDetector(onTap: () => Navigator.of(context).pop()),
            ),
            // Dropup Panel
            Positioned(
              right: 16,
              bottom: 96, // oberhalb der Bottom-Bar
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 260,
                  constraints: const BoxConstraints(
                    maxHeight: 180,
                    minWidth: 200,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE91E63), Color(0xFF8AB4F8), Color(0xFF00E5FF)],
                      stops: [0.0, 0.5, 1.0],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 16)],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: links.map((e) {
                        final provider = e['provider']!;
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            Navigator.of(context).pop();
                            final embedUrl = _buildSocialEmbedUrl(provider, avatarId);
                            _openAvatarIframe(embedUrl);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                _whiteIcon(provider, size: 22),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    provider,
                                    textAlign: TextAlign.left,
                                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // (Legacy GMBC-Button entfernt – aktuell nicht genutzt)

  Widget _brandBtn(Widget icon, VoidCallback onTap) {
    return SizedBox(
      width: 48,
      height: 48,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black.withValues(alpha: 0.7),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: EdgeInsets.zero,
        ),
        child: icon,
      ),
    );
  }

  // (Legacy GMBC-Button entfernt – aktuell nicht genutzt)

  String _buildSocialEmbedUrl(String provider, String avatarId) {
    final p = provider.toLowerCase();
    if (p == 'instagram') {
      return 'https://us-central1-sunriza26.cloudfunctions.net/socialEmbedPage?provider=instagram&avatarId=$avatarId';
    }
    if (p == 'facebook') {
      return 'https://us-central1-sunriza26.cloudfunctions.net/socialEmbedPage?provider=facebook&avatarId=$avatarId';
    }
    return 'about:blank';
  }

  Future<List<Map<String, String>>> _fetchConnectedSocials(String avatarId) async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('avatars')
          .doc(avatarId)
          .collection('social_accounts')
          .where('connected', isEqualTo: true)
          .get();
      final items = <Map<String, String>>[];
      for (final d in qs.docs) {
        final m = d.data();
        final url = (m['url'] as String?) ?? '';
        if (url.isEmpty) continue;
        final provider = (m['providerName'] as String?) ?? _detectProvider(url);
        items.add({'provider': provider, 'url': url});
      }
      return items;
    } catch (_) {
      return [];
    }
  }

  String _detectProvider(String url) {
    final u = url.toLowerCase();
    if (u.contains('instagram.com')) return 'Instagram';
    if (u.contains('facebook.com')) return 'Facebook';
    if (u.contains('tiktok.com')) return 'TikTok';
    if (u.contains('x.com') || u.contains('twitter.com')) return 'X';
    if (u.contains('linkedin.com')) return 'LinkedIn';
    return 'Website';
  }

  Widget _brandIcon(String provider, {double size = 20}) {
    switch (provider.toLowerCase()) {
      case 'instagram':
        return FaIcon(FontAwesomeIcons.instagram, color: const Color(0xFFE4405F), size: size);
      case 'facebook':
        return FaIcon(FontAwesomeIcons.facebook, color: const Color(0xFF1877F2), size: size);
      case 'x':
        return FaIcon(FontAwesomeIcons.xTwitter, color: Colors.white, size: size);
      case 'tiktok':
        return FaIcon(FontAwesomeIcons.tiktok, color: Colors.white, size: size);
      case 'linkedin':
        return FaIcon(FontAwesomeIcons.linkedin, color: const Color(0xFF0A66C2), size: size);
      default:
        return FaIcon(FontAwesomeIcons.globe, color: Colors.white, size: size);
    }
  }

  Widget _whiteIcon(String provider, {double size = 20}) {
    switch (provider.toLowerCase()) {
      case 'instagram':
        return FaIcon(FontAwesomeIcons.instagram, color: Colors.white, size: size);
      case 'facebook':
        return FaIcon(FontAwesomeIcons.facebook, color: Colors.white, size: size);
      default:
        return FaIcon(FontAwesomeIcons.globe, color: Colors.white, size: size);
    }
  }

  void _openAvatarIframe(String url) {
    setState(() {
      _socialOverlayUrl = url;
    });
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
