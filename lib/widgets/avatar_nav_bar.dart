import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/localization_service.dart';
import '../services/avatar_service.dart';
import '../screens/avatar_review_facts_screen.dart';

/// Globale Navigation für alle Avatar-Bereiche
/// Design wie "Meine Avatare": IconButtons mit weißen Icons in schwarzem Container
class AvatarNavBar extends StatelessWidget {
  final String avatarId;
  final String
  currentScreen; // 'media', 'playlists', 'moments', 'details', 'facts'

  const AvatarNavBar({
    super.key,
    required this.avatarId,
    required this.currentScreen,
  });

  @override
  Widget build(BuildContext context) {
    final loc = context.read<LocalizationService>();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Fakten prüfen Icon (nur wenn nicht auf Fakten-Screen)
          if (currentScreen != 'facts')
            IconButton(
              tooltip: 'Fakten prüfen',
              icon: const Icon(Icons.fact_check, size: 18, color: Colors.white),
              onPressed: () async {
                await Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AvatarReviewFactsScreen(
                      avatarId: avatarId,
                    ), // KEIN fromScreen → Ersetzt aktuellen Screen, Zurück geht zu Details
                  ),
                );
              },
            ),

          // Datenwelt Icon
          if (currentScreen != 'details')
            IconButton(
              tooltip: 'Datenwelt',
              icon: const Icon(Icons.edit, size: 18, color: Colors.white),
              onPressed: () async {
                // Avatar-Objekt laden und übergeben
                final avatarService = AvatarService();
                final avatar = await avatarService.getAvatar(avatarId);
                if (avatar != null && context.mounted) {
                  await Navigator.pushReplacementNamed(
                    context,
                    '/avatar-details',
                    arguments: avatar,
                  );
                }
              },
            ),

          // Media Bereich Icon
          if (currentScreen != 'media')
            IconButton(
              tooltip: loc.t('gallery.title'),
              icon: const Icon(
                Icons.photo_library_outlined,
                size: 18,
                color: Colors.white,
              ),
              onPressed: () {
                Navigator.pushReplacementNamed(
                  context,
                  '/media-gallery',
                  arguments: {
                    'avatarId': avatarId,
                  }, // KEIN fromScreen → Ersetzt aktuellen Screen, Zurück geht zu Details
                );
              },
            ),

          // Playlists Icon
          if (currentScreen != 'playlists')
            IconButton(
              tooltip: loc.t('playlists.title'),
              icon: const Icon(
                Icons.playlist_play,
                size: 20,
                color: Colors.white,
              ),
              onPressed: () {
                Navigator.pushReplacementNamed(
                  context,
                  '/playlist-list',
                  arguments: {
                    'avatarId': avatarId,
                  }, // KEIN fromScreen → Ersetzt aktuellen Screen, Zurück geht zu Details
                );
              },
            ),

          // Geteilte Momente Icon
          if (currentScreen != 'moments')
            IconButton(
              tooltip: loc.t('sharedMoments.title'),
              icon: const Icon(
                Icons.collections_bookmark_outlined,
                size: 18,
                color: Colors.white,
              ),
              onPressed: () {
                Navigator.pushReplacementNamed(
                  context,
                  '/shared-moments',
                  arguments: {
                    'avatarId': avatarId,
                  }, // KEIN fromScreen → Ersetzt aktuellen Screen, Zurück geht zu Details
                );
              },
            ),
        ],
      ),
    );
  }
}
