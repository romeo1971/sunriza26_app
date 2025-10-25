import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/playlist_models.dart';
import '../models/media_models.dart';
import '../services/media_service.dart';
import '../services/playlist_service.dart';
import '../theme/app_theme.dart';
import 'playlist_media_assets_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import '../services/doc_thumb_service.dart';

class PlaylistTimelineScreen extends StatefulWidget {
  final Playlist playlist;
  const PlaylistTimelineScreen({super.key, required this.playlist});

  @override
  State<PlaylistTimelineScreen> createState() => _PlaylistTimelineScreenState();
}

class _PlaylistTimelineScreenState extends State<PlaylistTimelineScreen>
    with SingleTickerProviderStateMixin {
  String _tab = 'images'; // images|videos|documents|audio
  bool _portrait = true;
  bool _showAssets = true; // Toggle: Media Assets sichtbar
  final bool _showTimeline = true; // Toggle: Timeline sichtbar
  final _mediaSvc = MediaService();
  final _playlistSvc = PlaylistService();
  List<AvatarMedia> _allMedia = [];
  final List<AvatarMedia> _timeline = [];
  final List<Key> _timelineKeys = [];
  // Persistente Entry-IDs (Firestore doc.id) je Timeline-Item
  final List<String> _timelineEntryIds = [];
  final List<AvatarMedia> _assets = []; // rechte Seite: Timeline-Assets
  // (entfernt) alter horizontaler Split-Ratio
  // double _splitRatio = 0.38;
  // ignore: unused_field
  final bool _showSearch = false;
  final String _searchTerm = '';
  final TextEditingController _searchController = TextEditingController();
  bool _timelineHover = false;
  // (entfernt) alter Resizer-Hover
  // bool _resizerHover = false;
  final String _assetSort = 'name'; // 'name' | 'type'
  final TextEditingController _assetsSearchCtl = TextEditingController();
  String _assetsSearchTerm = '';
  bool _isDirty = false; // Trackt ob Änderungen vorgenommen wurden
  bool _searchOpen = false; // toggled Search in CTA-Zeile
  // Verzögerung pro Timeline-Asset (Sekunden bis Einblendung im Chat)
  final Map<String, int> _itemDelaySec = {};
  // Sichtbarkeit pro Timeline-Asset (on/off wie HeroImages)
  final Map<String, bool> _itemEnabled = {};
  // Timeline Playback/Enable Toggles
  bool _timelineLoop = true;
  bool _timelineEnabled = true;

  String _formatMmSs(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  int _getItemMinutes(int index) {
    // Verwende Timeline-Index als eindeutige ID für jeden Entry
    final timelineId = 'timeline_$index';
    final sec = _itemDelaySec[timelineId] ?? 60; // Default 1 Min
    return (sec / 60).round().clamp(1, 30);
  }

  // NEUE Methode für Timeline mit entryId = playlistId + timestamp
  String _getTimelineEntryId(int index) {
    // Stabile ID: aus Firestore oder lokal erzeugt und gemerkt
    if (index < _timelineEntryIds.length &&
        _timelineEntryIds[index].isNotEmpty) {
      return _timelineEntryIds[index];
    }
    // Fallback: generiere neue ID und speichere sie lokal, bis persistiert
    final media = (index < _timeline.length) ? _timeline[index] : null;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    // Gewünscht: timelineAssetsId (== media.id) + timestamp
    final generated = '${media?.id ?? 'asset'}_$stamp';
    if (index >= _timelineEntryIds.length) {
      _timelineEntryIds.add(generated);
    } else {
      _timelineEntryIds[index] = generated;
    }
    return generated;
  }

  int _getTimelineItemMinutes(int index) {
    final entryId = _getTimelineEntryId(index);
    final sec = _itemDelaySec[entryId] ?? 60; // Default 1 Min
    return (sec / 60).round().clamp(1, 30);
  }

  // NEUE Methode für Timeline-Dropdown-Anzeige
  int _getTimelineDisplayMinutes(int index) {
    // Berechne den Anzeigezeitpunkt basierend auf dem Vorgänger
    if (index == 0) return 1; // Erster Entry startet bei 1 Min

    int startMinutes = 0;
    for (int k = 0; k < index; k++) {
      final timelineId = 'timeline_$k';
      final sec = _itemDelaySec[timelineId] ?? 60;
      startMinutes += (sec / 60).round();
    }
    // Begrenze auf 1-30 für Dropdown
    return (startMinutes + 1).clamp(1, 30);
  }

  Future<void> _setItemMinutes(int index, int minutes) async {
    // Verwende Timeline-Index als eindeutige ID für jeden Entry
    final timelineId = 'timeline_$index';
    final sec = (minutes.clamp(1, 30)) * 60;
    setState(() => _itemDelaySec[timelineId] = sec);
    try {
      final items = await _playlistSvc.listTimelineItems(
        widget.playlist.avatarId,
        widget.playlist.id,
      );
      if (index < items.length) {
        final itemId = items[index]['id'] as String?;
        if (itemId != null) {
          await FirebaseFirestore.instance
              .collection('avatars')
              .doc(widget.playlist.avatarId)
              .collection('playlists')
              .doc(widget.playlist.id)
              .collection('timelineItems')
              .doc(itemId)
              .set({'delaySec': sec}, SetOptions(merge: true));
        }
      }
    } catch (_) {}
  }

  // NEUE Methode für Timeline mit entryId - speichert alle Felder
  Future<void> _setTimelineItemMinutes(int index, int minutes) async {
    final entryId = _getTimelineEntryId(index);
    final sec = (minutes.clamp(1, 30)) * 60;
    setState(() => _itemDelaySec[entryId] = sec);

    try {
      final items = await _playlistSvc.listTimelineItems(
        widget.playlist.avatarId,
        widget.playlist.id,
      );
      if (index < items.length) {
        final itemId = items[index]['id'] as String?;
        if (itemId != null) {
          // Berechne Startzeit (kumulative Summe aller Vorgänger)
          int startTime = 0;
          for (int k = 0; k < index; k++) {
            final prevEntryId = _getTimelineEntryId(k);
            startTime += (_itemDelaySec[prevEntryId] ?? 60);
          }

          await FirebaseFirestore.instance
              .collection('avatars')
              .doc(widget.playlist.avatarId)
              .collection('playlists')
              .doc(widget.playlist.id)
              .collection('timelineItems')
              .doc(itemId)
              .set({
                'eindeutigeId': entryId,
                'minDropdown': minutes,
                'timeStartzeit': startTime,
                'delaySec': sec,
                'activity': true, // initial=true
              }, SetOptions(merge: true));
        }
      }
    } catch (_) {}
  }

  // NEUE Methode für Timeline-Dropdown-Setzen
  Future<void> _setTimelineDisplayMinutes(int index, int minutes) async {
    // Berechne die Dauer basierend auf dem gewählten Anzeigezeitpunkt
    int durationMinutes;
    if (index == 0) {
      durationMinutes = minutes; // Erster Entry: Dauer = Anzeigezeitpunkt
    } else {
      // Berechne Dauer = Anzeigezeitpunkt - Summe der Vorgänger
      int previousSum = 0;
      for (int k = 0; k < index; k++) {
        final timelineId = 'timeline_$k';
        final sec = _itemDelaySec[timelineId] ?? 60;
        previousSum += (sec / 60).round();
      }
      durationMinutes = minutes - previousSum;
    }

    final sec = (durationMinutes.clamp(1, 30)) * 60;
    final timelineId = 'timeline_$index';
    setState(() => _itemDelaySec[timelineId] = sec);

    try {
      final items = await _playlistSvc.listTimelineItems(
        widget.playlist.avatarId,
        widget.playlist.id,
      );
      if (index < items.length) {
        final itemId = items[index]['id'] as String?;
        if (itemId != null) {
          await FirebaseFirestore.instance
              .collection('avatars')
              .doc(widget.playlist.avatarId)
              .collection('playlists')
              .doc(widget.playlist.id)
              .collection('timelineItems')
              .doc(itemId)
              .set({'delaySec': sec}, SetOptions(merge: true));
        }
      }
    } catch (_) {}
  }

  List<int> _computeStartEndSeconds(int index) {
    // Verwende die Dropdown-Logik für die Zeitanzeige
    int start = 0;
    for (int k = 0; k < index; k++) {
      final timelineId = 'timeline_$k';
      start += (_itemDelaySec[timelineId] ?? 60);
    }
    final timelineId = 'timeline_$index';
    final cur = (_itemDelaySec[timelineId] ?? 60);
    return [start, start + cur];
  }

  // NEUE Methode für Timeline-Zeitanzeige - zeigt Anzeigezeitpunkt
  // List<int> _computeTimelineDisplayTime(int index) {
  //   // Berechne Anzeigezeitpunkt basierend auf Dropdown-Werten
  //   int displayTime = 0;
  //   for (int k = 0; k < index; k++) {
  //     final timelineId = 'timeline_$k';
  //     displayTime += (_itemDelaySec[timelineId] ?? 60);
  //   }
  //   // Anzeigezeitpunkt = Summe aller Vorgänger
  //   return [displayTime, displayTime];
  // }

  // KORREKTE Methode für Timeline-Zeitanzeige - zeigt kumulativen Anzeigezeitpunkt
  List<int> _computeTimelineDisplayTimeCorrect(int index) {
    // Berechne kumulative Summe aller Vorgänger + aktueller Wert
    int displayTime = 0;
    for (int k = 0; k <= index; k++) {
      final timelineId = 'timeline_$k';
      displayTime += (_itemDelaySec[timelineId] ?? 60);
    }
    return [displayTime, displayTime];
  }

  // NEUE Methode für Timeline mit entryId - zeigt kumulativen Anzeigezeitpunkt
  List<int> _computeTimelineDisplayTimeWithEntryId(int index) {
    // Berechne kumulative Summe NUR für AKTIVE Entries
    int displayTime = 0;
    for (int k = 0; k <= index; k++) {
      final entryId = _getTimelineEntryId(k);
      final isActive = _itemEnabled[entryId] ?? true;
      if (isActive) {
        displayTime += (_itemDelaySec[entryId] ?? 60);
      }
    }
    return [displayTime, displayTime];
  }

  // Toggle activity for a single timeline entry and persist
  Future<void> _toggleEntryActivity(int index) async {
    final entryId = _getTimelineEntryId(index);
    final newVal = !(_itemEnabled[entryId] ?? true);
    setState(() => _itemEnabled[entryId] = newVal);
    try {
      final items = await _playlistSvc.listTimelineItems(
        widget.playlist.avatarId,
        widget.playlist.id,
      );
      if (index < items.length) {
        final itemId = items[index]['id'] as String?;
        if (itemId != null) {
          await FirebaseFirestore.instance
              .collection('avatars')
              .doc(widget.playlist.avatarId)
              .collection('playlists')
              .doc(widget.playlist.id)
              .collection('timelineItems')
              .doc(itemId)
              .set({'activity': newVal}, SetOptions(merge: true));
        }
      }
    } catch (_) {}
  }

  // (entfernt) Breiten-Anker – nicht mehr nötig im vertikalen Layout

  // Puls-Animation für CTA, wenn noch keine Assets vorhanden sind
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  // Audio-Player-Logik (wie in media_assets)
  final Map<String, VideoPlayerController> _audioCtrls = {};
  final Map<String, Duration> _audioDurations = {};
  String? _playingAudioUrl;
  final Map<String, Duration> _audioCurrent = {};
  final Set<String> _audioHasListener = {};
  Timer? _audioTicker;
  bool _loading = false; // Ladezustand für sanfte UI
  bool _firstLoadDone = false; // verhindert flackernde Start-UI

  // Vertikaler Split (Assets oben, Timeline unten)
  double _verticalRatio = 0.55; // Anteil Assets-Höhe
  bool _vResizerHover = false;

  String _displayName(AvatarMedia m) {
    final ofn = m.originalFileName;
    if ((ofn ?? '').trim().isNotEmpty) {
      return ofn!.trim();
    }
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
    // Puls-Animation initialisieren
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    // Puls über Opacity: 0.3 ↔ 1.0
    _pulse = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).chain(CurveTween(curve: Curves.easeInOut)).animate(_pulseCtrl);
    _load();
    _assetsSearchCtl.addListener(() {
      setState(() => _assetsSearchTerm = _assetsSearchCtl.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    // Puls-Animation freigeben
    try {
      _pulseCtrl.dispose();
    } catch (_) {}
    _searchController.dispose();
    _assetsSearchCtl.dispose();
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
            if (selected || isHover) {
              return const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              );
            }
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

  // ignore: unused_element
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
                      if (isHover) {
                        return const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        );
                      }
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
    if (mounted) setState(() => _loading = true);
    try {
      final list = await _mediaSvc.list(widget.playlist.avatarId);
      _allMedia = list;
      // gespeichertes Split-Verhältnis anwenden, falls vorhanden
      // (alt) horizontale Split-Ratio wird nicht mehr genutzt
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
      // EntryIds aus Firestore übernehmen (Doc-IDs)
      _timelineEntryIds
        ..clear()
        ..addAll(items2.map((it) => (it['id'] as String?) ?? ''));
      
      // DelaySec und Activity aus Firestore in Maps laden
      _itemDelaySec.clear();
      _itemEnabled.clear();
      for (final it in items2) {
        final entryId = it['id'] as String?;
        if (entryId != null && entryId.isNotEmpty) {
          _itemDelaySec[entryId] = it['delaySec'] as int? ?? 60;
          _itemEnabled[entryId] = it['activity'] as bool? ?? true;
        }
      }
      
      _timelineKeys
        ..clear()
        ..addAll(List.generate(_timeline.length, (_) => UniqueKey()));
      
      // Loop/Enabled Status aus Firestore laden
      final doc = await FirebaseFirestore.instance
          .collection('avatars')
          .doc(widget.playlist.avatarId)
          .collection('playlists')
          .doc(widget.playlist.id)
          .get();
      
      if (doc.exists) {
        final data = doc.data();
        _timelineLoop = data?['timelineLoop'] as bool? ?? true;
        _timelineEnabled = data?['timelineEnabled'] as bool? ?? true;
      }
      
      if (mounted) setState(() {});
    } catch (_) {}
    if (mounted) {
      setState(() {
        _loading = false;
        _firstLoadDone = true;
      });
    }
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

  Widget _gradientSpinner({double size = 40}) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [AppColors.magenta, AppColors.lightBlue],
      ).createShader(bounds),
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: 4,
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          backgroundColor: Colors.transparent,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final coverW = 100.0; // gleich wie in playlist_list_screen
    final coverH = 178.0; // gleich wie in playlist_list_screen

    if (!_firstLoadDone) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Timeline'),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(child: _gradientSpinner(size: 44)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Timeline'),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
            IconButton(
            tooltip: _showAssets ? 'Media aus' : 'Media an',
            onPressed: () => setState(() => _showAssets = !_showAssets),
            icon: _showAssets
                ? ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFFE91E63), Color(0xFF64B5F6)],
                    ).createShader(bounds),
                    child: const Icon(
                      Icons.layers,
                      color: Colors.white,
                    ),
                  )
                : const Icon(
                    Icons.layers_outlined,
                    color: Colors.grey,
                  ),
            ),
          const SizedBox(width: 4),
        ],
        // Keine Bottom‑Tabs hier – Tabs kommen unter den Header
      ),
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Cover + Name (einheitlich strukturiert)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
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
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 12),
                            // Abstand entfernt – CTA direkt unter Navi
                            Text(                              
                              '${_timeline.length} Medien in der Playlist',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Loop/Ende ON/OFF Toggle
                            Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Loop/Ende Teil
                                        InkWell(
                                          onTap: () async {
                                            setState(() => _timelineLoop = !_timelineLoop);
                                            await FirebaseFirestore.instance
                                                .collection('avatars')
                                                .doc(widget.playlist.avatarId)
                                                .collection('playlists')
                                                .doc(widget.playlist.id)
                                                .set({'timelineLoop': _timelineLoop}, SetOptions(merge: true));
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              gradient: _timelineLoop
                                                  ? Theme.of(context).extension<AppGradients>()!.magentaBlue
                                                  : null,
                                              borderRadius: const BorderRadius.only(
                                                topLeft: Radius.circular(4),
                                                bottomLeft: Radius.circular(4),
                                              ),
                                            ),
                                            child: SizedBox(
                                              width: 30,
                                              child: Center(
                                                child: Text(
                                                  _timelineLoop ? 'Loop' : 'Ende',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        // Pipe
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 6),
                                          child: Text(
                                            '|',
                                            style: TextStyle(
                                              color: Colors.white.withValues(alpha: 0.5),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w300,
                                            ),
                                          ),
                                        ),
                                        // ON/OFF Teil
                                        InkWell(
                                          onTap: () async {
                                            setState(() => _timelineEnabled = !_timelineEnabled);
                                            await FirebaseFirestore.instance
                                                .collection('avatars')
                                                .doc(widget.playlist.avatarId)
                                                .collection('playlists')
                                                .doc(widget.playlist.id)
                                                .set({'timelineEnabled': _timelineEnabled}, SetOptions(merge: true));
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              gradient: _timelineEnabled
                                                  ? Theme.of(context).extension<AppGradients>()!.magentaBlue
                                                  : null,
                                              borderRadius: const BorderRadius.only(
                                                topRight: Radius.circular(4),
                                                bottomRight: Radius.circular(4),
                                              ),
                                            ),
                                            child: SizedBox(
                                              width: 24,
                                              child: Center(
                                                child: Text(
                                                  _timelineEnabled ? 'ON' : 'OFF',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w500,
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
                      ),
                    ],
                  ),
                ),
              ),

              // (entfernt) Galerie-Navi – gehört nur in den Assets-Screen

              // Neue Struktur: Tabs/Navi (oben), darunter CTA-Zeile mit Suche-Toggle
              // Navi oben (nur Tabs + Orientation) – direkt an das Cover anschließen
              if (_showAssets)
              LayoutBuilder(
                builder: (context, cons) {
                  final bool roomy = cons.maxWidth >= (4 * 48 + 40 + 16);
                  final double tabW = roomy ? 48 : 36;
                  final double iconSize = roomy ? 18 : 16;
                  return Container(
                    color: const Color(0xFF1E1E1E),
                    height: 35,
                    padding: EdgeInsets.zero,
                    child: Row(
                      children: [
                        _tabBtn(
                          'images',
                          Icons.image_outlined,
                          tabW: tabW,
                          iconSize: iconSize,
                        ),
                        _tabBtn(
                          'videos',
                          Icons.videocam_outlined,
                          tabW: tabW,
                          iconSize: iconSize,
                        ),
                        _tabBtn(
                          'documents',
                          Icons.description_outlined,
                          tabW: tabW,
                          iconSize: iconSize,
                        ),
                        _tabBtn(
                          'audio',
                          Icons.audiotrack,
                          tabW: tabW,
                          iconSize: iconSize,
                        ),
                        const Spacer(),
                        const SizedBox(width: 12),
                        if (_tab != 'audio')
                          TextButton(
                            onPressed: () =>
                                setState(() => _portrait = !_portrait),
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
                                      shaderCallback: (b) =>
                                          const LinearGradient(
                                      colors: [
                                        AppColors.magenta,
                                        AppColors.lightBlue,
                                      ],
                                    ).createShader(b),
                                    child: Icon(
                                      Icons.stay_primary_portrait,
                                      size: iconSize,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    Icons.stay_primary_landscape,
                                    size: iconSize,
                                    color: Colors.white54,
                                  ),
                          ),
                      ],
                    ),
                  );
                },
              ),

              // CTA-Zeile unter Navi: +Media links, Search-Toggle rechts
              if (_showAssets)
              Container(
                height: 35,
                color: Colors.grey.shade900,
                padding: const EdgeInsets.only(left: 12, right: 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (!_searchOpen)
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _assets.isEmpty
                              ? FadeTransition(
                                  opacity: _pulse,
                                  child: InkWell(
                                    onTap: _openAssetsPicker,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(
                                          Icons.add,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          'Media Assets',
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : InkWell(
                                  onTap: _openAssetsPicker,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(
                                        Icons.add,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Media',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      )
                    else
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 300),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: SizedBox(
                                height: 32,
                                child: TextField(
                                  controller: _assetsSearchCtl,
                                  onChanged: (v) => setState(
                                    () => _assetsSearchTerm = v.toLowerCase(),
                                  ),
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
                                      vertical: 8,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 12),
                    // Lupe rechts: toggelt Suche, Hintergrund weiß, Icon GMBC bei aktiv
                    InkWell(
                      onTap: () => setState(() => _searchOpen = !_searchOpen),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        width: 48,
                        height: 35,
                        decoration: BoxDecoration(
                          color: _searchOpen ? Colors.white : Colors.white10,
                          borderRadius: BorderRadius.zero,
                        ),
                        child: Center(
                          child: _searchOpen
                              ? ShaderMask(
                                  shaderCallback: (b) => const LinearGradient(
                                    colors: [
                                      AppColors.magenta,
                                      AppColors.lightBlue,
                                    ],
                                  ).createShader(b),
                                  child: const Icon(
                                    Icons.search,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                )
                              : const Icon(
                                  Icons.search,
                                  color: Colors.white70,
                                  size: 18,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Vertikaler Split: Oben Assets, unten Timeline, 100% Breite
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    // keine Border unten um den Split-Container
                  ),
                  child: LayoutBuilder(
                    builder: (context, cons) {
                      final totalH = cons.maxHeight;
                      final double resizerH = _showAssets ? 12.0 : 0.0;
                      final double available = (totalH - resizerH).clamp(
                        0.0,
                        double.infinity,
                      );
                      double topH = _showAssets
                          ? (_verticalRatio * available).clamp(
                        120.0,
                        available - 120.0,
                            )
                          : 0.0;
                      final double bottomH = _showAssets
                          ? (available - topH)
                          : totalH;
                      return Column(
                        children: [
                          if (_showAssets)
                            SizedBox(height: topH, child: _buildAssetsPane())
                          else
                            const SizedBox.shrink(),
                          if (_showAssets)
                          _buildVerticalResizer(available, topH, resizerH),
                          SizedBox(
                            height: bottomH,
                            child: Column(
                              children: [
                                if (!_showAssets)
                                  Container(
                                    width: double.infinity,
                                    height: 35,
                                    color: Colors.grey.shade900,
                                    padding: const EdgeInsets.only(
                                      left: 12,
                                      right: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        const Text(
                                          'Timeline',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                Expanded(child: _buildTimelinePane()),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              // Entfernt: Fußzeile mit "Speichern"-Button – Speichern jetzt oben rechts in der AppBar
            ],
          ),
          if (_loading && _firstLoadDone)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.5),
                child: Center(child: _gradientSpinner(size: 44)),
              ),
            ),
        ],
      ),
    );
  }

  // ignore: unused_element
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
      if ((m.thumbUrl ?? '').isNotEmpty) {
        content = Image.network(
          m.thumbUrl!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              const Center(child: Icon(Icons.videocam, color: Colors.white70)),
        );
      } else {
        content = const Center(
          child: Icon(Icons.videocam, color: Colors.white70),
        );
      }
    } else if (m.type == AvatarMediaType.document) {
      if ((m.thumbUrl ?? '').isNotEmpty) {
        content = Image.network(
          m.thumbUrl!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const Center(
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
    for (int i = 0; i < _timeline.length; i++) {
      final m = _timeline[i];
      final entryId =
          (i < _timelineEntryIds.length && _timelineEntryIds[i].isNotEmpty)
          ? _timelineEntryIds[i]
          : _getTimelineEntryId(i);
      _timelineEntryIds.length <= i
          ? _timelineEntryIds.add(entryId)
          : _timelineEntryIds[i] = entryId;
      final delaySec = _itemDelaySec[entryId] ?? 60;
      int startSec = 0;
      for (int k = 0; k < i; k++) {
        final prevId =
            (k < _timelineEntryIds.length && _timelineEntryIds[k].isNotEmpty)
            ? _timelineEntryIds[k]
            : _getTimelineEntryId(k);
        startSec += (_itemDelaySec[prevId] ?? 60);
      }
      itemDocs.add({
        'id': entryId,
        'assetId': m.id,
        'delaySec': delaySec,
        'minutes': (delaySec / 60).round(),
        'startSec': startSec,
        'activity': _itemEnabled[entryId] ?? true,
        'nameSnapshot': _displayName(m),
        'type': m.type.name,
        'thumbUrl': m.thumbUrl ?? m.url,
      });
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
    for (int i = 0; i < _timeline.length; i++) {
      final m = _timeline[i];
      final entryId =
          (i < _timelineEntryIds.length && _timelineEntryIds[i].isNotEmpty)
          ? _timelineEntryIds[i]
          : _getTimelineEntryId(i);
      _timelineEntryIds.length <= i
          ? _timelineEntryIds.add(entryId)
          : _timelineEntryIds[i] = entryId;

      final delaySec = _itemDelaySec[entryId] ?? 60;
      // kumulativer Start (Anzeigezeitpunkt)
      int startSec = 0;
      for (int k = 0; k < i; k++) {
        final prevId =
            (k < _timelineEntryIds.length && _timelineEntryIds[k].isNotEmpty)
            ? _timelineEntryIds[k]
            : _getTimelineEntryId(k);
        startSec += (_itemDelaySec[prevId] ?? 60);
      }

      itemDocs.add({
        'id': entryId,
        'assetId': m.id,
        'delaySec': delaySec,
        'minutes': (delaySec / 60).round(),
        'startSec': startSec,
        'activity': _itemEnabled[entryId] ?? true,
        'nameSnapshot': _displayName(m),
        'type': m.type.name,
        'thumbUrl': m.thumbUrl ?? m.url,
      });
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
      // Im leeren Zustand unten im Assets-Bereich: GMBC-Text als Hinweis
      return Center(
        child: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [AppColors.magenta, AppColors.lightBlue],
          ).createShader(bounds),
          child: const Text(
            'Klicke Media Assets hinzufügen, um zu starten.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
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
            // Für Nicht-Audio: ca. 30% kleinere Höhe
            childAspectRatio: _tab == 'audio' ? 1.0 : (_portrait ? 0.8 : 2.3),
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
                            _timelineEntryIds.add(
                              '',
                            ); // wird beim Persistieren gesetzt
                            _syncKeysLength();
                            // NICHT _isDirty setzen, da bereits persistiert
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
                                    // NICHT _isDirty setzen, da bereits persistiert
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
                    _timelineEntryIds.add('');
                    _syncKeysLength();
                    // NICHT _isDirty setzen, da bereits persistiert
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
                            // NICHT _isDirty setzen, da bereits persistiert
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
    if (!mounted) return;
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
                  const Color(0xFFE91E63).withValues(
                    alpha: (_timelineHover || cand.isNotEmpty) ? 0.55 : 0.3,
                  ),
                  AppColors.lightBlue.withValues(
                    alpha: (_timelineHover || cand.isNotEmpty) ? 0.55 : 0.3,
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
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, index, animation) => child,
                    onReorder: (oldIndex, newIndex) async {
                      // Defensive checks
                      if (oldIndex < 0 || oldIndex >= _timeline.length) return;
                      if (oldIndex >= _timelineKeys.length) return;
                      if (newIndex > _timeline.length) {
                        newIndex = _timeline.length;
                      }
                      if (newIndex > oldIndex) newIndex -= 1;

                      // setState SOFORT aufrufen, BEVOR wir auf Listen zugreifen
                      setState(() {
                        // Sync vor dem Verschieben
                        _syncKeysLength();

                        // Nochmal prüfen nach Sync
                        if (oldIndex >= _timeline.length ||
                            oldIndex >= _timelineKeys.length) {
                          return;
                        }

                        final it = _timeline.removeAt(oldIndex);
                        final k = _timelineKeys.removeAt(oldIndex);
                        final id = (oldIndex < _timelineEntryIds.length)
                            ? _timelineEntryIds.removeAt(oldIndex)
                            : '';
                        _timeline.insert(newIndex, it);
                        _timelineKeys.insert(newIndex, k);
                        if (id.isNotEmpty) {
                          if (newIndex > _timelineEntryIds.length) {
                            _timelineEntryIds.add(id);
                          } else {
                            _timelineEntryIds.insert(newIndex, id);
                          }
                        }

                        // Final Sync
                        _syncKeysLength();
                        // NICHT _isDirty setzen, da bereits persistiert
                      });

                      await _persistTimelineItems();
                    },
                    children: [
                      // Hard-Sync vor dem Rendern – vermeidet Null/Index-Probleme bei schnellem D&D
                      // (Spread entfernt, um Parser-Fehler zu vermeiden)
                      // _syncKeysLength();
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
                              child: ReorderableDragStartListener(
                                index: i,
                                child: Container(
                                  margin: const EdgeInsets.only(
                                    top: 12,
                                    left: 16,
                                    right: 16,
                                  ),
                                  height: 72,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color:
                                        (_itemEnabled[_getTimelineEntryId(i)] ??
                                            true)
                                        ? const Color(
                                            0xFF00C853,
                                          ).withValues(alpha: 0.10)
                                        : Colors.white.withValues(alpha: 0.06),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Row(
                                      children: [
                                        // Image links - volle Höhe, kein Abstand
                                        SizedBox(
                                          width: 50,
                                          height: 72,
                                          child: Stack(
                                            children: [
                                              ClipRRect(
                                                borderRadius:
                                                    const BorderRadius.only(
                                                      topLeft: Radius.circular(
                                                        8,
                                                      ),
                                                      bottomLeft:
                                                          Radius.circular(8),
                                                    ),
                                                child: Builder(
                                                  builder: (_) {
                                                    final entryId =
                                                        _getTimelineEntryId(i);
                                                    final active =
                                                        _itemEnabled[entryId] ??
                                                        true;
                                                    final Widget img =
                                                        (_timeline[i].type ==
                                                            AvatarMediaType
                                                                .image)
                                                        ? Image.network(
                                                            _timeline[i].url,
                                                            width: 50,
                                                            height: 72,
                                                            fit: BoxFit.cover,
                                                          )
                                                        : _buildThumb(
                                                            _timeline[i],
                                                            size: 65,
                                                          );
                                                    if (active) return img;
                                                    return ColorFiltered(
                                                      colorFilter:
                                                          const ColorFilter.matrix(
                                                            [
                                                              0.2126,
                                                              0.7152,
                                                              0.0722,
                                                              0,
                                                              0,
                                                              0.2126,
                                                              0.7152,
                                                              0.0722,
                                                              0,
                                                              0,
                                                              0.2126,
                                                              0.7152,
                                                              0.0722,
                                                              0,
                                                              0,
                                                              0,
                                                              0,
                                                              0,
                                                              1,
                                                              0,
                                                            ],
                                                          ),
                                                      child: img,
                                                    );
                                                  },
                                                ),
                                              ),
                                              // Auge nicht mehr im Bild – wird rechts außen gerendert
                                            ],
                                          ),
                                        ),
                                        // Content Mitte mit 16px padding links
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.only(left: 16),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                              // Nur Startzeit anzeigen
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 4,
                                                ),
                                                child: Builder(
                                                  builder: (_) {
                                                    final se =
                                                        _computeTimelineDisplayTimeWithEntryId(
                                                          i,
                                                        );
                                                    return Text(
                                                      _formatMmSs(se[0]),
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.white70,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              // Dropdown - exakt wie details_screen
                                              Container(
                                                height: 24,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.3),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: DropdownButtonHideUnderline(
                                                  child: DropdownButton<int>(
                                                    value:
                                                        _getTimelineItemMinutes(
                                                          i,
                                                        ),
                                                    isExpanded: false,
                                                    dropdownColor:
                                                        Colors.black87,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                  icon: const Icon(
                                                      Icons.arrow_drop_down,
                                                      size: 14,
                                    color: Colors.white70,
                                  ),
                                                    items: List.generate(
                                                      30,
                                                      (
                                                        index,
                                                      ) => DropdownMenuItem<int>(
                                                        value: index + 1,
                                                        child: Text(
                                                          '${index + 1} Min.',
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                    onChanged: (value) {
                                                      if (value != null) {
                                                        _setTimelineItemMinutes(
                                                          i,
                                                          value,
                                                        );
                                                      }
                                                    },
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              // Name mit Ellipsis
                                              Text(
                                                _displayName(_timeline[i]),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                               ],
                                             ),
                                           ),
                                         ),
                                        // Rechte Navi Column am oberen Rand mit 16px rechts padding
                                        Padding(
                                          padding: const EdgeInsets.only(right: 16),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.start,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4,
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  // Auge
                                                  MouseRegion(
                                                    cursor: SystemMouseCursors
                                                        .click,
                                                    child: GestureDetector(
                                                      onTap: () =>
                                                          _toggleEntryActivity(
                                                            i,
                                                          ),
                                                      child: Container(
                                                        width: 24,
                                                        height: 24,
                                                        decoration: BoxDecoration(
                                                          shape:
                                                              BoxShape.circle,
                                                          gradient:
                                                              (_itemEnabled[_getTimelineEntryId(
                                                                    i,
                                                                  )] ??
                                                                  true)
                                                              ? const LinearGradient(
                                                                  colors: [
                                                                    AppColors
                                                                        .magenta,
                                                                    AppColors
                                                                        .lightBlue,
                                                                  ],
                                                                )
                                                              : null,
                                                          color:
                                                              (_itemEnabled[_getTimelineEntryId(
                                                                    i,
                                                                  )] ??
                                                                  true)
                                                              ? null
                                                              : Colors.white24,
                                                        ),
                                                        child: Icon(
                                                          (_itemEnabled[_getTimelineEntryId(
                                                                    i,
                                                                  )] ??
                                                                  true)
                                                              ? Icons.visibility
                                                              : Icons
                                                                    .visibility_off,
                                                          size: 16,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  // 6-Punkte Drag Icon
                                                  MouseRegion(
                                                    cursor: SystemMouseCursors
                                                        .click,
                                                    child: Icon(
                                                      Icons.drag_indicator,
                                                      color: Colors.white70,
                                                      size: 20,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  // Delete Button
                                                  GestureDetector(
                                                    onTap: () async {
                                                      final confirm = await showDialog<bool>(
                                                        context: context,
                                                        builder: (ctx) => AlertDialog(
                                                          title: const Text(
                                                            'Asset entfernen?',
                                                          ),
                                                          content: const Text(
                                                            'Dieses Asset aus der Timeline entfernen?',
                                                          ),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                    ctx,
                                                                    false,
                                                                  ),
                                                              child: const Text(
                                                                'Abbrechen',
                                                              ),
                                                            ),
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                    ctx,
                                                                    true,
                                                                  ),
                                                              child: const Text(
                                                                'Entfernen',
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                      if (confirm != true) {
                                                        return;
                                                      }
                                      setState(() {
                                                        if (i <
                                                                _timeline
                                                                    .length &&
                                                            i <
                                                                _timelineKeys
                                                                    .length) {
                                          _timeline.removeAt(i);
                                                          _timelineKeys
                                                              .removeAt(i);
                                                          if (i <
                                                              _timelineEntryIds
                                                                  .length) {
                                                            _timelineEntryIds
                                                                .removeAt(i);
                                                          }
                                          _syncKeysLength();
                                          // NICHT _isDirty setzen, da bereits persistiert
                                        }
                                      });
                                      await _persistTimelineItems();
                                                    },
                                                    child: Icon(
                                                      Icons.close,
                                                      size: 20,
                                                      color: Colors.white70,
                                                    ),
                                                    ),
                                                  ],
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
                            ),
                          ),
                    ],
                  ),
          );
        },
        onWillAcceptWithDetails: (m) {
          setState(() => _timelineHover = true);
          return true;
        },
        onLeave: (m) => setState(() => _timelineHover = false),
        onAcceptWithDetails: (m) {
          setState(() {
            _timeline.add(m.data);
            _timelineKeys.add(UniqueKey());
            _syncKeysLength();
            // NICHT _isDirty setzen, da bereits persistiert
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
          // (Entfernt) Doppelte Navi im Assets-Pane – oben existiert die globale Navi
          // Fixer Mini-Hinweis direkt unter der Icon-Navi (scrollt nicht mit dem Grid)
          if (_assets.isNotEmpty)
            const SizedBox(
              height: 18,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'Klicke auf "Media Assets hinzufügen", um zu starten.',
                    style: TextStyle(color: Colors.white70, fontSize: 10),
                  ),
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

  Widget _tabBtn(
    String t,
    IconData icon, {
    double tabW = 36,
    double iconSize = 16,
  }) {
    final sel = _tab == t;
    final grad = Theme.of(context).extension<AppGradients>()?.magentaBlue;
    return SizedBox(
      height: 35,
      child: TextButton(
        onPressed: () => setState(() {
          _tab = t;
          if (t == 'documents' || t == 'audio') _portrait = true;
        }),
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          minimumSize: WidgetStatePropertyAll(Size(tabW, 35)),
        ),
        child: Container(
          width: tabW,
          height: 35,
          decoration: sel && grad != null
              ? BoxDecoration(gradient: grad, borderRadius: BorderRadius.zero)
              : null,
          child: Icon(
            icon,
            size: iconSize,
            color: sel ? Colors.white : Colors.white54,
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
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

  // (ehem.) horizontaler Resizer vollständig entfernt

  Widget _buildVerticalResizer(double totalH, double topH, double resizerH) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _vResizerHover = true),
      onExit: (_) => setState(() => _vResizerHover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: (d) {
          setState(() {
            final available2 = totalH.clamp(0.0, double.infinity);
            const double minTop = 120.0;
            const double minBottom = 120.0;
            if (available2 <= (minTop + minBottom)) return;
            final double newTop = (topH + d.delta.dy).clamp(
              minTop,
              available2 - minBottom,
            );
            _verticalRatio = available2 > 0 ? (newTop / available2) : 0.5;
          });
        },
        child: Container(
          height: resizerH,
          decoration: _vResizerHover
              ? BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.magenta, AppColors.lightBlue],
                  ),
                  color: const Color(0xFF1E1E1E).withValues(alpha: 0.8),
                )
              : const BoxDecoration(color: Color(0xFF1E1E1E)),
          child: Center(
            child: Container(
              width: 28,
              height: _vResizerHover ? 3 : 2,
              decoration: _vResizerHover
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
    // ignore: unused_element
  }
}

class _TogglePill extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _TogglePill({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: value ? Colors.white : Colors.black.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: value
                    ? Theme.of(context).extension<AppGradients>()?.magentaBlue
                    : null,
                color: value ? null : Colors.white24,
              ),
              child: const Icon(Icons.check, size: 14, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: value ? Colors.black : Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniToggleButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _MiniToggleButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active ? Colors.white : const Color(0x1AFFFFFF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? Colors.white : Colors.white38),
          ),
          child: active
              ? ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (b) => const LinearGradient(
                    colors: [AppColors.magenta, AppColors.lightBlue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(b),
                  child: const Text(
                    'Media Assets',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                )
              : const Text(
                  'Media Assets',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70, // light grey
                  ),
                ),
        ),
      ),
    );
  }
}

class _GradientToggleGroup extends StatelessWidget {
  final String leftLabel;
  final String rightLabel;
  final bool leftActive;
  final bool rightActive;
  final VoidCallback onLeftTap;
  final VoidCallback onRightTap;

  const _GradientToggleGroup({
    required this.leftLabel,
    required this.rightLabel,
    required this.leftActive,
    required this.rightActive,
    required this.onLeftTap,
    required this.onRightTap,
  });

  @override
  Widget build(BuildContext context) {
    final grad = Theme.of(context).extension<AppGradients>()?.magentaBlue;
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onLeftTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              height: double.infinity,
              decoration: leftActive && grad != null
                  ? BoxDecoration(
                      gradient: grad,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        bottomLeft: Radius.circular(8),
                      ),
                    )
                  : null,
              alignment: Alignment.center,
              child: Text(
                leftLabel,
                style: TextStyle(
                  color: leftActive ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          Container(
            width: 10,
            height: double.infinity,
            alignment: Alignment.center,
            child: Container(width: 1, height: 16, color: Colors.white24),
          ),
          InkWell(
            onTap: onRightTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              height: double.infinity,
              decoration: rightActive && grad != null
                  ? BoxDecoration(
                      gradient: grad,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                    )
                  : null,
              alignment: Alignment.center,
              child: Row(
                children: [
                  Text(
                    rightLabel,
                    style: TextStyle(
                      color: rightActive ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const Icon(
                      Icons.arrow_drop_down,
                      size: 12,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientMinutesPicker extends StatelessWidget {
  final int minutes; // 1..30
  final ValueChanged<int> onPick;

  const _GradientMinutesPicker({required this.minutes, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final grad = Theme.of(context).extension<AppGradients>()?.magentaBlue;
    return InkWell(
      onTap: () async {
        int sel = minutes.clamp(1, 30);
        final picked = await showCupertinoModalPopup<int>(
          context: context,
          builder: (ctx) => Container(
            height: 260,
            color: Colors.black,
            child: Column(
              children: [
                Expanded(
                  child: CupertinoPicker(
                    itemExtent: 32,
                    scrollController: FixedExtentScrollController(
                      initialItem: sel - 1,
                    ),
                    onSelectedItemChanged: (idx) => sel = idx + 1,
                    children: List.generate(
                      30,
                      (i) => Center(
                        child: Text(
                          '${i + 1} Min.',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, sel),
                  child: const Text(
                    'OK',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
        if (picked != null) onPick(picked);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (grad != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  gradient: grad,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '1 Min.',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Text(
              '$minutes Min.',
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.arrow_drop_down, size: 16, color: Colors.black87),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
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
