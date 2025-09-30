import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:crop_your_image/crop_your_image.dart' as cyi;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../services/media_service.dart';
import '../services/firebase_storage_service.dart';
import '../models/media_models.dart';
import '../services/playlist_service.dart';
import '../models/playlist_models.dart';
import '../services/localization_service.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

class MediaGalleryScreen extends StatefulWidget {
  final String avatarId;
  const MediaGalleryScreen({super.key, required this.avatarId});

  @override
  State<MediaGalleryScreen> createState() => _MediaGalleryScreenState();
}

class _MediaGalleryScreenState extends State<MediaGalleryScreen> {
  final _mediaSvc = MediaService();
  final _picker = ImagePicker();
  final _cropCtrl = cyi.CropController();
  final _playlistSvc = PlaylistService();

  List<AvatarMedia> _items = [];
  List<Playlist> _playlists = [];
  bool _loading = true;
  double _cropAspect = 9 / 16; // 9:16 standard

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _mediaSvc.list(widget.avatarId);
      final pls = await _playlistSvc.list(widget.avatarId);
      if (!mounted) return;
      setState(() {
        _items = list;
        _playlists = pls;
      });
    } catch (e) {
      if (!mounted) return;
      final loc = context.read<LocalizationService>();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            loc.t('avatars.details.error', params: {'msg': e.toString()}),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickImageFrom(ImageSource source) async {
    final x = await _picker.pickImage(source: source, imageQuality: 95);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    await _openCrop(bytes, p.extension(x.path));
  }

  Future<void> _openCrop(Uint8List imageBytes, String ext) async {
    await showDialog(
      context: context,
      builder: (ctx) {
        double aspect = _cropAspect;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            contentPadding: EdgeInsets.zero,
            content: SizedBox(
              width: 380,
              height: 560,
              child: Column(
                children: [
                  // Aspect switcher
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.crop, color: Colors.white70),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('9:16'),
                          selected: aspect == 9 / 16,
                          onSelected: (_) => setLocal(() => aspect = 9 / 16),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('16:9'),
                          selected: aspect == 16 / 9,
                          onSelected: (_) => setLocal(() => aspect = 16 / 9),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: cyi.Crop(
                      controller: _cropCtrl,
                      image: imageBytes,
                      aspectRatio: aspect,
                      withCircleUi: false,
                      onCropped: (croppedBytes) async {
                        if (!mounted) return;
                        _cropAspect = aspect;
                        Navigator.of(context).pop();
                        await _uploadImage(croppedBytes, ext);
                      },
                    ),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Abbrechen'),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () {
                          _cropCtrl.crop();
                        },
                        child: const Text('Zuschneiden'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _uploadImage(Uint8List bytes, String ext) async {
    // Bewährter Weg wie in avatar_details_screen: Bytes → Temp-Datei → uploadImage(File)
    final dir = await getTemporaryDirectory();
    final path = p.join(
      dir.path,
      'crop_${DateTime.now().millisecondsSinceEpoch}${ext.isNotEmpty ? ext : '.jpg'}',
    );
    final f = File(path);
    await f.writeAsBytes(bytes, flush: true);
    final url = await FirebaseStorageService.uploadImage(
      f,
      customPath:
          'avatars/${widget.avatarId}/gallery/${DateTime.now().millisecondsSinceEpoch}${ext.isNotEmpty ? ext : '.jpg'}',
    );
    if (url == null) return;
    final m = AvatarMedia(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      avatarId: widget.avatarId,
      type: AvatarMediaType.image,
      url: url,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _mediaSvc.add(widget.avatarId, m);
    await _load();
  }

  Future<void> _pickVideoFrom(ImageSource source) async {
    final x = await _picker.pickVideo(source: source);
    if (x == null) return;
    final url = await FirebaseStorageService.uploadVideo(
      File(x.path),
      customPath:
          'avatars/${widget.avatarId}/gallery/${DateTime.now().millisecondsSinceEpoch}.mp4',
    );
    if (url == null) return;
    final m = AvatarMedia(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      avatarId: widget.avatarId,
      type: AvatarMediaType.video,
      url: url,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _mediaSvc.add(widget.avatarId, m);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.read<LocalizationService>();
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.t('gallery.title')),
        actions: [
          IconButton(
            tooltip: loc.t('avatars.refreshTooltip'),
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: loc.t('gallery.tooltip.photo'),
            icon: const Icon(Icons.photo),
            onSelected: (v) {
              if (v == 'gallery') _pickImageFrom(ImageSource.gallery);
              if (v == 'camera') _pickImageFrom(ImageSource.camera);
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'gallery',
                child: Text(loc.t('gallery.source.gallery')),
              ),
              PopupMenuItem(
                value: 'camera',
                child: Text(loc.t('gallery.source.camera')),
              ),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: loc.t('gallery.tooltip.video'),
            icon: const Icon(Icons.videocam),
            onSelected: (v) {
              if (v == 'gallery') _pickVideoFrom(ImageSource.gallery);
              if (v == 'camera') _pickVideoFrom(ImageSource.camera);
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'gallery',
                child: Text(loc.t('gallery.source.gallery')),
              ),
              PopupMenuItem(
                value: 'camera',
                child: Text(loc.t('gallery.source.camera')),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, color: Colors.white70),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            loc.t('avatars.details.mediaHint'),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Center(
                        child: Text(
                          loc.t('avatars.details.noImageFound'),
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                            ),
                        itemCount: _items.length,
                        itemBuilder: (context, i) {
                          final it = _items[i];
                          return GestureDetector(
                            onTap: () => _openViewer(it),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    it.url,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  left: 6,
                                  top: 6,
                                  child: PopupMenuButton<String>(
                                    icon: const Icon(
                                      Icons.playlist_add,
                                      color: Colors.white,
                                    ),
                                    onSelected: (pid) async {
                                      final items = await _playlistSvc
                                          .listItems(widget.avatarId, pid);
                                      await _playlistSvc.addItem(
                                        widget.avatarId,
                                        pid,
                                        it.id,
                                        order: items.length,
                                      );
                                    },
                                    itemBuilder: (ctx) => _playlists
                                        .map(
                                          (p) => PopupMenuItem<String>(
                                            value: p.id,
                                            child: Text(p.name),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                                if (it.type == AvatarMediaType.video)
                                  const Positioned(
                                    right: 6,
                                    bottom: 6,
                                    child: Icon(
                                      Icons.play_circle_filled,
                                      color: Colors.white,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Future<void> _openViewer(AvatarMedia media) async {
    if (media.type == AvatarMediaType.image) {
      await showDialog(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: InteractiveViewer(
            child: Image.network(media.url, fit: BoxFit.contain),
          ),
        ),
      );
    } else {
      // Video
      await showDialog(
        context: context,
        builder: (_) => _VideoDialog(url: media.url),
      );
    }
  }
}

class _VideoDialog extends StatefulWidget {
  final String url;
  const _VideoDialog({required this.url});
  @override
  State<_VideoDialog> createState() => _VideoDialogState();
}

class _VideoDialogState extends State<_VideoDialog> {
  late VideoPlayerController _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _ctrl.play();
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: AspectRatio(
        aspectRatio: _ready ? _ctrl.value.aspectRatio : 16 / 9,
        child: _ready
            ? Stack(
                children: [
                  VideoPlayer(_ctrl),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: VideoProgressIndicator(_ctrl, allowScrubbing: true),
                  ),
                ],
              )
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
