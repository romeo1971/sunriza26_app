import 'package:flutter/material.dart';
import '../services/playlist_service.dart';
import '../models/playlist_models.dart';
import '../services/localization_service.dart';
import 'package:provider/provider.dart';

class PlaylistListScreen extends StatefulWidget {
  final String avatarId;
  const PlaylistListScreen({super.key, required this.avatarId});

  @override
  State<PlaylistListScreen> createState() => _PlaylistListScreenState();
}

class _PlaylistListScreenState extends State<PlaylistListScreen> {
  final _svc = PlaylistService();
  List<Playlist> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await _svc.list(widget.avatarId);
      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _create() async {
    final name = await _promptName();
    if (name == null || name.trim().isEmpty) return;
    await _svc.create(widget.avatarId, name: name.trim(), showAfterSec: 0);
    await _load();
  }

  Future<String?> _promptName() async {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.read<LocalizationService>().t('playlists.new')),
        content: TextField(
          controller: c,
          decoration: InputDecoration(
            hintText: context.read<LocalizationService>().t('common.name'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              context.read<LocalizationService>().t('buttons.cancel'),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: Text(
              context.read<LocalizationService>().t('playlists.create'),
            ),
          ),
        ],
      ),
    );
  }

  void _openEdit(Playlist p) {
    Navigator.pushNamed(context, '/playlist-edit', arguments: p);
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.read<LocalizationService>();
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.t('playlists.title')),
        actions: [
          IconButton(
            tooltip: loc.t('avatars.refreshTooltip'),
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: loc.t('playlists.new'),
            onPressed: _create,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Text(
                            'Keine Playlists vorhanden',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final p = _items[i];
                        return ListTile(
                          title: Text(p.name),
                          subtitle: Text(
                            loc.t('playlists.showAfterSecPrefix') +
                                ' ' +
                                p.showAfterSec.toString() +
                                loc.t('playlists.secondsSuffix'),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openEdit(p),
                        );
                      },
                    ),
            ),
    );
  }
}
