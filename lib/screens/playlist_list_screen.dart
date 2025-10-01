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

  void _openEdit(Playlist p) async {
    final result = await Navigator.pushNamed(context, '/playlist-edit', arguments: p);
    if (result == true) {
      _load(); // Reload list after edit
    }
  }

  Widget _buildScheduleSummary(Playlist p) {
    if (p.weeklySchedules.isEmpty && p.specialSchedules.isEmpty) {
      return const Text('Kein Zeitplan', style: TextStyle(fontSize: 11, color: Colors.grey));
    }
    
    final weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final slotIcons = ['🌅', '☀️', '🌞', '🌤️', '🌆', '🌙'];
    final slotTimes = ['3-6', '6-11', '11-14', '14-18', '18-23', '23-3'];
    
    // Erstelle Map: weekday -> timeSlots
    final Map<int, List<int>> weekdaySlots = {};
    for (final ws in p.weeklySchedules) {
      weekdaySlots[ws.weekday] = ws.timeSlots.map((t) => t.index).toList();
    }
    
    final dayWidgets = <Widget>[];
    
    // Erstelle Spalte für jeden Wochentag (1-7)
    for (int wd = 1; wd <= 7; wd++) {
      if (weekdaySlots.containsKey(wd)) {
        final slotWidgets = weekdaySlots[wd]!.map((i) {
          return Text(
            '${slotIcons[i]} ${slotTimes[i]}',
            style: const TextStyle(fontSize: 9, color: Colors.white70),
          );
        }).toList();
        
        dayWidgets.add(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                weekdays[wd - 1],
                style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
              ),
              ...slotWidgets,
            ],
          ),
        );
      }
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: dayWidgets,
        ),
        if (p.specialSchedules.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '📅 ${p.specialSchedules.length} Sondertermin${p.specialSchedules.length > 1 ? "e" : ""}',
              style: const TextStyle(fontSize: 10, color: Colors.amber),
            ),
          ),
      ],
    );
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
                        return InkWell(
                          onTap: () => _openEdit(p),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Cover Image
                                p.coverImageUrl != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          p.coverImageUrl!,
                                          width: 100,
                                          height: 178,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : Container(
                                        width: 100,
                                        height: 178,
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade800,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.playlist_play, size: 60, color: Colors.white54),
                                      ),
                                const SizedBox(width: 16),
                                // Content
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            p.name,
                                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                                          ),
                                          if (p.highlightTag != null) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.amber.withOpacity(0.3),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: Colors.amber),
                                              ),
                                              child: Text(
                                                p.highlightTag!,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.amber,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Anzeigezeit: ${p.showAfterSec}s nach Chat-Beginn',
                                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                                      ),
                                      const SizedBox(height: 4),
                                      _buildScheduleSummary(p),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
