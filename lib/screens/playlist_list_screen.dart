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
import '../theme/app_theme.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:crop_your_image/crop_your_image.dart' as cyi;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'dart:typed_data';

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
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          bool hasText = c.text.isNotEmpty;
          return AlertDialog(
            title: Text(context.read<LocalizationService>().t('playlists.new')),
            content: SizedBox(
              width: double.maxFinite,
              child: CustomTextField(
                label: 'Name der Playlist',
                controller: c,
                onChanged: (value) {
                  setState(() {
                    hasText = value.isNotEmpty;
                  });
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                child: Text(
                  context.read<LocalizationService>().t('buttons.cancel'),
                ),
              ),
              ElevatedButton(
                onPressed: hasText ? () => Navigator.pop(ctx, c.text) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.white,
                  shadowColor: Colors.transparent,
                  disabledBackgroundColor: Colors.white24,
                  disabledForegroundColor: Colors.white24,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (bounds) => LinearGradient(
                    colors: hasText
                        ? [AppColors.magenta, AppColors.lightBlue]
                        : [Colors.white24, Colors.white24],
                  ).createShader(bounds),
                  child: Text(
                    context.read<LocalizationService>().t('playlists.create'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
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

  void _openTimeline(Playlist p) async {
    await Navigator.pushNamed(context, '/playlist-timeline', arguments: p);
    _load(); // Reload list after timeline
  }

  Future<File?> _cropToPortrait916(File input) async {
    try {
      final bytes = await input.readAsBytes();
      final cropController = cyi.CropController();
      Uint8List? result;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          backgroundColor: Colors.black,
          clipBehavior: Clip.hardEdge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: LayoutBuilder(
            builder: (dCtx, _) {
              final sz = MediaQuery.of(dCtx).size;
              final double dlgW = (sz.width * 0.9).clamp(320.0, 900.0);
              final double dlgH = (sz.height * 0.9).clamp(480.0, 1200.0);
              return SizedBox(
                width: dlgW,
                height: dlgH,
                child: Column(
                  children: [
                    Expanded(
                      child: cyi.Crop(
                        controller: cropController,
                        image: bytes,
                        aspectRatio: 9 / 16,
                        withCircleUi: false,
                        baseColor: Colors.black,
                        maskColor: Colors.black38,
                        onCropped: (cropResult) {
                          if (cropResult is cyi.CropSuccess) {
                            result = cropResult.croppedImage;
                          }
                          Navigator.pop(ctx);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                result = null;
                                Navigator.pop(ctx);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Ink(
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade800,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  child: Center(
                                    child: Text(
                                      'Abbrechen',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                cropController.crop();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Ink(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFE91E63),
                                      AppColors.lightBlue,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  child: Center(
                                    child: Text(
                                      'Zuschneiden',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

      if (result == null) return null;
      final dir = await getTemporaryDirectory();
      final tmp = await File(
        '${dir.path}/crop_${DateTime.now().millisecondsSinceEpoch}.png',
      ).create(recursive: true);
      await tmp.writeAsBytes(result!, flush: true);
      return tmp;
    } catch (_) {
      return null;
    }
  }

  Future<void> _uploadCoverImage(Playlist playlist) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    File f = File(pickedFile.path);
    final originalFileName = p.basename(pickedFile.path);

    final cropped = await _cropToPortrait916(f);
    if (cropped == null) return;

    f = cropped;

    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance.ref().child(
        'avatars/${playlist.avatarId}/playlists/${playlist.id}/cover_$ts.jpg',
      );

      await ref.putFile(f);
      var url = await ref.getDownloadURL();
      url = '$url?v=$ts';

      // Update playlist
      final updated = Playlist(
        id: playlist.id,
        avatarId: playlist.avatarId,
        name: playlist.name,
        showAfterSec: playlist.showAfterSec,
        highlightTag: playlist.highlightTag,
        coverImageUrl: url,
        coverOriginalFileName: originalFileName,
        weeklySchedules: playlist.weeklySchedules,
        specialSchedules: playlist.specialSchedules,
        targeting: playlist.targeting,
        priority: playlist.priority,
        scheduleMode: playlist.scheduleMode,
        createdAt: playlist.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      await _svc.update(updated);
      await _load(); // Reload list

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Cover-Bild hochgeladen')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler beim Upload: $e')));
      }
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
          icon: const Icon(Icons.arrow_back, color: Colors.white),
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
                                                  style: TextButton.styleFrom(
                                                    foregroundColor:
                                                        Colors.white70,
                                                  ),
                                                  child: const Text(
                                                    'Abbrechen',
                                                  ),
                                                ),
                                                ElevatedButton(
                                                  onPressed: () =>
                                                      Navigator.pop(c2, true),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.white,
                                                    foregroundColor:
                                                        Colors.white,
                                                    shadowColor:
                                                        Colors.transparent,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 24,
                                                          vertical: 12,
                                                        ),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                  ),
                                                  child: ShaderMask(
                                                    shaderCallback: (bounds) =>
                                                        const LinearGradient(
                                                          colors: [
                                                            AppColors.magenta,
                                                            AppColors.lightBlue,
                                                          ],
                                                        ).createShader(bounds),
                                                    child: const Text(
                                                      'Löschen',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
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
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                        ),
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
            icon: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppColors.magenta, AppColors.lightBlue],
              ).createShader(bounds),
              child: const Icon(
                Icons.rule_folder_outlined,
                color: Colors.white,
                size: 21.4,
              ),
            ),
          ),
          IconButton(
            tooltip: loc.t('avatars.refreshTooltip'),
            onPressed: _load,
            icon: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppColors.magenta, AppColors.lightBlue],
              ).createShader(bounds),
              child: const Icon(
                Icons.refresh_outlined,
                color: Colors.white,
                size: 21.4,
              ),
            ),
          ),
          IconButton(
            tooltip: loc.t('playlists.new'),
            onPressed: _create,
            icon: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppColors.magenta, AppColors.lightBlue],
              ).createShader(bounds),
              child: const Icon(
                Icons.add_outlined,
                color: Colors.white,
                size: 21.4,
              ),
            ),
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
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minHeight: 178,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Cover Image mit Upload-Icon
                                      SizedBox(
                                        width: 100,
                                        height: 178,
                                        child: Stack(
                                          children: [
                                            // Cover Image
                                            Container(
                                              width: 100,
                                              height: 178,
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade800,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              clipBehavior: Clip.hardEdge,
                                              child: p.coverImageUrl != null
                                                  ? Image.network(
                                                      p.coverImageUrl!,
                                                      width: 100,
                                                      height: 178,
                                                      fit: BoxFit.cover,
                                                    )
                                                  : const Icon(
                                                      Icons.playlist_play,
                                                      size: 60,
                                                      color: Colors.white54,
                                                    ),
                                            ),
                                            // Upload-Icon (nur in list)
                                            Positioned(
                                              bottom: 4,
                                              right: 4,
                                              child: MouseRegion(
                                                cursor:
                                                    SystemMouseCursors.click,
                                                child: GestureDetector(
                                                  onTap: () =>
                                                      _uploadCoverImage(p),
                                                  child: Container(
                                                    width: 28,
                                                    height: 28,
                                                    decoration: BoxDecoration(
                                                      gradient:
                                                          const LinearGradient(
                                                            colors: [
                                                              AppColors.magenta,
                                                              AppColors
                                                                  .lightBlue,
                                                            ],
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            14,
                                                          ),
                                                    ),
                                                    child: const Icon(
                                                      Icons.file_upload,
                                                      color: Colors.white,
                                                      size: 16,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      // Content
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // Name (Vorgabe-Stil)
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
                                            const SizedBox(height: 8),
                                            _buildSafeSummary(p),
                                            const SizedBox(height: 12),
                                            // Zwei Buttons: Zeitplan & Timeline
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: ElevatedButton.icon(
                                                    onPressed: () =>
                                                        _openEdit(p),
                                                    icon: const Icon(
                                                      Icons.calendar_today,
                                                      size: 16,
                                                    ),
                                                    label: const Text(
                                                      'Zeitplan',
                                                    ),
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: Colors
                                                          .white
                                                          .withValues(
                                                            alpha: 0.1,
                                                          ),
                                                      foregroundColor:
                                                          Colors.white,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            vertical: 8,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: ElevatedButton.icon(
                                                    onPressed: () =>
                                                        _openTimeline(p),
                                                    icon: const Icon(
                                                      Icons.view_timeline,
                                                      size: 16,
                                                    ),
                                                    label: const Text(
                                                      'Timeline',
                                                    ),
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: Colors
                                                          .white
                                                          .withValues(
                                                            alpha: 0.1,
                                                          ),
                                                      foregroundColor:
                                                          Colors.white,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            vertical: 8,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
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
