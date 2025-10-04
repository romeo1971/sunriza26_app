import 'package:flutter/material.dart';
import '../services/localization_service.dart';
import 'package:provider/provider.dart';

class AvatarBottomNavBar extends StatelessWidget {
  final String avatarId;
  final String
  currentScreen; // 'details' | 'media' | 'playlists' | 'moments' | 'facts'
  const AvatarBottomNavBar({
    super.key,
    required this.avatarId,
    required this.currentScreen,
  });

  Color _iconColor(bool active) =>
      active ? Colors.white : Colors.white.withOpacity(0.5);

  @override
  Widget build(BuildContext context) {
    final loc = context.read<LocalizationService>();
    return SafeArea(
      top: false,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _item(
              context,
              active: currentScreen == 'details',
              iconFilled: Icons.edit,
              iconOutlined: Icons.edit_outlined,
              label: loc.t('profile'),
              route: '/avatar-details',
            ),
            _item(
              context,
              active: currentScreen == 'media',
              iconFilled: Icons.photo_library,
              iconOutlined: Icons.photo_library_outlined,
              label: loc.t('gallery.title'),
              route: '/media-gallery',
              args: {'avatarId': avatarId},
            ),
            _item(
              context,
              active: currentScreen == 'playlists',
              iconFilled: Icons.queue_music,
              iconOutlined: Icons.queue_music_outlined,
              label: loc.t('playlists.title'),
              route: '/playlist-list',
              args: {'avatarId': avatarId},
            ),
            _item(
              context,
              active: currentScreen == 'moments',
              iconFilled: Icons.collections_bookmark,
              iconOutlined: Icons.collections_bookmark_outlined,
              label: loc.t('sharedMoments.title'),
              route: '/shared-moments',
              args: {'avatarId': avatarId},
            ),
            _item(
              context,
              active: currentScreen == 'facts',
              iconFilled: Icons.fact_check,
              iconOutlined: Icons.fact_check_outlined,
              label: 'Fakten',
              route: '/avatar-review-facts',
              args: {'avatarId': avatarId},
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context, {
    required bool active,
    required IconData iconFilled,
    required IconData iconOutlined,
    required String label,
    required String route,
    Map<String, dynamic>? args,
  }) {
    final color = _iconColor(active);
    final icon = active ? iconFilled : iconOutlined;
    return GestureDetector(
      onTap: () {
        if (active) return;
        Navigator.pushReplacementNamed(
          context,
          route,
          arguments: args ?? {'avatarId': avatarId},
        );
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: color, fontSize: 8)),
        ],
      ),
    );
  }
}
