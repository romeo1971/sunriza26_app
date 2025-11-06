import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/moments_service.dart';
import '../models/media_models.dart';
import '../theme/app_theme.dart';
import 'media_purchase_dialog.dart';

enum _TimelineFilter { free, paid }

class TimelineItemsSheet extends StatefulWidget {
  final String avatarId;
  const TimelineItemsSheet({super.key, required this.avatarId});

  @override
  State<TimelineItemsSheet> createState() => _TimelineItemsSheetState();
}

class _TimelineItemsSheetState extends State<TimelineItemsSheet> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  bool _loading = true;
  String? _error;
  List<_TimelineVm> _items = <_TimelineVm>[];
  _TimelineFilter _filter = _TimelineFilter.free;
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
      _items = <_TimelineVm>[];
      _selected.clear();
      _filter = _TimelineFilter.free;
    });
    try {
      final now = DateTime.now();
      final weekday = now.weekday; // 1=Mo..7=So

      // 1) Alle Playlists holen
      final playlistsSnap = await _fs
          .collection('avatars')
          .doc(widget.avatarId)
          .collection('playlists')
          .get();

      // 2) Filter: weeklySchedules enthält heutigen Wochentag
      final List<String> activePlaylistIds = [];
      for (final d in playlistsSnap.docs) {
        final m = d.data();
        final weekly = m['weeklySchedules'] as List?;
        if (weekly == null) continue;
        bool isActiveToday = false;
        for (final s in weekly) {
          if (s is Map && (s['weekday'] as int?) == weekday) { isActiveToday = true; break; }
        }
        if (isActiveToday) activePlaylistIds.add(d.id);
      }

      if (activePlaylistIds.isEmpty) {
        setState(() { _loading = false; _items = <_TimelineVm>[]; });
        return;
      }

      // 3) Sammle timelineItems (aktiv) aus allen aktiven Playlists
      final List<Map<String, dynamic>> allItems = [];
      for (final pid in activePlaylistIds) {
        final itemsSnap = await _fs
            .collection('avatars')
            .doc(widget.avatarId)
            .collection('playlists')
            .doc(pid)
            .collection('timelineItems')
            .orderBy('order')
            .get();
        for (final it in itemsSnap.docs) {
          final m = it.data();
          final isActive = (m['activity'] as bool?) ?? true;
          if (!isActive) continue;
          m['id'] = it.id;
          m['playlistId'] = pid;
          allItems.add(m);
        }
      }

      if (allItems.isEmpty) { setState(() { _loading = false; }); return; }

      // 4) Sortieren nach order
      allItems.sort((a, b) => (a['order'] as int? ?? 0).compareTo(b['order'] as int? ?? 0));

      // 5) Confirmed-Set für aktuellen Nutzer
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final confirmedIds = <String>{};
      if (uid != null) {
        for (final pid in activePlaylistIds) {
          try {
            final confSnap = await _fs
                .collection('avatars')
                .doc(widget.avatarId)
                .collection('playlists')
                .doc(pid)
                .collection('confirmedItems')
                .where('userId', isEqualTo: uid)
                .get();
            for (final d in confSnap.docs) {
              final mid = d.data()['mediaId'] as String?;
              if (mid != null && mid.isNotEmpty) confirmedIds.add(mid);
            }
          } catch (_) {}
        }
      }

      // 6) Auflösen: assetId -> mediaId -> AvatarMedia
      final List<_TimelineVm> built = <_TimelineVm>[];
      for (final item in allItems) {
        final assetId = item['assetId'] as String?;
        if (assetId == null) continue;

        // asset -> mediaId
        String mediaId = assetId;
        try {
          final assetSnap = await _fs
              .collection('avatars')
              .doc(widget.avatarId)
              .collection('playlists')
              .doc(item['playlistId'] as String)
              .collection('timelineAssets')
              .doc(assetId)
              .get();
          final asset = assetSnap.data();
          final mid = asset != null ? (asset['mediaId'] as String?) : null;
          if (mid != null && mid.isNotEmpty) mediaId = mid;
        } catch (_) {}

        // media laden
        Map<String, dynamic>? data;
        for (final col in const ['images', 'videos', 'audios', 'documents']) {
          final snap = await _fs
              .collection('avatars')
              .doc(widget.avatarId)
              .collection(col)
              .doc(mediaId)
              .get();
          if (snap.exists) { data = snap.data(); break; }
        }
        if (data == null) continue;

        final map = {'id': mediaId, ...data};
        final media = AvatarMedia.fromMap(map);
        if (confirmedIds.contains(media.id)) continue;

        built.add(_TimelineVm(id: media.id, media: media));
      }

      setState(() { _items = built; _loading = false; });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Fehler beim Laden';
      });
    }
  }

  List<_TimelineVm> _filtered() {
    return _items.where((e) {
      final isFree = (e.media.price ?? 0.0) <= 0.0;
      return _filter == _TimelineFilter.free ? isFree : !isFree;
    }).toList();
  }

  Future<void> _removeById(String id) async {
    setState(() {
      _items.removeWhere((e) => e.id == id);
      _selected.remove(id);
    });
  }

  IconData _iconFor(AvatarMediaType t) {
    switch (t) {
      case AvatarMediaType.image:
        return Icons.image;
      case AvatarMediaType.video:
        return Icons.videocam;
      case AvatarMediaType.audio:
        return Icons.audiotrack;
      case AvatarMediaType.document:
        return Icons.description;
    }
  }

  Future<void> _confirmAndProcess(BuildContext ctx) async {
    final selectedItems = _filtered().where((e) => _selected.contains(e.id)).toList();
    if (selectedItems.isEmpty) return;

    final Set<String> tempSel = Set.of(_selected);
    await showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          _filter == _TimelineFilter.free ? 'Annehmen bestätigen' : 'Kauf bestätigen',
          style: const TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 260,
                child: ListView.builder(
                  itemCount: selectedItems.length,
                  itemBuilder: (_, i) {
                    final vm = selectedItems[i];
                    final isChecked = tempSel.contains(vm.id);
                    return CheckboxListTile(
                      value: isChecked,
                      onChanged: (v) {
                        (v == true) ? tempSel.add(vm.id) : tempSel.remove(vm.id);
                        (dCtx as Element).markNeedsBuild();
                      },
                      activeColor: AppColors.lightBlue,
                      title: Text(vm.media.originalFileName ?? 'Media', style: const TextStyle(color: Colors.white)),
                      subtitle: Text(
                        (vm.media.price ?? 0.0) <= 0.0
                            ? 'Gratis'
                            : '${(vm.media.price ?? 0).toStringAsFixed(2)} ${vm.media.currency ?? '€'}',
                        style: const TextStyle(color: Colors.white54),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Zurück'),
          ),
          TextButton(
            onPressed: () {
              _selected
                ..clear()
                ..addAll(tempSel);
              Navigator.pop(dCtx);
            },
            child: const Text('Bestätigen'),
          ),
        ],
      ),
    );

    final toProcess = _filtered().where((e) => _selected.contains(e.id)).toList();
    if (toProcess.isEmpty) return;

    if (_filter == _TimelineFilter.free) {
      for (final vm in toProcess) {
        try {
          await MomentsService().saveMoment(
            media: vm.media,
            price: 0.0,
            paymentMethod: 'free',
          );
          await _removeById(vm.id);
        } catch (_) {}
      }
      setState(() {});
      return;
    }

    for (final vm in toProcess) {
      if (!Navigator.of(ctx).mounted) break;
      await showDialog(
        context: ctx,
        builder: (_) => MediaPurchaseDialog(
          media: vm.media,
          onPurchaseSuccess: () async {
            await _removeById(vm.id);
          },
        ),
      );
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            const Text('Aktuelle Timeline', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            // Content area: loading, error, empty, list
            if (_loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Text(_error!, style: const TextStyle(color: Colors.white70)),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: const Text('Kostenlos'),
                              selected: _filter == _TimelineFilter.free,
                              onSelected: (_) {
                                setState(() {
                                  _filter = _TimelineFilter.free;
                                  _selected.clear();
                                });
                              },
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('Kostenpflichtig'),
                              selected: _filter == _TimelineFilter.paid,
                              onSelected: (_) {
                                setState(() {
                                  _filter = _TimelineFilter.paid;
                                  _selected.clear();
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        final list = _filtered();
                        if (list.isEmpty) return;
                        final allSelected = list.every((e) => _selected.contains(e.id));
                        setState(() {
                          if (allSelected) {
                            for (final e in list) {
                              _selected.remove(e.id);
                            }
                          } else {
                            for (final e in list) {
                              _selected.add(e.id);
                            }
                          }
                        });
                      },
                      child: const Text('Alle'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _filtered().isEmpty
                    ? const Center(child: Text('Keine Items (bereits gekauft?)', style: TextStyle(color: Colors.white60)))
                    : ListView.separated(
                        itemCount: _filtered().length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
                        itemBuilder: (_, i) {
                          final vm = _filtered()[i];
                          final isFree = (vm.media.price ?? 0.0) <= 0.0;
                          return ListTile(
                            leading: Checkbox(
                              value: _selected.contains(vm.id),
                              onChanged: (v) {
                                setState(() {
                                  v == true ? _selected.add(vm.id) : _selected.remove(vm.id);
                                });
                              },
                              activeColor: AppColors.lightBlue,
                            ),
                            title: Row(
                              children: [
                                Icon(_iconFor(vm.media.type), color: Colors.white70, size: 18),
                                const SizedBox(width: 8),
                                Expanded(child: Text(vm.media.originalFileName ?? 'Media', style: const TextStyle(color: Colors.white))),
                              ],
                            ),
                            subtitle: Text(
                              isFree
                                  ? 'Gratis'
                                  : '${(vm.media.price ?? 0).toStringAsFixed(2)} ${vm.media.currency ?? '€'}',
                              style: const TextStyle(color: Colors.white60),
                            ),
                            trailing: const SizedBox.shrink(),
                          );
                        },
                      ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                decoration: const BoxDecoration(color: Color(0xFF121212), boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 6)]),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_selected.length} ausgewählt',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _selected.isEmpty ? null : () => _confirmAndProcess(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _filter == _TimelineFilter.free ? Colors.green : AppColors.lightBlue,
                      ),
                      child: Text(_filter == _TimelineFilter.free ? 'Annehmen' : 'Kaufen'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimelineVm {
  final String id;
  final AvatarMedia media;
  _TimelineVm({required this.id, required this.media});
}


