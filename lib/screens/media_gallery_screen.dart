import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:crop_your_image/crop_your_image.dart' as cyi;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:ui' as ui;
import '../services/media_service.dart';
import '../services/firebase_storage_service.dart';
import '../services/cloud_vision_service.dart';
import '../models/media_models.dart';
import '../services/playlist_service.dart';
import '../models/playlist_models.dart';
import '../services/localization_service.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_theme.dart';

class MediaGalleryScreen extends StatefulWidget {
  final String avatarId;
  const MediaGalleryScreen({super.key, required this.avatarId});

  @override
  State<MediaGalleryScreen> createState() => _MediaGalleryScreenState();
}

class _MediaGalleryScreenState extends State<MediaGalleryScreen> {
  final _mediaSvc = MediaService();
  final _playlistSvc = PlaylistService();
  final _visionSvc = CloudVisionService();
  final _picker = ImagePicker();
  final _searchController = TextEditingController();

  // Multi-Upload Variablen
  List<File> _uploadQueue = [];
  bool _isUploading = false;
  int _uploadProgress = 0;
  String _uploadStatus = '';

  List<AvatarMedia> _items = [];
  Map<String, List<Playlist>> _mediaToPlaylists =
      {}; // mediaId -> List<Playlist>
  bool _loading = true;
  double _cropAspect = 9 / 16;
  String _mediaTab = 'images'; // 'images', 'videos', 'audio'
  String _searchTerm = '';
  int _currentPage = 0;
  static const int _itemsPerPage = 9;
  bool _isDeleteMode = false;
  final Set<String> _selectedMediaIds = {};
  bool _showSearch = false;
  bool _showPortrait = true; // true = portrait, false = landscape
  final Map<String, double> _imageAspectRatios =
      {}; // Cache für Bild-Aspekt-Verhältnisse

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(() {
      setState(() {
        _searchTerm = _searchController.text.toLowerCase();
        _currentPage = 0;
      });
    });
    // Teste Vision API beim Start
    _visionSvc.testVisionAPI();
    // Aktualisiere Tags für bestehende Bilder
    _updateExistingImageTags();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _mediaSvc.list(widget.avatarId);
      final pls = await _playlistSvc.list(widget.avatarId);

      // Für jedes Medium prüfen, in welchen Playlists es vorkommt
      final Map<String, List<Playlist>> mediaToPlaylists = {};
      for (final media in list) {
        final usedInPlaylists = <Playlist>[];
        for (final playlist in pls) {
          final items = await _playlistSvc.listItems(
            widget.avatarId,
            playlist.id,
          );
          if (items.any((item) => item.mediaId == media.id)) {
            usedInPlaylists.add(playlist);
          }
        }
        if (usedInPlaylists.isNotEmpty) {
          mediaToPlaylists[media.id] = usedInPlaylists;
        }
      }

      if (!mounted) return;
      setState(() {
        _items = list;
        _mediaToPlaylists = mediaToPlaylists;
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

  List<AvatarMedia> get _filteredItems {
    var items = _items.where((it) {
      if (_mediaTab == 'images' && it.type != AvatarMediaType.image)
        return false;
      if (_mediaTab == 'videos' && it.type != AvatarMediaType.video)
        return false;
      if (_mediaTab == 'audio') return false; // Audio noch nicht unterstützt

      // Orientierungsfilter: IMMER filtern, nie gemischt
      // Für Bilder ohne aspectRatio: tatsächliche Bildgröße ermitteln
      bool itemIsPortrait = it.isPortrait;
      bool itemIsLandscape = it.isLandscape;

      if (it.aspectRatio == null && it.type == AvatarMediaType.image) {
        // Prüfe Cache für bereits ermittelte Aspect Ratios
        final cachedAspectRatio = _imageAspectRatios[it.url];
        if (cachedAspectRatio != null) {
          itemIsPortrait = cachedAspectRatio < 1.0;
          itemIsLandscape = cachedAspectRatio > 1.0;
        } else {
          // Asynchron Aspect Ratio ermitteln (lädt im Hintergrund)
          _loadImageAspectRatio(it.url);
          // Default: Portrait für unbekannte Bilder (wird später korrigiert)
          itemIsPortrait = true;
          itemIsLandscape = false;
        }
      }

      if (_showPortrait && !itemIsPortrait) return false;
      if (!_showPortrait && !itemIsLandscape) return false;

      // KI-Such-Filter
      if (_searchTerm.isNotEmpty) {
        // Verwende VisionService für intelligente Suche basierend auf Bildinhalten
        if (it.tags != null && it.tags!.isNotEmpty) {
          if (_visionSvc.matchesSearch(it.tags!, _searchTerm)) {
            return true;
          }
        }

        // Fallback: Suche in URL/Dateiname
        if (it.url.toLowerCase().contains(_searchTerm.toLowerCase())) {
          return true;
        }

        return false;
      }
      return true;
    }).toList();
    return items;
  }

  int get _totalPages {
    final count = _filteredItems.length;
    if (count == 0) return 1;
    return (count / _itemsPerPage).ceil();
  }

  List<AvatarMedia> get _pageItems {
    final filtered = _filteredItems;
    final start = _currentPage * _itemsPerPage;
    final end = (start + _itemsPerPage).clamp(0, filtered.length);
    if (start >= filtered.length) return [];
    return filtered.sublist(start, end);
  }

  Future<void> _pickImageFrom(ImageSource source) async {
    final x = await _picker.pickImage(source: source, imageQuality: 95);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    await _openCrop(bytes, p.extension(x.path));
  }

  /// Zeigt Dialog für Kamera/Galerie Auswahl
  Future<void> _showImageSourceDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bildquelle wählen'),
        content: const Text('Woher sollen die Bilder kommen?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _pickImageFrom(ImageSource.camera); // Single für Kamera
            },
            child: const Text('Kamera (1 Bild)'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _pickMultipleImages(); // Multi für Galerie
            },
            child: const Text('Galerie (Mehrere)'),
          ),
        ],
      ),
    );
  }

  /// Zeigt Dialog für Video Quelle
  Future<void> _showVideoSourceDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Videoquelle wählen'),
        content: const Text('Woher soll das Video kommen?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _pickVideoFrom(ImageSource.camera);
            },
            child: const Text('Kamera'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _pickVideoFrom(ImageSource.gallery);
            },
            child: const Text('Galerie'),
          ),
        ],
      ),
    );
  }

  /// Multi-Upload: Mehrere Bilder auf einmal auswählen
  Future<void> _pickMultipleImages() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isEmpty) return;

    setState(() {
      _uploadQueue = images.map((x) => File(x.path)).toList();
      _isUploading = true;
      _uploadProgress = 0;
      _uploadStatus = 'Bilder werden hochgeladen...';
    });

    await _processUploadQueue();
  }

  /// Verarbeitet die Upload-Queue
  Future<void> _processUploadQueue() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    for (int i = 0; i < _uploadQueue.length; i++) {
      final file = _uploadQueue[i];
      final ext = p.extension(file.path).toLowerCase();

      setState(() {
        _uploadProgress = ((i + 1) / _uploadQueue.length * 100).round();
        _uploadStatus = 'Lade Bild ${i + 1} von ${_uploadQueue.length} hoch...';
      });

      try {
        // Direkt hochladen ohne Cropping
        final timestamp =
            DateTime.now().millisecondsSinceEpoch + i; // Eindeutige IDs

        // KI-Bildanalyse
        List<String> tags = [];
        try {
          tags = await _visionSvc.analyzeImage(file.path);
          print('KI-Tags für Bild ${i + 1}: $tags');
        } catch (e) {
          print('Fehler bei KI-Analyse für Bild ${i + 1}: $e');
        }

        // Upload
        final url = await FirebaseStorageService.uploadImage(
          file,
          customPath:
              'avatars/$uid/${widget.avatarId}/media/images/$timestamp$ext',
        );

        if (url != null) {
          final media = AvatarMedia(
            id: timestamp.toString(),
            avatarId: widget.avatarId,
            type: AvatarMediaType.image,
            url: url,
            createdAt: timestamp,
            tags: tags.isNotEmpty ? tags : null,
          );
          await _mediaSvc.add(widget.avatarId, media);
        }
      } catch (e) {
        print('Fehler beim Upload von Bild ${i + 1}: $e');
      }
    }

    // Upload abgeschlossen
    setState(() {
      _isUploading = false;
      _uploadQueue.clear();
      _uploadProgress = 0;
      _uploadStatus = '';
    });

    await _load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_uploadQueue.length} Bilder erfolgreich hochgeladen!',
          ),
          action: SnackBarAction(
            label: 'Zuschneiden',
            textColor: Colors.white,
            onPressed: () => _showBatchCropDialog(),
          ),
        ),
      );
    }
  }

  /// Zeigt Dialog für Batch-Cropping aller hochgeladenen Bilder
  Future<void> _showBatchCropDialog() async {
    // Hole alle Bilder der letzten 5 Minuten (frisch hochgeladen)
    final now = DateTime.now().millisecondsSinceEpoch;
    final recentImages = _items
        .where(
          (item) =>
              item.type == AvatarMediaType.image &&
              (now - item.createdAt) < 300000, // 5 Minuten
        )
        .toList();

    if (recentImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keine neuen Bilder zum Zuschneiden gefunden'),
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bilder zuschneiden'),
        content: Text(
          '${recentImages.length} Bilder können zugeschnitten werden. Möchtest du fortfahren?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startBatchCropping(recentImages);
            },
            child: const Text('Zuschneiden'),
          ),
        ],
      ),
    );
  }

  /// Startet Batch-Cropping für alle Bilder
  Future<void> _startBatchCropping(List<AvatarMedia> images) async {
    for (int i = 0; i < images.length; i++) {
      final image = images[i];

      setState(() {
        _uploadStatus = 'Zuschneide Bild ${i + 1} von ${images.length}...';
        _isUploading = true;
      });

      try {
        // Lade Bild herunter
        final source = await _downloadToTemp(image.url, suffix: '.png');
        if (source == null) continue;

        final bytes = await source.readAsBytes();

        // Zeige Cropping-Dialog
        await _openCrop(bytes, p.extension(image.url));

        // Kurze Pause zwischen den Bildern
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        print('Fehler beim Zuschneiden von Bild ${i + 1}: $e');
      }
    }

    setState(() {
      _isUploading = false;
      _uploadStatus = '';
    });

    await _load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Batch-Cropping abgeschlossen!')),
      );
    }
  }

  Future<void> _openCrop(Uint8List imageBytes, String ext) async {
    double currentAspect = _cropAspect;
    final cropController =
        cyi.CropController(); // Neuer Controller für jeden Dialog
    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            contentPadding: EdgeInsets.zero,
            content: SizedBox(
              width: 380,
              height: 560,
              child: Column(
                children: [
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
                          selected: currentAspect == 9 / 16,
                          onSelected: (_) {
                            setLocal(() => currentAspect = 9 / 16);
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('16:9'),
                          selected: currentAspect == 16 / 9,
                          onSelected: (_) {
                            setLocal(() => currentAspect = 16 / 9);
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: cyi.Crop(
                      key: ValueKey(currentAspect),
                      controller: cropController,
                      image: imageBytes,
                      aspectRatio: currentAspect,
                      withCircleUi: false,
                      onCropped: (croppedBytes) async {
                        if (!mounted) return;
                        _cropAspect = currentAspect;
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
                          // Force crop auch wenn nicht bewegt wurde
                          try {
                            cropController.crop();
                          } catch (e) {
                            // Fallback: Croppe das ganze Bild
                            final image = imageBytes;
                            Navigator.of(context).pop();
                            _uploadImage(image, ext);
                          }
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
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = p.join(
      dir.path,
      'crop_$timestamp${ext.isNotEmpty ? ext : '.jpg'}',
    );
    final f = File(path);
    await f.writeAsBytes(bytes, flush: true);

    // KI-Bildanalyse durchführen
    List<String> tags = [];
    try {
      tags = await _visionSvc.analyzeImage(path);
      print('KI-Tags erkannt: $tags');
    } catch (e) {
      print('Fehler bei KI-Analyse: $e');
    }

    final url = await FirebaseStorageService.uploadImage(
      f,
      customPath:
          'avatars/$uid/${widget.avatarId}/media/images/$timestamp${ext.isNotEmpty ? ext : '.jpg'}',
    );
    if (url == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bild-Upload fehlgeschlagen')),
        );
      }
      return;
    }
    final m = AvatarMedia(
      id: timestamp.toString(),
      avatarId: widget.avatarId,
      type: AvatarMediaType.image,
      url: url,
      createdAt: timestamp,
      aspectRatio: _cropAspect,
      tags: tags.isNotEmpty ? tags : null,
    );
    await _mediaSvc.add(widget.avatarId, m);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tags.isNotEmpty
                ? 'Bild hochgeladen (${tags.length} Tags erkannt)'
                : 'Bild erfolgreich hochgeladen',
          ),
        ),
      );
    }
  }

  Future<void> _pickVideoFrom(ImageSource source) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final x = await _picker.pickVideo(source: source);
    if (x == null) return;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final url = await FirebaseStorageService.uploadVideo(
      File(x.path),
      customPath: 'avatars/$uid/${widget.avatarId}/media/videos/$timestamp.mp4',
    );
    if (url == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video-Upload fehlgeschlagen')),
        );
      }
      return;
    }
    final m = AvatarMedia(
      id: timestamp.toString(),
      avatarId: widget.avatarId,
      type: AvatarMediaType.video,
      url: url,
      createdAt: timestamp,
      aspectRatio: 16 / 9, // Default landscape für Videos
    );
    await _mediaSvc.add(widget.avatarId, m);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video erfolgreich hochgeladen')),
      );
    }
  }

  Future<void> _pickAudio() async {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Audio Upload kommt bald')));
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
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Suchfeld oder Intro-Text (Toggle via Lupen-Button) - FIXE HÖHE
                Container(
                  width: double.infinity,
                  height: 80, // Reduzierte Höhe da nur 2 Zeilen
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: _showSearch
                      ? Container(
                          color: Colors.white.withValues(alpha: 0.05),
                          padding: const EdgeInsets.all(12),
                          child: TextField(
                            controller: _searchController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Suche nach Medien...',
                              hintStyle: const TextStyle(color: Colors.white54),
                              prefixIcon: const Icon(
                                Icons.search,
                                color: Colors.white70,
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.06),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _searchTerm = value.toLowerCase();
                                _currentPage = 0;
                              });
                            },
                          ),
                        )
                      : Container(
                          color: Colors.white.withValues(alpha: 0.05),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Center(
                            child: Text(
                              'Verlinke Deine Medien z.B. in der Chat-Playlist oder anderen Bereichen.',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                height: 1.2,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 16),

                // Upload-Fortschrittsanzeige
                if (_isUploading)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _uploadStatus,
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: _uploadProgress / 100,
                          backgroundColor: Colors.white.withValues(alpha: 0.3),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.lightBlue,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$_uploadProgress%',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                if (_isUploading) const SizedBox(height: 16),

                // Navigation + Upload + Suchfeld ODER Delete-Toolbar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    height:
                        40, // Fixe Höhe für beide Modi, um Layout-Shift zu vermeiden
                    child: _isDeleteMode && _selectedMediaIds.isNotEmpty
                        ? // Delete-Toolbar (ersetzt Navigation)
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () {
                                      setState(() {
                                        _isDeleteMode = false;
                                        _selectedMediaIds.clear();
                                      });
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.grey,
                                      foregroundColor: Colors.white,
                                      padding: EdgeInsets.zero,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const Text('Abbrechen'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _confirmDeleteSelected,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.redAccent,
                                      foregroundColor: Colors.white,
                                      padding: EdgeInsets.zero,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const Text('Endgültig löschen'),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : // Normale Navigation
                          Row(
                            children: [
                              // Tab-Buttons (Bilder/Videos/Audio)
                              _buildTabButton('images', Icons.image),
                              const SizedBox(width: 8),
                              _buildTabButton('videos', Icons.videocam),
                              const SizedBox(width: 8),
                              _buildTabButton('audio', Icons.audiotrack),
                              const SizedBox(width: 8),

                              // Upload-Button (Multi-Upload für alle Medien)
                              _buildUploadButton(),
                              const SizedBox(width: 25),

                              // Lupen-Icon Toggle für Suche
                              SizedBox(
                                width: 40,
                                height: 40,
                                child: ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _showSearch = !_showSearch;
                                      if (!_showSearch) {
                                        _searchController.clear();
                                        _searchTerm = '';
                                      }
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _showSearch
                                        ? Colors.white
                                        : const Color(0x40FFFFFF),
                                    foregroundColor: _showSearch
                                        ? null
                                        : Colors.white,
                                    shadowColor: Colors.transparent,
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: _showSearch
                                      ? ShaderMask(
                                          shaderCallback: (bounds) =>
                                              const LinearGradient(
                                                colors: [
                                                  AppColors.magenta,
                                                  AppColors.lightBlue,
                                                ],
                                              ).createShader(bounds),
                                          child: Icon(
                                            Icons.search_off,
                                            size: 20,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Icon(Icons.search, size: 20),
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Portrait/Landscape Toggle (nur für Bilder/Videos)
                              if (_mediaTab != 'audio')
                                SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: ElevatedButton(
                                    onPressed: () {
                                      setState(() {
                                        _showPortrait = !_showPortrait;
                                        _currentPage = 0;
                                      });
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _showPortrait
                                          ? Colors.white
                                          : const Color(0x40FFFFFF),
                                      foregroundColor: _showPortrait
                                          ? null
                                          : Colors.white,
                                      shadowColor: Colors.transparent,
                                      padding: EdgeInsets.zero,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: _showPortrait
                                        ? ShaderMask(
                                            shaderCallback: (bounds) =>
                                                const LinearGradient(
                                                  colors: [
                                                    AppColors.magenta,
                                                    AppColors.lightBlue,
                                                  ],
                                                ).createShader(bounds),
                                            child: Icon(
                                              Icons.stay_current_portrait,
                                              size: 20,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Icon(
                                            Icons.stay_current_landscape,
                                            size: 20,
                                          ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 16),

                // Grid mit variabler Breite, fixer Höhe
                Expanded(
                  child: _pageItems.isEmpty
                      ? Center(
                          child: Text(
                            'Keine Medien gefunden',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _pageItems.map((it) {
                              return _buildMediaCard(it);
                            }).toList(),
                          ),
                        ),
                ),

                // Pagination
                if (_totalPages > 1)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: _currentPage > 0
                              ? () => setState(() => _currentPage--)
                              : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text(
                          '${_currentPage + 1} / $_totalPages',
                          style: const TextStyle(color: Colors.white),
                        ),
                        IconButton(
                          onPressed: _currentPage < _totalPages - 1
                              ? () => setState(() => _currentPage++)
                              : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildTabButton(String tab, IconData icon, {bool isSpecial = false}) {
    final selected = _mediaTab == tab;
    const double btnSize = 40.0;
    return SizedBox(
      width: btnSize,
      height: btnSize,
      child: ElevatedButton(
        onPressed: () {
          if (isSpecial && tab == 'search') {
            setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) {
                _searchController.clear();
                _searchTerm = '';
              }
            });
          } else if (isSpecial && tab == 'orientation') {
            setState(() {
              _showPortrait = !_showPortrait;
              _currentPage = 0;
            });
          } else {
            setState(() {
              _mediaTab = tab;
              _currentPage = 0;
            });
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: selected
              ? AppColors.accentGreenDark
              : Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: selected ? AppColors.accentGreenDark : Colors.white24,
            ),
          ),
        ),
        child: Icon(icon, size: 20),
      ),
    );
  }

  Widget _buildUploadButton() {
    const double btnSize = 40.0;
    return SizedBox(
      width: btnSize,
      height: btnSize,
      child: ElevatedButton(
        onPressed: _isUploading
            ? null
            : () {
                if (_mediaTab == 'images') {
                  _showImageSourceDialog();
                } else if (_mediaTab == 'videos') {
                  _showVideoSourceDialog();
                } else {
                  _pickAudio();
                }
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
              colors: [Color(0xFFE91E63), AppColors.lightBlue],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(
            child: Icon(Icons.file_upload, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaCard(AvatarMedia it) {
    const double cardHeight = 150.0; // 25% weniger als 200
    // Berechne Breite basierend auf tatsächlichem Aspect Ratio
    double aspectRatio =
        it.aspectRatio ?? (9 / 16); // Default Portrait wenn nicht gesetzt

    // Für Bilder ohne aspectRatio: Cache prüfen
    if (it.aspectRatio == null && _imageAspectRatios.containsKey(it.url)) {
      aspectRatio = _imageAspectRatios[it.url]!;
    }

    final double cardWidth = cardHeight * aspectRatio;
    final usedInPlaylists = _mediaToPlaylists[it.id] ?? [];
    final isInPlaylist = usedInPlaylists.isNotEmpty;
    final selected = _selectedMediaIds.contains(it.id);

    return GestureDetector(
      onTap: () {
        if (_isDeleteMode) {
          setState(() {
            if (selected) {
              _selectedMediaIds.remove(it.id);
            } else {
              _selectedMediaIds.add(it.id);
            }
          });
        } else {
          _openViewer(it);
        }
      },
      child: SizedBox(
        width: cardWidth,
        height: cardHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: it.type == AvatarMediaType.image
                  ? Image.network(
                      it.url,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) {
                        return Container(
                          color: Colors.black26,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.image_not_supported,
                            color: Colors.white54,
                          ),
                        );
                      },
                    )
                  : Container(
                      color: Colors.grey.shade800,
                      child: const Icon(
                        Icons.play_circle_filled,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
            ),
            // Playlist Icon oben links (nur wenn in Playlists verwendet)
            if (isInPlaylist && !_isDeleteMode)
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accentGreenDark,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.playlist_play,
                      color: Colors.white,
                      size: 16,
                    ),
                    onPressed: () => _showPlaylistsDialog(it, usedInPlaylists),
                  ),
                ),
              ),
            // Cropping Icon unten links (nur für Bilder)
            if (it.type == AvatarMediaType.image && !_isDeleteMode)
              Positioned(
                left: 6,
                bottom: 6,
                child: InkWell(
                  onTap: () => _reopenCrop(it),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0x30000000),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0x66FFFFFF)),
                    ),
                    child: const Icon(
                      Icons.crop,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),

            // Delete Button unten rechts
            Positioned(
              right: 6,
              bottom: 6,
              child: InkWell(
                onTap: () {
                  setState(() {
                    _isDeleteMode = true;
                    if (selected) {
                      _selectedMediaIds.remove(it.id);
                    } else {
                      _selectedMediaIds.add(it.id);
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: selected ? null : const Color(0x30000000),
                    gradient: selected
                        ? const LinearGradient(
                            colors: [AppColors.magenta, AppColors.lightBlue],
                          )
                        : null,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected
                          ? AppColors.lightBlue.withValues(alpha: 0.7)
                          : const Color(0x66FFFFFF),
                    ),
                  ),
                  child: const Icon(
                    Icons.delete_outline,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPlaylistsDialog(
    AvatarMedia media,
    List<Playlist> playlists,
  ) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('In Playlists verwendet'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: playlists.length,
            itemBuilder: (context, i) {
              final pl = playlists[i];
              return ListTile(
                title: Text(pl.name),
                trailing: IconButton(
                  icon: const Icon(
                    Icons.remove_circle_outline,
                    color: Colors.redAccent,
                  ),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx2) => AlertDialog(
                        title: const Text('Aus Playlist entfernen?'),
                        content: Text(
                          'Möchtest du dieses Medium aus "${pl.name}" entfernen?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx2, false),
                            child: const Text('Abbrechen'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx2, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                            ),
                            child: const Text('Entfernen'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;

                    try {
                      final items = await _playlistSvc.listItems(
                        widget.avatarId,
                        pl.id,
                      );
                      final itemToRemove = items.firstWhere(
                        (item) => item.mediaId == media.id,
                      );
                      await _playlistSvc.deleteItem(
                        widget.avatarId,
                        pl.id,
                        itemToRemove.id,
                      );
                      await _load();
                      if (mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Aus Playlist entfernt'),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('Fehler: $e')));
                      }
                    }
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteSelected() async {
    final count = _selectedMediaIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Medien löschen?'),
        content: Text(
          'Möchtest du $count ${count == 1 ? 'Medium' : 'Medien'} wirklich löschen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      // Lösche alle selected Medien
      for (final mediaId in _selectedMediaIds.toList()) {
        await _mediaSvc.delete(widget.avatarId, mediaId);
      }
      setState(() {
        _isDeleteMode = false;
        _selectedMediaIds.clear();
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$count ${count == 1 ? 'Medium' : 'Medien'} erfolgreich gelöscht',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler beim Löschen: $e')));
      }
    }
  }

  Future<File?> _downloadToTemp(String url, {String? suffix}) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) return null;
      final dir = await getTemporaryDirectory();
      final name = 'dl_${DateTime.now().millisecondsSinceEpoch}${suffix ?? ''}';
      final f = File('${dir.path}/$name');
      await f.writeAsBytes(res.bodyBytes, flush: true);
      return f;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadImageAspectRatio(String url) async {
    if (_imageAspectRatios.containsKey(url)) return;

    try {
      // Lade das komplette Bild um echte Dimensionen zu ermitteln
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        // Verwende dart:ui um echte Dimensionen zu ermitteln
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final image = frame.image;

        final aspectRatio = image.width / image.height;
        _imageAspectRatios[url] = aspectRatio;
        image.dispose();
        if (mounted) setState(() {}); // Trigger rebuild
      }
    } catch (e) {
      // Bei Fehler: Default Portrait
      _imageAspectRatios[url] = 9 / 16;
    }
  }

  Future<void> _reopenCrop(AvatarMedia media) async {
    try {
      final source = await _downloadToTemp(media.url, suffix: '.png');
      if (source == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bild konnte nicht geladen werden.')),
          );
        }
        return;
      }

      final bytes = await source.readAsBytes();
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      // Verwende das bestehende Crop-Dialog
      double currentAspect = _cropAspect;
      Uint8List? croppedBytes;
      final cropController =
          cyi.CropController(); // Neuer Controller für jeden Dialog

      await showDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setLocal) => AlertDialog(
              contentPadding: EdgeInsets.zero,
              content: SizedBox(
                width: 380,
                height: 560,
                child: Column(
                  children: [
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
                            selected: currentAspect == 9 / 16,
                            onSelected: (_) {
                              setLocal(() => currentAspect = 9 / 16);
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('16:9'),
                            selected: currentAspect == 16 / 9,
                            onSelected: (_) {
                              setLocal(() => currentAspect = 16 / 9);
                            },
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: cyi.Crop(
                        key: ValueKey(currentAspect),
                        controller: cropController,
                        image: bytes,
                        aspectRatio: currentAspect,
                        withCircleUi: false,
                        onCropped: (cropped) async {
                          croppedBytes = cropped;
                          if (!mounted) return;
                          _cropAspect = currentAspect;
                          Navigator.of(ctx).pop();
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
                            // Force crop auch wenn nicht bewegt wurde
                            try {
                              cropController.crop();
                            } catch (e) {
                              // Fallback: Croppe das ganze Bild
                              croppedBytes = bytes;
                              Navigator.of(ctx).pop();
                            }
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

      if (croppedBytes == null) return;

      // Upload neu gescroptes Bild
      final originalPath = FirebaseStorageService.pathFromUrl(media.url);
      if (originalPath.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Speicherpfad konnte nicht ermittelt werden.'),
            ),
          );
        }
        return;
      }

      final baseDir = p.dirname(originalPath);
      final ext = p.extension(originalPath).isNotEmpty
          ? p.extension(originalPath)
          : '.jpg';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final newPath = '$baseDir/recrop_$timestamp$ext';

      final dir = await getTemporaryDirectory();
      final tempFile = File('${dir.path}/recrop_$timestamp$ext');
      await tempFile.writeAsBytes(croppedBytes!, flush: true);

      // KI-Bildanalyse für neu gescroptes Bild
      List<String> newTags = [];
      try {
        newTags = await _visionSvc.analyzeImage(tempFile.path);
        print('Neue KI-Tags erkannt: $newTags');
      } catch (e) {
        print('Fehler bei KI-Analyse (Re-crop): $e');
      }

      final upload = await FirebaseStorageService.uploadImage(
        tempFile,
        customPath: newPath,
      );

      if (upload != null && mounted) {
        // Update media URL, aspectRatio und Tags in Firestore
        await _mediaSvc.update(
          widget.avatarId,
          media.id,
          url: upload,
          aspectRatio: _cropAspect,
          tags: newTags.isNotEmpty ? newTags : null,
        );
        await _load();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newTags.isNotEmpty
                  ? 'Bild neu zugeschnitten (${newTags.length} Tags erkannt)'
                  : 'Bild erfolgreich neu zugeschnitten',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler beim Zuschneiden: $e')));
      }
    }
  }

  Future<void> _openViewer(AvatarMedia media) async {
    if (media.type == AvatarMediaType.image) {
      await showDialog(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: GestureDetector(
            onLongPress: () {
              Navigator.pop(context);
              _reopenCrop(media);
            },
            child: InteractiveViewer(
              child: Image.network(media.url, fit: BoxFit.contain),
            ),
          ),
        ),
      );
    } else if (media.type == AvatarMediaType.video) {
      await showDialog(
        context: context,
        builder: (_) => _VideoDialog(url: media.url),
      );
    }
  }

  /// Aktualisiert Tags für bestehende Bilder ohne Tags
  Future<void> _updateExistingImageTags() async {
    try {
      // Finde Bilder ohne Tags
      final imagesWithoutTags = _items
          .where(
            (item) =>
                item.type == AvatarMediaType.image &&
                (item.tags == null || item.tags!.isEmpty),
          )
          .toList();

      if (imagesWithoutTags.isEmpty) return;

      print('🔄 Aktualisiere Tags für ${imagesWithoutTags.length} Bilder...');

      for (final image in imagesWithoutTags) {
        try {
          // Lade Bild herunter für Analyse
          final tempFile = await _downloadToTemp(image.url, suffix: '.jpg');
          if (tempFile == null) continue;

          // Analysiere mit Vision API
          final tags = await _visionSvc.analyzeImage(tempFile.path);

          if (tags.isNotEmpty) {
            // Aktualisiere in Firestore
            await _mediaSvc.update(widget.avatarId, image.id, tags: tags);
            print('✅ Tags für Bild ${image.id}: $tags');
          }

          // Lösche temporäre Datei
          await tempFile.delete();
        } catch (e) {
          print('❌ Fehler bei Tag-Update für Bild ${image.id}: $e');
        }
      }

      // Lade Daten neu
      await _load();
      print('🎉 Tag-Update abgeschlossen!');
    } catch (e) {
      print('❌ Fehler beim Tag-Update: $e');
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
