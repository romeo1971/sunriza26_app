import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/shared_moments_service.dart';
import '../models/shared_moment.dart';
import '../services/media_service.dart';
import '../models/media_models.dart';
import '../services/localization_service.dart';
import 'package:provider/provider.dart';
import '../widgets/avatar_bottom_nav_bar.dart';
import '../services/avatar_service.dart';
import '../web/web_helpers.dart' as web;

class BolScreen extends StatefulWidget {
  final String avatarId;
  final String? fromScreen; // 'avatar-list' oder null
  const BolScreen({
    super.key,
    required this.avatarId,
    this.fromScreen,
  });

  @override
  State<BolScreen> createState() => _BolScreenState();
}

class _BolScreenState extends State<BolScreen> {
  final _svc = SharedMomentsService();
  final _mediaSvc = MediaService();
  final _scrollController = ScrollController();
  List<SharedMoment> _items = [];
  Map<String, AvatarMedia> _media = {};
  bool _loading = true;
  
  String _effectiveAvatarId = '';

  @override
  void initState() {
    super.initState();
    // Web: aktuelle avatarId für Refresh merken (nur wenn von Route übergeben)
    if (kIsWeb && widget.avatarId.isNotEmpty) {
      try {
        web.setSessionStorage('last_bol_avatar', widget.avatarId);
      } catch (_) {}
    }
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      String effectiveAvatarId = _effectiveAvatarId;
      if (effectiveAvatarId.isEmpty && kIsWeb) {
        try {
          final raw = web.getSessionStorage('last_bol_avatar');
          if (raw != null && raw.isNotEmpty) {
            effectiveAvatarId = raw;
          }
        } catch (_) {}
      }
      if (effectiveAvatarId.isEmpty) {
        setState(() {
          _effectiveAvatarId = '';
          _items = [];
          _media = {};
          _loading = false;
        });
        return;
      }

      _effectiveAvatarId = effectiveAvatarId;

      final list = await _svc.list(_effectiveAvatarId);
      final medias = await _mediaSvc.list(_effectiveAvatarId);
      if (!mounted) return;
      setState(() {
        _items = list;
        _media = {for (final m in medias) m.id: m};
      });
    } catch (e) {
      if (mounted) {
        final loc = context.read<LocalizationService>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              loc.t('avatars.details.error', params: {'msg': e.toString()}),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleBackNavigation(BuildContext context) async {
    if (widget.fromScreen == 'avatar-list') {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/avatar-list',
        (route) => false,
      );
    } else {
      final nav = Navigator.of(context);
      final avatarService = AvatarService();
      final avatar = await avatarService.getAvatar(_effectiveAvatarId);
      if (!mounted) return;
      if (avatar != null) {
        nav.pushReplacementNamed('/avatar-details', arguments: avatar);
      } else {
        nav.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BOL – Book of life'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          style: IconButton.styleFrom(
            overlayColor: Colors.white.withValues(alpha: 0.1),
          ),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => _handleBackNavigation(context),
        ),
      ),
      body: Column(
        children: [
          const SizedBox.shrink(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const Center(
                        child: Text(
                          'Keine Einträge',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    : ListView.separated(
                        controller: _scrollController,
                        itemCount: _items.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final it = _items[i];
                          final media = _media[it.mediaId];
                          return ListTile(
                            leading: Icon(
                              (media?.type == AvatarMediaType.video)
                                  ? Icons.videocam
                                  : Icons.photo,
                            ),
                            title: Text(media?.url.split('/').last ?? it.mediaId),
                            subtitle: Text(
                              it.decision == 'rejected'
                                  ? 'Abgelehnt'
                                  : 'Gezeigt',
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: AvatarBottomNavBar(
        avatarId: _effectiveAvatarId,
        currentScreen: 'bol',
      ),
      backgroundColor: Colors.black,
    );
  }
}
