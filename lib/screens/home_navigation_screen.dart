import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'explore_screen.dart';
import 'favorites_screen.dart';
import 'avatar_list_screen.dart';
import 'user_profile_public_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  late final List<Widget> _screens = [
    ExploreScreen(key: _exploreKey),
    const AvatarListScreen(),
    const FavoritesScreen(),
    const UserProfilePublicScreen(),
  ];

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

  Future<void> _removeFavoriteInFavorites() async {
    // TODO: Im Favoriten-Screen aktuellen Avatar ermitteln und entfernen
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
          // Haupt-Content (Explore, Favoriten, etc.)
          _screens[_currentIndex],

          // Chat-Overlay (wenn aktiv)
          if (_activeChatAvatarId != null)
            AvatarChatScreen(
              avatarId: _activeChatAvatarId!,
              onClose: closeChat,
            ),
        ],
      ),
      bottomNavigationBar: Container(
        height: 70,
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
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
            // Plus Button (nur in Home) / Hook Button (in Favoriten)
            _buildMiddleButton(),
            // Favoriten
            _buildNavItem(
              iconFilled: Icons.favorite,
              iconOutlined: Icons.favorite_border,
              label: 'Favoriten',
              index: 2,
            ),
            // Profil
            _buildNavItem(
              iconFilled: Icons.person,
              iconOutlined: Icons.person_outline,
              label: 'Profil',
              index: 3,
            ),
          ],
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

    return GestureDetector(
      onTap: () {
        if (_activeChatAvatarId != null) {
          closeChat(); // Chat schließen
        }
        setState(() => _currentIndex = index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
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
                child: Icon(iconFilled, color: Colors.white, size: 28),
              )
            else
              Icon(
                isSelected ? iconFilled : iconOutlined,
                color: isSelected ? Colors.white : Colors.grey.shade400,
                size: 28,
              ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: (isSelected || isChatActive)
                    ? Colors.white
                    : Colors.white.withOpacity(0.5),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

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
