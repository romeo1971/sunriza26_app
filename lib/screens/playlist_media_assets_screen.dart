import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/media_models.dart';
import '../services/media_service.dart';
import '../services/playlist_service.dart';
import '../theme/app_theme.dart';

class PlaylistMediaAssetsScreen extends StatefulWidget {
  final String avatarId;
  final List<AvatarMedia> preselected;
  final String? playlistId; // optional: für Bereinigung
  const PlaylistMediaAssetsScreen({
    super.key,
    required this.avatarId,
    this.preselected = const [],
    this.playlistId,
  });

  @override
  State<PlaylistMediaAssetsScreen> createState() =>
      _PlaylistMediaAssetsScreenState();
}

class _PlaylistMediaAssetsScreenState extends State<PlaylistMediaAssetsScreen> {
  final _mediaSvc = MediaService();
  final _playlistSvc = PlaylistService();
  List<AvatarMedia> _all = [];
  final List<String> _selected = [];
  String _tab = 'images';
  bool _portrait = true;
  final TextEditingController _search = TextEditingController();
  String _term = '';
  final Map<String, VideoPlayerController> _videoCtrls = {};

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(
      () => setState(() => _term = _search.text.toLowerCase()),
    );
  }

  @override
  void dispose() {
    for (final c in _videoCtrls.values) {
      c.dispose();
    }
    _videoCtrls.clear();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Optional: Inkonsistenzen bereinigen (Assets ohne Media)
    if (widget.playlistId != null) {
      try {
        await _playlistSvc.pruneTimelineData(
          widget.avatarId,
          widget.playlistId!,
        );
      } catch (_) {}
    }
    final list = await _mediaSvc.list(widget.avatarId);
    setState(() {
      _all = list;
      _selected.addAll(widget.preselected.map((e) => e.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assets wählen'),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Abbrechen',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
          IconButton(
            tooltip: 'Speichern',
            onPressed: _save,
            icon: const Icon(Icons.save),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(84),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                color: const Color(0xFF1E1E1E),
                height: 35,
                child: Row(
                  children: [
                    _tabBtn('images', Icons.image_outlined),
                    _tabBtn('videos', Icons.videocam_outlined),
                    _tabBtn('documents', Icons.description_outlined),
                    _tabBtn('audio', Icons.audiotrack),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() => _portrait = !_portrait),
                      child: Icon(
                        _portrait
                            ? Icons.stay_primary_portrait
                            : Icons.stay_primary_landscape,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
              // Suche in separatem Fullwidth-Container
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                alignment: Alignment.center,
                child: SizedBox(
                  height: 36,
                  width: double.infinity,
                  child: TextField(
                    controller: _search,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    cursorColor: Colors.white,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Suche nach Medien...',
                      hintStyle: TextStyle(color: Colors.white54, fontSize: 12),
                      prefixIcon: Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.search,
                          color: Colors.white70,
                          size: 18,
                        ),
                      ),
                      prefixIconConstraints: BoxConstraints(
                        minWidth: 24,
                        maxWidth: 28,
                      ),
                      filled: true,
                      fillColor: Color(0x1FFFFFFF),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Padding(padding: const EdgeInsets.all(12), child: _buildGrid()),
    );
  }

  Widget _tabBtn(String t, IconData icon) {
    final sel = _tab == t;
    final grad = Theme.of(context).extension<AppGradients>()?.magentaBlue;
    return SizedBox(
      height: 35,
      child: TextButton(
        onPressed: () => setState(() => _tab = t),
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        ),
        child: sel
            ? Ink(
                decoration: BoxDecoration(gradient: grad),
                child: SizedBox(
                  width: 60,
                  height: double.infinity,
                  child: Icon(icon, color: Colors.white),
                ),
              )
            : SizedBox(
                width: 60,
                height: double.infinity,
                child: Icon(icon, color: Colors.white54),
              ),
      ),
    );
  }

  List<AvatarMedia> get _filtered {
    return _all.where((m) {
      switch (_tab) {
        case 'images':
          if (m.type != AvatarMediaType.image) return false;
          break;
        case 'videos':
          if (m.type != AvatarMediaType.video) return false;
          break;
        case 'documents':
          if (m.type != AvatarMediaType.document) return false;
          break;
        case 'audio':
          if (m.type != AvatarMediaType.audio) return false;
          break;
      }
      final ar = m.aspectRatio ?? 9 / 16;
      final isPortrait = ar < 1.0;
      final orientOk = _portrait ? isPortrait : !isPortrait;
      if (!orientOk) return false;
      if (_term.isEmpty) return true;
      final name = (m.originalFileName ?? m.url).toLowerCase();
      final tagsStr = (m.tags ?? []).map((t) => t.toLowerCase()).join(' ');
      return name.contains(_term) || tagsStr.contains(_term);
    }).toList();
  }

  Widget _buildGrid() {
    final items = _filtered;
    return LayoutBuilder(
      builder: (context, cons) {
        final col = (cons.maxWidth / 180).floor().clamp(2, 8);
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: col,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            // Kachelverhältnis wie in media_gallery: Portrait 9:16, Landscape 16:9
            childAspectRatio: _portrait ? (9 / 16) : (16 / 9),
          ),
          itemCount: items.length,
          itemBuilder: (ctx, i) {
            final m = items[i];
            final sel = _selected.contains(m.id);
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (sel) {
                    _selected.remove(m.id);
                  } else {
                    _selected.insert(0, m.id); // nach oben
                  }
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: sel ? Colors.lightGreenAccent : Colors.white24,
                    width: sel ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.hardEdge,
                child: _buildMediaCard(m),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMediaCard(AvatarMedia m) {
    switch (m.type) {
      case AvatarMediaType.image:
        return Image.network(m.thumbUrl ?? m.url, fit: BoxFit.cover);
      case AvatarMediaType.video:
        return FutureBuilder<VideoPlayerController>(
          future: _videoControllerFor(m.url),
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done || !snap.hasData) {
              if ((m.thumbUrl ?? '').isNotEmpty) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      m.thumbUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(),
                    ),
                    const Align(
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.play_circle_outline,
                        size: 36,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                );
              }
              return const Center(
                child: Icon(Icons.videocam, color: Colors.white70, size: 32),
              );
            }
            final ctrl = snap.data!;
            return Stack(
              fit: StackFit.expand,
              children: [
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: ctrl.value.size.width,
                    height: ctrl.value.size.height,
                    child: VideoPlayer(ctrl),
                  ),
                ),
                const Align(
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.play_circle_outline,
                    size: 36,
                    color: Colors.white70,
                  ),
                ),
              ],
            );
          },
        );
      case AvatarMediaType.document:
        if ((m.thumbUrl ?? '').isNotEmpty) {
          return Image.network(
            m.thumbUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _docFallback(m),
          );
        }
        // Fallback: Versuche eine Thumb-Datei aus Storage (documents/thumbs/{id}*) zu finden
        return FutureBuilder<String?>(
          future: _findDocThumbFromStorage(widget.avatarId, m.id),
          builder: (ctx, snap) {
            final url = snap.data;
            if (url != null && url.isNotEmpty) {
              return Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _docFallback(m),
              );
            }
            return _docFallback(m);
          },
        );
      case AvatarMediaType.audio:
        String fmtDuration() {
          final ms = m.durationMs ?? 0;
          final s = (ms ~/ 1000) % 60;
          final min = (ms ~/ 1000) ~/ 60;
          String two(int n) => n.toString().padLeft(2, '0');
          return '${two(min)}:${two(s)}';
        }
        return Container(
          color: const Color(0xFF101010),
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.play_arrow, color: Colors.white70),
                  SizedBox(width: 12),
                  Icon(Icons.pause, color: Colors.white38),
                  SizedBox(width: 12),
                  Icon(Icons.replay, color: Colors.white38),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                (m.originalFileName ?? m.url.split('/').last),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                fmtDuration(),
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ],
          ),
        );
    }
  }

  Widget _docFallback(AvatarMedia m) {
    return Container(
      color: const Color(0xFF101010),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description, color: Colors.white70, size: 28),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                (m.originalFileName ?? m.url.split('/').last),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<VideoPlayerController> _videoControllerFor(String url) async {
    if (_videoCtrls.containsKey(url)) return _videoCtrls[url]!;
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    await c.initialize();
    c.setVolume(0);
    _videoCtrls[url] = c;
    return c;
  }

  Future<String?> _findDocThumbFromStorage(
    String avatarId,
    String mediaId,
  ) async {
    try {
      final prefix = 'avatars/$avatarId/documents/thumbs/$mediaId';
      final bucket = FirebaseStorage.instance.ref();
      final list = await bucket.child(prefix).listAll();
      if (list.items.isEmpty) return null;
      // wähle erstes (oder bestes) Element
      final ref = list.items.first;
      return await ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  void _save() {
    final result = _all.where((m) => _selected.contains(m.id)).toList();
    Navigator.pop(context, result);
  }
}
