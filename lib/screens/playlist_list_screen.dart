import 'package:flutter/material.dart';
import '../services/playlist_service.dart';
import '../models/playlist_models.dart';
import '../services/localization_service.dart';
import 'package:provider/provider.dart';
// import 'package:intl/intl.dart'; // ungenutzt
// import '../utils/playlist_time_utils.dart'; // ungenutzt, durch Widget ausgelagert
import '../widgets/playlist_schedule_summary.dart';
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
import '../services/firebase_storage_service.dart';
import 'package:image/image.dart' as img;

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

  Future<void> _confirmDeletePlaylist(Playlist p) async {
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Playlist löschen?'),
        content: const Text(
          'Dieser Vorgang löscht die Playlist, alle zugehörigen Timeline-Einträge, Timeline-Assets und Scheduler-Einträge. Medien selbst werden nicht gelöscht. Fortfahren?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Ja, löschen'),
          ),
        ],
      ),
    );
    if (first != true) return;

    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wirklich endgültig löschen?'),
        content: const Text(
          'Letzte Bestätigung: Die Playlist und alle zugehörigen Verlinkungen werden entfernt. Dieser Schritt kann nicht rückgängig gemacht werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.white,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: ShaderMask(
              shaderCallback: (bounds) => Theme.of(
                context,
              ).extension<AppGradients>()!.magentaBlue.createShader(bounds),
              child: const Text(
                'Endgültig löschen',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (second != true) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _svc.deleteDeep(widget.avatarId, p.id);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Playlist gelöscht.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Lösch-Fehler: $e')));
    }
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
      if (!mounted) return null;
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

    // Loading-Dialog anzeigen
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // ERST: Altes Cover + ALLE Thumbnails löschen
      if (playlist.coverImageUrl != null &&
          playlist.coverImageUrl!.isNotEmpty) {
        try {
          await FirebaseStorageService.deleteFile(playlist.coverImageUrl!);
          debugPrint('Altes Cover gelöscht');
        } catch (_) {}
        // ALLE Thumbnails im thumbs-Ordner für diese Playlist löschen
        try {
          final thumbsPath =
              'avatars/${playlist.avatarId}/playlists/${playlist.id}/thumbs';
          debugPrint('Lösche ALLE Thumbnails in: $thumbsPath');
          final ref = FirebaseStorage.instance.ref().child(thumbsPath);
          final listResult = await ref.listAll();
          for (final item in listResult.items) {
            await item.delete();
            debugPrint('Thumbnail gelöscht: ${item.name}');
          }
        } catch (e) {
          debugPrint('Fehler beim Löschen der Thumbnails: $e');
        }
      }

      final ts = DateTime.now().millisecondsSinceEpoch;

      // Cover hochladen
      final ref = FirebaseStorage.instance.ref().child(
        'avatars/${playlist.avatarId}/playlists/${playlist.id}/cover_$ts.jpg',
      );
      await ref.putFile(f);
      final url = await ref.getDownloadURL();

      // Thumbnail erstellen und hochladen
      String? thumbUrl;
      try {
        final imgBytes = await f.readAsBytes();
        final decoded = img.decodeImage(imgBytes);
        if (decoded != null) {
          final resized = img.copyResize(decoded, width: 360);
          final jpg = img.encodeJpg(resized, quality: 70);
          final dir = await getTemporaryDirectory();
          final thumbFile = await File('${dir.path}/thumb_$ts.jpg').create();
          await thumbFile.writeAsBytes(jpg, flush: true);

          final thumbRef = FirebaseStorage.instance.ref().child(
            'avatars/${playlist.avatarId}/playlists/${playlist.id}/thumbs/cover_$ts.jpg',
          );
          await thumbRef.putFile(thumbFile);
          thumbUrl = await thumbRef.getDownloadURL();
          debugPrint('Cover-Thumbnail erstellt: $thumbUrl');
        }
      } catch (e) {
        debugPrint('Fehler bei Thumbnail-Erstellung: $e');
      }

      // Update playlist mit Cover + Thumbnail
      final updated = Playlist(
        id: playlist.id,
        avatarId: playlist.avatarId,
        name: playlist.name,
        showAfterSec: playlist.showAfterSec,
        highlightTag: playlist.highlightTag,
        coverImageUrl: url,
        coverThumbUrl: thumbUrl,
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

      // Loading-Dialog schließen
      if (mounted) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Cover-Bild hochgeladen')));
      }
    } catch (e) {
      // Loading-Dialog schließen
      if (mounted) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler beim Upload: $e')));
      }
    }
  }

  Future<void> _deleteCoverImage(Playlist playlist) async {
    // Bestätigung
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cover löschen?'),
        content: const Text('Soll das Cover-Bild gelöscht werden?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      // Cover aus Storage löschen
      if (playlist.coverImageUrl != null &&
          playlist.coverImageUrl!.isNotEmpty) {
        try {
          await FirebaseStorageService.deleteFile(playlist.coverImageUrl!);
          debugPrint('Cover gelöscht');
        } catch (_) {}
      }
      // ALLE Thumbnails aus thumbs-Ordner löschen
      try {
        final thumbsPath =
            'avatars/${playlist.avatarId}/playlists/${playlist.id}/thumbs';
        debugPrint('Lösche ALLE Thumbnails in: $thumbsPath');
        final ref = FirebaseStorage.instance.ref().child(thumbsPath);
        final listResult = await ref.listAll();
        for (final item in listResult.items) {
          await item.delete();
          debugPrint('Thumbnail gelöscht: ${item.name}');
        }
      } catch (e) {
        debugPrint('Fehler beim Löschen der Thumbnails: $e');
      }

      // Update playlist ohne Cover (zurück zu default)
      final updated = Playlist(
        id: playlist.id,
        avatarId: playlist.avatarId,
        name: playlist.name,
        showAfterSec: playlist.showAfterSec,
        highlightTag: playlist.highlightTag,
        coverImageUrl: null,
        coverThumbUrl: null,
        coverOriginalFileName: null,
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
        ).showSnackBar(const SnackBar(content: Text('Cover-Bild gelöscht')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler beim Löschen: $e')));
      }
    }
  }

  Widget _buildDeletePlaylistButton(Playlist p) {
    const Color baseTextColor = Colors.white54; // dezentes Hellgrau
    const Color baseBorderColor = Colors.white30; // sehr dezenter Rand
    const Color dangerColor = Colors.redAccent;
    return OutlinedButton(
      onPressed: () async {
        final first = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Playlist löschen?'),
            content: const Text(
              'Dieser Vorgang löscht die Playlist, alle zugehörigen Timeline-Einträge, Timeline-Assets und Scheduler-Einträge. Medien selbst werden nicht gelöscht. Fortfahren?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                child: const Text('Abbrechen'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                child: const Text('Ja, löschen'),
              ),
            ],
          ),
        );
        if (first != true) return;

        final second = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Wirklich endgültig löschen?'),
            content: const Text(
              'Letzte Bestätigung: Die Playlist und alle zugehörigen Verlinkungen werden entfernt. Dieser Schritt kann nicht rückgängig gemacht werden.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                child: const Text('Abbrechen'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.white,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: ShaderMask(
                  shaderCallback: (bounds) => Theme.of(
                    context,
                  ).extension<AppGradients>()!.magentaBlue.createShader(bounds),
                  child: const Text(
                    'Endgültig löschen',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
        if (second != true) return;

        final messenger = ScaffoldMessenger.of(context);
        try {
          await _svc.deleteDeep(widget.avatarId, p.id);
          if (!mounted) return;
          messenger.showSnackBar(
            const SnackBar(content: Text('Playlist gelöscht.')),
          );
          await _load();
        } catch (e) {
          if (!mounted) return;
          messenger.showSnackBar(SnackBar(content: Text('Lösch-Fehler: $e')));
        }
      },
      style: ButtonStyle(
        side: WidgetStateProperty.resolveWith<BorderSide>((states) {
          final isHover =
              states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed);
          return BorderSide(
            color: isHover ? dangerColor : baseBorderColor,
            width: 1,
          );
        }),
        foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          final isHover =
              states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed);
          return isHover ? dangerColor : baseTextColor;
        }),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(0, 24)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 9, fontWeight: FontWeight.w400),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      child: const Padding(
        padding: EdgeInsets.all(2),
        child: Text('Playlist löschen'),
      ),
    );
  }

  Widget _buildScheduleSummary(Playlist p) {
    return PlaylistScheduleSummary(playlist: p);
  }

  // Failsafe: Verhindert, dass UI crasht, falls die Zusammenfassung
  // in Edgecases (z. B. ungewöhnliche Slot-Kombinationen) wirft
  Widget _buildSafeSummary(Playlist p) {
    try {
      return _buildScheduleSummary(p);
    } catch (_) {
      return const Text(
        'Scheduler kann nicht angezeigt werden',
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
      final nav = Navigator.of(context);
      final avatarService = AvatarService();
      final avatar = await avatarService.getAvatar(widget.avatarId);
      if (!mounted) return;
      if (avatar != null) {
        nav.pushReplacementNamed('/avatar-details', arguments: avatar);
      } else {
        nav.pop();
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
              final messenger = ScaffoldMessenger.of(context);
              try {
                final issues = await _svc.validate(widget.avatarId);
                if (!mounted) return;
                if (issues.isEmpty) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Keine Probleme gefunden')),
                  );
                  return;
                }
                if (!context.mounted) return;
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
                                          final messenger =
                                              ScaffoldMessenger.of(context);
                                          final nav = Navigator.of(ctx);
                                          try {
                                            final res = await _svc.repair(
                                              widget.avatarId,
                                              docId,
                                            );
                                            if (!mounted) return;
                                            messenger.showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Repariert: ${res['status']}',
                                                ),
                                              ),
                                            );
                                            nav.pop();
                                            await _load();
                                          } catch (e) {
                                            if (!mounted) return;
                                            messenger.showSnackBar(
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
                                          final messenger =
                                              ScaffoldMessenger.of(context);
                                          final nav = Navigator.of(ctx);
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
                                              messenger.showSnackBar(
                                                const SnackBar(
                                                  content: Text('Gelöscht.'),
                                                ),
                                              );
                                              nav.pop();
                                              await _load();
                                            } catch (e) {
                                              if (!mounted) return;
                                              messenger.showSnackBar(
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
                messenger.showSnackBar(
                  SnackBar(content: Text('Diagnosefehler: $e')),
                );
              }
            },
            icon: Builder(
              builder: (context) {
                final grad = Theme.of(
                  context,
                ).extension<AppGradients>()?.magentaBlue;
                if (grad == null) {
                  return const Icon(
                    Icons.rule_folder_outlined,
                    color: Colors.white,
                    size: 21.4,
                  );
                }
                return ShaderMask(
                  shaderCallback: (bounds) => grad.createShader(bounds),
                  child: const Icon(
                    Icons.rule_folder_outlined,
                    color: Colors.white,
                    size: 21.4,
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: loc.t('avatars.refreshTooltip'),
            onPressed: _load,
            icon: Builder(
              builder: (context) {
                final grad = Theme.of(
                  context,
                ).extension<AppGradients>()?.magentaBlue;
                if (grad == null) {
                  return const Icon(
                    Icons.refresh_outlined,
                    color: Colors.white,
                    size: 21.4,
                  );
                }
                return ShaderMask(
                  shaderCallback: (bounds) => grad.createShader(bounds),
                  child: const Icon(
                    Icons.refresh_outlined,
                    color: Colors.white,
                    size: 21.4,
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: loc.t('playlists.new'),
            onPressed: _create,
            icon: Builder(
              builder: (context) {
                final grad = Theme.of(
                  context,
                ).extension<AppGradients>()?.magentaBlue;
                if (grad == null) {
                  return const Icon(
                    Icons.add_outlined,
                    color: Colors.white,
                    size: 21.4,
                  );
                }
                return ShaderMask(
                  shaderCallback: (bounds) => grad.createShader(bounds),
                  child: const Icon(
                    Icons.add_outlined,
                    color: Colors.white,
                    size: 21.4,
                  ),
                );
              },
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
                            separatorBuilder: (context, index) =>
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
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Titel + Anzeigezeit (volle Breite)
                                      SizedBox(
                                        width: double.infinity,
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
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Anzeigezeit: ${p.showAfterSec}s nach Chat-Start',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Linke Spalte: Bild
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
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
                                                        color: Colors
                                                            .grey
                                                            .shade800,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                      clipBehavior:
                                                          Clip.hardEdge,
                                                      child:
                                                          p.coverImageUrl !=
                                                              null
                                                          ? Image.network(
                                                              p.coverImageUrl!,
                                                              width: 100,
                                                              height: 178,
                                                              fit: BoxFit.cover,
                                                            )
                                                          : const Icon(
                                                              Icons
                                                                  .playlist_play,
                                                              size: 60,
                                                              color: Colors
                                                                  .white54,
                                                            ),
                                                    ),
                                                    // Upload-Icon (unten rechts)
                                                    Positioned(
                                                      bottom: 4,
                                                      right: 4,
                                                      child: MouseRegion(
                                                        cursor:
                                                            SystemMouseCursors
                                                                .click,
                                                        child: GestureDetector(
                                                          onTap: () =>
                                                              _uploadCoverImage(
                                                                p,
                                                              ),
                                                          child: Container(
                                                            width: 28,
                                                            height: 28,
                                                            decoration: BoxDecoration(
                                                              gradient: const LinearGradient(
                                                                colors: [
                                                                  AppColors
                                                                      .magenta,
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
                                                              color:
                                                                  Colors.white,
                                                              size: 16,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    // Kleines Trash-Icon nur anzeigen, wenn ein Cover existiert
                                                    if (p.coverImageUrl !=
                                                            null &&
                                                        p
                                                            .coverImageUrl!
                                                            .isNotEmpty)
                                                      Positioned(
                                                        left: 4,
                                                        bottom: 4,
                                                        child: Container(
                                                          width: 28,
                                                          height: 28,
                                                          decoration:
                                                              const BoxDecoration(
                                                                color: Color(
                                                                  0x40000000,
                                                                ), // #00000040
                                                                shape: BoxShape
                                                                    .circle,
                                                              ),
                                                          child: IconButton(
                                                            tooltip:
                                                                'Cover löschen',
                                                            padding:
                                                                EdgeInsets.zero,
                                                            constraints:
                                                                const BoxConstraints(),
                                                            icon: const Icon(
                                                              Icons
                                                                  .delete_outline,
                                                              size: 16,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                            onPressed: () =>
                                                                _deleteCoverImage(
                                                                  p,
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                                    // Großer "Playlist löschen"-Chip oben links im Bild
                                                    Positioned(
                                                      left: 6,
                                                      top: 6,
                                                      child: OutlinedButton(
                                                        onPressed: () =>
                                                            _confirmDeletePlaylist(
                                                              p,
                                                            ),
                                                        style: OutlinedButton.styleFrom(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 6,
                                                                vertical: 2,
                                                              ),
                                                          side:
                                                              const BorderSide(
                                                                color: Colors
                                                                    .white70,
                                                                width: 1,
                                                              ),
                                                          foregroundColor:
                                                              Colors.white,
                                                          backgroundColor:
                                                              const Color(
                                                                0x55000000,
                                                              ),
                                                          textStyle:
                                                              const TextStyle(
                                                                fontSize: 10,
                                                              ),
                                                          minimumSize:
                                                              const Size(0, 0),
                                                          tapTargetSize:
                                                              MaterialTapTargetSize
                                                                  .shrinkWrap,
                                                        ),
                                                        child: const Text(
                                                          'Playlist löschen',
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                            ],
                                          ),
                                          const SizedBox(width: 16),
                                          // Rechte Spalte: Wochentage + kleine Buttons
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
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
                                                          .withValues(
                                                            alpha: 0.3,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
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
                                                const SizedBox(height: 4),
                                                _buildSafeSummary(p),
                                                const SizedBox(height: 8),
                                                LayoutBuilder(
                                                  builder: (context, constraints) {
                                                    final isNarrow =
                                                        constraints.maxWidth <
                                                        240;
                                                    final buttons = [
                                                      SizedBox(
                                                        height: 24,
                                                        child: ElevatedButton(
                                                          onPressed: () =>
                                                              _openEdit(p),
                                                          style: ElevatedButton.styleFrom(
                                                            backgroundColor:
                                                                Colors.white,
                                                            foregroundColor:
                                                                AppColors
                                                                    .magenta,
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      12,
                                                                  vertical: 10,
                                                                ),
                                                            shape: RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    12,
                                                                  ),
                                                            ),
                                                            minimumSize:
                                                                const Size(
                                                                  0,
                                                                  24,
                                                                ),
                                                          ),
                                                          child: ShaderMask(
                                                            blendMode:
                                                                BlendMode.srcIn,
                                                            shaderCallback: (b) =>
                                                                const LinearGradient(
                                                                  colors: [
                                                                    AppColors
                                                                        .magenta,
                                                                    AppColors
                                                                        .lightBlue,
                                                                  ],
                                                                  begin: Alignment
                                                                      .topLeft,
                                                                  end: Alignment
                                                                      .bottomRight,
                                                                ).createShader(
                                                                  b,
                                                                ),
                                                            child: const Text(
                                                              'Scheduler',
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                fontSize: 14,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        height: 24,
                                                        child: ElevatedButton(
                                                          onPressed: () =>
                                                              _openTimeline(p),
                                                          style: ElevatedButton.styleFrom(
                                                            backgroundColor:
                                                                Colors.white,
                                                            foregroundColor:
                                                                AppColors
                                                                    .magenta,
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      12,
                                                                  vertical: 10,
                                                                ),
                                                            shape: RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    12,
                                                                  ),
                                                            ),
                                                            minimumSize:
                                                                const Size(
                                                                  0,
                                                                  24,
                                                                ),
                                                          ),
                                                          child: ShaderMask(
                                                            blendMode:
                                                                BlendMode.srcIn,
                                                            shaderCallback: (b) =>
                                                                const LinearGradient(
                                                                  colors: [
                                                                    AppColors
                                                                        .magenta,
                                                                    AppColors
                                                                        .lightBlue,
                                                                  ],
                                                                  begin: Alignment
                                                                      .topLeft,
                                                                  end: Alignment
                                                                      .bottomRight,
                                                                ).createShader(
                                                                  b,
                                                                ),
                                                            child: const Text(
                                                              'Timeline',
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                fontSize: 14,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ];
                                                    return isNarrow
                                                        ? Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              buttons[0],
                                                              const SizedBox(
                                                                height: 6,
                                                              ),
                                                              buttons[1],
                                                            ],
                                                          )
                                                        : Row(
                                                            children: [
                                                              buttons[0],
                                                              const SizedBox(
                                                                width: 8,
                                                              ),
                                                              buttons[1],
                                                            ],
                                                          );
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
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
