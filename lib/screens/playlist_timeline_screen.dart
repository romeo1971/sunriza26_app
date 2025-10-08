import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../models/playlist_models.dart';
import '../models/media_models.dart';
import '../services/media_service.dart';
import '../services/playlist_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_text_field.dart';
import 'playlist_media_assets_screen.dart';
import '../services/doc_thumb_service.dart';

class PlaylistTimelineScreen extends StatefulWidget {
  final Playlist playlist;
  const PlaylistTimelineScreen({super.key, required this.playlist});

  @override
  State<PlaylistTimelineScreen> createState() => _PlaylistTimelineScreenState();
}

class _PlaylistTimelineScreenState extends State<PlaylistTimelineScreen> {
  String _tab = 'images'; // images|videos|documents|audio
  bool _portrait = true;
  final _mediaSvc = MediaService();
  final _playlistSvc = PlaylistService();
  List<AvatarMedia> _allMedia = [];
  final List<AvatarMedia> _timeline = [];
  final List<Key> _timelineKeys = [];
  final List<AvatarMedia> _assets = []; // rechte Seite: Timeline-Assets
  double _splitRatio = 0.38; // Anteil der linken Spalte (0..1)
  bool _showSearch = false;
  String _searchTerm = '';
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _intervalCtl = TextEditingController();
  bool _timelineHover = false;
  bool _resizerHover = false;
  String _assetSort = 'name'; // 'name' | 'type'
  final TextEditingController _assetsSearchCtl = TextEditingController();
  String _assetsSearchTerm = '';
  bool _isDirty = false; // Trackt ob Änderungen vorgenommen wurden

  // Audio-Player-Logik (wie in media_assets)
  final Map<String, VideoPlayerController> _audioCtrls = {};
  final Map<String, Duration> _audioDurations = {};
  String? _playingAudioUrl;
  final Map<String, Duration> _audioCurrent = {};
  final Set<String> _audioHasListener = {};
  Timer? _audioTicker;

  String _displayName(AvatarMedia m) {
    if ((m.originalFileName ?? '').trim().isNotEmpty)
      return m.originalFileName!.trim();
    try {
      final uri = Uri.parse(m.url);
      String last = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : m.url;
      final qIdx = last.indexOf('?');
      if (qIdx >= 0) last = last.substring(0, qIdx);
      return Uri.decodeComponent(last).replaceAll('+', ' ');
    } catch (_) {
      final raw = m.url.split('/').last;
      final qIdx = raw.indexOf('?');
      final cut = qIdx >= 0 ? raw.substring(0, qIdx) : raw;
      return cut;
    }
  }

  void _syncKeysLength() {
    // Halte die Keys-Liste stabil gleich lang wie die Timeline
    while (_timelineKeys.length < _timeline.length) {
      _timelineKeys.add(UniqueKey());
    }
    while (_timelineKeys.length > _timeline.length) {
      _timelineKeys.removeLast();
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    _intervalCtl.text = widget.playlist.showAfterSec.toString();
    _assetsSearchCtl.addListener(() {
      setState(() => _assetsSearchTerm = _assetsSearchCtl.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _assetsSearchCtl.dispose();
    _intervalCtl.dispose();
    for (final c in _audioCtrls.values) {
      c.dispose();
    }
    _audioCtrls.clear();
    try {
      _audioTicker?.cancel();
    } catch (_) {}
    super.dispose();
  }

  // AppBar‑Style Tab Button (35px hoch), angelehnt an media_gallery_screen
  Widget _buildTopTabAppbarBtn(String tab, IconData icon) {
    final selected = _tab == tab;
    final appGrad = Theme.of(context).extension<AppGradients>()?.magentaBlue;
    const double tabWidth = 68; // Einheitliche Zielbreite (breitere Variante)
    return SizedBox(
      height: 35,
      child: TextButton(
        onPressed: () => setState(() => _tab = tab),
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          minimumSize: const WidgetStatePropertyAll(Size(tabWidth, 35)),
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused) ||
                states.contains(WidgetState.pressed)) {
              final mix = Color.lerp(
                AppColors.magenta,
                AppColors.lightBlue,
                0.5,
              )!;
              return mix.withValues(alpha: 0.12);
            }
            return null;
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          shape: WidgetStateProperty.resolveWith<OutlinedBorder>((states) {
            final isHover =
                states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused);
            if (selected || isHover)
              return const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              );
            return RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            );
          }),
        ),
        child: Container(
                  width: tabWidth,
                  height: double.infinity,
          decoration: selected
              ? BoxDecoration(
                  gradient: appGrad,
                  borderRadius: BorderRadius.zero,
                )
              : null,
          child: Icon(
            icon,
            size: 22,
            color: selected ? Colors.white : Colors.white54,
          ),
              ),
      ),
    );
  }

  Widget _buildTopNavBar() {
    return Stack(
      children: [
        Container(height: 35, color: const Color(0xFF0D0D0D)),
        Positioned.fill(child: Container(color: const Color(0x15FFFFFF))),
        SizedBox(
          height: 35,
          child: Row(
            children: [
              _buildTopTabAppbarBtn('images', Icons.image_outlined),
              _buildTopTabAppbarBtn('videos', Icons.videocam_outlined),
              _buildTopTabAppbarBtn('documents', Icons.description_outlined),
              _buildTopTabAppbarBtn('audio', Icons.audiotrack),
              const Spacer(),
              // Orientierung
              SizedBox(
                height: 35,
                child: TextButton(
                  onPressed: () => setState(() => _portrait = !_portrait),
                  style: ButtonStyle(
                    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                    minimumSize: const WidgetStatePropertyAll(Size(48, 35)),
                    backgroundColor: const WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                    overlayColor: WidgetStateProperty.resolveWith<Color?>((
                      states,
                    ) {
                      if (states.contains(WidgetState.hovered) ||
                          states.contains(WidgetState.focused) ||
                          states.contains(WidgetState.pressed)) {
                        final mix = Color.lerp(
                          AppColors.magenta,
                          AppColors.lightBlue,
                          0.5,
                        )!;
                        return mix.withValues(alpha: 0.12);
                      }
                      return null;
                    }),
                    foregroundColor: const WidgetStatePropertyAll(Colors.white),
                    shape: WidgetStateProperty.resolveWith<OutlinedBorder>((
                      states,
                    ) {
                      final isHover =
                          states.contains(WidgetState.hovered) ||
                          states.contains(WidgetState.focused);
                      if (isHover)
                        return const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        );
                      return RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      );
                    }),
                  ),
                  child: _portrait
                      ? const Icon(
                            Icons.stay_primary_portrait,
                            size: 22,
                          color: Colors.white, // Weiß wenn selected
                        )
                      : const Icon(
                          Icons.stay_primary_landscape,
                          size: 22,
                          color: Colors.white54,
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _load() async {
    try {
      final list = await _mediaSvc.list(widget.playlist.avatarId);
      _allMedia = list;
      // gespeichertes Split-Verhältnis anwenden, falls vorhanden
      if (widget.playlist.timelineSplitRatio != null) {
        _splitRatio = widget.playlist.timelineSplitRatio!.clamp(0.1, 0.9);
      }
      // Assets + Items laden
      final assets = await _playlistSvc.listAssets(
        widget.playlist.avatarId,
        widget.playlist.id,
      );
      final items = await _playlistSvc.listTimelineItems(
        widget.playlist.avatarId,
        widget.playlist.id,
      );
      // Inkonstistenzen bereinigen (Items ohne Assets, Assets ohne Media)
      await _playlistSvc.pruneTimelineData(
        widget.playlist.avatarId,
        widget.playlist.id,
      );
      // Nach dem Prune neu laden
      final assets2 = await _playlistSvc.listAssets(
        widget.playlist.avatarId,
        widget.playlist.id,
      );
      final items2 = await _playlistSvc.listTimelineItems(
        widget.playlist.avatarId,
        widget.playlist.id,
      );
      // Asset-Resolution: wir nehmen als Asset-ID die media.id (gleiches id-Feld)
      final mediaById = {for (final m in _allMedia) m.id: m};
      _assets
        ..clear()
        ..addAll(
          assets2.map((a) {
            final mid = (a['mediaId'] as String?) ?? (a['id'] as String?);
            final m = (mid != null) ? mediaById[mid] : null;
            return m;
          }).whereType<AvatarMedia>(),
        );
      _timeline
        ..clear()
        ..addAll(
          items2.map((it) {
            final aid = it['assetId'] as String?;
            return (aid != null) ? mediaById[aid] : null;
          }).whereType<AvatarMedia>(),
        );
      _timelineKeys
        ..clear()
        ..addAll(List.generate(_timeline.length, (_) => UniqueKey()));
      setState(() {});
    } catch (_) {}
  }

  List<AvatarMedia> get _filtered {
    final list = _allMedia.where((m) {
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
      return _portrait ? isPortrait : !isPortrait;
    }).toList();

    if (_searchTerm.isEmpty) return list;
    final term = _searchTerm.toLowerCase();
    return list.where((m) {
      final name = (m.originalFileName ?? m.url).toLowerCase();
      final tagsStr = (m.tags ?? []).map((t) => t.toLowerCase()).join(' ');
      return name.contains(term) || tagsStr.contains(term);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final coverW = 100.0; // gleich wie in playlist_list_screen
    final coverH = 178.0; // gleich wie in playlist_list_screen

    return Scaffold(
      appBar: AppBar(
        title: const Text('Timeline'),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_isDirty)
          IconButton(
            tooltip: 'Speichern',
            onPressed: _saveTimeline,
            icon: const Icon(Icons.save),
          ),
          const SizedBox(width: 4),
        ],
        // Keine Bottom‑Tabs hier – Tabs kommen unter den Header
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Cover + Name (einheitlich strukturiert)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Container(
              constraints: const BoxConstraints(minHeight: 178),
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                  // Cover Image
                  SizedBox(
                    width: coverW,
                    height: coverH,
                    child: Container(
                  width: coverW,
                  height: coverH,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade800,
                        borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: widget.playlist.coverImageUrl != null
                      ? Image.network(
                          widget.playlist.coverImageUrl!,
                              width: coverW,
                              height: coverH,
                          fit: BoxFit.cover,
                        )
                      : const Center(
                          child: Icon(
                                Icons.playlist_play,
                                size: 60,
                            color: Colors.white54,
                          ),
                        ),
                ),
                  ),
                  const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        // Name (gleicher Stil wie playlist_list)
                      Text(
                        widget.playlist.name,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                        const SizedBox(height: 8),
                        Text(
                          '${_timeline.length} Medien in der Playlist',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 200),
                          child: CustomTextField(
                            label: 'Zeit-Intervall',
                                  controller: _intervalCtl,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                            hintText: 'Anzeigezeit in Sekunden',
                            onChanged: (v) {
                              setState(() {
                                _isDirty = true;
                              });
                            },
                            ),
                          ),
                        ],
                        ),
                      ),
                    ],
                  ),
            ),
          ),

          // (entfernt) Galerie-Navi – gehört nur in den Assets-Screen
          const SizedBox(height: 8),

          // Call-to-Action: Media Assets hinzufügen (öffnet Asset-Auswahl)
                    Container(
                      height: 44,
            color: Colors.grey.shade900,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                InkWell(
                  onTap: _openAssetsPicker,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.add, color: Colors.white, size: 22),
                      SizedBox(width: 8),
                          Text(
                        'Media Assets hinzufügen',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                            ),
                          ),
                          const Spacer(),
                if (_assets.isNotEmpty)
                  Flexible(
                    child: SizedBox(
                            height: 32,
                      child: TextField(
                        controller: _assetsSearchCtl,
                        onChanged: (v) =>
                            setState(() => _assetsSearchTerm = v.toLowerCase()),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                ),
                        cursorColor: Colors.white,
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Suche nach Medien...',
                          hintStyle: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
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
                            vertical: 8,
                          ),
                        ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

          // Kombinierter Container: FullWidth-Header, darunter links Timeline, rechts Assets mit Resizer
                    Expanded(
                            child: Container(
                                    decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                // keine Border unten um den Split-Container
              ),
              child: Column(
                children: [
                  // Kein innerer Header/Label mehr – direkt die Split-Ansicht
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, cons) {
                        final totalW = cons.maxWidth;
                        const double resizerW = 14.0;
                        // verfügbare Breite (ohne Resizer)
                        final available = (totalW - resizerW).clamp(
                          0.0,
                          double.infinity,
                        );
                        // Mindestbreiten: Links kleiner, Rechts größer (für Navi-Icons)
                        const double minLeftPane = 100.0;
                        const double minRightPane =
                            200.0; // für Timeline-Assets Navi
                        if (available <= (minLeftPane + minRightPane)) {
                          // zu schmal: mittig teilen
                          final leftW = available / 2;
                          return Row(
                            children: [
                              SizedBox(
                                width: leftW,
                                child: _buildTimelinePane(),
                              ),
                              _buildResizer(totalW, leftW, resizerW),
                              Expanded(child: _buildAssetsPane()),
                            ],
                          );
                        }
                        final double minLeft = minLeftPane;
                        final double maxLeft = (available - minRightPane).clamp(
                          minLeft,
                          available,
                        );
                        // leftW aus Ratio, aber relativ zu available rechnen
                        double leftW = (_splitRatio * available).clamp(
                          minLeft,
                          maxLeft,
                        );
                        return Row(
                                            children: [
                            // Timeline links
                            SizedBox(width: leftW, child: _buildTimelinePane()),
                            // Resizer
                            _buildResizer(totalW, leftW, resizerW),
                            // Assets rechts
                            Expanded(child: _buildAssetsPane()),
                          ],
                        );
                      },
                            ),
                          ),
                        ],
              ),
            ),
          ),
          // Entfernt: Fußzeile mit "Speichern"-Button – Speichern jetzt oben rechts in der AppBar
        ],
      ),
    );
  }

  Widget _buildMediaGrid() {
    final items = _filtered;
    if (items.isEmpty) {
      return const Center(
        child: Text(
          'Keine Medien gefunden',
          style: TextStyle(color: Colors.white60),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, cons) {
        const double targetTileW = 240.0; // Zielbreite
        int cols = (cons.maxWidth / targetTileW).floor();
        if (cols < 2) cols = 2; // Mindestens 2 pro Reihe
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio:
                1, // neutral → Media zeigt eigenes Verhältnis (Portrait/Landscape)
          ),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final m = items[i];
            return LongPressDraggable<AvatarMedia>(
              data: m,
              feedback: Material(
                color: Colors.transparent,
                child: SizedBox(width: 100, child: _buildThumb(m)),
              ),
              child: _buildThumbCard(m),
            );
          },
        );
      },
    );
  }

  Widget _buildThumbCard(AvatarMedia m) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      clipBehavior: Clip.hardEdge,
      child: _buildThumb(m),
    );
  }

  Widget _buildThumb(AvatarMedia m, {double? size}) {
    final ar = m.aspectRatio ?? (9 / 16);
    Widget content;
    if (m.type == AvatarMediaType.image) {
      content = Image.network(m.url, fit: BoxFit.cover);
    } else if (m.type == AvatarMediaType.video) {
      if (m.thumbUrl != null && m.thumbUrl!.isNotEmpty) {
        content = Image.network(
          m.thumbUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Center(child: Icon(Icons.videocam, color: Colors.white70)),
        );
      } else {
      content = const Center(
        child: Icon(Icons.videocam, color: Colors.white70),
      );
      }
    } else if (m.type == AvatarMediaType.document) {
      if (m.thumbUrl != null && m.thumbUrl!.isNotEmpty) {
      content = Image.network(
          m.thumbUrl!,
        fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.description, color: Colors.white70),
          ),
      );
    } else {
        content = Container(
          color: const Color(0xFF101010),
          child: const Center(
            child: Icon(Icons.description, color: Colors.white70, size: 28),
          ),
        );
      }
    } else {
      // Audio: nur Name + Zeit (keine Icons IN der Kachel wie in media_assets)
      if (size != null) {
      content = const Center(
        child: Icon(Icons.audiotrack, color: Colors.white70),
      );
      } else {
        String fmt() {
          final ms = m.durationMs ?? 0;
          final s = (ms ~/ 1000) % 60;
          final min = (ms ~/ 1000) ~/ 60;
          String two(int n) => n.toString().padLeft(2, '0');
          return '${two(min)}:${two(s)}';
        }

        final fileName = _displayName(m);
        content = Container(
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
              Text(
                fmt(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        );
      }
    }
    // Zeige Medien im eigenen Seitenverhältnis (Portrait/Landscape korrekt),
    // ohne starre Kachelgröße – passt sich der verfügbaren Breite an
    final aspect = AspectRatio(aspectRatio: ar, child: content);
    if (size != null) return SizedBox(width: size, child: aspect);
    return aspect;
  }

  Future<void> _saveTimeline() async {
    // 1) Assets in Firestore spiegeln (id = media.id)
    final assetsDocs = _assets
        .map(
          (m) => {
            'id': m.id,
            'mediaId': m.id,
            'thumbUrl': m.thumbUrl ?? m.url,
            'aspectRatio': m.aspectRatio,
            'type': m.type.name,
            'createdAt': DateTime.now().millisecondsSinceEpoch,
          },
        )
        .toList();
    await _playlistSvc.setAssets(
      widget.playlist.avatarId,
      widget.playlist.id,
      assetsDocs,
    );

    // 2) Timeline-Items (assetId-Referenzen) in Reihenfolge schreiben
    final itemDocs = <Map<String, dynamic>>[];
    for (final m in _timeline) {
      itemDocs.add({'assetId': m.id});
    }
    try {
      await _playlistSvc.writeTimelineItems(
        widget.playlist.avatarId,
        widget.playlist.id,
        itemDocs,
      );
      if (mounted) {
        setState(() => _isDirty = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Timeline gespeichert')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Speichern der Timeline: $e')),
        );
      }
    }
  }

  Future<void> _saveAssetsPool() async {
    final docs = _assets
        .map(
          (m) => {
            'id': m.id,
            'mediaId': m.id,
            'thumbUrl': m.thumbUrl ?? m.url,
            'aspectRatio': m.aspectRatio,
            'type': m.type.name,
            'createdAt': DateTime.now().millisecondsSinceEpoch,
          },
        )
        .toList();
    try {
      await _playlistSvc.setAssets(
        widget.playlist.avatarId,
        widget.playlist.id,
        docs,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Speichern der Assets: $e')),
        );
      }
    }
  }

  Future<void> _persistTimelineItems() async {
    final itemDocs = <Map<String, dynamic>>[];
    for (final m in _timeline) {
      itemDocs.add({'assetId': m.id});
    }
    try {
      await _playlistSvc.writeTimelineItems(
        widget.playlist.avatarId,
        widget.playlist.id,
        itemDocs,
      );
    } catch (_) {}
  }

  Widget _buildAssetsGrid() {
    if (_assets.isEmpty) {
      return const Center(
        child: Text(
          'Keine Media Assets ausgewählt',
          style: TextStyle(color: Colors.white60),
        ),
      );
    }
    // sortierte Sicht
    List<AvatarMedia> view = List.of(_assets);
    // Filter nach Tab/Portrait
    view = view.where((m) {
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
          // Bei Audio KEINEN Orientation-Filter anwenden!
          return true;
      }
      final ar = m.aspectRatio ?? 9 / 16;
      final isPortrait = ar < 1.0;
      return _portrait ? isPortrait : !isPortrait;
    }).toList();
    if (_assetsSearchTerm.isNotEmpty) {
      final t = _assetsSearchTerm.toLowerCase();
      view = view.where((m) {
        final name = (m.originalFileName ?? m.url).toLowerCase();
        final tagsStr = (m.tags ?? []).map((x) => x.toLowerCase()).join(' ');
        return name.contains(t) || tagsStr.contains(t);
      }).toList();
    }
    if (_assetSort == 'type') {
      view.sort((a, b) => a.type.name.compareTo(b.type.name));
    } else {
      view.sort(
        (a, b) => (a.originalFileName ?? a.url).toLowerCase().compareTo(
          (b.originalFileName ?? b.url).toLowerCase(),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, cons) {
        // Audio: fixe Breite 328px, sonst dynamisch basierend auf Portrait/Landscape
        final crossAxis = _tab == 'audio'
            ? (cons.maxWidth / 328).floor().clamp(1, 6)
            : (_portrait
                  ? (cons.maxWidth / 100).floor().clamp(
                      2,
                      10,
                    ) // Portrait schmaler
                  : (cons.maxWidth / 180).floor().clamp(
                      2,
                      10,
                    )); // Landscape breiter
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxis,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            // Für Audio fixe Höhe statt AspectRatio
            mainAxisExtent: _tab == 'audio' ? 148 : null,
            // Für Nicht-Audio: 9/16 (Portrait) oder 16/9 (Landscape)
            childAspectRatio: _tab == 'audio'
                ? 1.0
                : (_portrait ? (9 / 16) : (16 / 9)),
          ),
          itemCount: view.length,
          itemBuilder: (context, i) {
            final m = view[i];
            final usage = _timeline.where((t) => t.id == m.id).length;

            // Für Audio: Column mit Kachel oben + Buttons unten
            if (_tab == 'audio') {
              final fileName = _displayName(m);
              return Column(
                children: [
                  // Kachel oben: nur Name + Zeit (wie in media_assets)
                  Expanded(
                    child: LongPressDraggable<AvatarMedia>(
                      data: m,
                      feedback: Material(
                        color: Colors.transparent,
                        child: SizedBox(
                          width: 100,
                          child: Container(
                            color: const Color(0xFF101010),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.audiotrack,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ),
                      child: GestureDetector(
                        onTap: () async {
                          setState(() {
                            _timeline.add(m);
                            _timelineKeys.add(UniqueKey());
                            _syncKeysLength();
                            _isDirty = true;
                          });
                          await _persistTimelineItems();
                        },
                        child: Stack(
                          children: [
                            // Audio-Kachel: 1:1 wie in media_assets
                            Tooltip(
                              message: fileName,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white24),
                                ),
                                clipBehavior: Clip.hardEdge,
                                child: Container(
                                  color: const Color(0xFF101010),
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        fileName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Builder(
                                        builder: (_) {
                                          final cur =
                                              _audioCurrent[m.url] ??
                                              Duration.zero;
                                          final tot =
                                              _audioDurations[m.url] ??
                                              Duration.zero;
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
                              ),
                            ),
                            if (usage > 1)
                              Positioned(
                                right: 42,
                                top: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.white30),
                                  ),
                                  child: Text(
                                    'x$usage',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                            Positioned(
                              right: 6,
                              top: 6,
                              child: InkWell(
                                onTap: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Asset entfernen?'),
                                      content: const Text(
                                        'Dieses Asset aus dem Pool entfernen? Verwendete Timeline‑Einträge werden ebenfalls gelöscht.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text('Abbrechen'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: const Text('Entfernen'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm != true) return;
                                  setState(() {
                                    _assets.removeWhere((a) => a.id == m.id);
                                    _timeline.removeWhere((t) => t.id == m.id);
                                    _syncKeysLength();
                                    _isDirty = true;
                                  });
                                  await _playlistSvc.deleteTimelineItemsByAsset(
                                    widget.playlist.avatarId,
                                    widget.playlist.id,
                                    m.id,
                                  );
                                  await _saveAssetsPool();
                                },
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(15),
                                    border: Border.all(
                                      color: Colors.white54,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Buttons UNTER der Kachel
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Builder(
                          builder: (_) {
                            final isPlaying =
                                _playingAudioUrl == m.url &&
                                ((_audioCtrls[m.url]?.value.isPlaying) == true);
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
              );
            }

            // Für Nicht-Audio: wie bisher
            return LongPressDraggable<AvatarMedia>(
              data: m,
              feedback: Material(
                color: Colors.transparent,
                child: SizedBox(width: 100, child: _buildThumb(m)),
              ),
              child: GestureDetector(
                onTap: () async {
                  setState(() {
                    _timeline.add(m);
                    _timelineKeys.add(UniqueKey());
                    _syncKeysLength();
                    _isDirty = true;
                  });
                  await _persistTimelineItems();
                },
                child: Stack(
                  children: [
                    Tooltip(
                      message:
                          '${_displayName(m)}\n${m.type.name}  AR:${(m.aspectRatio ?? 0).toStringAsFixed(2)}',
                      child: _buildThumbCard(m),
                    ),
                    if (usage > 1)
                      Positioned(
                        right: 42,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white30),
                          ),
                          child: Text(
                            'x$usage',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: InkWell(
                        onTap: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Asset entfernen?'),
                              content: const Text(
                                'Dieses Asset aus dem Pool entfernen? Verwendete Timeline‑Einträge werden ebenfalls gelöscht.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Abbrechen'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Entfernen'),
                                ),
                              ],
                            ),
                          );
                          if (confirm != true) return;
                          setState(() {
                            _assets.removeWhere((a) => a.id == m.id);
                            _timeline.removeWhere((t) => t.id == m.id);
                            _syncKeysLength();
                            _isDirty = true;
                          });
                          await _playlistSvc.deleteTimelineItemsByAsset(
                            widget.playlist.avatarId,
                            widget.playlist.id,
                            m.id,
                          );
                          await _saveAssetsPool();
                        },
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: Colors.white54,
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openAssetsPicker() async {
    // Bevor der Picker geöffnet wird: fehlende Dokument-Thumbnails generieren
    try {
      final missing = _allMedia.where(
        (m) =>
            m.type == AvatarMediaType.document && ((m.thumbUrl ?? '').isEmpty),
      );
      for (final m in missing) {
        await DocThumbService.generateAndStoreThumb(
          widget.playlist.avatarId,
          m,
        );
      }
    } catch (_) {}
    final result = await Navigator.push<List<AvatarMedia>>(
      context,
      MaterialPageRoute(
        builder: (_) => PlaylistMediaAssetsScreen(
        avatarId: widget.playlist.avatarId,
          playlistId: widget.playlist.id,
          preselected: _assets,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _assets
          ..clear()
          ..addAll(result);
        _isDirty = true;
      });
      // Nach Auswahl speichern wir die Assets sofort (Pool)
      final docs = _assets
          .map(
            (m) => {
              'id': m.id,
              'mediaId': m.id,
              'thumbUrl': m.thumbUrl ?? m.url,
              'aspectRatio': m.aspectRatio,
              'type': m.type.name,
              'createdAt': DateTime.now().millisecondsSinceEpoch,
            },
          )
          .toList();
      try {
        await _playlistSvc.setAssets(
          widget.playlist.avatarId,
          widget.playlist.id,
          docs,
        );
      } catch (e) {
    if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler beim Speichern der Assets: $e')),
          );
        }
      }
      await _load();
    }
  }

  Widget _buildTimelinePane() {
    return Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(12)),
      ),
      child: DragTarget<AvatarMedia>(
        builder: (context, cand, rej) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFE91E63).withOpacity(
                    (_timelineHover || cand.isNotEmpty) ? 0.55 : 0.3,
                  ),
                  AppColors.lightBlue.withOpacity(
                    (_timelineHover || cand.isNotEmpty) ? 0.55 : 0.3,
                  ),
                ],
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
              ),
              boxShadow: (_timelineHover || cand.isNotEmpty)
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 12,
                        spreadRadius: 1,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: _timeline.isEmpty
                ? const Center(
                    child: Text(
                      'Timeline mit Media Assets befüllen',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  )
                : ReorderableListView(
                    buildDefaultDragHandles: true,
                    proxyDecorator: (child, index, animation) => child,
                    onReorder: (oldIndex, newIndex) async {
                      // Defensive checks
                      if (oldIndex < 0 || oldIndex >= _timeline.length) return;
                      if (oldIndex >= _timelineKeys.length) return;
                      if (newIndex > _timeline.length)
                        newIndex = _timeline.length;
                      if (newIndex > oldIndex) newIndex -= 1;

                      // setState SOFORT aufrufen, BEVOR wir auf Listen zugreifen
                      setState(() {
                        // Sync vor dem Verschieben
                        _syncKeysLength();

                        // Nochmal prüfen nach Sync
                        if (oldIndex >= _timeline.length ||
                            oldIndex >= _timelineKeys.length)
                          return;

                        final it = _timeline.removeAt(oldIndex);
                        final k = _timelineKeys.removeAt(oldIndex);
                        _timeline.insert(newIndex, it);
                        _timelineKeys.insert(newIndex, k);

                        // Final Sync
                        _syncKeysLength();
                        _isDirty = true;
                      });

                      await _persistTimelineItems();
                    },
                    children: [
                      // Hard-Sync vor dem Rendern – vermeidet Null/Index-Probleme bei schnellem D&D
                      ...() {
                        _syncKeysLength();
                        return <Widget>[];
                      }(),
                      for (
                        int i = 0;
                        i <
                            (_timeline.length <= _timelineKeys.length
                                ? _timeline.length
                                : _timelineKeys.length);
                        i++
                      )
                        if (i < _timeline.length && i < _timelineKeys.length)
                          Material(
                            key: _timelineKeys[i],
                            color: Colors.transparent,
                            child: Tooltip(
                              message:
                                  '${_timeline[i].originalFileName ?? _timeline[i].url.split('/').last}\n${_timeline[i].type.name}  AR:${(_timeline[i].aspectRatio ?? 0).toStringAsFixed(2)}',
                              child: ListTile(
                                leading: _buildThumb(_timeline[i], size: 40),
                                title: Text(
                                  _displayName(_timeline[i]),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 3,
                                  style: const TextStyle(fontSize: 10),
                                ),
                                trailing: PopupMenuButton<String>(
                                  icon: const Icon(
                                    Icons.more_vert,
                                    color: Colors.white70,
                                  ),
                                  onSelected: (v) async {
                                    if (v == 'dup') {
                                      setState(() {
                                        // Defensive check
                                        if (i < _timeline.length) {
                                          _timeline.insert(i + 1, _timeline[i]);
                                          _timelineKeys.insert(
                                            i + 1,
                                            UniqueKey(),
                                          );
                                          _syncKeysLength();
                                          _isDirty = true;
                                        }
                                      });
                                      await _persistTimelineItems();
                                    } else if (v == 'del') {
                                      setState(() {
                                        // Defensive check
                                        if (i < _timeline.length &&
                                            i < _timelineKeys.length) {
                                          _timeline.removeAt(i);
                                          _timelineKeys.removeAt(i);
                                          _syncKeysLength();
                                          _isDirty = true;
                                        }
                                      });
                                      await _persistTimelineItems();
                                    }
                                  },
                                  itemBuilder: (ctx) => [
                                    const PopupMenuItem<String>(
                                      value: 'dup',
                                      child: Text('Duplizieren'),
                                    ),
                                    const PopupMenuItem<String>(
                                      value: 'del',
                                      child: Text('Aus Timeline entfernen'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                    ],
                  ),
          );
        },
        onWillAccept: (m) {
          setState(() => _timelineHover = true);
          return true;
        },
        onLeave: (m) => setState(() => _timelineHover = false),
        onAccept: (m) {
          setState(() {
            _timeline.add(m);
            _timelineKeys.add(UniqueKey());
            _syncKeysLength();
            _isDirty = true;
          });
          // Persist nach dem Hinzufügen
          _persistTimelineItems();
        },
      ),
    );
  }

  Widget _buildAssetsPane() {
    return Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.only(bottomRight: Radius.circular(12)),
      ),
      child: Column(
        children: [
          // Navigation Header wie in playlist_media_assets_screen (full width)
          SizedBox(
            width: double.infinity,
            child: Container(
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
                        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                        minimumSize: const WidgetStatePropertyAll(Size(40, 35)),
                      ),
                      child: _portrait
                          ? ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
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
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildAssetsGrid(),
            ),
          ),
        ],
      ),
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
          // Bei Dokumente/Audio automatisch auf Portrait setzen
          if (t == 'documents' || t == 'audio') _portrait = true;
        }),
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          minimumSize: const WidgetStatePropertyAll(Size(48, 35)),
        ),
        child: Container(
          width: 48,
          height: 35,
          decoration: sel && grad != null
              ? BoxDecoration(gradient: grad, borderRadius: BorderRadius.zero)
              : null,
          child: Icon(
            icon,
            size: 18,
            color: sel ? Colors.white : Colors.white54,
          ),
        ),
      ),
    );
  }

  Widget _miniNavIcon(IconData icon, bool sel, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 28,
        decoration: BoxDecoration(
          color: sel ? Colors.white12 : Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    );
  }

  Widget _buildResizer(double totalW, double leftW, double resizerW) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _resizerHover = true),
      onExit: (_) => setState(() => _resizerHover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) {
          setState(() {
            final available2 = (totalW - resizerW).clamp(0.0, double.infinity);
            const double minLeftPane2 = 100.0;
            const double minRightPane2 = 200.0;
            if (available2 <= (minLeftPane2 + minRightPane2)) return;
            final double newLeft = (leftW + d.delta.dx).clamp(
              minLeftPane2,
              available2 - minRightPane2,
            );
            _splitRatio = available2 > 0 ? (newLeft / available2) : 0.5;
          });
        },
        onHorizontalDragEnd: (_) async {
          await _playlistSvc.setTimelineSplitRatio(
            widget.playlist.avatarId,
            widget.playlist.id,
            _splitRatio,
          );
          // neuen Wert aus DB laden und setzen
          final p = await _playlistSvc.getOne(
            widget.playlist.avatarId,
            widget.playlist.id,
          );
          if (p?.timelineSplitRatio != null) {
            setState(
              () => _splitRatio = p!.timelineSplitRatio!.clamp(0.1, 0.9),
            );
          }
        },
        child: Container(
          width: resizerW,
          decoration: _resizerHover
              ? BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.magenta, AppColors.lightBlue],
                  ),
                  backgroundBlendMode: BlendMode.overlay,
                  color: const Color(0xFF1E1E1E).withValues(alpha: 0.8),
                )
              : const BoxDecoration(color: Color(0xFF1E1E1E)),
          child: Center(
            child: Container(
              width: _resizerHover ? 3 : 2,
              height: 28,
              decoration: _resizerHover
                  ? BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.magenta, AppColors.lightBlue],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    )
                  : BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  // === Audio-Player-Logik (1:1 von media_assets) ===

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
}

class _NavIcon extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _NavIcon({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 32,
        decoration: selected
            ? BoxDecoration(
                gradient: Theme.of(
                  context,
                ).extension<AppGradients>()?.magentaBlue,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              )
            : BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }
}
