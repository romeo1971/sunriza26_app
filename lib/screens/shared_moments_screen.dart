import 'package:flutter/material.dart';
import '../services/shared_moments_service.dart';
import '../models/shared_moment.dart';
import '../services/media_service.dart';
import '../models/media_models.dart';
import '../services/localization_service.dart';
import 'package:provider/provider.dart';
import '../widgets/avatar_nav_bar.dart';
import '../widgets/avatar_bottom_nav_bar.dart';
import '../services/avatar_service.dart';

class SharedMomentsScreen extends StatefulWidget {
  final String avatarId;
  final String? fromScreen; // 'avatar-list' oder null
  const SharedMomentsScreen({
    super.key,
    required this.avatarId,
    this.fromScreen,
  });

  @override
  State<SharedMomentsScreen> createState() => _SharedMomentsScreenState();
}

class _SharedMomentsScreenState extends State<SharedMomentsScreen> {
  final _svc = SharedMomentsService();
  final _mediaSvc = MediaService();
  final _scrollController = ScrollController();
  List<SharedMoment> _items = [];
  Map<String, AvatarMedia> _media = {};
  bool _loading = true;
  double _scrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _load();
    _scrollController.addListener(() {
      setState(() => _scrollOffset = _scrollController.offset);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _svc.list(widget.avatarId);
      final medias = await _mediaSvc.list(widget.avatarId);
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
      // Von "Meine Avatare" → zurück zu "Meine Avatare" (ALLE Screens schließen)
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/avatar-list',
        (route) => false,
      );
    } else {
      // Von anderen Screens → zurück zu Avatar Details
      final avatarService = AvatarService();
      final avatar = await avatarService.getAvatar(widget.avatarId);
      if (avatar != null && context.mounted) {
        Navigator.pushReplacementNamed(
          context,
          '/avatar-details',
          arguments: avatar,
        );
      } else {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final opacity = (_scrollOffset / 150.0).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.read<LocalizationService>().t('sharedMoments.title'),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _handleBackNavigation(context),
        ),
      ),
      body: Column(
        children: [
          const SizedBox.shrink(),
          // Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                ? Center(
                    child: Text(
                      context.read<LocalizationService>().t(
                        'sharedMoments.empty',
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: _scrollController,
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
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
                              ? context.read<LocalizationService>().t(
                                  'sharedMoments.rejected',
                                )
                              : context.read<LocalizationService>().t(
                                  'sharedMoments.shown',
                                ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: AvatarBottomNavBar(
        avatarId: widget.avatarId,
        currentScreen: 'moments',
      ),
    );
  }
}
