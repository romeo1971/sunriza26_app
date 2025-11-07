import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../web/web_helpers.dart' as web;
import 'dart:convert';
import 'explore_screen.dart';
import 'favorites_screen.dart';
import 'avatar_list_screen.dart';
import 'moments_screen.dart';
import 'avatar_chat_screen.dart';
import '../theme/app_theme.dart';
import '../services/moments_service.dart';
import '../widgets/purchase_success_dialog.dart';

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
  late final Widget _momentsScreen;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;

    // Screens einmalig initialisieren
    _exploreScreen = ExploreScreen(key: _exploreKey);
    _avatarListScreen = const AvatarListScreen();
    _favoritesScreen = const FavoritesScreen();
    _momentsScreen = const MomentsScreen();

    // Prüfe Stripe-Success aus sessionStorage
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        
        // Prüfe sessionStorage für Stripe-Success
        final stripeData = web.getSessionStorage('stripe_media_success');
        
        if (stripeData != null && stripeData.isNotEmpty) {
          debugPrint('✅✅✅ [HomeNav] Stripe-Success gefunden: $stripeData');
          web.removeSessionStorage('stripe_media_success');
          
          try {
            final data = json.decode(stripeData);
            final avatarId = data['avatarId'] as String?;
            final mediaName = data['mediaName'] as String?;
            
            if (avatarId != null && mediaName != null && mounted) {
              openChat(avatarId);
              
              await Future.delayed(const Duration(milliseconds: 800));
              
              // Auto-Download: Polling bis Moment geschrieben ist (Webhook-Delay)
              String? downloadUrl = await _resolveDownloadUrl(avatarId: avatarId, mediaName: mediaName);
              if (downloadUrl != null && downloadUrl.isNotEmpty) {
                try {
                  final uri = Uri.parse(downloadUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
                  } else {
                    await _triggerBrowserDownload(downloadUrl);
                  }
                } catch (_) {
                  await _triggerBrowserDownload(downloadUrl);
                }
              }

              if (mounted) {
                // Anzeigename des Avatars ermitteln
                String displayName = 'Avatar';
                try {
                  final doc = await FirebaseFirestore.instance.collection('avatars').doc(avatarId).get();
                  if (doc.exists) {
                    final d = doc.data() ?? {};
                    final nickname = (d['nickname'] as String?)?.trim();
                    final firstName = (d['firstName'] as String?)?.trim();
                    displayName = (nickname != null && nickname.isNotEmpty) ? nickname : (firstName ?? 'Avatar');
                  }
                } catch (_) {}
                await showPurchaseSuccessDialog(
                  context: context,
                  data: PurchaseSuccessData(
                    mediaName: mediaName,
                    avatarName: displayName,
                    source: 'home',
                    variant: 'cash',
                    downloadUrl: downloadUrl,
                  ),
                );
              }
            }
          } catch (e) {
            debugPrint('🔴 [HomeNav] JSON parse error: $e');
          }
        }
        
        // Alt: pending_open_chat_avatar_id
        final pendingAvatarId = prefs.getString('pending_open_chat_avatar_id');
        if (pendingAvatarId != null && pendingAvatarId.isNotEmpty && mounted) {
          openChat(pendingAvatarId);
          await prefs.remove('pending_open_chat_avatar_id');
        }
      } catch (e) {
        debugPrint('❌ [HomeNav] Error: $e');
      }
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

  Future<String?> _resolveDownloadUrl({required String avatarId, required String mediaName, int tries = 6, Duration delay = const Duration(milliseconds: 600)}) async {
    for (int i = 0; i < tries; i++) {
      try {
        final moments = await MomentsService().listMoments(avatarId: avatarId);
        if (moments.isNotEmpty) {
          final byName = moments.firstWhere(
            (m) => (m.originalFileName ?? '').trim() == mediaName.trim(),
            orElse: () => moments.first,
          );
          final url = byName.storedUrl.isNotEmpty ? byName.storedUrl : byName.originalUrl;
          if (url.isNotEmpty) return url;
        }
      } catch (_) {}
      await Future.delayed(delay);
    }
    return null;
  }

  Future<void> _triggerBrowserDownload(String url, {String? filename}) async {
    // Erzwinge Download-Header für Firebase-URLs
    try {
      if (url.contains('firebasestorage.googleapis.com')) {
        final hasQuery = url.contains('?');
        final encoded = Uri.encodeComponent('attachment; filename="${filename ?? 'download'}"');
        final param = 'response-content-disposition=$encoded';
        if (!url.contains('response-content-disposition=')) {
          url = url + (hasQuery ? '&' : '?') + param;
        }
      }
    } catch (_) {}
    // Übergib Download an Web-Helper (Web) bzw. Launcher (Mobile)
    await web.downloadUrlCompat(url, filename: filename);
  }

  void _showMediaSuccessDialog(String mediaName, String avatarName, String mediaUrl) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: const Text('Kauf bestätigt', style: TextStyle(color: Colors.white)),
        content: Text(
          '"$mediaName" von "$avatarName" wurde zu deinen Momenten hinzugefügt. Der Download wurde gestartet.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Später', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () async {
              if (mediaUrl.isNotEmpty) {
                try {
                  final uri = Uri.parse(mediaUrl);
                  await launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
                } catch (_) {}
              }
              if (Navigator.canPop(context)) Navigator.pop(context);
            },
            child: const Text('Nochmal herunterladen', style: TextStyle(color: AppColors.lightBlue)),
          ),
        ],
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
