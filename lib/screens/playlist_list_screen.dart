import 'package:flutter/material.dart';
import '../services/playlist_service.dart';
import '../models/playlist_models.dart';
import '../services/localization_service.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../utils/playlist_time_utils.dart';
import '../widgets/avatar_bottom_nav_bar.dart';
import '../services/avatar_service.dart';
import '../widgets/custom_text_field.dart';

class PlaylistListScreen extends StatefulWidget {
  final String avatarId;
  final String? fromScreen; // 'avatar-list' oder null
  const PlaylistListScreen({
    super.key,
    required this.avatarId,
    this.fromScreen,
  });

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
    // Lade erst nach dem ersten Frame, damit die Seite sicher rendert
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
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
        content: CustomTextField(
          label: context.read<LocalizationService>().t('common.name'),
          controller: c,
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
        // Guard: ungültige Epochenwerte abfangen
        DateTime d;
        try {
          d = DateTime.fromMillisecondsSinceEpoch(sp.startDate);
        } catch (_) {
          continue; // überspringen
        }
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

    String mergeSlotsLabel(List<int> slots) => buildSlotSummaryLabel(slots);

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
      // Guard: ungültige Epochenwerte abfangen
      DateTime? start;
      try {
        start = DateTime.fromMillisecondsSinceEpoch(first.startDate);
      } catch (_) {
        start = null;
      }
      final locale = Localizations.localeOf(context).toLanguageTag();
      final label = start != null
          ? DateFormat('EEEE, d. MMM. y', locale).format(start)
          : 'Sondertermin';
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

  // Failsafe: Verhindert, dass UI crasht, falls die Zusammenfassung
  // in Edgecases (z. B. ungewöhnliche Slot-Kombinationen) wirft
  Widget _buildSafeSummary(Playlist p) {
    try {
      return _buildScheduleSummary(p);
    } catch (_) {
      return const Text(
        'Zeitplan kann nicht angezeigt werden',
        style: TextStyle(fontSize: 11, color: Colors.amber),
      );
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
    final loc = context.read<LocalizationService>();
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.t('playlists.title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _handleBackNavigation(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Diagnose',
            onPressed: () async {
              try {
                final issues = await _svc.validate(widget.avatarId);
                if (!mounted) return;
                if (issues.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Keine Probleme gefunden')),
                  );
                  return;
                }
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Playlist-Diagnose'),
                    content: SizedBox(
                      width: 480,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: issues.map((e) {
                            final id = e['id'];
                            final docId = e['docId'] ?? id;
                            final List problems =
                                (e['problems'] as List?) ?? [];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ID: $id',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'Doc: $docId',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white70,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  ...problems
                                      .map((p) => Text('• $p'))
                                      .cast<Widget>(),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: () async {
                                          try {
                                            final res = await _svc.repair(
                                              widget.avatarId,
                                              docId,
                                            );
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Repariert: ${res['status']}',
                                                ),
                                              ),
                                            );
                                            Navigator.pop(ctx);
                                            await _load();
                                          } catch (e) {
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Repair-Fehler: $e',
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                        icon: const Icon(Icons.build),
                                        label: const Text('Fixen'),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton.icon(
                                        onPressed: () async {
                                          final confirm = await showDialog<bool>(
                                            context: context,
                                            builder: (c2) => AlertDialog(
                                              title: const Text(
                                                'Löschen bestätigen',
                                              ),
                                              content: Text(
                                                'Playlist "$id" wirklich löschen?',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(c2, false),
                                                  child: const Text(
                                                    'Abbrechen',
                                                  ),
                                                ),
                                                ElevatedButton(
                                                  onPressed: () =>
                                                      Navigator.pop(c2, true),
                                                  child: const Text('Löschen'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirm == true) {
                                            try {
                                              await _svc.delete(
                                                widget.avatarId,
                                                docId,
                                              );
                                              if (!mounted) return;
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Gelöscht.'),
                                                ),
                                              );
                                              Navigator.pop(ctx);
                                              await _load();
                                            } catch (e) {
                                              if (!mounted) return;
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Lösch-Fehler: $e',
                                                  ),
                                                ),
                                              );
                                            }
                                          }
                                        },
                                        icon: const Icon(Icons.delete_outline),
                                        label: const Text('Löschen'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Schließen'),
                      ),
                    ],
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Diagnosefehler: $e')));
              }
            },
            icon: const Icon(Icons.rule_folder),
          ),
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
          : Column(
              children: [
                // Bottom-Navigation aktiv – keine Top-Nav mehr
                const SizedBox.shrink(),
                Expanded(
                  child: RefreshIndicator(
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
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final p = _items[i];
                              return InkWell(
                                onTap: () => _openEdit(p),
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Cover Image
                                      p.coverImageUrl != null
                                          ? ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
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
                                                borderRadius:
                                                    BorderRadius.circular(8),
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
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.amber
                                                      .withOpacity(0.3),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
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
                                            _buildSafeSummary(p),
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
                ),
              ],
            ),
      bottomNavigationBar: AvatarBottomNavBar(
        avatarId: widget.avatarId,
        currentScreen: 'playlists',
      ),
    );
  }
}
