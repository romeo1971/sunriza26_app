import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  final List<Widget> _screens = [
    const ExploreScreen(),
    const AvatarListScreen(),
    const FavoritesScreen(),
    const UserProfilePublicScreen(),
  ];

  void _toggleFavorite() {
    // TODO: Implementiere Favoriten-Toggle
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Favorit hinzugefügt ✓')));
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
            _buildNavItem(icon: Icons.home_filled, label: 'Home', index: 0),
            // Meine Avatare
            _buildNavItem(icon: Icons.people, label: 'Meine Avatare', index: 1),
            // Plus Button (nur in Home) / Hook Button (in Favoriten)
            _buildMiddleButton(),
            // Favoriten
            _buildNavItem(icon: Icons.favorite, label: 'Favoriten', index: 2),
            // Profil
            _buildNavItem(icon: Icons.person, label: 'Profil', index: 3),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final isSelected = _currentIndex == index;

    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: Colors.white, // Immer weiß
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected
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
    // In Home (Index 0): PLUS Button
    // In Favoriten (Index 2): HOOK Button (Remove from Favorites)
    if (_currentIndex == 0) {
      // PLUS Button (Home)
      return GestureDetector(
        onTap: _toggleFavorite,
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
          child: const Icon(Icons.add, color: Colors.white, size: 20),
        ),
      );
    } else if (_currentIndex == 2) {
      // HOOK Button (Favoriten - Remove)
      return GestureDetector(
        onTap: () {
          // TODO: Implementiere Remove from Favorites
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Favorit entfernt ✓')));
        },
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
          child: const Icon(Icons.check, color: Colors.white, size: 20),
        ),
      );
    } else {
      // Anderen Tabs: Unsichtbar
      return const SizedBox(width: 32, height: 32);
    }
  }
}
