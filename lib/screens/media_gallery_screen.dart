import 'dart:typed_data';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:crop_your_image/crop_your_image.dart' as cyi;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../widgets/custom_price_field.dart';
import '../widgets/custom_currency_select.dart';
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
import 'package:audioplayers/audioplayers.dart';
import '../theme/app_theme.dart';
import '../widgets/video_player_widget.dart';
import '../widgets/avatar_nav_bar.dart';
import '../services/avatar_service.dart';
import '../services/audio_player_service.dart';
import '../widgets/custom_text_field.dart';

class MediaGalleryScreen extends StatefulWidget {
  final String avatarId;
  final String? fromScreen; // 'avatar-list' oder null
  const MediaGalleryScreen({
    super.key,
    required this.avatarId,
    this.fromScreen,
  });

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

  // Audio Player State
  String? _playingAudioUrl;
  final Map<String, double> _audioProgress = {}; // url -> progress (0.0 - 1.0)
  final Map<String, Duration> _audioCurrentTime = {}; // url -> current time
  final Map<String, Duration> _audioTotalTime = {}; // url -> total time
  AudioPlayer? _audioPlayer;
  final Set<String> _editingPriceMediaIds =
      {}; // IDs der Medien mit offenen Price-Inputs
  final Map<String, TextEditingController> _priceControllers =
      {}; // Controllers für Preis-Inputs
  final Map<String, String> _tempCurrency = {}; // Temporäre Currency pro Media

  // Statische Referenz um Player über Hot-Reload hinweg zu tracken
  static AudioPlayer? _globalAudioPlayer;

  @override
  void initState() {
    super.initState();

    // WICHTIG: Stoppe evtl. laufenden Player (Hot-Restart)
    _stopAllPlayers();

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
  void reassemble() {
    super.reassemble();
    // WIRD BEI HOT-RELOAD AUFGERUFEN - Stoppe Player!
    print('🔄 HOT RELOAD: Stoppe Audio Player');
    _stopAllPlayers();
  }

  /// Zentrale Methode zum Stoppen aller Player
  void _stopAllPlayers() {
    _audioPlayer?.stop();
    _audioPlayer?.dispose();
    _audioPlayer = null;
    _globalAudioPlayer?.stop();
    _globalAudioPlayer?.dispose();
    _globalAudioPlayer = null;
    AudioPlayerService().stopAll();
    _playingAudioUrl = null;
    _audioProgress.clear();
    _audioCurrentTime.clear();
    _audioTotalTime.clear();
  }

  @override
  void dispose() {
    _searchController.dispose();
    // Thumbnail-Controller aufräumen
    for (final controller in _thumbControllers.values) {
      controller.dispose();
    }
    _thumbControllers.clear();
    // Preis-Controller aufräumen
    for (final controller in _priceControllers.values) {
      controller.dispose();
    }
    _priceControllers.clear();
    // Audio Player STOPPEN und aufräumen
    _audioPlayer?.stop();
    _audioPlayer?.dispose();
    _audioPlayer = null;
    _globalAudioPlayer?.stop();
    _globalAudioPlayer?.dispose();
    _globalAudioPlayer = null;
    super.dispose();
  }

  Future<void> _load() async {
    // Audio-Player stoppen bei Screen-Refresh
    _audioPlayer?.stop();
    _audioPlayer?.dispose();
    _audioPlayer = null;
    if (mounted) {
      setState(() {
        _playingAudioUrl = null;
        _audioProgress.clear();
        _audioCurrentTime.clear();
        _audioTotalTime.clear();
      });
    }

    setState(() => _loading = true);
    try {
      final list = await _mediaSvc.list(widget.avatarId);
      print('📦 Medien geladen: ${list.length} Objekte');
      print(
        '  - Bilder: ${list.where((m) => m.type == AvatarMediaType.image).length}',
      );
      print(
        '  - Videos: ${list.where((m) => m.type == AvatarMediaType.video).length}',
      );
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
      if (_mediaTab == 'images' && it.type != AvatarMediaType.image) {
        return false;
      }
      if (_mediaTab == 'videos' && it.type != AvatarMediaType.video) {
        return false;
      }
      if (_mediaTab == 'audio' && it.type != AvatarMediaType.audio) {
        return false;
      }

      // Orientierungsfilter: IMMER filtern, nie gemischt (außer Audio)
      if (it.type != AvatarMediaType.audio) {
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
      }

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
    final originalName = p.basename(x.path);
    await _openCrop(bytes, p.extension(x.path), originalName);
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
        content: const Text('Woher sollen die Videos kommen?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _pickVideoFrom(ImageSource.camera); // Single für Kamera
            },
            child: const Text('Kamera (1 Video)'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _pickMultipleVideos(); // Multi für Galerie
            },
            child: const Text('Galerie (Mehrere)'),
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

  /// Multi-Upload: Mehrere Videos auf einmal auswählen (nur Galerie)
  Future<void> _pickMultipleVideos() async {
    try {
      // FilePicker mit Video-Filter (nur Videos erlaubt)
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) return;

      // Konvertiere PlatformFile zu File
      final videos = result.files
          .where((file) => file.path != null)
          .map((file) => File(file.path!))
          .toList();

      if (videos.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keine Videos ausgewählt')),
        );
        return;
      }

      setState(() {
        _uploadQueue = videos;
        _isUploading = true;
        _uploadProgress = 0;
        _uploadStatus = 'Videos werden hochgeladen...';
      });

      await _processVideoUploadQueue();
    } catch (e) {
      print('Fehler bei Video-Auswahl: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Fehler bei Video-Auswahl')));
    }
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
          print('🔍 KI-Tags für Bild ${i + 1}: $tags');
        } catch (e) {
          print('❌ Fehler bei KI-Analyse für Bild ${i + 1}: $e');
        }

        // Upload
        final url = await FirebaseStorageService.uploadImage(
          file,
          customPath: 'avatars/${widget.avatarId}/images/$timestamp$ext',
        );

        if (url != null) {
          // Berechne Aspect Ratio
          final aspectRatio = await _calculateAspectRatio(file);

          final media = AvatarMedia(
            id: timestamp.toString(),
            avatarId: widget.avatarId,
            type: AvatarMediaType.image,
            url: url,
            createdAt: timestamp,
            aspectRatio: aspectRatio,
            tags: tags.isNotEmpty ? tags : null,
          );
          await _mediaSvc.add(widget.avatarId, media);
          print('✅ Bild ${i + 1} hochgeladen mit ${tags.length} Tags');
        }
      } catch (e) {
        print('Fehler beim Upload von Bild ${i + 1}: $e');
      }
    }

    // Upload abgeschlossen
    final uploadedCount =
        _uploadQueue.length; // Speichere Anzahl VOR dem Leeren
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
          content: Text('$uploadedCount Bilder erfolgreich hochgeladen!'),
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

        // Verwende originalen Dateinamen oder generiere einen
        final originalName = image.originalFileName ?? 'image_${image.id}.png';

        // Zeige Cropping-Dialog
        await _openCrop(bytes, p.extension(image.url), originalName);

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

  Future<void> _openCrop(
    Uint8List imageBytes,
    String ext,
    String originalFileName,
  ) async {
    double currentAspect = _cropAspect;
    final cropController =
        cyi.CropController(); // Neuer Controller für jeden Dialog
    bool isCropping = false; // Loading-State

    await showDialog(
      context: context,
      barrierDismissible: false, // Nicht während Upload schließbar
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            contentPadding: EdgeInsets.zero,
            content: SizedBox(
              width: 380,
              height: 560,
              child: Stack(
                children: [
                  Column(
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
                              onSelected: isCropping
                                  ? null
                                  : (_) {
                                      setLocal(() => currentAspect = 9 / 16);
                                    },
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('16:9'),
                              selected: currentAspect == 16 / 9,
                              onSelected: isCropping
                                  ? null
                                  : (_) {
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
                          onCropped: (cropResult) async {
                            if (!mounted) return;
                            if (cropResult is cyi.CropSuccess) {
                              _cropAspect = currentAspect;

                              // SOFORT Loading anzeigen
                              setLocal(() => isCropping = true);

                              // Upload durchführen
                              await _uploadImage(cropResult.croppedImage, ext);

                              // Dialog schließen
                              if (mounted) Navigator.of(context).pop();
                            }
                          },
                        ),
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: isCropping
                                ? null
                                : () => Navigator.pop(ctx),
                            child: const Text('Abbrechen'),
                          ),
                          const Spacer(),
                          ElevatedButton(
                            onPressed: isCropping
                                ? null
                                : () {
                                    // Force crop auch wenn nicht bewegt wurde
                                    try {
                                      cropController.crop();
                                    } catch (e) {
                                      // Fallback: Croppe das ganze Bild
                                      setLocal(() => isCropping = true);
                                      _uploadImage(imageBytes, ext).then((_) {
                                        if (mounted) Navigator.of(ctx).pop();
                                      });
                                    }
                                  },
                            child: const Text('Zuschneiden'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // Loading Overlay
                  if (isCropping)
                    Container(
                      color: Colors.black87,
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text(
                              'Bild wird hochgeladen...',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
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
          'avatars/${widget.avatarId}/images/$timestamp${ext.isNotEmpty ? ext : '.jpg'}',
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

  /// Verarbeitet die Video-Upload-Queue
  Future<void> _processVideoUploadQueue() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    for (int i = 0; i < _uploadQueue.length; i++) {
      final file = _uploadQueue[i];
      final ext = p.extension(file.path).toLowerCase();

      setState(() {
        _uploadProgress = ((i + 1) / _uploadQueue.length * 100).round();
        _uploadStatus =
            'Lade Video ${i + 1} von ${_uploadQueue.length} hoch...';
      });

      try {
        final timestamp =
            DateTime.now().millisecondsSinceEpoch + i; // Eindeutige IDs

        // KI-Video-Analyse (aktuell: nur Metadaten, keine echte KI)
        List<String> tags = ['video']; // Basis-Tag
        print('📹 Video ${i + 1}: Basis-Tags: $tags');

        // Video-Dimensionen ermitteln
        double videoAspectRatio = 16 / 9; // Default
        try {
          final ctrl = VideoPlayerController.file(file);
          await ctrl.initialize();
          if (ctrl.value.aspectRatio != 0) {
            videoAspectRatio = ctrl.value.aspectRatio;
            print(
              '📐 Video ${i + 1} Aspect Ratio: $videoAspectRatio (${videoAspectRatio > 1.0 ? "Landscape" : "Portrait"})',
            );
          }
          await ctrl.dispose();
        } catch (e) {
          print('❌ Fehler bei Video-Dimensionen für Video ${i + 1}: $e');
        }

        // Upload
        final url = await FirebaseStorageService.uploadVideo(
          file,
          customPath: 'avatars/${widget.avatarId}/videos/$timestamp$ext',
        );

        if (url != null) {
          final media = AvatarMedia(
            id: timestamp.toString(),
            avatarId: widget.avatarId,
            type: AvatarMediaType.video,
            url: url,
            createdAt: timestamp,
            aspectRatio: videoAspectRatio,
            tags: tags,
          );
          await _mediaSvc.add(widget.avatarId, media);
          print(
            '✅ Video ${i + 1} gespeichert: ID=${media.id}, URL=$url, AspectRatio=$videoAspectRatio',
          );
        } else {
          print('❌ Video ${i + 1}: Upload fehlgeschlagen - URL ist null');
        }
      } catch (e) {
        print('❌ Fehler beim Upload von Video ${i + 1}: $e');
      }
    }

    // Upload abgeschlossen
    final uploadedCount = _uploadQueue.length;
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
          content: Text('$uploadedCount Videos erfolgreich hochgeladen!'),
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

    // KI-Video-Analyse (aktuell: nur Metadaten, keine echte KI)
    List<String> tags = ['video']; // Basis-Tag

    // Video-Dimensionen ermitteln
    double videoAspectRatio = 16 / 9; // Default
    try {
      final ctrl = VideoPlayerController.file(File(x.path));
      await ctrl.initialize();
      if (ctrl.value.aspectRatio != 0) {
        videoAspectRatio = ctrl.value.aspectRatio;
        print(
          '📐 Video Aspect Ratio: $videoAspectRatio (${videoAspectRatio > 1.0 ? "Landscape" : "Portrait"})',
        );
      }
      await ctrl.dispose();
    } catch (e) {
      print('❌ Fehler bei Video-Dimensionen: $e');
    }

    final url = await FirebaseStorageService.uploadVideo(
      File(x.path),
      customPath: 'avatars/${widget.avatarId}/videos/$timestamp.mp4',
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
      aspectRatio: videoAspectRatio,
      tags: tags,
    );
    await _mediaSvc.add(widget.avatarId, m);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video erfolgreich hochgeladen')),
      );
    }
  }

  void _handleBackNavigation(BuildContext context) async {
    // WICHTIG: Audio Player STOPPEN beim Verlassen des Screens
    await _audioPlayer?.stop();
    _audioPlayer?.dispose();
    _audioPlayer = null;
    await _globalAudioPlayer?.stop();
    _globalAudioPlayer?.dispose();
    _globalAudioPlayer = null;
    setState(() {
      _playingAudioUrl = null;
      _audioProgress.clear();
      _audioCurrentTime.clear();
      _audioTotalTime.clear();
    });

    if (widget.fromScreen == 'avatar-list') {
      // Von "Meine Avatare" → zurück zu "Meine Avatare" (ALLE Screens schließen)
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/avatar-list',
        (route) => false,
      );
    } else {
      // Von anderen Screens → zurück zu Avatar Details
      final avatarService = AvatarService();
      final avatar = await avatarService.getAvatar(widget.avatarId);
      if (avatar != null && context.mounted) {
        Navigator.pushReplacementNamed(
          context,
          '/avatar-details',
          arguments: avatar,
        );
      } else {
        Navigator.pop(context);
      }
    }
  }

  /// Audio abspielen / pausieren
  Future<void> _toggleAudioPlayback(AvatarMedia media) async {
    // Wenn dasselbe Audio bereits spielt → Pause
    if (_playingAudioUrl == media.url && _audioPlayer != null) {
      await _audioPlayer!.pause();
      setState(() => _playingAudioUrl = null);
      return;
    }

    // Wenn dasselbe Audio pausiert ist → Resume
    if (_playingAudioUrl == null &&
        _audioPlayer != null &&
        (_audioCurrentTime[media.url]?.inMilliseconds ?? 0) > 0) {
      try {
        await _audioPlayer!.resume();
        setState(() => _playingAudioUrl = media.url);
        return;
      } catch (e) {
        // Fallback: Neuen Player erstellen
      }
    }

    // Anderes Audio → Stop aktuelles und starte neues
    await _audioPlayer?.stop();
    _audioPlayer?.dispose();
    _audioPlayer = AudioPlayer();
    _globalAudioPlayer = _audioPlayer; // Lokale Referenz setzen
    AudioPlayerService().setCurrentPlayer(
      _audioPlayer!,
    ); // Service für Hot-Restart

    // Listener für Fortschritt
    _audioPlayer!.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() {
          _audioCurrentTime[media.url] = position;
          final total = _audioTotalTime[media.url];
          if (total != null && total.inMilliseconds > 0) {
            _audioProgress[media.url] =
                position.inMilliseconds / total.inMilliseconds;
          }
        });
      }
    });

    // Listener für Ende
    _audioPlayer!.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playingAudioUrl = null;
          _audioProgress[media.url] = 0.0;
          _audioCurrentTime[media.url] = Duration.zero;
        });
      }
    });

    // Listener für Dauer
    _audioPlayer!.onDurationChanged.listen((duration) {
      if (mounted) {
        setState(() => _audioTotalTime[media.url] = duration);
      }
    });

    try {
      await _audioPlayer!.play(UrlSource(media.url));
      setState(() => _playingAudioUrl = media.url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler beim Abspielen: $e')));
      }
    }
  }

  /// Audio von Anfang an starten
  Future<void> _restartAudio(AvatarMedia media) async {
    await _audioPlayer?.stop();
    setState(() {
      _audioProgress[media.url] = 0.0;
      _audioCurrentTime[media.url] = Duration.zero;
      _playingAudioUrl = null;
    });

    // Neu starten
    await _toggleAudioPlayback(media);
  }

  /// Formatiere Duration für Anzeige
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _pickAudio() async {
    try {
      // File Picker für Audio-Dateien
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) return;

      setState(() {
        _isUploading = true;
        _uploadProgress = 0;
        _uploadStatus = 'Audio-Dateien werden hochgeladen...';
      });

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        throw Exception('Benutzer nicht angemeldet');
      }

      int uploaded = 0;
      for (int i = 0; i < result.files.length; i++) {
        final file = result.files[i];
        if (file.path == null) continue;

        setState(() {
          _uploadProgress = ((i / result.files.length) * 100).toInt();
          _uploadStatus =
              'Audio ${i + 1}/${result.files.length} wird hochgeladen...';
        });

        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileExtension = file.extension ?? 'mp3';

        // Firebase Storage Upload
        final url = await FirebaseStorageService.uploadAudio(
          File(file.path!),
          customPath:
              'avatars/${widget.avatarId}/audio/${timestamp}_$i.$fileExtension',
        );

        if (url != null) {
          // Firestore speichern
          final m = AvatarMedia(
            id: '${timestamp}_$i',
            avatarId: widget.avatarId,
            type: AvatarMediaType.audio,
            url: url,
            createdAt: timestamp,
            tags: ['audio', file.name],
            originalFileName: file.name, // Originaler Dateiname
          );
          await _mediaSvc.add(widget.avatarId, m);
          uploaded++;
        }
      }

      setState(() {
        _isUploading = false;
        _uploadProgress = 0;
        _uploadStatus = '';
      });

      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$uploaded Audio-Dateien erfolgreich hochgeladen!'),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isUploading = false;
        _uploadProgress = 0;
        _uploadStatus = '';
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler beim Audio-Upload: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.read<LocalizationService>();
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.t('gallery.title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _handleBackNavigation(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Tags aktualisieren',
            onPressed: _updateExistingImageTags,
            icon: const Icon(Icons.auto_awesome),
          ),
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
                // Globale Navigation
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: AvatarNavBar(
                    avatarId: widget.avatarId,
                    currentScreen: 'media',
                  ),
                ),
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
                          child: CustomTextField(
                            label: 'Suche nach Medien...',
                            controller: _searchController,
                            prefixIcon: const Icon(
                              Icons.search,
                              color: Colors.white70,
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

                // Responsive Grid wie in avatar_details_screen
                Expanded(
                  child: _pageItems.isEmpty
                      ? Center(
                          child: Text(
                            'Keine Medien gefunden',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        )
                      : _mediaTab == 'audio'
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Wrap(
                            alignment: WrapAlignment.start,
                            spacing: 12.0,
                            runSpacing: 12.0,
                            children: _pageItems.map((it) {
                              return _buildResponsiveMediaCard(
                                it,
                                0, // Unused for audio
                                0, // Unused for audio
                              );
                            }).toList(),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: LayoutBuilder(
                            builder: (ctx, cons) {
                              const double spacing = 16.0;
                              const double minThumbWidth = 120.0;
                              const double gridSpacing = 12.0;
                              const double cardHeight = 150.0;

                              // Rechts mindestens 2 Thumbs: 2 * min + Zwischenabstand
                              final double minRightWidth =
                                  (2 * minThumbWidth) + gridSpacing;
                              double leftW =
                                  cons.maxWidth - spacing - minRightWidth;
                              // Begrenze links sinnvoll - 25% weniger als avatar_details_screen
                              if (leftW > 180) leftW = 180; // 240 * 0.75 = 180
                              if (leftW < 120) leftW = 120; // 160 * 0.75 = 120

                              return Wrap(
                                spacing: gridSpacing,
                                runSpacing: gridSpacing,
                                children: _pageItems.map((it) {
                                  return _buildResponsiveMediaCard(
                                    it,
                                    leftW,
                                    cardHeight,
                                  );
                                }).toList(),
                              );
                            },
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

  /// Responsive Media Card wie in avatar_details_screen
  Widget _buildResponsiveMediaCard(
    AvatarMedia it,
    double cardWidth,
    double cardHeight,
  ) {
    final usedInPlaylists = _mediaToPlaylists[it.id] ?? [];
    final isInPlaylist = usedInPlaylists.isNotEmpty;
    final selected = _selectedMediaIds.contains(it.id);

    // Berechne echte Dimensionen basierend auf Crop-Aspekt-Verhältnis
    // cardWidth ist die responsive Basis-Breite (120-180px)
    double aspectRatio = it.aspectRatio ?? (9 / 16); // Default Portrait

    // Audio: Breite wie 7 Navi-Buttons (40px * 7 + 8px * 6 = 328px), Höhe mit Platz für Tags
    if (it.type == AvatarMediaType.audio) {
      const double audioCardWidth =
          328.0; // 7 Buttons (40px) + 6 Abstände (8px)

      // KEIN GestureDetector mehr - alle Interaktionen sind in _buildAudioCard!
      return _buildAudioCard(
        it,
        audioCardWidth,
        null, // Auto-Height!
        isInPlaylist,
        usedInPlaylists,
        selected,
      );
    }

    // Landscape-Bilder bekommen doppelte Start-Höhe
    double baseWidth = cardWidth;
    if (aspectRatio > 1.0) {
      // Landscape (16:9): Doppelte Basis-Breite für mehr Höhe
      baseWidth = cardWidth * 2;
    }

    // Höhe basierend auf responsive Breite
    double actualHeight = baseWidth / aspectRatio; // Höhe berechnet aus Breite
    double actualWidth = baseWidth; // Responsive Breite

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
        width: actualWidth,
        height: actualHeight,
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
                  : it.type == AvatarMediaType.video
                  ? FutureBuilder<VideoPlayerController?>(
                      future: _videoControllerForThumb(it.url),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.done &&
                            snapshot.hasData &&
                            snapshot.data != null) {
                          final controller = snapshot.data!;
                          if (controller.value.isInitialized) {
                            return FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: controller.value.size.width,
                                height: controller.value.size.height,
                                child: VideoPlayer(controller),
                              ),
                            );
                          }
                        }
                        // Während des Ladens: schwarzer Container
                        return Container(color: Colors.black26);
                      },
                    )
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF1A1A1A), Color(0xFF0A0A0A)],
                        ),
                      ),
                      child: Stack(
                        children: [
                          // Moderne Waveform-Visualisierung
                          Center(child: _buildWaveform()),
                          // Audio Icon mit Gradient
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFE91E63), // Magenta
                                        AppColors.lightBlue, // Blue
                                        Color(0xFF00E5FF), // Cyan
                                      ],
                                      stops: [0.0, 0.5, 1.0],
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.music_note,
                                    size: 32,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    it.tags?.isNotEmpty == true
                                        ? it.tags!.first
                                        : 'Audio',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
                  onLongPress: () => _showTagsDialog(it),
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

            // Tag-Icon unten links (für Videos und Audio)
            if ((it.type == AvatarMediaType.video ||
                    it.type == AvatarMediaType.audio) &&
                !_isDeleteMode)
              Positioned(
                left: 6,
                bottom: 6,
                child: InkWell(
                  onTap: () => _showTagsDialog(it),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0x25FFFFFF), // #ffffff25
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0x66FFFFFF)),
                    ),
                    child: ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Color(0xFFE91E63), AppColors.lightBlue],
                      ).createShader(bounds),
                      child: const Icon(
                        Icons.label_outline,
                        color: Colors.white,
                        size: 16,
                      ),
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
        // Prüfe ob dieses Medium gerade abgespielt wird
        final media = _items.firstWhere(
          (m) => m.id == mediaId,
          orElse: () => _items.first,
        );
        if (_playingAudioUrl == media.url) {
          // Stoppe Audio Player
          await _audioPlayer?.stop();
          _audioPlayer?.dispose();
          _audioPlayer = null;
          setState(() {
            _playingAudioUrl = null;
            _audioProgress.remove(media.url);
            _audioCurrentTime.remove(media.url);
            _audioTotalTime.remove(media.url);
          });
        }

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

  Future<double> _calculateAspectRatio(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final aspectRatio = image.width / image.height;
      image.dispose();
      return aspectRatio;
    } catch (e) {
      print('❌ Fehler bei Aspect Ratio Berechnung: $e');
      return 9 / 16; // Default Portrait
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

  // Cache für Thumbnail-Controller
  final Map<String, VideoPlayerController> _thumbControllers = {};

  Future<VideoPlayerController?> _videoControllerForThumb(String url) async {
    try {
      // Cache-Check
      if (_thumbControllers.containsKey(url)) {
        final cached = _thumbControllers[url];
        if (cached != null && cached.value.isInitialized) {
          return cached;
        }
      }

      // Frische Download-URL holen
      final fresh = await _refreshDownloadUrl(url) ?? url;
      debugPrint('🎬 _videoControllerForThumb url=$url | fresh=$fresh');

      final controller = VideoPlayerController.networkUrl(Uri.parse(fresh));
      await controller.initialize();
      await controller.setLooping(false);
      // Nicht abspielen - nur erstes Frame zeigen

      _thumbControllers[url] = controller;
      return controller;
    } catch (e) {
      debugPrint('🎬 _videoControllerForThumb error: $e');
      return null;
    }
  }

  /// Video-Thumbnail generieren (1:1 aus avatar_details_screen)

  /// Refresh Firebase Storage Download URL (1:1 aus avatar_details_screen)
  Future<String?> _refreshDownloadUrl(String maybeExpiredUrl) async {
    try {
      final path = _storagePathFromUrl(maybeExpiredUrl);
      if (path.isEmpty) return null;
      final ref = FirebaseStorage.instance.ref().child(path);
      final fresh = await ref.getDownloadURL();
      return fresh;
    } catch (_) {
      return null;
    }
  }

  /// Extrahiert Storage-Pfad aus Download-URL (1:1 aus avatar_details_screen)
  String _storagePathFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path; // enthält ggf. /o/<ENCODED_PATH>
      String enc;
      if (path.contains('/o/')) {
        enc = path.split('/o/').last;
      } else {
        enc = path.startsWith('/') ? path.substring(1) : path;
      }
      final decoded = Uri.decodeComponent(enc);
      final clean = decoded.split('?').first;
      return clean;
    } catch (_) {
      return url;
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
                        onCropped: (cropResult) async {
                          if (cropResult is cyi.CropSuccess) {
                            croppedBytes = cropResult.croppedImage;
                          }
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
    // Audio hat keinen Viewer, nur Tag-Dialog
    if (media.type == AvatarMediaType.audio) {
      await _showTagsDialog(media);
      return;
    }

    // Bestimme Kategorie: Portrait/Landscape + Image/Video
    final isPortrait = _isPortraitMedia(media);
    final mediaType = media.type;

    // Filtere nur Medien der gleichen Kategorie
    final filteredMedia = _items.where((m) {
      return m.type == mediaType && _isPortraitMedia(m) == isPortrait;
    }).toList();

    // Finde Index in gefilterter Liste
    final currentIndex = filteredMedia.indexOf(media);

    await showDialog(
      context: context,
      builder: (_) => _MediaViewerDialog(
        initialMedia: media,
        allMedia: filteredMedia,
        initialIndex: currentIndex,
        onCropRequest: (m) {
          Navigator.pop(context);
          _reopenCrop(m);
        },
      ),
    );
  }

  /// Prüft ob Medium Portrait-Format hat (Höhe > Breite)
  bool _isPortraitMedia(AvatarMedia media) {
    // Nutze aspectRatio (width / height)
    // Portrait: aspectRatio < 1.0 (z.B. 9/16 = 0.5625)
    // Landscape: aspectRatio > 1.0 (z.B. 16/9 = 1.7778)
    if (media.aspectRatio != null) {
      return media.aspectRatio! < 1.0;
    }
    // Fallback: Prüfe "portrait" in Tags
    if (media.tags != null && media.tags!.contains('portrait')) {
      return true;
    }
    // Standard: Landscape (wenn keine Info verfügbar)
    return false;
  }

  /// Preis-Setup Container: Klickbar, zeigt Input-Ansicht
  Widget _buildPriceSetupContainer(AvatarMedia media) {
    final isEditing = _editingPriceMediaIds.contains(media.id);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          // Nur öffnen wenn NICHT editing - Klick bei geöffnetem Input ignorieren
          if (!isEditing) {
            setState(() {
              // Controller initialisieren beim Öffnen
              if (!_priceControllers.containsKey(media.id)) {
                final price = media.price ?? 0.0;
                final priceText = price.toStringAsFixed(2).replaceAll('.', ',');
                _priceControllers[media.id] = TextEditingController(
                  text: priceText,
                );
              }
              // Temp-Currency setzen
              _tempCurrency[media.id] = media.currency ?? '€';
              _editingPriceMediaIds.add(media.id);
            });
          }
        },
        child: Container(
          height: 40,
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(7),
              bottomRight: Radius.circular(7),
            ),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xFFE91E63), // Magenta
                AppColors.lightBlue, // Blue
                Color(0xFF00E5FF), // Cyan
              ],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
          padding: EdgeInsets.zero,
          child: Row(
            children: [
              // LINKS: Preis-Anzeige oder Input
              Expanded(child: _buildPriceField(media, isEditing)),
              // RECHTS: Credits kaufen Link (immer) + Hook (nur wenn editing)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // "Credits kaufen" Link
                  TextButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/credits-shop');
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Credits →',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  // X-Button (Abbrechen) - nur wenn editing, LINKS vom Hook
                  if (isEditing)
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          // Abbrechen ohne Speichern - alte Werte wiederherstellen
                          final price = media.price ?? 0.0;
                          final priceText = price
                              .toStringAsFixed(2)
                              .replaceAll('.', ',');
                          _priceControllers[media.id]?.text = priceText;
                          _tempCurrency[media.id] = media.currency ?? '€';
                          _editingPriceMediaIds.remove(media.id);
                          setState(() {});
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: Colors.transparent,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  // Hook Icon (nur wenn editing) - Speichern, RECHTS vom X
                  if (isEditing)
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () async {
                          // Preis aus Input parsen
                          final inputText =
                              _priceControllers[media.id]?.text ?? '0,00';
                          final cleanText = inputText.replaceAll(',', '.');
                          final newPrice = double.tryParse(cleanText) ?? 0.0;
                          final newCurrency = _tempCurrency[media.id] ?? '€';

                          // Firestore Update
                          try {
                            await FirebaseFirestore.instance
                                .collection('avatars')
                                .doc(widget.avatarId)
                                .collection('media')
                                .doc(media.id)
                                .update({
                                  'price': newPrice,
                                  'currency': newCurrency,
                                });

                            // Lokale Liste aktualisieren
                            final index = _items.indexWhere(
                              (m) => m.id == media.id,
                            );
                            if (index != -1) {
                              _items[index] = AvatarMedia(
                                id: media.id,
                                avatarId: media.avatarId,
                                type: media.type,
                                url: media.url,
                                thumbUrl: media.thumbUrl,
                                createdAt: media.createdAt,
                                durationMs: media.durationMs,
                                aspectRatio: media.aspectRatio,
                                tags: media.tags,
                                originalFileName: media.originalFileName,
                                isFree: media.isFree,
                                price: newPrice,
                                currency: newCurrency,
                              );
                            }

                            // Input schließen
                            _editingPriceMediaIds.remove(media.id);
                            setState(() {});
                          } catch (e) {
                            debugPrint('Fehler beim Speichern des Preises: $e');
                          }
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.only(
                              bottomRight: Radius.circular(7),
                            ),
                          ),
                          child: ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFFE91E63), // Magenta
                                Color(0xFFE91E63), // Mehr Magenta
                                AppColors.lightBlue, // Blue
                                Color(0xFF00E5FF), // Cyan
                              ],
                              stops: [0.0, 0.4, 0.7, 1.0],
                            ).createShader(bounds),
                            child: const Icon(
                              Icons.check,
                              size: 24,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    // Platzhalter für X + Hook (damit Credits-Link an Stelle bleibt)
                    const SizedBox(width: 80, height: 40),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Preis-Feld: Zeigt Preis + Credits oder Input
  Widget _buildPriceField(AvatarMedia media, bool isEditing) {
    final price = media.price ?? 0.0;
    final priceText = price.toStringAsFixed(2).replaceAll('.', ',');
    final credits = (price / 0.1).round(); // 10 Cent = 1 Credit
    final currency = media.currency ?? '€';

    return Container(
      height: 40,
      padding: EdgeInsets.zero,
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Preis-Feld (Display + Input in EINEM Widget)
            // Preis-Feld (Display + Input) - KEINE width, auto
            CustomPriceField(
              isEditing: isEditing,
              displayText: priceText,
              hintText: '0,00',
              autofocus: true,
              controller: isEditing ? _priceControllers[media.id] : null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (value) {
                // Nur State neu bauen, kein Firestore-Update
                setState(() {});
              },
            ),
            const SizedBox(width: 8),
            // Währungs-Select (immer) - vertikal mittig
            SizedBox(
              height: 40,
              child: Align(
                alignment: Alignment.center,
                child: CustomCurrencySelect(
                  value: isEditing
                      ? (_tempCurrency[media.id] ?? currency)
                      : currency,
                  onChanged: (value) {
                    if (isEditing && value != null) {
                      setState(() {
                        _tempCurrency[media.id] = value;
                      });
                    }
                  },
                ),
              ),
            ),
            if (!isEditing) ...[
              const SizedBox(width: 10),
              // Credits-Anzeige
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '($credits',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.diamond, size: 12, color: Colors.white),
                  Text(
                    ')',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Audio-Preview für Tags-Dialog im Audio-Card-Style
  Widget _buildAudioPreviewForDialog(AvatarMedia media) {
    final isPlaying = _playingAudioUrl == media.url;
    final progress = _audioProgress[media.url] ?? 0.0;
    final currentTime = _audioCurrentTime[media.url] ?? Duration.zero;
    final totalTime = _audioTotalTime[media.url] ?? Duration.zero;
    final fileName =
        media.originalFileName ??
        Uri.parse(media.url).pathSegments.last.split('?').first;

    return Container(
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A1A), Color(0xFF0A0A0A)],
        ),
      ),
      child: Stack(
        children: [
          // Waveform - volle Breite, VERTIKAL MITTIG (ZUERST, damit Buttons darüber liegen)
          Positioned(
            left: 20,
            right: 20,
            top: 0,
            bottom: 32, // Minimaler Platz für Name/Zeit unten (32px total)
            child: GestureDetector(
              onTap: () {
                _toggleAudioPlayback(media);
                // Dialog neu bauen, damit Play/Pause Icon aktualisiert wird
                if (mounted) setState(() {});
              },
              child: Center(
                child: ClipRect(
                  clipBehavior: Clip.hardEdge,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return _buildCompactWaveform(
                        availableWidth: constraints.maxWidth,
                        progress: progress,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          // Play/Pause + Restart Buttons ÜBER der Waveform, VERTIKAL MITTIG (höherer Z-Index)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 32, // Minimaler Platz für Name/Zeit unten (32px total)
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Play/Pause Button
                  GestureDetector(
                    onTap: () {
                      _toggleAudioPlayback(media);
                      // Timer wird Dialog automatisch aktualisieren
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFFE91E63), // Magenta
                            AppColors.lightBlue, // Blau
                            Color(0xFF00E5FF), // Cyan
                          ],
                          stops: [0.0, 0.6, 1.0],
                        ),
                      ),
                      child: Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        size: 32,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  // Restart Button (nur wenn Audio läuft oder pausiert)
                  if (progress > 0.0 || isPlaying)
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: GestureDetector(
                        onTap: () {
                          _restartAudio(media);
                          // Timer wird Dialog automatisch aktualisieren
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0x60FFFFFF),
                          ),
                          child: const Icon(
                            Icons.replay,
                            size: 22,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // NAME und ZEIT - ABSTAND REDUZIERT (roter Kasten!)
          Positioned(
            left: 20,
            right: 20,
            bottom: 25, // 25% nach oben - nicht zu viel!
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Dateiname OBEN
                Text(
                  fileName,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 1),
                // Zeit UNTEN
                Text(
                  '${_formatDuration(currentTime)} / ${_formatDuration(totalTime)}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Generiere intelligente Tag-Vorschläge aus Dateinamen
  List<String> _generateSmartTags(AvatarMedia media) {
    // Dateiname extrahieren
    final fileName =
        media.originalFileName ??
        Uri.parse(media.url).pathSegments.last.split('?').first;

    // Stopp-Wörter Liste (case-insensitive)
    final stopWords = [
      'audio',
      'the',
      'track',
      'song',
      'music',
      'file',
      'recording',
      'mix',
      'version',
      'edit',
      'final',
      'mp3',
      'wav',
      'flac',
      'm4a',
      'aac',
      'ogg',
    ];

    // Dateiendung entfernen und bereinigen
    String cleaned = fileName
        .replaceAll(
          RegExp(
            r'\.(mp3|wav|m4a|flac|aac|ogg|mp4|mov|avi)$',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s*[Pp]t\.?\s*\d+'), '') // "Pt.2", "pt2" entfernen
        .replaceAll(RegExp(r'\s*[Tt]eil\s*\d+'), '') // "Teil 2" entfernen
        .replaceAll(
          RegExp(r'[_\-]+'),
          ' ',
        ) // Unterstriche/Bindestriche → Leerzeichen
        .replaceAll(RegExp(r'[\(\)\[\]{}]'), '') // Klammern entfernen
        .replaceAll(RegExp(r'\d+'), '') // Zahlen entfernen
        .replaceAll(RegExp(r'\s+'), ' ') // Mehrfache Leerzeichen
        .trim();

    // In Wörter splitten
    final words = cleaned.split(' ');

    // Filtere und bereinige Tags
    final tags = words
        .where((word) => word.length >= 3) // Mindestens 3 Zeichen
        .where(
          (word) => !stopWords.contains(word.toLowerCase()),
        ) // Stopp-Wörter raus
        .map((word) => word.trim().toLowerCase())
        .where((word) => word.isNotEmpty)
        .toSet() // Duplikate entfernen
        .toList();

    // Falls keine Tags übrig: Verwende ersten Teil des Dateinamens
    if (tags.isEmpty && fileName.isNotEmpty) {
      final fallback = fileName.split(RegExp(r'[_\-\.\s]')).first.toLowerCase();
      if (fallback.length >= 3 && !stopWords.contains(fallback)) {
        tags.add(fallback);
      }
    }

    // Falls IMMER NOCH leer: Nimm "audio" als Fallback
    if (tags.isEmpty) {
      tags.add('audio');
    }

    return tags;
  }

  /// Zeigt Dialog zum Anzeigen und Bearbeiten der Tags
  Future<void> _showTagsDialog(AvatarMedia media) async {
    // Ursprüngliche Tags (falls vorhanden) oder intelligente Vorschläge
    final originalTags = media.tags ?? [];
    final smartTags = _generateSmartTags(media);

    // Start mit den ursprünglichen Tags (oder Smart Tags wenn keine vorhanden)
    final controller = TextEditingController(
      text: originalTags.isNotEmpty
          ? originalTags.join(', ')
          : smartTags.join(', '),
    );
    final initialText = controller.text;

    // State für Vorschläge/Verwerfen Toggle
    bool showingSuggestions = false;
    String? savedText; // Text vor dem Wechsel zu Vorschlägen

    // Timer für Live-Update des Play/Pause Icons
    Timer? updateTimer;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Timer starten für kontinuierliche Updates (mit setDialogState)
            updateTimer?.cancel();
            updateTimer = Timer.periodic(const Duration(milliseconds: 100), (
              _,
            ) {
              if (context.mounted) {
                setDialogState(() {});
              }
            });
            final hasChanged = controller.text != initialText;

            return Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(
                  top: 100.0,
                  left: 16.0,
                  right: 16.0,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: 400, // Maximal 400px Breite
                    constraints: const BoxConstraints(maxWidth: 400),
                    decoration: BoxDecoration(
                      color: Theme.of(context).dialogBackgroundColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Action Buttons OBEN (über dem Bild)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Abbrechen'),
                                ),
                                ElevatedButton(
                                  onPressed: hasChanged
                                      ? () async {
                                          final newTags = controller.text
                                              .split(',')
                                              .map((tag) => tag.trim())
                                              .where((tag) => tag.isNotEmpty)
                                              .toList();

                                          await _mediaSvc.update(
                                            widget.avatarId,
                                            media.id,
                                            tags: newTags,
                                          );
                                          await _load();
                                          Navigator.pop(ctx);

                                          if (mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  '${newTags.length} Tags gespeichert',
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                      : null, // Disabled wenn keine Änderung
                                  child: const Text('Speichern'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // Media Preview - Audio im Audio-Card-Style
                            if (media.type == AvatarMediaType.audio)
                              _buildAudioPreviewForDialog(media)
                            else
                              SizedBox(
                                height: 320,
                                child: media.type == AvatarMediaType.video
                                    ? FutureBuilder<VideoPlayerController?>(
                                        future: _videoControllerForThumb(
                                          media.url,
                                        ),
                                        builder: (context, snapshot) {
                                          if (snapshot.connectionState ==
                                                  ConnectionState.done &&
                                              snapshot.hasData &&
                                              snapshot.data != null) {
                                            final controller = snapshot.data!;
                                            if (controller
                                                .value
                                                .isInitialized) {
                                              return AspectRatio(
                                                aspectRatio: controller
                                                    .value
                                                    .aspectRatio,
                                                child: VideoPlayer(controller),
                                              );
                                            }
                                          }
                                          return Container(
                                            color: Colors.black26,
                                          );
                                        },
                                      )
                                    : Image.network(
                                        media.url,
                                        height: 320,
                                        fit: BoxFit.cover,
                                      ),
                              ),
                            const SizedBox(height: 16),
                            // Header mit Vorschläge/Verwerfen Icon-Button RECHTS neben Text
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // "Audio-Tags" Text LINKS
                                Text(
                                  media.type == AvatarMediaType.video
                                      ? 'Video-Tags'
                                      : media.type == AvatarMediaType.audio
                                      ? 'Audio-Tags'
                                      : 'Bild-Tags',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                // Vorschläge/Verwerfen Icon-Button RECHTS (wie Navi-Buttons)
                                Tooltip(
                                  message: showingSuggestions
                                      ? 'Verwerfen'
                                      : 'Vorschläge',
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: const LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color(0xFFE91E63), // Magenta
                                          AppColors.lightBlue, // Blue
                                          Color(0xFF00E5FF), // Cyan
                                        ],
                                        stops: [0.0, 0.5, 1.0],
                                      ),
                                    ),
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      iconSize: 18,
                                      icon: Icon(
                                        showingSuggestions
                                            ? Icons.close
                                            : Icons.auto_awesome,
                                        color: Colors.white,
                                      ),
                                      onPressed: () {
                                        setDialogState(() {
                                          if (!showingSuggestions) {
                                            // Zu Vorschlägen wechseln
                                            savedText = controller.text;
                                            controller.text = smartTags.join(
                                              ', ',
                                            );
                                            showingSuggestions = true;
                                          } else {
                                            // Vorschläge verwerfen → zurück zum gespeicherten Text
                                            controller.text = savedText ?? '';
                                            showingSuggestions = false;
                                            savedText = null;
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            CustomTextArea(
                              label: 'Tags (durch Komma getrennt)',
                              controller: controller,
                              hintText: media.type == AvatarMediaType.video
                                  ? 'z.B. interview, outdoor, talking'
                                  : media.type == AvatarMediaType.audio
                                  ? 'z.B. musik, podcast, interview'
                                  : 'z.B. hund, outdoor, park',
                              onChanged: (_) => setDialogState(() {}),
                              minLines: 3,
                              maxLines: 5,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    // Timer stoppen nach Dialog-Schließung
    updateTimer?.cancel();
  }

  /// Audio Card - schmale Darstellung
  Widget _buildAudioCard(
    AvatarMedia it,
    double width,
    double? height, // Nullable für Auto-Height
    bool isInPlaylist,
    List<Playlist> usedInPlaylists,
    bool selected,
  ) {
    // Audio Player State für diese Card
    final isPlaying = _playingAudioUrl == it.url;
    final progress = _audioProgress[it.url] ?? 0.0;
    final currentTime = _audioCurrentTime[it.url] ?? Duration.zero;
    final totalTime = _audioTotalTime[it.url] ?? Duration.zero;

    // Verwende originalen Dateinamen (OHNE Pfad) oder Fallback aus URL
    final fileName =
        it.originalFileName ??
        Uri.parse(it.url).pathSegments.last.split('?').first;

    return SizedBox(
      width: width,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0x80E91E63), // Magenta 50% opacity
              Color(0x8000B0FF), // Blue 50% opacity
              Color(0x8000E5FF), // Cyan 50% opacity
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Container(
          margin: const EdgeInsets.all(1), // 1px für Border
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7), // 8 - 1 = 7
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A1A1A), Color(0xFF0A0A0A)],
            ),
          ),
          clipBehavior: Clip.hardEdge, // Verhindert Overflow
          child: Column(
            mainAxisSize: MainAxisSize.min, // Auto-Height!
            children: [
              // OBERER CONTAINER: Play, Waveform, Icons
              SizedBox(
                height: 78, // Feste Höhe für Waveform-Bereich
                child: Padding(
                  padding: const EdgeInsets.only(top: 8), // 0.5rem
                  child: Stack(
                    children: [
                      // Waveform - ZENTRIERT (5px nach links)
                      Positioned(
                        left: 30, // 35 - 5 = 30px
                        right: 80, // 75 + 5 = 80px (bleibt gleich breit)
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: GestureDetector(
                            onTap: () => _toggleAudioPlayback(it),
                            child: ClipRect(
                              clipBehavior: Clip.hardEdge,
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  return _buildCompactWaveform(
                                    availableWidth: constraints.maxWidth,
                                    progress: progress,
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Play-Button ÜBER Waveform - LINKS (5px nach rechts)
                      Positioned(
                        left: 13, // 8 + 5 = 13px
                        top: 0,
                        bottom: 0,
                        child: Align(
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Play/Pause Button
                              GestureDetector(
                                onTap: () => _toggleAudioPlayback(it),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFFE91E63), // Magenta
                                        Color(0xFFE91E63), // Mehr Magenta
                                        AppColors.lightBlue, // Blau
                                        Color(0xFF00E5FF), // Cyan
                                      ],
                                      stops: [0.0, 0.4, 0.7, 1.0],
                                    ),
                                  ),
                                  child: Icon(
                                    isPlaying ? Icons.pause : Icons.play_arrow,
                                    size: 24,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              // Restart Button (nur anzeigen wenn Audio läuft oder pausiert)
                              if (progress > 0.0 || isPlaying)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: GestureDetector(
                                    onTap: () => _restartAudio(it),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: const Color(0x40FFFFFF),
                                      ),
                                      child: const Icon(
                                        Icons.replay,
                                        size: 16,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      // Tag + Delete Icons RECHTS (10px nach links)
                      Positioned(
                        right: 13, // 3 + 10 = 13px
                        top: 0,
                        bottom: 0,
                        child: Align(
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Tag Icon
                              if (!_isDeleteMode)
                                InkWell(
                                  onTap: () => _showTagsDialog(it),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0x25FFFFFF),
                                      border: Border.all(
                                        color: const Color(0x66FFFFFF),
                                      ),
                                    ),
                                    child: ShaderMask(
                                      shaderCallback: (bounds) =>
                                          const LinearGradient(
                                            colors: [
                                              Color(0xFFE91E63),
                                              AppColors.lightBlue,
                                            ],
                                          ).createShader(bounds),
                                      child: const Icon(
                                        Icons.label_outline,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              if (!_isDeleteMode) const SizedBox(width: 4),
                              // Delete Icon
                              InkWell(
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
                                    shape: BoxShape.circle,
                                    color: selected
                                        ? null
                                        : const Color(0x30000000),
                                    gradient: selected
                                        ? const LinearGradient(
                                            colors: [
                                              AppColors.magenta,
                                              AppColors.lightBlue,
                                            ],
                                          )
                                        : null,
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.lightBlue.withValues(
                                              alpha: 0.7,
                                            )
                                          : const Color(0x66FFFFFF),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Playlist Icon oben links (5px nach links)
                      if (isInPlaylist && !_isDeleteMode)
                        Positioned(
                          left: 1, // 6 - 5 = 1px
                          top: 6,
                          child: Container(
                            width: 24,
                            height: 24,
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
                                size: 12,
                              ),
                              onPressed: () =>
                                  _showPlaylistsDialog(it, usedInPlaylists),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // MITTLERER CONTAINER: Name, Zeit, Tags
              Container(
                padding: const EdgeInsets.only(
                  left: 8,
                  right: 8,
                  bottom: 0, // Kein bottom padding, da Setup-Container folgt
                  top: 5,
                ), // top reduziert um 40%
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Dateiname
                    Text(
                      fileName,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    // Zeit
                    Text(
                      '${_formatDuration(currentTime)} / ${_formatDuration(totalTime)}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    // Tags (wenn vorhanden) - mit MBC Gradient (OHNE Grün!)
                    if (it.tags != null && it.tags!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Color(0xFFE91E63), // Magenta
                            AppColors.lightBlue, // Blue
                            Color(0xFF00E5FF), // Cyan
                          ],
                          stops: [0.0, 0.5, 1.0],
                        ).createShader(bounds),
                        child: Text(
                          it.tags!.join(', '),
                          style: const TextStyle(
                            color: Colors
                                .white, // Wird durch Gradient überschrieben
                            fontSize: 10,
                            fontWeight: FontWeight.w300,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 15), // Abstand nach oben
              // PREIS-SETUP CONTAINER: Klickbar, zeigt Input-Ansicht
              _buildPriceSetupContainer(it),
            ],
          ),
        ),
      ),
    );
  }

  /// Kompakte Waveform für Audio-Cards
  Widget _buildCompactWaveform({
    required double availableWidth,
    double progress = 0.0,
  }) {
    // Berechne Anzahl der Striche basierend auf verfügbarer Breite
    // Jeder Strich: 1.2px breit, kein Abstand (spaceBetween verteilt automatisch)
    final barCount = (availableWidth / 1.4).floor().clamp(50, 300);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(barCount, (index) {
        final heights = [
          0.3,
          0.5,
          0.7,
          0.9,
          0.6,
          0.4,
          0.8,
          0.5,
          0.7,
          0.3,
          0.6,
          0.8,
          0.4,
          0.9,
          0.5,
          0.7,
          0.3,
          0.6,
          0.4,
          0.8,
          0.5,
          0.7,
          0.6,
          0.9,
          0.4,
          0.8,
          0.5,
          0.6,
          0.3,
          0.7,
          0.4,
          0.6,
          0.8,
          0.5,
          0.9,
          0.3,
          0.7,
          0.6,
          0.4,
          0.8,
          0.5,
          0.7,
          0.4,
          0.6,
          0.9,
          0.3,
          0.8,
          0.5,
          0.7,
          0.4,
        ];
        final height = heights[index % heights.length];

        // Berechne ob dieser Strich schon abgespielt wurde
        final barPosition = index / barCount;
        final isPlayed = barPosition <= progress;

        return Container(
          width: 1.2,
          height: 54.43 * height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(0.6),
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: isPlayed
                  ? [
                      // Hellblau (Cyan) für abgespielte Striche
                      const Color(0xFF00E5FF).withValues(alpha: 0.4),
                      const Color(0xFF00E5FF).withValues(alpha: 0.7),
                      const Color(0xFF00E5FF).withValues(alpha: 0.9),
                    ]
                  : [
                      // Weiß für noch nicht abgespielte Striche
                      Colors.white.withValues(alpha: 0.2),
                      Colors.white.withValues(alpha: 0.5),
                      Colors.white.withValues(alpha: 0.7),
                    ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      }),
    );
  }

  /// Waveform-Visualisierung für Audio-Karten (Tag-Dialog)
  Widget _buildWaveform() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(20, (index) {
        // Pseudo-zufällige Höhen für Waveform-Effekt
        final heights = [
          0.3,
          0.5,
          0.7,
          0.9,
          0.6,
          0.4,
          0.8,
          0.5,
          0.7,
          0.3,
          0.6,
          0.8,
          0.4,
          0.9,
          0.5,
          0.7,
          0.3,
          0.6,
          0.4,
          0.8,
        ];
        final height = heights[index % heights.length];

        return Container(
          width: 3,
          height: 60 * height,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Color(0xFFE91E63).withValues(alpha: 0.3), // Magenta
                AppColors.lightBlue.withValues(alpha: 0.3), // Blue
                Color(0xFF00E5FF).withValues(alpha: 0.3), // Cyan
              ],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
        );
      }),
    );
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

      if (imagesWithoutTags.isEmpty) {
        print('✅ Alle Bilder haben bereits Tags');
        return;
      }

      print('🔄 Aktualisiere Tags für ${imagesWithoutTags.length} Bilder...');

      for (int i = 0; i < imagesWithoutTags.length; i++) {
        final image = imagesWithoutTags[i];
        try {
          print('📸 Analysiere Bild ${i + 1}/${imagesWithoutTags.length}...');

          // Lade Bild herunter für Analyse
          final tempFile = await _downloadToTemp(image.url, suffix: '.jpg');
          if (tempFile == null) {
            print('❌ Konnte Bild ${image.id} nicht herunterladen');
            continue;
          }

          // Analysiere mit Vision API
          final tags = await _visionSvc.analyzeImage(tempFile.path);
          print('🔍 Gefundene Tags: $tags');

          if (tags.isNotEmpty) {
            // Aktualisiere in Firestore
            await _mediaSvc.update(widget.avatarId, image.id, tags: tags);
            print('✅ Tags für Bild ${image.id} gespeichert: $tags');
          } else {
            print('⚠️ Keine Tags für Bild ${image.id} gefunden');
          }

          // Lösche temporäre Datei
          await tempFile.delete();

          // Kurze Pause zwischen den Bildern
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          print('❌ Fehler bei Tag-Update für Bild ${image.id}: $e');
        }
      }

      // Lade Daten neu
      await _load();
      print(
        '🎉 Tag-Update abgeschlossen! ${_items.where((i) => i.tags != null && i.tags!.isNotEmpty).length} Bilder haben jetzt Tags',
      );
    } catch (e) {
      print('❌ Fehler beim Tag-Update: $e');
    }
  }
}

// Neue Media Viewer Dialog mit Navigation
class _MediaViewerDialog extends StatefulWidget {
  final AvatarMedia initialMedia;
  final List<AvatarMedia> allMedia;
  final int initialIndex;
  final void Function(AvatarMedia) onCropRequest;

  const _MediaViewerDialog({
    required this.initialMedia,
    required this.allMedia,
    required this.initialIndex,
    required this.onCropRequest,
  });

  @override
  State<_MediaViewerDialog> createState() => _MediaViewerDialogState();
}

class _MediaViewerDialogState extends State<_MediaViewerDialog> {
  late int _currentIndex;
  late AvatarMedia _currentMedia;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _currentMedia = widget.initialMedia;
  }

  void _goToPrevious() {
    setState(() {
      if (_currentIndex > 0) {
        _currentIndex--;
      } else {
        // Am Anfang → zum Ende
        _currentIndex = widget.allMedia.length - 1;
      }
      _currentMedia = widget.allMedia[_currentIndex];
    });
  }

  void _goToNext() {
    setState(() {
      if (_currentIndex < widget.allMedia.length - 1) {
        _currentIndex++;
      } else {
        // Am Ende → zum Anfang
        _currentIndex = 0;
      }
      _currentMedia = widget.allMedia[_currentIndex];
    });
  }

  @override
  Widget build(BuildContext context) {
    // Pfeile immer anzeigen (Endlos-Navigation)
    final hasPrevious = widget.allMedia.length > 1;
    final hasNext = widget.allMedia.length > 1;

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          // Media Content (Image oder Video)
          if (_currentMedia.type == AvatarMediaType.image)
            GestureDetector(
              onLongPress: () => widget.onCropRequest(_currentMedia),
              child: InteractiveViewer(
                child: Image.network(
                  _currentMedia.url,
                  key: ValueKey(_currentMedia.id), // Key für Rebuild
                  fit: BoxFit.contain,
                ),
              ),
            )
          else
            _VideoDialog(
              key: ValueKey(_currentMedia.id), // Key für Rebuild bei Navigation
              url: _currentMedia.url,
            ),

          // Left Arrow
          if (hasPrevious)
            Positioned(
              left: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _goToPrevious,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black54,
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                    ),
                    child: const Icon(
                      Icons.chevron_left,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ),
            ),

          // Right Arrow
          if (hasNext)
            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _goToNext,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black54,
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                    ),
                    child: const Icon(
                      Icons.chevron_right,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ),
            ),

          // X-Button oben rechts
          Positioned(
            top: 12,
            right: 12,
            child: SizedBox(
              width: 40,
              height: 40,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
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
                    child: Icon(Icons.close, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoDialog extends StatefulWidget {
  final String url;
  const _VideoDialog({super.key, required this.url});
  @override
  State<_VideoDialog> createState() => _VideoDialogState();
}

class _VideoDialogState extends State<_VideoDialog> {
  VideoPlayerController? _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      // Frische URL holen falls abgelaufen (wie in avatar_details_screen)
      final fresh = await _refreshDownloadUrl(widget.url) ?? widget.url;
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(fresh));
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _ctrl = ctrl;
        _ready = true;
      });
      // Auto-play wie in avatar_details_screen
      await ctrl.play();
    } catch (e) {
      print('❌ Video-Fehler: $e');
      if (mounted) {
        setState(() => _ready = false);
      }
    }
  }

  Future<String?> _refreshDownloadUrl(String maybeExpiredUrl) async {
    try {
      final path = _storagePathFromUrl(maybeExpiredUrl);
      if (path.isEmpty) return null;
      final ref = FirebaseStorage.instance.ref().child(path);
      final fresh = await ref.getDownloadURL();
      return fresh;
    } catch (_) {
      return null;
    }
  }

  String _storagePathFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      String enc;
      if (path.contains('/o/')) {
        enc = path.split('/o/').last;
      } else {
        enc = path.startsWith('/') ? path.substring(1) : path;
      }
      final decoded = Uri.decodeComponent(enc);
      final clean = decoded.split('?').first;
      return clean;
    } catch (_) {
      return url;
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.black,
        ),
        clipBehavior: Clip.hardEdge,
        child: AspectRatio(
          aspectRatio: _ready && _ctrl != null
              ? _ctrl!.value.aspectRatio
              : 16 / 9,
          child: Stack(
            children: [
              if (_ready && _ctrl != null)
                Positioned.fill(child: VideoPlayerWidget(controller: _ctrl!)),
              if (!_ready)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
