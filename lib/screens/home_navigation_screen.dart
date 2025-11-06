import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'explore_screen.dart';
import 'favorites_screen.dart';
import 'avatar_list_screen.dart';
import 'user_profile_public_screen.dart';
import 'moments_screen.dart';
import 'avatar_chat_screen.dart';
import '../theme/app_theme.dart';

/// Home Navigation mit TikTok-Style Bottom Bar
class HomeNavigationScreen extends StatefulWidget {
  final int initialIndex; // Startseite (0 = Explore, 1 = Meine Avatare)

  const HomeNavigationScreen({super.key, this.initialIndex = 0});

  @override
  State<HomeNavigationScreen> createState() => HomeNavigationScreenState();
}

class HomeNavigationScreenState extends State<HomeNavigationScreen> {
  late int _currentIndex;
  String? _activeChatAvatarId; // Für Chat-Overlay
  final GlobalKey<ExploreScreenState> _exploreKey =
      GlobalKey<ExploreScreenState>();

  // Screens als late-Instanzvariablen, damit sie EINMAL erstellt werden
  late final Widget _exploreScreen;
  late final Widget _avatarListScreen;
  late final Widget _favoritesScreen;
  late final Widget _profileScreen;
  late final Widget _momentsScreen;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;

    // Screens einmalig initialisieren
    _exploreScreen = ExploreScreen(key: _exploreKey);
    _avatarListScreen = const AvatarListScreen();
    _favoritesScreen = const FavoritesScreen();
    _profileScreen = const UserProfilePublicScreen();
    _momentsScreen = const MomentsScreen();

    // Prüfe, ob ein Chat nach Resume geöffnet werden soll
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final pendingAvatarId = prefs.getString('pending_open_chat_avatar_id');
        if (pendingAvatarId != null && pendingAvatarId.isNotEmpty) {
          if (mounted) {
            openChat(pendingAvatarId);
          }
          await prefs.remove('pending_open_chat_avatar_id');
        }
      } catch (_) {}
    });
  }

  Future<void> _toggleFavoriteInExplore(
    String? avatarId,
    bool isFavorite,
  ) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    if (avatarId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Kein Avatar ausgewählt')));
      return;
    }

    try {
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId);

      if (isFavorite) {
        // Entfernen (HOOK-Button)
        await userRef.update({
          'favoriteAvatarIds': FieldValue.arrayRemove([avatarId]),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Aus Favoriten entfernt')),
          );
        }
      } else {
        // Hinzufügen (PLUS-Button)
        await userRef.update({
          'favoriteAvatarIds': FieldValue.arrayUnion([avatarId]),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Favorit hinzugefügt ✓')),
          );
        }
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

  // ignore: unused_element
  Future<void> _removeFavoriteInFavorites() async {
    // FEHLT NOCH: Im Favoriten-Screen aktuellen Avatar ermitteln und entfernen
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Favorit entfernt ✓')));
  }

  void openChat(String avatarId) {
    setState(() => _activeChatAvatarId = avatarId);
  }

  void closeChat() {
    setState(() => _activeChatAvatarId = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Haupt-Content: IndexedStack verhindert Neuaufbau beim Tab-Wechsel
          IndexedStack(
            index: _currentIndex,
            children: [
              _exploreScreen,
              _avatarListScreen,
              _favoritesScreen,
              _momentsScreen,
            ],
          ),

          // Chat-Overlay (wenn aktiv)
          if (_activeChatAvatarId != null)
            AvatarChatScreen(
              avatarId: _activeChatAvatarId!,
              onClose: closeChat,
            ),
        ],
      ),
      bottomNavigationBar: (_activeChatAvatarId != null)
          ? null // Chat aktiv → keine Bottom-Navigation (WhatsApp-Style)
          : SafeArea(
              top: false,
              child: Container(
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.black,
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // Home
                    _buildNavItem(
                      iconFilled: Icons.home,
                      iconOutlined: Icons.home_outlined,
                      label: 'Home',
                      index: 0,
                    ),
                    // Meine Avatare
                    _buildNavItem(
                      iconFilled: Icons.people,
                      iconOutlined: Icons.people_outline,
                      label: 'Meine Avatare',
                      index: 1,
                    ),
                    // Favoriten
                    _buildNavItem(
                      iconFilled: Icons.favorite,
                      iconOutlined: Icons.favorite_border,
                      label: 'Favoriten',
                      index: 2,
                    ),
                    // Momente (NEU)
                    _buildNavItem(
                      iconFilled: Icons.bookmarks,
                      iconOutlined: Icons.bookmarks_outlined,
                      label: 'Momente',
                      index: 3,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildNavItem({
    required IconData iconFilled,
    required IconData iconOutlined,
    required String label,
    required int index,
  }) {
    final isSelected = _currentIndex == index;
    final isChatActive =
        _activeChatAvatarId != null && index == 0; // Chat = Home

    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_activeChatAvatarId != null) {
            closeChat(); // Chat schließen
          }
          setState(() => _currentIndex = index);
        },
        behavior: HitTestBehavior.opaque, // WICHTIG: Gesamter Bereich klickbar
        child: Container(
          color: Colors.transparent, // Touch-Target vergrößern
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isChatActive)
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [
                          Color(0xFFE91E63), // Magenta
                          AppColors.lightBlue, // Blue
                          Color(0xFF00E5FF), // Cyan
                        ],
                      ).createShader(bounds),
                      child: Icon(iconFilled, color: Colors.white, size: 20),
                    )
                  else
                    Icon(
                      isSelected ? iconFilled : iconOutlined,
                      color: isSelected ? Colors.white : Colors.grey.shade400,
                      size: 20,
                    ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      color: (isSelected || isChatActive)
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.5),
                      fontSize: 8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildMiddleButton() {
    // In Home (Index 0): PLUS oder HOOK (je nach Favoriten-Status)
    // In Favoriten (Index 2): HOOK Button (Remove from Favorites)
    if (_currentIndex == 0) {
      // Home: Prüfe ob aktueller Avatar favorisiert ist
      final avatarId = _exploreKey.currentState?.getCurrentAvatarId();
      final isFavorite =
          _exploreKey.currentState?.isAvatarFavorite(avatarId) ?? false;

      return GestureDetector(
        onTap: () => _toggleFavoriteInExplore(avatarId, isFavorite),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFFE91E63), // Magenta
                AppColors.lightBlue, // Blue
                Color(0xFF00E5FF), // Cyan
              ],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isFavorite ? Icons.check : Icons.add,
            color: Colors.white,
            size: 20,
          ),
        ),
      );
    } else {
      // Anderen Tabs: Unsichtbar
      return const SizedBox(width: 32, height: 32);
    }
  }
}
