import 'package:flutter/material.dart';
import '../services/playlist_service.dart';
import '../models/playlist_models.dart';
import '../services/localization_service.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

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
    final result = await Navigator.pushNamed(
      context,
      '/playlist-edit',
      arguments: p,
    );
    if (result == true) {
      _load(); // Reload list after edit
    }
  }

  Widget _buildScheduleSummary(Playlist p) {
    if (p.weeklySchedules.isEmpty && p.specialSchedules.isEmpty) {
      return const Text(
        'Kein Zeitplan',
        style: TextStyle(fontSize: 11, color: Colors.grey),
      );
    }

    final weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    // Symbollisten nicht mehr genutzt; Anzeige erfolgt als zusammengefasste Zeitranges

    // Modus bestimmen: weekly oder special
    final mode = p.scheduleMode ?? 'weekly';
    final Map<int, List<int>> weekdaySlots = {};
    if (mode == 'weekly') {
      for (final ws in p.weeklySchedules) {
        weekdaySlots[ws.weekday] = ws.timeSlots.map((t) => t.index).toList();
      }
    } else {
      // Aggregiere SpecialSchedules zu Wochentagen (Infoansicht)
      for (final sp in p.specialSchedules) {
        final d = DateTime.fromMillisecondsSinceEpoch(sp.startDate);
        final wd = d.weekday;
        weekdaySlots.putIfAbsent(wd, () => []);
        for (final t in sp.timeSlots) {
          final idx = t.index;
          if (!weekdaySlots[wd]!.contains(idx)) {
            weekdaySlots[wd]!.add(idx);
          }
        }
      }
    }

    final dayWidgets = <Widget>[];

    String mergeSlotsLabel(List<int> slots) {
      if (slots.isEmpty) return '';
      if (slots.length == 6) return 'Ganztägig';
      // Circular merge über 6 Slots (0..5)
      final present = List<bool>.filled(6, false);
      for (final s in slots) {
        if (s >= 0 && s < 6) present[s] = true;
      }
      // finde Runs in zirkulärer Liste
      final rangesIdx = <List<int>>[];
      int i = 0;
      while (i < 6) {
        if (!present[i]) {
          i++;
          continue;
        }
        int start = i;
        int j = (i + 1) % 6;
        while (present[j] && j != start) {
          i = j;
          j = (j + 1) % 6;
          if (i == 5 && !present[0]) break; // Stop, wenn Wrap und 0 nicht aktiv
          if (!present[i]) break;
          if (!present[j]) break;
        }
        int end = i;
        rangesIdx.add([start, end]);
        i++;
        // Überspringe innerhalb des Runs
        while (i < 6 && present[i]) {
          i++;
        }
      }
      // Spezialfall: slots enthalten 5 und 0 → als ein zusammenhängender Run werten
      if (present[5] && present[0]) {
        // mergen: ersten und letzten Run zusammenführen
        if (rangesIdx.length >= 2) {
          final first = rangesIdx.first;
          final last = rangesIdx.last;
          rangesIdx
            ..clear()
            ..add([last[0], first[1]]);
        }
      }
      final startTimes = [3, 6, 11, 14, 18, 23];
      final endTimes = [6, 11, 14, 18, 23, 27];
      final out = rangesIdx.map((run) {
        int s = run[0];
        int e = run[1];
        int startHour = startTimes[s];
        int endHour = endTimes[e];
        if (e >= s) {
          // normaler Bereich
        } else {
          // Wrap: über Mitternacht – EndHour ggf. -24
          if (endHour >= 24) endHour -= 24;
        }
        if (endHour >= 24) endHour -= 24;
        return '$startHour–$endHour Uhr';
      }).toList();
      return out.join(', ');
    }

    // Erstelle Spalte für jeden Wochentag (1-7)
    for (int wd = 1; wd <= 7; wd++) {
      if (weekdaySlots.containsKey(wd)) {
        final ints = weekdaySlots[wd]!;
        final slotWidgets = <Widget>[
          Text(
            ints.length == 6 ? 'Ganztägig' : mergeSlotsLabel(List.from(ints)),
            style: const TextStyle(fontSize: 9, color: Colors.white70),
          ),
        ];

        dayWidgets.add(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                weekdays[wd - 1],
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              ...slotWidgets,
            ],
          ),
        );
      }
    }

    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: dayWidgets,
        ),
      ],
    );

    if ((p.scheduleMode ?? 'weekly') == 'special' &&
        p.specialSchedules.isNotEmpty) {
      final specials = List<SpecialSchedule>.from(p.specialSchedules)
        ..sort((a, b) => a.startDate.compareTo(b.startDate));
      final first = specials.first;
      final start = DateTime.fromMillisecondsSinceEpoch(first.startDate);
      final locale = Localizations.localeOf(context).toLanguageTag();
      final label = DateFormat('EEEE, d. MMM. y', locale).format(start);
      final ranges = mergeSlotsLabel(
        first.timeSlots.map((e) => e.index).toList(),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.amber,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            ranges,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
          const SizedBox(height: 6),
          // summary (Wochenübersicht) bewusst nicht erneut rendern
        ],
      );
    }

    return summary;
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
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.playlist_play,
                                          size: 60,
                                          color: Colors.white54,
                                        ),
                                      ),
                                const SizedBox(width: 16),
                                // Content
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.name,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      if (p.highlightTag != null) ...[
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.withOpacity(
                                              0.3,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: Colors.amber,
                                            ),
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
                                      const SizedBox(height: 8),
                                      Text(
                                        'Anzeigezeit: ${p.showAfterSec}s nach Chat-Beginn',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.white70,
                                        ),
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
