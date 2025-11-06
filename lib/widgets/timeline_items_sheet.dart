import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/moments_service.dart';
import '../services/audio_cover_service.dart';
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
  int _userCredits = 0;

  // Confirm-Progress State
  bool _confirmProcessing = false;
  final Map<String, String> _confirmStatusById = <String, String>{}; // pending|running|done|error
  List<_TimelineVm> _confirmItems = <_TimelineVm>[];
  int _confirmDone = 0;
  int _confirmTotal = 0;

  bool _loading = true;
  String? _error;
  List<_TimelineVm> _items = <_TimelineVm>[];
  _TimelineFilter _filter = _TimelineFilter.free;
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadUserCredits();
  }

  // GMBC Spinner (Magenta → LightBlue → Cyan)
  Widget _gmbcSpinner({double size = 32, double strokeWidth = 3}) {
    return SizedBox(
      width: size,
      height: size,
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => const LinearGradient(
          colors: [Color(0xFFE91E63), AppColors.lightBlue, Color(0xFF00E5FF)],
          stops: [0.0, 0.5, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
        child: CircularProgressIndicator(
          strokeWidth: strokeWidth,
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  // Credits-Summe und Verfügbarkeit
  Widget _creditsSummary(List<_TimelineVm> selected, Map<String, bool> isCash) {
    final int needed = selected
        .where((vm) => (vm.media.price ?? 0.0) > 0.0 && isCash[vm.id] != true)
        .fold(0, (s, vm) => s + ((vm.media.price ?? 0.0) / 0.1).round());
    if (needed == 0) return const SizedBox.shrink();
    final bool enough = _userCredits >= needed;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Benötigt', style: TextStyle(color: Colors.white70)),
        Text(
          '$needed Credits',
          style: TextStyle(color: enough ? Colors.white : Colors.redAccent),
        ),
      ],
    );
  }

  bool _canConfirm(List<_TimelineVm> selected, Map<String, bool> isCash) {
    final int needed = selected
        .where((vm) => (vm.media.price ?? 0.0) > 0.0 && isCash[vm.id] != true)
        .fold(0, (s, vm) => s + ((vm.media.price ?? 0.0) / 0.1).round());
    return _userCredits >= needed;
  }

  Widget _buildProcessingList() {
    final double progress = _confirmTotal == 0 ? 0 : _confirmDone / _confirmTotal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
          child: Row(
            children: [
              _gmbcSpinner(size: 24, strokeWidth: 3),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Annahme läuft...', style: TextStyle(color: Colors.white)),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        color: AppColors.lightBlue,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('${(_confirmDone)}/${_confirmTotal}', style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _confirmItems.length,
            itemBuilder: (_, i) {
              final vm = _confirmItems[i];
              final st = _confirmStatusById[vm.id] ?? 'pending';
              Color border = Colors.white12;
              Widget trailing;
              if (st == 'running') {
                trailing = const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));
              } else if (st == 'done') {
                border = Colors.green.withOpacity(0.4);
                trailing = const Icon(Icons.check_circle, color: Colors.green);
              } else if (st == 'error') {
                border = Colors.red.withOpacity(0.4);
                trailing = const Icon(Icons.error, color: Colors.redAccent);
              } else {
                trailing = const Icon(Icons.more_horiz, color: Colors.white24);
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    _buildThumb(vm.media),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        vm.media.originalFileName ?? 'Media',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: st == 'done' ? Colors.green : Colors.white70),
                      ),
                    ),
                    const SizedBox(width: 8),
                    trailing,
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
  Future<void> _loadUserCredits() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final doc = await _fs.collection('users').doc(uid).get();
      final data = doc.data();
      if (data != null) {
        setState(() => _userCredits = (data['credits'] as int?) ?? 0);
      }
    } catch (_) {}
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

      // 6) Bereits vorhandene Moments (User) laden → nicht erneut anzeigen
      Set<String> existingUrls = <String>{};
      Set<String> existingNames = <String>{};
      Set<String> existingBaseNames = <String>{}; // fallback: Dateiname aus URL
      try {
        final moments = await MomentsService().listMoments();
        existingUrls = moments.map((m) => m.originalUrl).whereType<String>().toSet();
        existingNames = moments
            .map((m) => (m.originalFileName ?? '').trim().toLowerCase())
            .where((s) => s.isNotEmpty)
            .toSet();
        existingBaseNames = moments
            .map((m) {
              try {
                final u = Uri.parse(m.originalUrl);
                final seg = u.pathSegments.isNotEmpty ? u.pathSegments.last : '';
                return seg.toLowerCase();
              } catch (_) {
                return '';
              }
            })
            .where((s) => s.isNotEmpty)
            .toSet();
      } catch (_) {}

      // 7) Auflösen: assetId -> mediaId -> AvatarMedia
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
        AvatarMedia media = AvatarMedia.fromMap(map);
        if (confirmedIds.contains(media.id)) continue;
        // Filter: bereits in Moments vorhanden (nach URL oder Dateiname)
        final nameTrim = (media.originalFileName ?? '').trim().toLowerCase();
        String urlBase = '';
        try {
          final u = Uri.parse(media.url);
          urlBase = u.pathSegments.isNotEmpty ? u.pathSegments.last.toLowerCase() : '';
        } catch (_) {}
        if (existingUrls.contains(media.url) ||
            (nameTrim.isNotEmpty && existingNames.contains(nameTrim)) ||
            (urlBase.isNotEmpty && existingBaseNames.contains(urlBase))) {
          continue;
        }

        // Audio-Cover nachladen (wie im Chat)
        if (media.type == AvatarMediaType.audio) {
          try {
            final covers = await AudioCoverService().getCoverImages(
              avatarId: widget.avatarId,
              audioId: media.id,
              audioUrl: media.url,
            );
            if (covers.isNotEmpty) {
              media = AvatarMedia(
                id: media.id,
                avatarId: media.avatarId,
                type: media.type,
                url: media.url,
                thumbUrl: media.thumbUrl,
                createdAt: media.createdAt,
                durationMs: media.durationMs,
                aspectRatio: media.aspectRatio,
                tags: media.tags,
                originalFileName: media.originalFileName,
                isFree: media.isFree,
                price: media.price,
                currency: media.currency,
                platformFeePercent: media.platformFeePercent,
                voiceClone: media.voiceClone,
                coverImages: covers,
              );
            }
          } catch (_) {}
        }

        built.add(_TimelineVm(id: media.id, media: media, playlistId: item['playlistId'] as String?));
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

  

  Future<void> _confirmAndProcess(BuildContext ctx) async {
    final selectedItems = _filtered().where((e) => _selected.contains(e.id)).toList();
    if (selectedItems.isEmpty) return;

    // Default: Credits (kein Stripe), Cash nur wenn explizit umgeschaltet
    final Map<String, bool> isCash = {
      for (final vm in selectedItems) vm.id: false
    };

    double subtotalCash() => selectedItems
        .where((vm) => isCash[vm.id] == true)
        .fold(0.0, (s, vm) => s + (vm.media.price ?? 0.0));
    const double vatRate = 0.19; // MwSt
    double vatCash() => subtotalCash() * vatRate;
    double totalCash() => subtotalCash() + vatCash();

    await showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bCtx) {
        return StatefulBuilder(builder: (bCtx, setStateConfirm) {
          final cashItems = selectedItems.where((vm) => isCash[vm.id] == true).toList();
          final creditItems = selectedItems.where((vm) => isCash[vm.id] != true).toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(bCtx).size.height * 0.8,
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Bestätigung', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 8),

                  // Stripe (Cash) Zusammenfassung
                  if (cashItems.isNotEmpty) Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF222222),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Stripe (Kauf)', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Zwischensumme', style: TextStyle(color: Colors.white70)),
                              Text('${subtotalCash().toStringAsFixed(2)} €', style: const TextStyle(color: Colors.white)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('MwSt (19%)', style: TextStyle(color: Colors.white70)),
                              Text('${vatCash().toStringAsFixed(2)} €', style: const TextStyle(color: Colors.white)),
                            ],
                          ),
                          const Divider(height: 16, color: Colors.white12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Gesamt', style: TextStyle(color: Colors.white)),
                              Text('${totalCash().toStringAsFixed(2)} €', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (cashItems.isNotEmpty) const SizedBox(height: 12),
                  Expanded(
                    child: _confirmProcessing
                        ? _buildProcessingList()
                        : ListView(
                      children: [
                        // CASH-Liste
                        if (cashItems.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text('Kauf (Stripe)', style: TextStyle(color: Colors.white70)),
                                const SizedBox(height: 8),
                                ...cashItems.map((vm) => _buildConfirmRow(vm, isCash, setStateConfirm)),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),
                        // CREDITS-Liste
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('Credits (Konto: $_userCredits)', style: const TextStyle(color: Colors.white70)),
                              const SizedBox(height: 8),
                              _creditsSummary(selectedItems, isCash),
                              const SizedBox(height: 8),
                              if (creditItems.isEmpty)
                                const Text('Keine Items ausgewählt', style: TextStyle(color: Colors.white38))
                              else ...creditItems.map((vm) => _buildConfirmRow(vm, isCash, setStateConfirm)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Bottom-Bar
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    decoration: const BoxDecoration(color: Color(0xFF121212), boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 6)]),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(bCtx),
                          child: const Text('Abbrechen'),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: (selectedItems.isEmpty || !_canConfirm(selectedItems, isCash) || _confirmProcessing)
                              ? null
                              : () async {
                                  // Nur Credits/Free → zeige Fortschritt
                                  final onlyCreditsOrFree = !selectedItems.any((vm) => isCash[vm.id] == true);
                                  if (onlyCreditsOrFree) {
                                    _confirmProcessing = true;
                                    _confirmItems = List<_TimelineVm>.from(selectedItems);
                                    _confirmStatusById
                                      ..clear()
                                      ..addEntries(_confirmItems.map((e) => MapEntry(e.id, 'pending')));
                                    _confirmDone = 0;
                                    _confirmTotal = _confirmItems.length;
                                    setStateConfirm(() {});

                                    for (final vm in _confirmItems) {
                                      _confirmStatusById[vm.id] = 'running';
                                      setStateConfirm(() {});
                                      try {
                                        final price = vm.media.price ?? 0.0;
                                        final method = price <= 0.0 ? 'free' : 'credits';
                                        await MomentsService().saveMoment(media: vm.media, price: price, paymentMethod: method);
                                        await _removeById(vm.id);
                                        // bestätige im playlist-spezifischen Pfad (für Filter)
                                        try {
                                          final uid = FirebaseAuth.instance.currentUser?.uid;
                                          if (uid != null && vm.playlistId != null) {
                                            await _fs
                                                .collection('avatars')
                                                .doc(widget.avatarId)
                                                .collection('playlists')
                                                .doc(vm.playlistId)
                                                .collection('confirmedItems')
                                                .add({
                                              'userId': uid,
                                              'mediaId': vm.id,
                                              'confirmedAt': FieldValue.serverTimestamp(),
                                            });
                                          }
                                        } catch (_) {}
                                        _confirmStatusById[vm.id] = 'done';
                                      } catch (_) {
                                        _confirmStatusById[vm.id] = 'error';
                                      }
                                      _confirmDone += 1;
                                      setStateConfirm(() {});
                                    }

                                    if (mounted) setState(() {});
                                    if (mounted && Navigator.canPop(context)) {
                                      Navigator.of(context).pop();
                                    }
                                    _confirmProcessing = false;
                                    setStateConfirm(() {});
                                    return;
                                  }

                                  // Mit Cash → gleiches Verhalten wie zuvor
                                  for (final vm in List<_TimelineVm>.from(selectedItems.where((e) => isCash[e.id] != true))) {
                                    try {
                                      final price = vm.media.price ?? 0.0;
                                      final method = price <= 0.0 ? 'free' : 'credits';
                                      await MomentsService().saveMoment(media: vm.media, price: price, paymentMethod: method);
                                      await _removeById(vm.id);
                                      try {
                                        final uid = FirebaseAuth.instance.currentUser?.uid;
                                        if (uid != null && vm.playlistId != null) {
                                          await _fs
                                              .collection('avatars')
                                              .doc(widget.avatarId)
                                              .collection('playlists')
                                              .doc(vm.playlistId)
                                              .collection('confirmedItems')
                                              .add({
                                            'userId': uid,
                                            'mediaId': vm.id,
                                            'confirmedAt': FieldValue.serverTimestamp(),
                                          });
                                        }
                                      } catch (_) {}
                                    } catch (_) {}
                                  }
                                  for (final vm in List<_TimelineVm>.from(selectedItems.where((e) => isCash[e.id] == true))) {
                                    if (!mounted) break;
                                    await showDialog(
                                      context: context,
                                      builder: (_) => MediaPurchaseDialog(
                                        media: vm.media,
                                        onPurchaseSuccess: () async {
                                          await _removeById(vm.id);
                                          // playlist-confirmed auch bei Cash setzen
                                          try {
                                            final uid = FirebaseAuth.instance.currentUser?.uid;
                                            if (uid != null && vm.playlistId != null) {
                                              await _fs
                                                  .collection('avatars')
                                                  .doc(widget.avatarId)
                                                  .collection('playlists')
                                                  .doc(vm.playlistId)
                                                  .collection('confirmedItems')
                                                  .add({
                                                'userId': uid,
                                                'mediaId': vm.id,
                                                'confirmedAt': FieldValue.serverTimestamp(),
                                              });
                                            }
                                          } catch (_) {}
                                        },
                                      ),
                                    );
                                  }
                                  if (mounted) setState(() {});
                                  if (mounted && Navigator.canPop(context)) {
                                    Navigator.of(context).pop();
                                  }
                                },
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.lightBlue),
                          child: _confirmProcessing
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text(
                                  selectedItems.any((vm) => isCash[vm.id] == true)
                                      ? 'Kaufen'
                                      : 'Annehmen',
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Widget _buildConfirmRow(_TimelineVm vm, Map<String, bool> isCash, void Function(void Function()) setStateConfirm) {
    final price = vm.media.price ?? 0.0;
    final currency = vm.media.currency ?? '€';
    final canToggle = price > 0.0 && _userCredits > 0; // Gratis oder keine Credits → kein Toggle
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          _buildThumb(vm.media),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(vm.media.originalFileName ?? 'Media', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 2),
                Text(
                  price <= 0.0
                      ? 'Gratis'
                      : (isCash[vm.id] == true
                          ? '${price.toStringAsFixed(2)} $currency inkl. MwSt'
                          : '${price.toStringAsFixed(2)} $currency'),
                  style: const TextStyle(color: Colors.white60),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (price > 0.0)
            Row(
              children: [
                Text('Credits', style: TextStyle(color: Colors.white.withOpacity(canToggle ? 0.6 : 0.3))),
                const SizedBox(width: 6),
                Switch(
                  value: isCash[vm.id] == true,
                  onChanged: canToggle ? (v) => setStateConfirm(() => isCash[vm.id] = v) : null,
                  activeColor: AppColors.lightBlue,
                ),
                const SizedBox(width: 6),
                const Text('Cash', style: TextStyle(color: Colors.white70)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildThumb(AvatarMedia media) {
    String? url;
    if (media.coverImages != null && media.coverImages!.isNotEmpty) {
      url = media.coverImages!.first.thumbUrl.isNotEmpty == true
          ? media.coverImages!.first.thumbUrl
          : media.coverImages!.first.url;
    } else if (media.thumbUrl != null && media.thumbUrl!.isNotEmpty) {
      url = media.thumbUrl;
    } else if (media.type == AvatarMediaType.image) {
      url = media.url;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        color: Colors.black,
        width: 80,
        height: 80,
        child: (url != null && url.isNotEmpty)
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Icon(
                    media.type == AvatarMediaType.video
                        ? Icons.videocam
                        : (media.type == AvatarMediaType.audio
                            ? Icons.audiotrack
                            : (media.type == AvatarMediaType.document ? Icons.description : Icons.image)),
                    color: Colors.white38,
                    size: 28,
                  ),
                ),
              )
            : Center(
                child: Icon(
                  media.type == AvatarMediaType.video
                      ? Icons.videocam
                      : (media.type == AvatarMediaType.audio
                          ? Icons.audiotrack
                          : (media.type == AvatarMediaType.document ? Icons.description : Icons.image)),
                  color: Colors.white38,
                  size: 28,
                ),
              ),
      ),
    );
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
              Expanded(
                child: Center(
                  child: _gmbcSpinner(size: 42, strokeWidth: 3),
                ),
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
                          return InkWell(
                            onTap: () {
                              setState(() {
                                _selected.contains(vm.id) ? _selected.remove(vm.id) : _selected.add(vm.id);
                              });
                            },
                            child: Container(
                              height: 80,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: Row(
                                children: [
                                  _buildThumb(vm.media),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(vm.media.originalFileName ?? 'Media', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                                        const SizedBox(height: 4),
                                        Text(isFree ? 'Gratis' : '${(vm.media.price ?? 0).toStringAsFixed(2)} ${vm.media.currency ?? '€'}', style: const TextStyle(color: Colors.white60)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Checkbox(
                                    value: _selected.contains(vm.id),
                                    onChanged: (v) {
                                      setState(() {
                                        v == true ? _selected.add(vm.id) : _selected.remove(vm.id);
                                      });
                                    },
                                    activeColor: AppColors.lightBlue,
                                  ),
                                ],
                              ),
                            ),
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
  final String id; // mediaId
  final AvatarMedia media;
  final String? playlistId; // für confirmedItems Pfad
  _TimelineVm({required this.id, required this.media, this.playlistId});
}


