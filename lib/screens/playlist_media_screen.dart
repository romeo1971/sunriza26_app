import 'package:flutter/material.dart';
import '../models/playlist_models.dart';
import '../models/media_models.dart';
import '../services/media_service.dart';
import '../services/playlist_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_text_field.dart';

class PlaylistMediaScreen extends StatefulWidget {
  final Playlist playlist;
  const PlaylistMediaScreen({super.key, required this.playlist});

  @override
  State<PlaylistMediaScreen> createState() => _PlaylistMediaScreenState();
}

class _PlaylistMediaScreenState extends State<PlaylistMediaScreen> {
  String _tab = 'images'; // images|videos|documents|audio
  bool _portrait = true;
  final _mediaSvc = MediaService();
  final _playlistSvc = PlaylistService();
  List<AvatarMedia> _allMedia = [];
  final List<AvatarMedia> _timeline = [];
  bool _showSearch = false;
  String _searchTerm = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // AppBar‑Style Tab Button (35px hoch), angelehnt an media_gallery_screen
  Widget _buildTopTabAppbarBtn(String tab, IconData icon) {
    final selected = _tab == tab;
    return SizedBox(
      height: 35,
      child: TextButton(
        onPressed: () => setState(() => _tab = tab),
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          minimumSize: const WidgetStatePropertyAll(Size(60, 35)),
          backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (selected) return const Color(0x26FFFFFF);
            return Colors.transparent;
          }),
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
        child: Icon(
          icon,
          size: 22,
          color: selected ? Colors.white : Colors.white54,
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
              // Orientierung (links von der Lupe)
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
              // Lupe rechts außen (toggle search) – GMBC wenn aktiv
              SizedBox(
                height: 35,
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      _showSearch = !_showSearch;
                      if (!_showSearch) {
                        _searchController.clear();
                        _searchTerm = '';
                      }
                    });
                  },
                  style: ButtonStyle(
                    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                    minimumSize: const WidgetStatePropertyAll(Size(60, 35)),
                    backgroundColor: WidgetStatePropertyAll(
                      _showSearch ? Colors.white : Colors.transparent,
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
                    foregroundColor: WidgetStatePropertyAll(
                      _showSearch ? AppColors.darkSurface : Colors.white,
                    ),
                    shape: WidgetStateProperty.resolveWith<OutlinedBorder>((
                      states,
                    ) {
                      final isHover =
                          states.contains(WidgetState.hovered) ||
                          states.contains(WidgetState.focused);
                      if (_showSearch || isHover)
                        return const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        );
                      return RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      );
                    }),
                  ),
                  child: _showSearch
                      ? ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [AppColors.magenta, AppColors.lightBlue],
                          ).createShader(bounds),
                          child: const Icon(
                            Icons.search,
                            size: 22,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.search,
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
      setState(() => _allMedia = list);
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
                      Text(
                        'Anzeige ab Chat-Start: ${widget.playlist.showAfterSec}s',
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

          // Navi im Stil der Media-Galerie (unter dem Header)
          _buildTopNavBar(),
          const SizedBox(height: 8),

          // Kombinierter Container: FullWidth-Header, darunter links Timeline, rechts Medien
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  children: [
                    // FullWidth Header mit nur einem Titel (Tab)
                    Container(
                      height: 44,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.lightGreen.withOpacity(0.18),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _tab == 'images'
                                ? 'Bilder'
                                : _tab == 'videos'
                                ? 'Videos'
                                : _tab == 'documents'
                                ? 'Dokumente'
                                : 'Audio',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          if (_showSearch)
                            SizedBox(
                              height: 32,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 160,
                                  minWidth: 160,
                                ),
                                child: CustomTextField(
                                  label: 'Suche nach Medien...',
                                  controller: _searchController,
                                  style: const TextStyle(fontSize: 12),
                                  prefixIcon: const Padding(
                                    padding: EdgeInsets.only(left: 6),
                                    child: Icon(
                                      Icons.search,
                                      color: Colors.white70,
                                      size: 18,
                                    ),
                                  ),
                                  prefixIconConstraints: const BoxConstraints(
                                    minWidth: 24,
                                    maxWidth: 28,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 10,
                                  ),
                                  onChanged: (value) {
                                    setState(() {
                                      _searchTerm = value.toLowerCase();
                                    });
                                  },
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          // Timeline links
                          Expanded(
                            flex: 1,
                            child: Container(
                              decoration: const BoxDecoration(
                                borderRadius: BorderRadius.only(
                                  bottomLeft: Radius.circular(12),
                                ),
                              ),
                              child: DragTarget<AvatarMedia>(
                                builder: (context, cand, rej) {
                                  return Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          const Color(0xFFE91E63).withOpacity(
                                            cand.isNotEmpty ? 0.4 : 0.3,
                                          ),
                                          AppColors.lightBlue.withOpacity(
                                            cand.isNotEmpty ? 0.4 : 0.3,
                                          ),
                                        ],
                                      ),
                                      borderRadius: const BorderRadius.only(
                                        bottomLeft: Radius.circular(12),
                                      ),
                                    ),
                                    child: _timeline.isEmpty
                                        ? const Center(
                                            child: Text(
                                              'Medien per Drag & Drop Hier her',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: Colors.white60,
                                                fontSize: 13,
                                              ),
                                            ),
                                          )
                                        : ReorderableListView(
                                            onReorder: (oldIndex, newIndex) {
                                              if (newIndex > oldIndex)
                                                newIndex -= 1;
                                              final it = _timeline.removeAt(
                                                oldIndex,
                                              );
                                              _timeline.insert(newIndex, it);
                                              setState(() {});
                                            },
                                            children: [
                                              for (
                                                int i = 0;
                                                i < _timeline.length;
                                                i++
                                              )
                                                ListTile(
                                                  key: ValueKey(
                                                    _timeline[i].id,
                                                  ),
                                                  leading: _buildThumb(
                                                    _timeline[i],
                                                    size: 40,
                                                  ),
                                                  title: Text(
                                                    _timeline[i]
                                                            .originalFileName ??
                                                        _timeline[i].url
                                                            .split('/')
                                                            .last,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  trailing: const Icon(
                                                    Icons.drag_handle,
                                                  ),
                                                ),
                                            ],
                                          ),
                                  );
                                },
                                onAccept: (m) =>
                                    setState(() => _timeline.add(m)),
                              ),
                            ),
                          ),
                          // Medienliste rechts
                          Expanded(
                            flex: 2,
                            child: Container(
                              decoration: const BoxDecoration(
                                borderRadius: BorderRadius.only(
                                  bottomRight: Radius.circular(12),
                                ),
                              ),
                              padding: const EdgeInsets.all(16),
                              child: _buildMediaGrid(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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
      content = const Center(
        child: Icon(Icons.videocam, color: Colors.white70),
      );
    } else if (m.type == AvatarMediaType.document) {
      final thumb = m.thumbUrl ?? m.url;
      content = Image.network(
        thumb,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Center(child: Icon(Icons.description, color: Colors.white70)),
      );
    } else {
      content = const Center(
        child: Icon(Icons.audiotrack, color: Colors.white70),
      );
    }
    // Zeige Medien im eigenen Seitenverhältnis (Portrait/Landscape korrekt),
    // ohne starre Kachelgröße – passt sich der verfügbaren Breite an
    final aspect = AspectRatio(aspectRatio: ar, child: content);
    if (size != null) return SizedBox(width: size, child: aspect);
    return aspect;
  }

  Future<void> _saveTimeline() async {
    // Persistiere Reihenfolge: existierende Items ersetzen
    // 1) Liste vorhandener Items laden
    final existing = await _playlistSvc.listItems(
      widget.playlist.avatarId,
      widget.playlist.id,
    );
    // 2) Vorhandene Items löschen
    for (final it in existing) {
      await _playlistSvc.deleteItem(
        widget.playlist.avatarId,
        widget.playlist.id,
        it.id,
      );
    }
    // 3) Neue Reihenfolge schreiben
    for (int i = 0; i < _timeline.length; i++) {
      await _playlistSvc.addItem(
        widget.playlist.avatarId,
        widget.playlist.id,
        _timeline[i].id,
        order: i,
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Timeline gespeichert')));
    }
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
