import 'package:flutter/material.dart';
import '../models/playlist_models.dart';
import '../services/playlist_service.dart';
import '../services/media_service.dart';
import '../models/media_models.dart';

class PlaylistEditScreen extends StatefulWidget {
  final Playlist playlist;
  const PlaylistEditScreen({super.key, required this.playlist});

  @override
  State<PlaylistEditScreen> createState() => _PlaylistEditScreenState();
}

class _PlaylistEditScreenState extends State<PlaylistEditScreen> {
  late TextEditingController _name;
  late TextEditingController _showAfter;
  final _svc = PlaylistService();
  final _mediaSvc = MediaService();
  List<PlaylistItem> _items = [];
  Map<String, AvatarMedia> _mediaMap = {};
  String _repeat = 'none';
  final _weeklyDays = const [1, 2, 3, 4, 5, 6, 7];
  int? _weeklyDay;
  int? _monthlyDay;
  final TextEditingController _specialDatesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.playlist.name);
    _showAfter = TextEditingController(
      text: widget.playlist.showAfterSec.toString(),
    );
    _repeat = widget.playlist.repeat;
    _weeklyDay = widget.playlist.weeklyDay;
    _monthlyDay = widget.playlist.monthlyDay;
    _specialDatesCtrl.text = (widget.playlist.specialDates).join(',');
    _load();
  }

  Future<void> _load() async {
    final items = await _svc.listItems(
      widget.playlist.avatarId,
      widget.playlist.id,
    );
    final medias = await _mediaSvc.list(widget.playlist.avatarId);
    setState(() {
      _items = items;
      _mediaMap = {for (final m in medias) m.id: m};
    });
  }

  Future<void> _save() async {
    final p = Playlist(
      id: widget.playlist.id,
      avatarId: widget.playlist.avatarId,
      name: _name.text.trim(),
      showAfterSec: int.tryParse(_showAfter.text.trim()) ?? 0,
      repeat: _repeat,
      weeklyDay: _repeat == 'weekly' ? _weeklyDay : null,
      monthlyDay: _repeat == 'monthly' ? _monthlyDay : null,
      specialDates: _parseDates(_specialDatesCtrl.text),
      createdAt: widget.playlist.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _svc.update(p);
    if (mounted) Navigator.pop(context);
  }

  List<String> _parseDates(String raw) {
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(e))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlist bearbeiten'),
        actions: [IconButton(onPressed: _save, icon: const Icon(Icons.save))],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _showAfter,
              decoration: const InputDecoration(
                labelText: 'Allgemeine Anzeigezeit (Sekunden) nach Chat-Beginn',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _repeat,
              items: const [
                DropdownMenuItem(
                  value: 'none',
                  child: Text('Keine Wiederholung'),
                ),
                DropdownMenuItem(value: 'daily', child: Text('Täglich')),
                DropdownMenuItem(value: 'weekly', child: Text('Wöchentlich')),
                DropdownMenuItem(value: 'monthly', child: Text('Monatlich')),
              ],
              onChanged: (v) => setState(() => _repeat = v ?? 'none'),
              decoration: const InputDecoration(labelText: 'Wiederholungsplan'),
            ),
            if (_repeat == 'weekly')
              DropdownButtonFormField<int>(
                value: _weeklyDay,
                items: _weeklyDays
                    .map(
                      (d) => DropdownMenuItem(value: d, child: Text('Tag $d')),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _weeklyDay = v),
                decoration: const InputDecoration(
                  labelText: 'Wochentag (1=Mo..7=So)',
                ),
              ),
            if (_repeat == 'monthly')
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Tag im Monat (1..31)',
                ),
                keyboardType: TextInputType.number,
                onChanged: (v) => _monthlyDay = int.tryParse(v),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _specialDatesCtrl,
              decoration: const InputDecoration(
                labelText: 'Sondertermine (YYYY-MM-DD, kommasepariert)',
              ),
            ),
            const SizedBox(height: 24),
            const Text('Medien & Reihenfolge'),
            const SizedBox(height: 8),
            Expanded(
              child: ReorderableListView.builder(
                itemCount: _items.length,
                onReorder: (oldIndex, newIndex) async {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final moved = _items.removeAt(oldIndex);
                  _items.insert(newIndex, moved);
                  setState(() {});
                  await _svc.setOrder(
                    widget.playlist.avatarId,
                    widget.playlist.id,
                    _items,
                  );
                },
                itemBuilder: (context, i) {
                  final it = _items[i];
                  final media = _mediaMap[it.mediaId];
                  return ListTile(
                    key: ValueKey(it.id),
                    leading: media == null
                        ? const Icon(Icons.broken_image)
                        : (media.type == AvatarMediaType.video
                              ? const Icon(Icons.videocam)
                              : const Icon(Icons.photo)),
                    title: Text(media?.url.split('/').last ?? it.mediaId),
                    trailing: const Icon(Icons.drag_handle),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
