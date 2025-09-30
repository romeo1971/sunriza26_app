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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _mediaSvc.list(widget.avatarId);
    final pls = await _playlistSvc.list(widget.avatarId);
    setState(() {
      _items = list;
      _playlists = pls;
      _loading = false;
    });
  }

  Future<void> _pickImage() async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );
    if (x == null) return;
    final bytes = await x.readAsBytes();
    await _openCrop(bytes, p.extension(x.path));
  }

  Future<void> _openCrop(Uint8List imageBytes, String ext) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        content: SizedBox(
          width: 360,
          height: 520,
          child: Column(
            children: [
              Expanded(
                child: cyi.Crop(
                  controller: _cropCtrl,
                  image: imageBytes,
                  aspectRatio: 9 / 16,
                  withCircleUi: false,
                  onCropped: (croppedBytes) async {
                    if (!mounted) return;
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
                      // Löst das Cropping aus; Ergebnis kommt im onCropped-Callback oben
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

  Future<void> _pickVideo() async {
    final x = await _picker.pickVideo(source: ImageSource.gallery);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Medien-Galerie')),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            onPressed: _pickImage,
            child: const Icon(Icons.photo),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            onPressed: _pickVideo,
            child: const Icon(Icons.videocam),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final it = _items[i];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(it.url, fit: BoxFit.cover),
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
                          // Einfach ans Ende anhängen
                          final items = await _playlistSvc.listItems(
                            widget.avatarId,
                            pid,
                          );
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
                );
              },
            ),
    );
  }
}
