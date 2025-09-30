import 'package:flutter/material.dart';
import '../services/shared_moments_service.dart';
import '../models/shared_moment.dart';
import '../services/media_service.dart';
import '../models/media_models.dart';
import '../services/localization_service.dart';
import 'package:provider/provider.dart';

class SharedMomentsScreen extends StatefulWidget {
  final String avatarId;
  const SharedMomentsScreen({super.key, required this.avatarId});

  @override
  State<SharedMomentsScreen> createState() => _SharedMomentsScreenState();
}

class _SharedMomentsScreenState extends State<SharedMomentsScreen> {
  final _svc = SharedMomentsService();
  final _mediaSvc = MediaService();
  List<SharedMoment> _items = [];
  Map<String, AvatarMedia> _media = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _svc.list(widget.avatarId);
    final medias = await _mediaSvc.list(widget.avatarId);
    setState(() {
      _items = list;
      _media = {for (final m in medias) m.id: m};
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.read<LocalizationService>().t('sharedMoments.title'),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? Center(
              child: Text(
                context.read<LocalizationService>().t('sharedMoments.empty'),
              ),
            )
          : ListView.separated(
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
    );
  }
}
