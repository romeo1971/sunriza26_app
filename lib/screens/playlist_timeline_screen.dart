import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  static const double _minPaneWidth = 240.0;
  bool _showSearch = false;
  String _searchTerm = '';
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _intervalCtl = TextEditingController();
  bool _timelineHover = false;
  bool _resizerHover = false;
  String _assetSort = 'name'; // 'name' | 'type'
  final TextEditingController _assetsSearchCtl = TextEditingController();
  String _assetsSearchTerm = '';

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
  }

  @override
  void dispose() {
    _searchController.dispose();
    _assetsSearchCtl.dispose();
    _intervalCtl.dispose();
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
        child: selected
            ? Ink(
                decoration: BoxDecoration(
                  gradient: appGrad,
                  borderRadius: BorderRadius.zero,
                ),
                child: SizedBox(
                  width: tabWidth,
                  height: double.infinity,
                  child: Icon(icon, size: 22, color: Colors.white),
                ),
              )
            : SizedBox(
                width: tabWidth,
                height: double.infinity,
                child: Icon(icon, size: 22, color: Colors.white54),
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
                      ? ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [AppColors.magenta, AppColors.lightBlue],
                          ).createShader(bounds),
                          child: const Icon(
                            Icons.stay_primary_portrait,
                            size: 22,
                            color: Colors.white,
                          ),
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
    final coverW = 60.0; // halb so groß wie in playlist_edit_screen (120)
    final coverH = 106.5; // halb so groß wie 213

    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlist Medien'),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
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
          // Header: kleines Cover, Name, Anzeigezeit
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: coverW,
                  height: coverH,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade800,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade600),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: widget.playlist.coverImageUrl != null
                      ? Image.network(
                          widget.playlist.coverImageUrl!,
                          fit: BoxFit.cover,
                        )
                      : const Center(
                          child: Icon(
                            Icons.image_outlined,
                            color: Colors.white54,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.playlist.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Zeit-Intervall:',
                            style: TextStyle(fontSize: 12),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: 'Anzeigezeit der Medien in Sekunden',
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minWidth: 40),
                              child: IntrinsicWidth(
                                child: TextField(
                                  controller: _intervalCtl,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  cursorColor: Colors.white,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    hintText: '0',
                                    filled: true,
                                    fillColor: Color(0x1FFFFFFF),
                                    border: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Colors.white24,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Colors.white24,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Colors.white24,
                                      ),
                                    ),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                  ),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_timeline.length} Medien in der Playlist',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // (entfernt) Galerie-Navi – gehört nur in den Assets-Screen
          const SizedBox(height: 8),

          // Call-to-Action: Medien hinzufügen (öffnet Asset-Auswahl)
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
                        'Medien hinzufügen',
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
                        // konstante Mindestbreite je Pane für maximale Beweglichkeit
                        const double minPane = 32.0;
                        if (available <= 2 * minPane) {
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
                        final double minLeft = minPane;
                        final double maxLeft = (available - minPane).clamp(
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
                          Expanded(
                            child: Container(
                              decoration: const BoxDecoration(
                                borderRadius: BorderRadius.only(
                                  bottomRight: Radius.circular(12),
                                ),
                              ),
                              padding: const EdgeInsets.all(16),
                                child: _buildAssetsGrid(),
                            ),
                          ),
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

        content = Container(
          color: const Color(0xFF101010),
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.play_arrow, color: Colors.white70, size: 20),
                  SizedBox(width: 12),
                  Icon(Icons.pause, color: Colors.white38, size: 20),
                  SizedBox(width: 12),
                  Icon(Icons.replay, color: Colors.white38, size: 20),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _displayName(m),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                fmt(),
                style: const TextStyle(fontSize: 11, color: Colors.white54),
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
          'Keine Assets ausgewählt',
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
          break;
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
        final crossAxis = (cons.maxWidth / 120).floor().clamp(2, 10);
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxis,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1,
          ),
          itemCount: view.length,
          itemBuilder: (context, i) {
            final m = view[i];
            final usage = _timeline.where((t) => t.id == m.id).length;
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
                        right: 6,
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
                      bottom: 6,
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
                          });
                          await _playlistSvc.deleteTimelineItemsByAsset(
                            widget.playlist.avatarId,
                            widget.playlist.id,
                            m.id,
                          );
                          await _saveAssetsPool();
                        },
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white30),
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 14,
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
                      'Medien per Drag & Drop Hier her',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  )
                : ReorderableListView(
                    buildDefaultDragHandles: true,
                    proxyDecorator: (child, index, animation) => child,
                    onReorder: (oldIndex, newIndex) async {
                      if (oldIndex < 0 || oldIndex >= _timeline.length) return;
                      if (newIndex > _timeline.length)
                        newIndex = _timeline.length;
                      if (newIndex > oldIndex) newIndex -= 1;
                      final it = _timeline.removeAt(oldIndex);
                      final k = _timelineKeys.removeAt(oldIndex);
                      _timeline.insert(newIndex, it);
                      _timelineKeys.insert(newIndex, k);
                      setState(_syncKeysLength);
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
                              ),
                              trailing: PopupMenuButton<String>(
                                icon: const Icon(
                                  Icons.more_vert,
                                  color: Colors.white70,
                                ),
                                onSelected: (v) async {
                                  if (v == 'dup') {
                                    setState(() {
                                      _timeline.insert(i + 1, _timeline[i]);
                                      _timelineKeys.insert(i + 1, UniqueKey());
                                      _syncKeysLength();
                                    });
                                    await _persistTimelineItems();
                                  } else if (v == 'del') {
                                    setState(() {
                                      _timeline.removeAt(i);
                                      _timelineKeys.removeAt(i);
                                      _syncKeysLength();
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
        onAccept: (m) => setState(() {
          _timeline.add(m);
          _timelineKeys.add(UniqueKey());
          _syncKeysLength();
        }),
      ),
    );
  }

  Widget _buildAssetsPane() {
    return Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.only(bottomRight: Radius.circular(12)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              // kleine Navi
              _miniNavIcon(
                Icons.image_outlined,
                _tab == 'images',
                () => setState(() => _tab = 'images'),
              ),
              const SizedBox(width: 8),
              _miniNavIcon(
                Icons.videocam_outlined,
                _tab == 'videos',
                () => setState(() => _tab = 'videos'),
              ),
              const SizedBox(width: 8),
              _miniNavIcon(
                Icons.description_outlined,
                _tab == 'documents',
                () => setState(() => _tab = 'documents'),
              ),
              const SizedBox(width: 8),
              _miniNavIcon(
                Icons.audiotrack,
                _tab == 'audio',
                () => setState(() => _tab = 'audio'),
              ),
              const Spacer(),
              // Portrait/Landscape Toggle klein
              InkWell(
                onTap: () => setState(() => _portrait = !_portrait),
                child: Container(
                  width: 36,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Icon(
                    _portrait
                        ? Icons.stay_primary_portrait
                        : Icons.stay_primary_landscape,
                    size: 16,
                    color: Colors.white70,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                onSelected: (v) => setState(() => _assetSort = v),
                itemBuilder: (ctx) => const [
                  PopupMenuItem(value: 'name', child: Text('Sortieren: Name')),
                  PopupMenuItem(value: 'type', child: Text('Sortieren: Typ')),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.sort, color: Colors.white70, size: 18),
                    SizedBox(width: 6),
                    Text('Sortieren', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildAssetsGrid()),
        ],
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
            const double minPane2 = 32.0;
            if (available2 <= 2 * minPane2) return;
            final double newLeft = (leftW + d.delta.dx).clamp(
              minPane2,
              available2 - minPane2,
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
          color: _resizerHover ? Colors.white10 : Colors.transparent,
          child: Center(
            child: Container(
              width: _resizerHover ? 3 : 2,
              height: 28,
              color: _resizerHover ? Colors.white54 : Colors.white24,
            ),
          ),
        ),
      ),
    );
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
