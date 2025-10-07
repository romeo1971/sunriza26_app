import 'package:flutter/material.dart';
import 'dart:async';
import 'package:video_player/video_player.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/doc_thumb_service.dart';
import '../models/media_models.dart';
import '../models/avatar_data.dart';
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
  final Map<String, VideoPlayerController> _audioCtrls = {};
  final Map<String, Duration> _audioDurations = {};
  String? _playingAudioUrl;
  final Map<String, Duration> _audioCurrent = {};
  final Set<String> _audioHasListener = {};
  Timer? _audioTicker;

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
    for (final c in _audioCtrls.values) {
      c.dispose();
    }
    _audioCtrls.clear();
    try {
      _audioTicker?.cancel();
    } catch (_) {}
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

    // Hero-URLs laden (imageUrls/videoUrls aus AvatarData)
    Set<String> heroUrls = {};
    try {
      final doc = await FirebaseFirestore.instance
          .collection('avatars')
          .doc(widget.avatarId)
          .get();
      if (doc.exists) {
        final data = AvatarData.fromMap({'id': doc.id, ...doc.data()!});
        heroUrls.addAll(data.imageUrls);
        heroUrls.addAll(data.videoUrls);
      }
    } catch (e) {
      debugPrint('❌ Fehler beim Laden der Hero-URLs: $e');
    }

    final list = await _mediaSvc.list(widget.avatarId);
    // Filtere Hero-Images/Videos heraus
    final filtered = list.where((m) => !heroUrls.contains(m.url)).toList();
    setState(() {
      _all = filtered;
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
                    if (_tab != 'audio')
                      TextButton(
                        onPressed: () => setState(() => _portrait = !_portrait),
                        style: ButtonStyle(
                          padding: const WidgetStatePropertyAll(
                            EdgeInsets.zero,
                          ),
                          minimumSize: const WidgetStatePropertyAll(
                            Size(40, 35),
                          ),
                        ),
                        child: _portrait
                            ? ShaderMask(
                                shaderCallback: (bounds) =>
                                    const LinearGradient(
                                      colors: [
                                        AppColors.magenta,
                                        AppColors.lightBlue,
                                      ],
                                    ).createShader(bounds),
                                child: const Icon(
                                  Icons.stay_primary_portrait,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.stay_primary_landscape,
                                size: 18,
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
        onPressed: () => setState(() {
          _tab = t;
          // Orientation nicht über Tabs hinweg „mitnehmen“:
          if (t == 'documents' || t == 'audio') {
            _portrait = true; // Dokumente/Audios immer sichtbar machen
          }
        }),
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
      // Orientation-Filter: Audio nie filtern, bei Videos/Bildern nur filtern,
      // wenn eine verlässliche aspectRatio vorhanden ist. Dokumente ohne AR
      // als Portrait behandeln (bis Thumb erstellt wurde).
      if (_tab != 'audio') {
        double? ar = m.aspectRatio;
        // Dokumente ohne AR als Portrait behandeln (bis Thumb da ist)
        if (ar == null && m.type == AvatarMediaType.document) {
          ar = 9 / 16;
        }
        // Videos/Bilder ohne AR nicht herausfiltern (behalten)
        if ((m.type == AvatarMediaType.video ||
                m.type == AvatarMediaType.image) &&
            ar == null) {
          // skip orientation filtering
        } else {
          final isPortrait = (ar ?? 9 / 16) < 1.0;
          final orientOk = _portrait ? isPortrait : !isPortrait;
          if (!orientOk) return false;
        }
      }
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
            crossAxisCount: _tab == 'audio'
                ? (cons.maxWidth / 328).floor().clamp(1, 6)
                : col,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            // Für Audio fixe Höhe statt AspectRatio
            mainAxisExtent: _tab == 'audio' ? 148 : null,
            // Für Nicht-Audio das bekannte Verhältnis
            childAspectRatio: _tab == 'audio'
                ? 1.0
                : (_portrait ? (9 / 16) : (16 / 9)),
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
                    _selected.insert(0, m.id);
                  }
                });
              },
              child: Column(
                children: [
                  // Kachel oben
                  Container(
                    height: _tab == 'audio' ? 96 : null,
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
                  // Steuerleiste unter der Kachel (nur Audio)
                  if (_tab == 'audio')
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Builder(
                            builder: (_) {
                              final isPlaying =
                                  _playingAudioUrl == m.url &&
                                  ((_audioCtrls[m.url]?.value.isPlaying) ==
                                      true);
                              if (isPlaying) {
                                return IconButton(
                                  icon: const Icon(Icons.pause, size: 18),
                                  color: Colors.white70,
                                  onPressed: () => _pauseAudio(m),
                                  tooltip: 'Pause',
                                );
                              }
                              // Play: benutze das gewohnte runde Gradient-Icon
                              return Tooltip(
                                message: 'Abspielen',
                                child: InkWell(
                                  onTap: () => _playAudio(m),
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color(0xFFE91E63),
                                          AppColors.lightBlue,
                                          Color(0xFF00E5FF),
                                        ],
                                        stops: [0.0, 0.6, 1.0],
                                      ),
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.play_arrow,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.replay, size: 18),
                            color: Colors.white54,
                            onPressed: () => _restartAudio(m),
                            tooltip: 'Neu starten',
                          ),
                        ],
                      ),
                    ),
                ],
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
        // 1) Wenn thumbUrl vorhanden → verwenden
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
        // 2) Thumb aus Storage versuchen und persistieren
        return FutureBuilder<String?>(
          future: _findVideoThumbFromStorage(widget.avatarId, m.id),
          builder: (ctx, snap) {
            final url = snap.data;
            if (url != null && url.isNotEmpty) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    url,
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
            // 3) Fallback: ersten Frame via VideoPlayer anzeigen
            return FutureBuilder<VideoPlayerController>(
              future: _videoControllerFor(m.url),
              builder: (ctx2, snap2) {
                if (snap2.connectionState != ConnectionState.done ||
                    !snap2.hasData) {
                  return const Center(
                    child: Icon(
                      Icons.videocam,
                      color: Colors.white70,
                      size: 32,
                    ),
                  );
                }
                final ctrl = snap2.data!;
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
        // Kein Thumb: Erzeuge live und speichere dauerhaft
        return FutureBuilder<String?>(
          future: _generateAndStoreDocThumb(m),
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
        final fileName =
            (m.originalFileName ??
            Uri.parse(m.url).pathSegments.last.split('?').first);
        // NUR Name + Zeit in der Kachel (keine Icons, keine Waveform)
        return Tooltip(
          message: fileName,
          child: Container(
            color: const Color(0xFF101010),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Builder(
                  builder: (_) {
                    final cur = _audioCurrent[m.url] ?? Duration.zero;
                    final tot = _audioDurations[m.url] ?? Duration.zero;
                    return Text(
                      '${_fmtDur(cur)} / ${_fmtDur(tot)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              ],
            ),
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

  // Placeholder-Wave, falls noch kein thumbUrl vorhanden oder Ladefehler
  Widget _audioWavePlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withOpacity(0.12),
            Colors.white.withOpacity(0.06),
            Colors.white.withOpacity(0.12),
          ],
        ),
      ),
    );
  }

  Future<VideoPlayerController> _audioControllerFor(String url) async {
    if (_audioCtrls.containsKey(url)) return _audioCtrls[url]!;
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    await c.initialize();
    c.setVolume(1);
    _audioCtrls[url] = c;
    _audioDurations[url] = c.value.duration;
    if (!_audioHasListener.contains(url)) {
      c.addListener(() {
        final v = c.value;
        _audioCurrent[url] = v.position;
        _audioDurations[url] = v.duration;
        if (mounted) setState(() {});
        if (!v.isPlaying && v.position >= v.duration && mounted) {
          if (_playingAudioUrl == url) {
            setState(() => _playingAudioUrl = null);
          }
        }
      });
      _audioHasListener.add(url);
    }
    return c;
  }

  Future<void> _stopAllAudiosExcept(String? keepUrl) async {
    for (final entry in _audioCtrls.entries) {
      if (keepUrl != null && entry.key == keepUrl) continue;
      try {
        await entry.value.pause();
      } catch (_) {}
    }
    if (keepUrl == null) {
      _playingAudioUrl = null;
    } else if (_playingAudioUrl != keepUrl) {
      _playingAudioUrl = keepUrl;
    }
  }

  Future<void> _playAudio(AvatarMedia m) async {
    final c = await _audioControllerFor(m.url);
    await _stopAllAudiosExcept(m.url);
    await c.play();
    _audioTicker ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      final url = _playingAudioUrl;
      if (url == null) return;
      final c = _audioCtrls[url];
      if (c != null) {
        _audioCurrent[url] = c.value.position;
        _audioDurations[url] = c.value.duration;
      }
      if (!mounted) return;
      setState(() {});
    });
    setState(() => _playingAudioUrl = m.url);
  }

  Future<void> _pauseAudio(AvatarMedia m) async {
    final c = await _audioControllerFor(m.url);
    await c.pause();
    setState(() {
      if (_playingAudioUrl == m.url) _playingAudioUrl = null;
    });
    if (_playingAudioUrl == null) {
      try {
        _audioTicker?.cancel();
      } catch (_) {}
      _audioTicker = null;
    }
  }

  Future<void> _restartAudio(AvatarMedia m) async {
    final c = await _audioControllerFor(m.url);
    await _stopAllAudiosExcept(m.url);
    await c.seekTo(Duration.zero);
    await c.play();
    setState(() => _playingAudioUrl = m.url);
  }

  String _fmtDur(Duration d) {
    final s = d.inSeconds;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Future<VideoPlayerController> _videoControllerFor(String url) async {
    if (_videoCtrls.containsKey(url)) return _videoCtrls[url]!;
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    await c.initialize();
    c.setVolume(0);
    _videoCtrls[url] = c;
    return c;
  }

  Future<String?> _findVideoThumbFromStorage(
    String avatarId,
    String mediaId,
  ) async {
    try {
      final prefix = 'avatars/$avatarId/videos/thumbs/$mediaId';
      final bucket = FirebaseStorage.instance.ref();
      final list = await bucket.child(prefix).listAll();
      if (list.items.isEmpty) return null;
      final ref = list.items.first;
      final url = await ref.getDownloadURL();
      try {
        await FirebaseFirestore.instance
            .collection('avatars')
            .doc(avatarId)
            .collection('media')
            .doc(mediaId)
            .set({'thumbUrl': url}, SetOptions(merge: true));
      } catch (_) {}
      return url;
    } catch (_) {
      return null;
    }
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
      final url = await ref.getDownloadURL();
      // Persistiere thumbUrl in Firestore, damit UI und Filter konsistent sind
      try {
        await FirebaseFirestore.instance
            .collection('avatars')
            .doc(avatarId)
            .collection('media')
            .doc(mediaId)
            .set({'thumbUrl': url}, SetOptions(merge: true));
      } catch (_) {}
      return url;
    } catch (_) {
      return null;
    }
  }

  // Generiert fehlende Dokument-Thumbs (gleiche Pipeline wie Galerie)
  Future<String?> _generateAndStoreDocThumb(AvatarMedia m) async {
    try {
      if ((m.thumbUrl ?? '').isNotEmpty) return m.thumbUrl;
      // 1) vorhandene Thumb-Datei?
      final existing = await _findDocThumbFromStorage(widget.avatarId, m.id);
      if (existing != null && existing.isNotEmpty) return existing;
      // 2) neu generieren und speichern
      final generated = await DocThumbService.generateAndStoreThumb(
        widget.avatarId,
        m,
      );
      return generated;
    } catch (_) {
      return null;
    }
  }

  void _save() {
    final result = _all.where((m) => _selected.contains(m.id)).toList();
    Navigator.pop(context, result);
  }
}
