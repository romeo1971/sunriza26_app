import 'dart:typed_data';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:crop_your_image/crop_your_image.dart' as cyi;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import '../widgets/custom_price_field.dart';
import '../widgets/custom_currency_select.dart';
import '../widgets/image_video_pricing_box.dart';
import 'dart:ui' as ui;
import '../services/media_service.dart';
import '../services/firebase_storage_service.dart';
import '../services/cloud_vision_service.dart';
import '../services/doc_thumb_service.dart';
import '../models/media_models.dart';
import '../services/playlist_service.dart';
import '../models/playlist_models.dart';
import '../services/localization_service.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:pdf_render/pdf_render.dart' as pdf;
import 'package:archive/archive.dart' as zip;
import 'package:audioplayers/audioplayers.dart';
import '../theme/app_theme.dart';
import '../widgets/video_player_widget.dart';
import '../widgets/avatar_bottom_nav_bar.dart';
import '../services/avatar_service.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/gmbc_buttons.dart';

// Custom SnackBar Helper
SnackBar buildSuccessSnackBar(String message) {
  return SnackBar(
    content: Row(
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFFE91E63), AppColors.lightBlue, Color(0xFF00E5FF)],
          ).createShader(bounds),
          child: const Icon(Icons.check_circle, color: Colors.white, size: 32),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(message, style: const TextStyle(color: Colors.grey)),
        ),
      ],
    ),
    backgroundColor: Colors.white,
    behavior: SnackBarBehavior.floating,
  );
}

SnackBar buildErrorSnackBar(String message) {
  return SnackBar(
    content: Row(
      children: [
        const Icon(Icons.error_outline, color: Colors.red, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Text(message, style: const TextStyle(color: Colors.grey)),
        ),
      ],
    ),
    backgroundColor: Colors.white,
    behavior: SnackBarBehavior.floating,
  );
}

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
  final ValueNotifier<bool> _isUploadingNotifier = ValueNotifier(false);
  final ValueNotifier<int> _uploadProgressNotifier = ValueNotifier(0);
  final ValueNotifier<String> _uploadStatusNotifier = ValueNotifier('');
  int _animationCycle = 0; // Für alternierende Wellen

  List<AvatarMedia> _items = [];
  Map<String, List<Playlist>> _mediaToPlaylists =
      {}; // mediaId -> List<Playlist>
  bool _loading = true;
  double _cropAspect = 9 / 16;
  String _mediaTab = 'images'; // 'images', 'videos', 'audio', 'documents'
  bool _portrait = true; // Portrait/Landscape Toggle
  String _searchTerm = '';
  int _currentPage = 0;
  static const int _itemsPerPage = 9;
  bool _isDeleteMode = false;
  final Set<String> _selectedMediaIds = {};
  bool _showSearch = false;
  final Map<String, double> _imageAspectRatios =
      {}; // Cache für Bild-Aspekt-Verhältnisse

  // Audio Player State
  String?
  _playingAudioUrl; // URL des aktuell spielenden Audios (null wenn pausiert)
  String? _currentAudioUrl; // URL des aktuellen Players (auch wenn pausiert)
  final Map<String, double> _audioProgress = {}; // url -> progress (0.0 - 1.0)
  final Map<String, Duration> _audioCurrentTime = {}; // url -> current time
  final Map<String, Duration> _audioTotalTime = {}; // url -> total time
  AudioPlayer? _audioPlayer;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _completeSubscription;
  StreamSubscription? _durationSubscription;
  final Set<String> _editingPriceMediaIds =
      {}; // IDs der Medien mit offenen Price-Inputs
  final Map<String, TextEditingController> _priceControllers =
      {}; // Controllers für Preis-Inputs
  final Map<String, String> _tempCurrency = {}; // Temporäre Currency pro Media

  // Statische Referenz um Player über Hot-Reload hinweg zu tracken
  static AudioPlayer? _globalAudioPlayer;
  Future<void> _disposeAudioPlayers() async {
    // Cancel alle Listener
    await _positionSubscription?.cancel();
    await _completeSubscription?.cancel();
    await _durationSubscription?.cancel();
    _positionSubscription = null;
    _completeSubscription = null;
    _durationSubscription = null;

    final local = _audioPlayer;
    final global = _globalAudioPlayer;
    if (local != null) {
      try {
        await local.stop();
        await local.dispose();
      } catch (_) {}
    }
    if (global != null && !identical(global, local)) {
      try {
        await global.stop();
        await global.dispose();
      } catch (_) {}
    }
    _audioPlayer = null;
    _globalAudioPlayer = null;
  }

  // Globale Preise pro Medientyp (image, video, audio, document)
  Map<String, dynamic> _globalPricing = const {
    'image': {'enabled': false, 'price': 0.0, 'currency': 'EUR'},
    'video': {'enabled': false, 'price': 0.0, 'currency': 'EUR'},
    'audio': {'enabled': false, 'price': 0.0, 'currency': 'EUR'},
    'document': {'enabled': false, 'price': 0.0, 'currency': 'EUR'},
  };

  String _normalizeCurrencyToSymbol(String? currency) {
    if (currency == null) return String.fromCharCode(0x20AC); // €
    final trimmed = currency.trim();
    final upper = trimmed.toUpperCase();
    if (upper == 'USD' ||
        trimmed == '\$' ||
        upper == 'US\$' ||
        trimmed == String.fromCharCode(0x24)) {
      return String.fromCharCode(0x24); // $
    }
    // Treat everything else as EUR
    return String.fromCharCode(0x20AC); // €
  }

  Future<Uint8List?> _fetchPdfPreviewBytes(String url) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) return null;
      final doc = await pdf.PdfDocument.openData(res.bodyBytes);
      final page = await doc.getPage(1);
      // Render in nativer Auflösung (keine erzwungene Breite/Höhe)
      final img = await page.render();
      final uiImg = await img.createImageIfNotAvailable();
      final byteData = await uiImg.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fetchTextSnippet(String url, bool isRtf) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) return '';
      final raw = res.body;
      final text = isRtf ? _extractPlainTextFromRtf(raw) : raw;
      return text.length > 300 ? '${text.substring(0, 300)}…' : text;
    } catch (_) {
      return '';
    }
  }

  /// Helper: Gibt den richtigen Collection-Namen für den Media-Typ zurück
  String _getCollectionNameForMediaType(AvatarMediaType type) {
    switch (type) {
      case AvatarMediaType.image:
        return 'images';
      case AvatarMediaType.video:
        return 'videos';
      case AvatarMediaType.audio:
        return 'audios';
      case AvatarMediaType.document:
        return 'documents';
    }
  }

  Future<Uint8List?> _fetchPptxPreviewBytes(String url) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) return null;
      final archive = zip.ZipDecoder().decodeBytes(
        res.bodyBytes,
        verify: false,
      );
      final candidates = [
        'ppt/media/image1.jpeg',
        'ppt/media/image1.jpg',
        'ppt/media/image1.png',
        'ppt/media/image2.jpeg',
        'ppt/media/image2.jpg',
        'ppt/media/image2.png',
      ];
      for (final name in candidates) {
        final f = archive.files.firstWhere(
          (af) => af.name == name,
          orElse: () => zip.ArchiveFile('', 0, null),
        );
        if (f.isFile && f.content is List<int>) {
          return Uint8List.fromList(f.content as List<int>);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _fetchDocxPreviewBytes(String url) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) return null;
      final archive = zip.ZipDecoder().decodeBytes(
        res.bodyBytes,
        verify: false,
      );
      final candidates = [
        'word/media/image1.jpeg',
        'word/media/image1.jpg',
        'word/media/image1.png',
        'word/media/image2.jpeg',
        'word/media/image2.jpg',
        'word/media/image2.png',
      ];
      for (final name in candidates) {
        final f = archive.files.firstWhere(
          (af) => af.name == name,
          orElse: () => zip.ArchiveFile('', 0, null),
        );
        if (f.isFile && f.content is List<int>) {
          return Uint8List.fromList(f.content as List<int>);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Auto-Thumb für Dokumente erzeugen: Preview laden, automatisch auf 9:16 oder 16:9 croppen
  Future<void> _autoGenerateDocThumb(AvatarMedia media) async {
    try {
      if (media.type != AvatarMediaType.document) return;

      // 1) Preview-Bytes laden
      Uint8List? bytes;
      final lower = (media.originalFileName ?? media.url).toLowerCase();
      debugPrint('🖼️ Lade Preview-Bytes für $lower...');
      if (lower.endsWith('.pdf')) {
        bytes = await _fetchPdfPreviewBytes(media.url);
      } else if (lower.endsWith('.pptx')) {
        bytes = await _fetchPptxPreviewBytes(media.url);
      } else if (lower.endsWith('.docx')) {
        bytes = await _fetchDocxPreviewBytes(media.url);
      }
      if (bytes == null) {
        debugPrint('❌ Keine Preview-Bytes für $lower verfügbar');
        return;
      }
      debugPrint('✅ Preview-Bytes geladen: ${bytes.length} bytes');

      // 2) Bildmaße bestimmen
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final src = frame.image;
      final srcW = src.width.toDouble();
      final srcH = src.height.toDouble();
      final srcAR = srcW / srcH;

      // 3) Zielverhältnis: Portrait 9:16 wenn hochkant, sonst 16:9
      final bool wantPortrait = srcAR < 1.0;
      final double targetAR = wantPortrait ? (9 / 16) : (16 / 9);

      // 4) Crop-Rechteck berechnen: cover-Logik
      // Wir wollen möglichst viel vom Bild behalten, daher schneiden wir nur die überstehende Seite ab
      double cropW, cropH;
      if (srcAR > targetAR) {
        // Quelle zu breit → beschneide Breite
        cropH = srcH;
        cropW = cropH * targetAR;
      } else {
        // Quelle zu hoch → beschneide Höhe
        cropW = srcW;
        cropH = cropW / targetAR;
      }
      final cropLeft = ((srcW - cropW) / 2).clamp(0, srcW);
      final cropTop = ((srcH - cropH) / 2).clamp(0, srcH);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final dstRect = Rect.fromLTWH(0, 0, cropW.toDouble(), cropH.toDouble());
      final srcRect = Rect.fromLTWH(
        cropLeft.toDouble(),
        cropTop.toDouble(),
        cropW.toDouble(),
        cropH.toDouble(),
      );
      final paint = Paint();
      canvas.drawImageRect(src, srcRect, dstRect, paint);
      final cropped = await recorder.endRecording().toImage(
        cropW.toInt(),
        cropH.toInt(),
      );
      final byteData = await cropped.toByteData(format: ui.ImageByteFormat.png);
      final out = byteData!.buffer.asUint8List();
      src.dispose();
      cropped.dispose();

      // 5) Upload Thumb
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance.ref().child(
        'avatars/${widget.avatarId}/documents/thumbs/${media.id}_$ts.png',
      );
      final task = await ref.putData(
        out,
        SettableMetadata(contentType: 'image/png'),
      );
      final thumbUrl = await task.ref.getDownloadURL();

      // 6) Firestore aktualisieren
      await FirebaseFirestore.instance
          .collection('avatars')
          .doc(widget.avatarId)
          .collection(_getCollectionNameForMediaType(media.type))
          .doc(media.id)
          .update({'thumbUrl': thumbUrl, 'aspectRatio': targetAR});

      // 7) lokal aktualisieren
      final idx = _items.indexWhere((m) => m.id == media.id);
      if (idx != -1) {
        _items[idx] = AvatarMedia(
          id: media.id,
          avatarId: media.avatarId,
          type: media.type,
          url: media.url,
          thumbUrl: thumbUrl,
          createdAt: media.createdAt,
          durationMs: media.durationMs,
          aspectRatio: targetAR,
          tags: media.tags,
          originalFileName: media.originalFileName,
          isFree: media.isFree,
          price: media.price,
          currency: media.currency,
        );
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Auto-Thumb Fehler: $e');
    }
  }

  // Filename-Sanitizer für sichere Speicherung
  String _sanitizeName(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  // Magic-Bytes Validierung für Dokumente (PDF, DOCX/PPTX, RTF, TXT/MD)
  Future<bool> _validateDocumentFile(File file) async {
    try {
      final stream = file.openRead(0, 512);
      final builder = BytesBuilder();
      await for (final chunk in stream) {
        builder.add(chunk);
        if (builder.length >= 512) break;
      }
      final head = builder.takeBytes();
      if (head.isEmpty) return false;

      // PDF: %PDF-
      final isPdf =
          head.length >= 5 &&
          String.fromCharCodes(head.sublist(0, 5)) == '%PDF-';
      if (isPdf) return true;

      // RTF: {\rtf
      final isRtf =
          head.length >= 5 &&
          String.fromCharCodes(head.sublist(0, 5)) == '{\\rtf';
      if (isRtf) return true;

      // Office OpenXML (docx/pptx): ZIP Header (PK\x03\x04|PK\x05\x06|PK\x07\x08)
      final isZip =
          head.length >= 4 &&
          head[0] == 0x50 &&
          head[1] == 0x4B &&
          ((head[2] == 0x03 && head[3] == 0x04) ||
              (head[2] == 0x05 && head[3] == 0x06) ||
              (head[2] == 0x07 && head[3] == 0x08));
      if (isZip) {
        final lower = file.path.toLowerCase();
        if (lower.endsWith('.docx') || lower.endsWith('.pptx')) return true;
        return false;
      }

      // Text/Markdown: keine Null-Bytes im Anfangsblock
      final lower = file.path.toLowerCase();
      if (lower.endsWith('.txt') || lower.endsWith('.md')) {
        final hasNull = head.any((b) => b == 0x00);
        return !hasNull;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // Sehr einfache RTF→Text Extraktion (für Vorschau geeignet, kein vollständiger Parser)
  String _extractPlainTextFromRtf(String rtf) {
    try {
      // Hex-escapes wie \'e4 → ä (nur grob: ersetze durch '?', optional dekodieren)
      String out = rtf.replaceAllMapped(RegExp(r"\\'[0-9a-fA-F]{2}"), (m) {
        try {
          final hex = m.group(0)!.substring(2);
          final code = int.parse(hex, radix: 16);
          return String.fromCharCode(code);
        } catch (_) {
          return '?';
        }
      });
      // Entferne Steuergruppen {\*...}
      out = out.replaceAll(RegExp(r"\{\\\*[^}]*\}"), ' ');
      // Entferne Steuerwörter \control und optionale Parameter
      out = out.replaceAll(RegExp(r"\\[a-zA-Z]+-?\d*\s?"), ' ');
      // Klammern und Backslashes raus
      out = out.replaceAll(RegExp(r"[{}]"), ' ');
      out = out.replaceAll('\\', ' ');
      // Whitespaces normalisieren
      out = out.replaceAll(RegExp(r"\s+"), ' ').trim();
      return out;
    } catch (_) {
      return '';
    }
  }

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

  Future<void> _openGlobalPriceDialog() async {
    final imageEnabled =
        (_globalPricing['image']?['enabled'] as bool?) ?? false;
    final videoEnabled =
        (_globalPricing['video']?['enabled'] as bool?) ?? false;
    final audioEnabled =
        (_globalPricing['audio']?['enabled'] as bool?) ?? false;

    final imagePrice =
        (_globalPricing['image']?['price'] as num?)?.toDouble() ?? 0.0;
    final videoPrice =
        (_globalPricing['video']?['price'] as num?)?.toDouble() ?? 0.0;
    final audioPrice =
        (_globalPricing['audio']?['price'] as num?)?.toDouble() ?? 0.0;

    final imageCurrency = _normalizeCurrencyToSymbol(
      _globalPricing['image']?['currency'] as String?,
    );
    final videoCurrency = _normalizeCurrencyToSymbol(
      _globalPricing['video']?['currency'] as String?,
    );
    final audioCurrency = _normalizeCurrencyToSymbol(
      _globalPricing['audio']?['currency'] as String?,
    );

    final imageCtrl = TextEditingController(
      text: imagePrice.toStringAsFixed(2).replaceAll('.', ','),
    );
    final videoCtrl = TextEditingController(
      text: videoPrice.toStringAsFixed(2).replaceAll('.', ','),
    );
    final audioCtrl = TextEditingController(
      text: audioPrice.toStringAsFixed(2).replaceAll('.', ','),
    );

    bool imgEnabled = imageEnabled;
    bool vidEnabled = videoEnabled;
    bool audEnabled = audioEnabled;

    String imgCur = imageCurrency;
    String vidCur = videoCurrency;
    String audCur = audioCurrency;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            backgroundColor: const Color(0xFF161616),
            surfaceTintColor: Colors.transparent,
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Globale Preise',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => Navigator.of(ctx).pushNamed('/credits-shop'),
                    child: ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [
                          Color(0xFFE91E63),
                          AppColors.lightBlue,
                          Color(0xFF00E5FF),
                        ],
                      ).createShader(bounds),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text(
                            'Credits',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                          Text(
                            ' → ',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                          Icon(Icons.diamond, color: Colors.white, size: 12),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildGlobalPriceRow(
                    label: 'Bilder',
                    enabled: imgEnabled,
                    onToggle: (v) => setLocal(() => imgEnabled = v),
                    controller: imageCtrl,
                    currency: imgCur,
                    onCurrency: (v) => setLocal(() => imgCur = v ?? imgCur),
                    icon: Icons.image_outlined,
                  ),
                  const SizedBox(height: 14),
                  _buildGlobalPriceRow(
                    label: 'Videos',
                    enabled: vidEnabled,
                    onToggle: (v) => setLocal(() => vidEnabled = v),
                    controller: videoCtrl,
                    currency: vidCur,
                    onCurrency: (v) => setLocal(() => vidCur = v ?? vidCur),
                    icon: Icons.videocam_outlined,
                  ),
                  const SizedBox(height: 14),
                  _buildGlobalPriceRow(
                    label: 'Dokumente',
                    enabled:
                        (_globalPricing['document']?['enabled'] as bool?) ??
                        false,
                    onToggle: (v) => setLocal(() {
                      final cur =
                          _globalPricing['document']?['currency'] as String? ??
                          imgCur;
                      _globalPricing['document'] = {
                        'enabled': v,
                        'price':
                            double.tryParse(
                              (_globalPricing['document']?['price']
                                          ?.toString() ??
                                      '0')
                                  .toString(),
                            ) ??
                            0.0,
                        'currency': cur,
                      };
                    }),
                    controller: TextEditingController(
                      text:
                          ((_globalPricing['document']?['price'] as num?)
                                      ?.toDouble() ??
                                  0.0)
                              .toStringAsFixed(2)
                              .replaceAll('.', ','),
                    ),
                    currency:
                        (_globalPricing['document']?['currency'] as String?) ??
                        imgCur,
                    onCurrency: (v) => setLocal(() {
                      final cur = v ?? imgCur;
                      final enabled =
                          (_globalPricing['document']?['enabled'] as bool?) ??
                          false;
                      final price =
                          (_globalPricing['document']?['price'] as num?)
                              ?.toDouble() ??
                          0.0;
                      _globalPricing['document'] = {
                        'enabled': enabled,
                        'price': price,
                        'currency': cur,
                      };
                    }),
                    icon: Icons.description_outlined,
                  ),
                  const SizedBox(height: 14),
                  _buildGlobalPriceRow(
                    label: 'Audio',
                    enabled: audEnabled,
                    onToggle: (v) => setLocal(() => audEnabled = v),
                    controller: audioCtrl,
                    currency: audCur,
                    onCurrency: (v) => setLocal(() => audCur = v ?? audCur),
                    icon: Icons.audiotrack,
                  ),
                ],
              ),
            ),
            actions: [
              GmbcTextButton(
                onPressed: () => Navigator.pop(ctx),
                text: 'X',
                width: 40,
                height: 32,
                borderRadius: 10,
                transparentBackground: true,
                outlined: true,
                background: const Color(0x20FFFFFF),
                borderColor: Colors.white24,
              ),
              ElevatedButton(
                onPressed: () async {
                  // Parse Preise
                  final imgPrice =
                      double.tryParse(imageCtrl.text.replaceAll(',', '.')) ??
                      0.0;
                  final vidPrice =
                      double.tryParse(videoCtrl.text.replaceAll(',', '.')) ??
                      0.0;
                  final audPrice =
                      double.tryParse(audioCtrl.text.replaceAll(',', '.')) ??
                      0.0;

                  final payload = {
                    'globalPricing': {
                      'image': {
                        'enabled': imgEnabled,
                        'price': imgPrice,
                        'currency': imgCur,
                      },
                      'video': {
                        'enabled': vidEnabled,
                        'price': vidPrice,
                        'currency': vidCur,
                      },
                      'audio': {
                        'enabled': audEnabled,
                        'price': audPrice,
                        'currency': audCur,
                      },
                    },
                  };

                  await FirebaseFirestore.instance
                      .collection('avatars')
                      .doc(widget.avatarId)
                      .set(payload, SetOptions(merge: true));

                  setState(() {
                    _globalPricing =
                        payload['globalPricing'] as Map<String, dynamic>;
                  });
                  if (context.mounted) Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [
                      Color(0xFFE91E63),
                      AppColors.lightBlue,
                      Color(0xFF00E5FF),
                    ],
                  ).createShader(bounds),
                  child: const Text(
                    'Speichern',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGlobalPriceRow({
    required String label,
    required bool enabled,
    required void Function(bool) onToggle,
    required TextEditingController controller,
    required String currency,
    required void Function(String?) onCurrency,
    required IconData icon,
  }) {
    // Credits grob schätzen (z. B. 10 Credits je 1,00 Einheit)
    // Hinweis: Credits werden jetzt nur noch im Header-Link angezeigt

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Kopfzeile: Icon + Label links, Eye rechts mit GMBC-Farbfüllung
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  InkResponse(
                    onTap: () => onToggle(!enabled),
                    radius: 18,
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: Center(
                        child: enabled
                            ? ShaderMask(
                                shaderCallback: (bounds) =>
                                    const LinearGradient(
                                      colors: [
                                        Color(0xFFE91E63),
                                        AppColors.lightBlue,
                                        Color(0xFF00E5FF),
                                      ],
                                    ).createShader(bounds),
                                child: const Icon(
                                  Icons.visibility,
                                  size: 22,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.visibility_off,
                                size: 22,
                                color: Colors.white54,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Untere GMBC-Leiste: Preis + Währung + Credits (in Klammern)
            Container(
              height: 40,
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFE91E63),
                    AppColors.lightBlue,
                    Color(0xFF00E5FF),
                  ],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  IntrinsicWidth(
                    child: CustomPriceField(
                      isEditing: true,
                      controller: controller,
                      hintText: '0,00',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged:
                          (_) {}, // Listener über ValueListenableBuilder unten
                    ),
                  ),
                  SizedBox(
                    height: 32,
                    width: 26,
                    child: CustomCurrencySelect(
                      value: _normalizeCurrencyToSymbol(currency),
                      onChanged: onCurrency,
                    ),
                  ),
                  const Spacer(),
                  // Credits dynamisch aus dem Preis (aufgerundet)
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      final t = value.text.replaceAll(',', '.');
                      final p = double.tryParse(t) ?? 0.0;
                      final c = (p * 10).ceil();
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            c.toString(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.diamond,
                            size: 12,
                            color: Colors.white,
                          ),
                        ],
                      );
                    },
                  ),
                  // float-left Verhalten: kein Spacer am Ende
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
    _disposeAudioPlayers();
    _playingAudioUrl = null;
    _currentAudioUrl = null;
    _audioProgress.clear();
    _audioCurrentTime.clear();
    _audioTotalTime.clear();
  }

  @override
  void dispose() {
    _searchController.dispose();
    // ValueNotifiers aufräumen
    _isUploadingNotifier.dispose();
    _uploadProgressNotifier.dispose();
    _uploadStatusNotifier.dispose();
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
    _disposeAudioPlayers();
    super.dispose();
  }

  Future<void> _load() async {
    // Audio-Player stoppen bei Screen-Refresh
    _disposeAudioPlayers();
    if (mounted) {
      setState(() {
        _playingAudioUrl = null;
        _currentAudioUrl = null;
        _audioProgress.clear();
        _audioCurrentTime.clear();
        _audioTotalTime.clear();
      });
    }

    setState(() => _loading = true);
    try {
      final list = await _mediaSvc.list(widget.avatarId);

      // Hero-URLs laden (imageUrls/videoUrls aus AvatarData) + Globale Preise
      Set<String> heroUrls = {};
      try {
        final doc = await FirebaseFirestore.instance
            .collection('avatars')
            .doc(widget.avatarId)
            .get();
        final data = doc.data();
        if (data != null) {
          // Hero-URLs extrahieren (Details-Screen Images/Videos)
          if (data.containsKey('imageUrls')) {
            final imgs = data['imageUrls'] as List<dynamic>?;
            if (imgs != null) heroUrls.addAll(imgs.map((e) => e.toString()));
          }
          if (data.containsKey('videoUrls')) {
            final vids = data['videoUrls'] as List<dynamic>?;
            if (vids != null) heroUrls.addAll(vids.map((e) => e.toString()));
          }

          // Globale Preise
          if (data.containsKey('globalPricing')) {
            final gp = data['globalPricing'] as Map<String, dynamic>;
            _globalPricing = {
              'image': {
                'enabled': (gp['image']?['enabled'] as bool?) ?? false,
                'price': (gp['image']?['price'] as num?)?.toDouble() ?? 0.0,
                'currency': _normalizeCurrencyToSymbol(
                  gp['image']?['currency'] as String?,
                ),
              },
              'video': {
                'enabled': (gp['video']?['enabled'] as bool?) ?? false,
                'price': (gp['video']?['price'] as num?)?.toDouble() ?? 0.0,
                'currency': _normalizeCurrencyToSymbol(
                  gp['video']?['currency'] as String?,
                ),
              },
              'audio': {
                'enabled': (gp['audio']?['enabled'] as bool?) ?? false,
                'price': (gp['audio']?['price'] as num?)?.toDouble() ?? 0.0,
                'currency': _normalizeCurrencyToSymbol(
                  gp['audio']?['currency'] as String?,
                ),
              },
            };
          }
        }
      } catch (_) {}

      // Filtere Hero-Images/Videos und voiceClone-Audios heraus
      final filtered = list
          .where(
            (m) =>
                !heroUrls.contains(m.url) &&
                m.voiceClone != true, // Filtere voiceClone-Audios
          )
          .toList();
      print(
        '📦 Medien geladen: ${filtered.length} Objekte (${list.length - filtered.length} Hero-Medien + voiceClone-Audios gefiltert)',
      );
      print(
        '  - Bilder: ${filtered.where((m) => m.type == AvatarMediaType.image).length}',
      );
      print(
        '  - Videos: ${filtered.where((m) => m.type == AvatarMediaType.video).length}',
      );
      final pls = await _playlistSvc.list(widget.avatarId);

      // Für jedes Medium prüfen, in welchen Playlists es vorkommt
      final Map<String, List<Playlist>> mediaToPlaylists = {};
      for (final media in filtered) {
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
        _items = filtered;
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
      if (_mediaTab == 'documents' && it.type != AvatarMediaType.document) {
        return false;
      }

      // Orientierungsfilter: IMMER filtern, nie gemischt (außer Audio)
      if (it.type != AvatarMediaType.audio) {
        // Für Dokumente ohne aspectRatio: standardmäßig Portrait (9:16)
        // Für Bilder ohne aspectRatio: asynchron ermitteln (siehe unten)
        bool itemIsPortrait =
            it.isPortrait ||
            (it.aspectRatio == null && it.type == AvatarMediaType.document);
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

        if (_portrait && !itemIsPortrait) return false;
        if (!_portrait && !itemIsLandscape) return false;
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
            child: const Text(
              'Kamera (1 Bild)',
              style: TextStyle(color: AppColors.lightBlue),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _pickMultipleImages(); // Multi für Galerie
            },
            child: const Text(
              'Galerie (Mehrere)',
              style: TextStyle(color: AppColors.lightBlue),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Abbrechen',
              style: TextStyle(color: Colors.white54),
            ),
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
            child: const Text(
              'Kamera (1 Video)',
              style: TextStyle(color: AppColors.lightBlue),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _pickMultipleVideos(); // Multi für Galerie
            },
            child: const Text(
              'Galerie (Mehrere)',
              style: TextStyle(color: AppColors.lightBlue),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Abbrechen',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  /// Multi-Upload: Mehrere Bilder auf einmal auswählen
  Future<void> _pickMultipleImages() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isEmpty) return;

    _uploadQueue = images.map((x) => File(x.path)).toList();
    _isUploadingNotifier.value = true;
    _uploadProgressNotifier.value = 0;
    _uploadStatusNotifier.value = 'Bilder werden hochgeladen...';

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(buildErrorSnackBar('Keine Videos ausgewählt'));
        return;
      }

      _uploadQueue = videos;
      _isUploadingNotifier.value = true;
      _uploadProgressNotifier.value = 0;
      _uploadStatusNotifier.value = 'Videos werden hochgeladen...';

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

      _uploadProgressNotifier.value = ((i + 1) / _uploadQueue.length * 100)
          .round();
      _uploadStatusNotifier.value =
          'Lade Bild ${i + 1} von ${_uploadQueue.length} hoch...';

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
            originalFileName: p.basename(file.path),
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
    _isUploadingNotifier.value = false;
    _uploadQueue.clear();
    _uploadProgressNotifier.value = 0;
    _uploadStatusNotifier.value = '';

    await _load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        buildSuccessSnackBar('$uploadedCount Bilder erfolgreich hochgeladen!'),
      );
    }
  }

  /// Zeigt Dialog für Batch-Cropping aller hochgeladenen Bilder (derzeit ungenutzt)
  /* Future<void> _showBatchCropDialog() async {
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
        buildErrorSnackBar('Keine neuen Bilder zum Zuschneiden gefunden'),
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
  } */

  /// Startet Batch-Cropping für alle Bilder (derzeit ungenutzt)
  /* Future<void> _startBatchCropping(List<AvatarMedia> images) async {
    for (int i = 0; i < images.length; i++) {
      final image = images[i];

      _uploadStatusNotifier.value = 'Zuschneide Bild ${i + 1} von ${images.length}...';
      _isUploadingNotifier.value = true;

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
        buildSuccessSnackBar('Batch-Cropping abgeschlossen!'),
      );
    }
  } */

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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.magenta, width: 3),
            ),
            content: SizedBox(
              width: 480,
              height: 560,
              child: Stack(
                children: [
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Row(
                          children: [
                            const Icon(Icons.crop, color: Colors.white70),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: isCropping
                                  ? null
                                  : () =>
                                        setLocal(() => currentAspect = 9 / 16),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  gradient: currentAspect == 9 / 16
                                      ? const LinearGradient(
                                          colors: [
                                            Color(0xFFE91E63),
                                            AppColors.lightBlue,
                                            Color(0xFF00E5FF),
                                          ],
                                        )
                                      : null,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.white24,
                                    width: 2,
                                  ),
                                ),
                                child: Text(
                                  '9:16',
                                  style: TextStyle(
                                    color: currentAspect == 9 / 16
                                        ? Colors.white
                                        : Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: isCropping
                                  ? null
                                  : () =>
                                        setLocal(() => currentAspect = 16 / 9),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  gradient: currentAspect == 16 / 9
                                      ? const LinearGradient(
                                          colors: [
                                            Color(0xFFE91E63),
                                            AppColors.lightBlue,
                                            Color(0xFF00E5FF),
                                          ],
                                        )
                                      : null,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.white24,
                                    width: 2,
                                  ),
                                ),
                                child: Text(
                                  '16:9',
                                  style: TextStyle(
                                    color: currentAspect == 16 / 9
                                        ? Colors.white
                                        : Colors.white70,
                                  ),
                                ),
                              ),
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
                              await _uploadImage(
                                cropResult.croppedImage,
                                ext,
                                originalFileName,
                              );

                              // Dialog schließen
                              if (mounted) Navigator.of(context).pop();
                            }
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Abbrechen (light grey)
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: TextButton(
                                onPressed: isCropping
                                    ? null
                                    : () => Navigator.pop(ctx),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 12,
                                  ),
                                ),
                                child: Text(
                                  'Abbrechen',
                                  style: TextStyle(
                                    color: isCropping
                                        ? Colors.grey.shade600
                                        : Colors.grey.shade400,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            // Zuschneiden (white button + GMBC text when enabled)
                            TextButton(
                              onPressed: isCropping
                                  ? null
                                  : () {
                                      // Force crop auch wenn nicht bewegt wurde
                                      try {
                                        cropController.crop();
                                      } catch (e) {
                                        // Fallback: Croppe das ganze Bild
                                        setLocal(() => isCropping = true);
                                        _uploadImage(
                                          imageBytes,
                                          ext,
                                          originalFileName,
                                        ).then((_) {
                                          if (mounted) Navigator.of(ctx).pop();
                                        });
                                      }
                                    },
                              style: TextButton.styleFrom(
                                backgroundColor: isCropping
                                    ? Colors.transparent
                                    : Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: ShaderMask(
                                shaderCallback: (bounds) =>
                                    const LinearGradient(
                                      colors: [
                                        Color(0xFFE91E63),
                                        AppColors.lightBlue,
                                        Color(0xFF00E5FF),
                                      ],
                                    ).createShader(bounds),
                                child: Text(
                                  'Zuschneiden',
                                  style: TextStyle(
                                    color: isCropping
                                        ? Colors.white30
                                        : Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
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
                            CircularProgressIndicator(
                              color: AppColors.lightBlue,
                            ),
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

  Future<void> _uploadImage(
    Uint8List bytes,
    String ext,
    String originalFileName,
  ) async {
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

    final safeExt = (ext.isNotEmpty ? ext : '.jpg');
    final storagePath = 'avatars/${widget.avatarId}/images/$timestamp$safeExt';
    final ref = FirebaseStorage.instance.ref().child(storagePath);
    final task = await ref.putFile(
      f,
      SettableMetadata(
        contentType: safeExt == '.png' ? 'image/png' : 'image/jpeg',
        contentDisposition: 'attachment; filename="image_$timestamp$safeExt"',
      ),
    );
    final url = await task.ref.getDownloadURL();
    final m = AvatarMedia(
      id: timestamp.toString(),
      avatarId: widget.avatarId,
      type: AvatarMediaType.image,
      url: url,
      createdAt: timestamp,
      aspectRatio: _cropAspect,
      tags: tags.isNotEmpty ? tags : null,
      originalFileName: originalFileName,
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

        // Upload mit Echtzeit-Progress
        final rawBase = p.basename(file.path);
        final videoPath =
            'avatars/${widget.avatarId}/videos/${timestamp}_${_sanitizeName(rawBase)}';

        final url = await FirebaseStorageService.uploadWithProgress(
          file,
          'video',
          customPath: videoPath,
          onProgress: (progress) {
            final perFileWeight = 1.0 / _uploadQueue.length;
            final totalProgress =
                (i * perFileWeight) + (progress * perFileWeight);
            _uploadProgressNotifier.value = (totalProgress * 100).toInt();
            _uploadStatusNotifier.value =
                'Video ${i + 1}/${_uploadQueue.length} wird hochgeladen... ${(progress * 100).toInt()}%';
          },
        );

        if (url == null) {
          print('❌ Video-Upload fehlgeschlagen: $rawBase');
          continue;
        }

        final media = AvatarMedia(
          id: timestamp.toString(),
          avatarId: widget.avatarId,
          type: AvatarMediaType.video,
          url: url,
          createdAt: timestamp,
          aspectRatio: videoAspectRatio,
          tags: tags,
          originalFileName: rawBase, // Original, nicht sanitized
        );
        await _mediaSvc.add(widget.avatarId, media);

        // Nach Upload: "Verarbeitung läuft..." anzeigen
        _uploadProgressNotifier.value = 100;
        _uploadStatusNotifier.value = 'Daten werden verarbeitet...';

        // Warte kurz auf Cloud Function (Video-Thumbnail-Generierung)
        await Future.delayed(const Duration(seconds: 2));

        print(
          '✅ Video ${i + 1} gespeichert: ID=${media.id}, URL=$url, AspectRatio=$videoAspectRatio',
        );
      } catch (e) {
        print('❌ Fehler beim Upload von Video ${i + 1}: $e');
      }
    }

    // Upload abgeschlossen
    final uploadedCount = _uploadQueue.length;
    _isUploadingNotifier.value = false;
    _uploadQueue.clear();
    _uploadProgressNotifier.value = 0;
    _uploadStatusNotifier.value = '';

    await _load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        buildSuccessSnackBar('$uploadedCount Videos erfolgreich hochgeladen!'),
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

    final rawBase = p.basename(x.path);
    final base = _sanitizeName(rawBase);
    final ref = FirebaseStorage.instance.ref().child(
      'avatars/${widget.avatarId}/videos/${timestamp}_$base',
    );
    final task = await ref.putFile(
      File(x.path),
      SettableMetadata(
        contentType: 'video/mp4',
        contentDisposition: 'attachment; filename="$base"',
      ),
    );
    final url = await task.ref.getDownloadURL();
    final m = AvatarMedia(
      id: timestamp.toString(),
      avatarId: widget.avatarId,
      type: AvatarMediaType.video,
      url: url,
      createdAt: timestamp,
      aspectRatio: videoAspectRatio,
      tags: tags,
      originalFileName: rawBase, // Original, nicht sanitized
    );
    await _mediaSvc.add(widget.avatarId, m);
    await _load();

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(buildSuccessSnackBar('Video erfolgreich hochgeladen'));
    }
  }

  void _handleBackNavigation(BuildContext context) async {
    // WICHTIG: Audio Player STOPPEN beim Verlassen des Screens
    await _disposeAudioPlayers();
    setState(() {
      _playingAudioUrl = null;
      _currentAudioUrl = null;
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

    // Wenn dasselbe Audio pausiert ist → Resume (nur wenn kein anderes Audio!)
    if (_playingAudioUrl == null &&
        _audioPlayer != null &&
        _currentAudioUrl == media.url &&
        (_audioCurrentTime[media.url]?.inMilliseconds ?? 0) > 0) {
      try {
        await _audioPlayer!.resume();
        setState(() => _playingAudioUrl = media.url);
        return;
      } catch (e) {
        // Fallback: Neuen Player erstellen
      }
    }

    // Anderes Audio oder erstes Mal → Stop aktuelles und starte neues
    // WICHTIG: Listener canceln bevor Player disposed wird!
    await _positionSubscription?.cancel();
    await _completeSubscription?.cancel();
    await _durationSubscription?.cancel();

    if (_audioPlayer != null) {
      try {
        await _audioPlayer!.stop();
        await _audioPlayer!.dispose();
        _audioPlayer = null;
      } catch (_) {}
    }

    _audioPlayer = AudioPlayer();
    _globalAudioPlayer = _audioPlayer;

    // Speichere aktuelle URL
    _currentAudioUrl = media.url;

    // Listener für Fortschritt (mit StreamSubscription speichern!)
    _positionSubscription = _audioPlayer!.onPositionChanged.listen((position) {
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

    // Listener für Ende (mit StreamSubscription speichern!)
    _completeSubscription = _audioPlayer!.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playingAudioUrl = null;
          _currentAudioUrl = null;
          _audioProgress[media.url] = 0.0;
          _audioCurrentTime[media.url] = Duration.zero;
        });
      }
    });

    // Listener für Dauer (mit StreamSubscription speichern!)
    _durationSubscription = _audioPlayer!.onDurationChanged.listen((duration) {
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
      _currentAudioUrl = null;
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

      _isUploadingNotifier.value = true;
      _uploadProgressNotifier.value = 0;
      _uploadStatusNotifier.value = 'Audio-Dateien werden hochgeladen...';

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        throw Exception('Benutzer nicht angemeldet');
      }

      int uploaded = 0;
      int baseTimestamp = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < result.files.length; i++) {
        final file = result.files[i];
        if (file.path == null) continue;

        final rawBase = file.name.isNotEmpty
            ? file.name
            : p.basename(file.path!);
        final safeBase = _sanitizeName(rawBase);
        final ext = (file.extension ?? 'mp3').toLowerCase();
        const audioAllowed = ['mp3', 'wav', 'm4a', 'aac'];
        if (!audioAllowed.contains(ext)) {
          debugPrint('Blockiert: Audio-Erweiterung nicht erlaubt: $ext');
          continue;
        }

        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final audioPath =
            'avatars/${widget.avatarId}/audio/${timestamp}_$safeBase';

        // Upload mit Echtzeit-Progress
        final url = await FirebaseStorageService.uploadWithProgress(
          File(file.path!),
          'audio',
          customPath: audioPath,
          onProgress: (progress) {
            // Berechne Gesamt-Progress: vorherige Dateien + aktueller Upload
            final perFileWeight = 1.0 / result.files.length;
            final totalProgress =
                (i * perFileWeight) + (progress * perFileWeight);
            _uploadProgressNotifier.value = (totalProgress * 100).toInt();
            _uploadStatusNotifier.value =
                'Audio ${i + 1}/${result.files.length} wird hochgeladen... ${(progress * 100).toInt()}%';
          },
        );

        if (url == null) {
          debugPrint('❌ Audio-Upload fehlgeschlagen: $safeBase');
          continue;
        }

        // Firestore speichern - eindeutige ID mit Counter
        final mediaId = '${baseTimestamp + i}';
        final m = AvatarMedia(
          id: mediaId,
          avatarId: widget.avatarId,
          type: AvatarMediaType.audio,
          url: url,
          createdAt: baseTimestamp + i,
          tags: ['audio', file.name],
          originalFileName: file.name,
        );
        await _mediaSvc.add(widget.avatarId, m);

        // Nach Upload: "Verarbeitung läuft..." anzeigen
        _uploadProgressNotifier.value = 100;
        _uploadStatusNotifier.value = 'Daten werden verarbeitet...';

        // Warten bis Cloud Function thumbUrl gesetzt hat
        for (int retry = 0; retry < 50; retry++) {
          await Future.delayed(const Duration(milliseconds: 300));
          final doc = await FirebaseFirestore.instance
              .collection('avatars')
              .doc(widget.avatarId)
              .collection('audios')
              .doc(mediaId)
              .get();
          if (doc.exists && doc.data()?['thumbUrl'] != null) {
            break;
          }
        }
        uploaded++;
      }

      _isUploadingNotifier.value = false;
      _uploadProgressNotifier.value = 0;
      _uploadStatusNotifier.value = '';

      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          buildSuccessSnackBar(
            '$uploaded Audio-Dateien erfolgreich hochgeladen!',
          ),
        );
      }
    } catch (e) {
      _isUploadingNotifier.value = false;
      _uploadProgressNotifier.value = 0;
      _uploadStatusNotifier.value = '';

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
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => _handleBackNavigation(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Globaler Preis',
            onPressed: () => _openGlobalPriceDialog(),
            icon: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppColors.magenta, AppColors.lightBlue],
              ).createShader(bounds),
              child: const Icon(
                Icons.sell_outlined,
                color: Colors.white,
                size: 21.4,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Tags aktualisieren',
            onPressed: _updateExistingImageTags,
            icon: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppColors.magenta, AppColors.lightBlue],
              ).createShader(bounds),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 21.4,
              ),
            ),
          ),
          IconButton(
            tooltip: loc.t('avatars.refreshTooltip'),
            onPressed: _load,
            icon: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppColors.magenta, AppColors.lightBlue],
              ).createShader(bounds),
              child: const Icon(
                Icons.refresh_outlined,
                color: Colors.white,
                size: 21.4,
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(35),
          child: Stack(
            children: [
              // Hintergrund: quasi black
              Container(height: 35, color: const Color(0xFF0D0D0D)),
              // Weißes Overlay #ffffff15
              Positioned.fill(child: Container(color: const Color(0x15FFFFFF))),
              // Inhalt
              Container(
                height: 35,
                padding: EdgeInsets.zero,
                child: Row(
                  children: [
                    _buildTopTabAppbarBtn('images', Icons.image_outlined),
                    _buildTopTabAppbarBtn('videos', Icons.videocam_outlined),
                    _buildTopTabAppbarBtn(
                      'documents',
                      Icons.description_outlined,
                    ),
                    _buildTopTabAppbarBtn('audio', Icons.audiotrack),
                    // Upload-Button
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: SizedBox(
                        height: 35,
                        child: TextButton(
                          onPressed: _showUploadDialog,
                          style: ButtonStyle(
                            padding: const WidgetStatePropertyAll(
                              EdgeInsets.zero,
                            ),
                            minimumSize: const WidgetStatePropertyAll(
                              Size(40, 35),
                            ),
                          ),
                          child: Container(
                            height: double.infinity,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.magenta,
                                  AppColors.lightBlue,
                                ],
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: const Icon(
                              Icons.file_upload,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Portrait/Landscape Toggle (ausgeblendet bei Audio)
                    if (_mediaTab != 'audio')
                      SizedBox(
                        height: 35,
                        child: TextButton(
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
                      ),
                    // Orientierungs-Button wird unten angezeigt
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.lightBlue),
            )
          : Column(
              children: [
                // Info-Text/Suchfeld (centered) + Lupe (fixed right) ODER Delete-Buttons
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                  child: SizedBox(
                    height: 40,
                    child: _isDeleteMode && _selectedMediaIds.isNotEmpty
                        ? LayoutBuilder(
                            builder: (ctx, cons) {
                              double measureTextWidth(
                                String text,
                                TextStyle style,
                              ) {
                                final tp = TextPainter(
                                  text: TextSpan(text: text, style: style),
                                  maxLines: 1,
                                  textScaleFactor: MediaQuery.of(
                                    ctx,
                                  ).textScaleFactor,
                                  textDirection: TextDirection.ltr,
                                )..layout();
                                return tp.width;
                              }

                              final TextStyle cancelStyle = TextStyle(
                                color: Colors.grey.shade300,
                                fontSize: 14,
                              );
                              const TextStyle deleteStyle = TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              );

                              final double cancelWidth =
                                  measureTextWidth('Abbrechen', cancelStyle) +
                                  16; // padding h=8*2
                              final double deleteWidth =
                                  measureTextWidth(
                                    'Endgültig löschen',
                                    deleteStyle,
                                  ) +
                                  40; // padding h=20*2
                              final bool compact =
                                  (cancelWidth + deleteWidth) > cons.maxWidth;

                              final Widget cancelBtn = compact
                                  ? IconButton(
                                      tooltip: 'Abbrechen',
                                      onPressed: () {
                                        setState(() {
                                          _isDeleteMode = false;
                                          _selectedMediaIds.clear();
                                        });
                                      },
                                      icon: Icon(
                                        Icons.close,
                                        color: Colors.grey.shade300,
                                      ),
                                    )
                                  : MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: TextButton(
                                        onPressed: () {
                                          setState(() {
                                            _isDeleteMode = false;
                                            _selectedMediaIds.clear();
                                          });
                                        },
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                        ),
                                        child: Text(
                                          'Abbrechen',
                                          style: cancelStyle,
                                        ),
                                      ),
                                    );

                              final selectedMedia = _items
                                  .where(
                                    (m) => _selectedMediaIds.contains(m.id),
                                  )
                                  .toList();
                              final hasImagesVideosOrDocs = selectedMedia.any(
                                (m) =>
                                    m.type == AvatarMediaType.image ||
                                    m.type == AvatarMediaType.video ||
                                    m.type == AvatarMediaType.document,
                              );
                              final hasAudio = selectedMedia.any(
                                (m) => m.type == AvatarMediaType.audio,
                              );

                              // Verwende das richtige Delete-Popup basierend auf Medientypen
                              final Widget deleteBtn = TextButton(
                                onPressed: hasImagesVideosOrDocs && !hasAudio
                                    ? _confirmDeleteSelectedComplete
                                    : _confirmDeleteSelectedMinimal,
                                style: TextButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: ShaderMask(
                                  shaderCallback: (bounds) =>
                                      const LinearGradient(
                                        colors: [
                                          Color(0xFFE91E63),
                                          AppColors.lightBlue,
                                          Color(0xFF00E5FF),
                                        ],
                                      ).createShader(bounds),
                                  child: const Text(
                                    'Endgültig löschen',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              );

                              return Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [cancelBtn, deleteBtn],
                              );
                            },
                          )
                        : Stack(
                            children: [
                              // Zentrierter Inhalt (Infotext ODER Suchfeld)
                              Center(
                                child: !_showSearch
                                    ? Text(
                                        'Verlinkbare Medien für Deine Playlists',
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.85,
                                          ),
                                          fontSize: 12,
                                        ),
                                      )
                                    : ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 400,
                                        ),
                                        child: TextField(
                                          controller: _searchController,
                                          autofocus: true,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                          ),
                                          cursorColor: Colors.white,
                                          decoration: InputDecoration(
                                            hintText: 'Suche nach Medien',
                                            hintStyle: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.4,
                                              ),
                                              fontSize: 13,
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 10,
                                                ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              borderSide: BorderSide(
                                                color: Colors.white.withValues(
                                                  alpha: 0.6,
                                                ),
                                                width: 1,
                                              ),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              borderSide: const BorderSide(
                                                color: Colors.white,
                                                width: 1,
                                              ),
                                            ),
                                            hoverColor: Colors.transparent,
                                            fillColor: Colors.transparent,
                                            isDense: true,
                                          ),
                                          onChanged: (val) {
                                            setState(() {
                                              _searchTerm = val.toLowerCase();
                                            });
                                          },
                                        ),
                                      ),
                              ),
                              // Lupe - IMMER rechts (fixed position)
                              Positioned(
                                right: 0,
                                top: 0,
                                bottom: 0,
                                child: Center(
                                  child: InkWell(
                                    onTap: _items.isEmpty
                                        ? null
                                        : () {
                                            setState(() {
                                              _showSearch = !_showSearch;
                                              if (!_showSearch) {
                                                _searchController.clear();
                                                _searchTerm = '';
                                              }
                                            });
                                          },
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: _showSearch
                                          ? ShaderMask(
                                              shaderCallback: (bounds) =>
                                                  const LinearGradient(
                                                    colors: [
                                                      AppColors.magenta,
                                                      AppColors.lightBlue,
                                                    ],
                                                  ).createShader(bounds),
                                              child: const Icon(
                                                Icons.search,
                                                size: 18,
                                                color: Colors.white,
                                              ),
                                            )
                                          : Icon(
                                              Icons.search,
                                              size: 18,
                                              color: _items.isEmpty
                                                  ? Colors.grey.shade700
                                                  : Colors.grey.shade500,
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),

                // Upload-Fortschrittsanzeige (ValueListenableBuilder verhindert Flackern)
                ValueListenableBuilder<bool>(
                  valueListenable: _isUploadingNotifier,
                  builder: (context, isUploading, child) {
                    if (!isUploading) return const SizedBox.shrink();

                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ValueListenableBuilder<String>(
                        valueListenable: _uploadStatusNotifier,
                        builder: (ctx, uploadStatus, _) {
                          return ValueListenableBuilder<int>(
                            valueListenable: _uploadProgressNotifier,
                            builder: (ctx, uploadProgress, _) {
                              return Column(
                                children: [
                                  // Animierter Text bei "Daten werden verarbeitet..."
                                  uploadStatus.contains('verarbeitet')
                                      ? TweenAnimationBuilder<double>(
                                          key: ValueKey(_animationCycle),
                                          tween: Tween(begin: 0.0, end: 1.0),
                                          duration: const Duration(
                                            milliseconds: 1500,
                                          ),
                                          builder: (context, value, child) {
                                            // Alternierende Farben
                                            final isReverse =
                                                _animationCycle % 2 == 1;
                                            final waveColors = isReverse
                                                ? [
                                                    AppColors.lightBlue,
                                                    AppColors.magenta,
                                                    AppColors.lightBlue,
                                                  ]
                                                : [
                                                    AppColors.magenta,
                                                    AppColors.lightBlue,
                                                    AppColors.magenta,
                                                  ];

                                            return Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: uploadStatus
                                                  .split('')
                                                  .asMap()
                                                  .entries
                                                  .map((entry) {
                                                    final index = entry.key;
                                                    final char = entry.value;
                                                    // Wellenförmige Bewegung pro Buchstabe
                                                    final offset =
                                                        (value +
                                                            (index * 0.1)) %
                                                        1.0;
                                                    final dy =
                                                        sin(offset * 2 * pi) *
                                                        3;

                                                    return Transform.translate(
                                                      offset: Offset(0, dy),
                                                      child: ShaderMask(
                                                        shaderCallback: (bounds) {
                                                          return LinearGradient(
                                                            begin: Alignment
                                                                .centerLeft,
                                                            end: Alignment
                                                                .centerRight,
                                                            colors: waveColors,
                                                            stops: [
                                                              (value - 0.3)
                                                                  .clamp(
                                                                    0.0,
                                                                    1.0,
                                                                  ),
                                                              value,
                                                              (value + 0.3)
                                                                  .clamp(
                                                                    0.0,
                                                                    1.0,
                                                                  ),
                                                            ],
                                                          ).createShader(
                                                            bounds,
                                                          );
                                                        },
                                                        child: Text(
                                                          char,
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                              ),
                                                        ),
                                                      ),
                                                    );
                                                  })
                                                  .toList(),
                                            );
                                          },
                                          onEnd: () {
                                            // Loop mit Farbwechsel
                                            if (_isUploadingNotifier.value &&
                                                uploadStatus.contains(
                                                  'verarbeitet',
                                                )) {
                                              setState(() {
                                                _animationCycle++;
                                              });
                                            }
                                          },
                                        )
                                      : Text(
                                          uploadStatus,
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value: uploadProgress / 100,
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.3,
                                    ),
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                          AppColors.lightBlue,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$uploadProgress%',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    );
                  },
                ),

                // Spacing nach Upload (auch mit ValueListenableBuilder)
                ValueListenableBuilder<bool>(
                  valueListenable: _isUploadingNotifier,
                  builder: (context, isUploading, child) {
                    return isUploading
                        ? const SizedBox(height: 16)
                        : const SizedBox.shrink();
                  },
                ),

                // Delete-Toolbar wurde nach oben verschoben (ersetzt Infotext/Suchfeld)
                const SizedBox.shrink(),

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
                          child: Center(
                            child: Wrap(
                              alignment: WrapAlignment.center,
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
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Center(
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
                                if (leftW > 180) {
                                  leftW = 180; // 240 * 0.75 = 180
                                }
                                if (leftW < 120) {
                                  leftW = 120; // 160 * 0.75 = 120
                                }

                                return Wrap(
                                  alignment: WrapAlignment.center,
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
      bottomNavigationBar: AvatarBottomNavBar(
        avatarId: widget.avatarId,
        currentScreen: 'media',
      ),
    );
  }

  // (alt) _buildTabButton nicht mehr genutzt

  // Top-Navi: Füllende Select-Boxen
  // (alt) _buildTopTabBox entfernt – ersetzt durch _buildTopTabAppbarBtn

  // AppBar‑Style Tab Button (48px hoch; selektiert/hover: eckig, sonst rund)
  Widget _buildTopTabAppbarBtn(String tab, IconData icon) {
    final selected = _mediaTab == tab;
    return SizedBox(
      height: 35,
      child: TextButton(
        onPressed: () {
          setState(() {
            _mediaTab = tab;
            _currentPage = 0;
          });
        },
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          minimumSize: const WidgetStatePropertyAll(Size(60, 35)),
          backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (selected) {
              return const Color(0x26FFFFFF); // ausgewählt: hellgrau
            }
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
        child: Icon(
          icon,
          size: 22,
          color: selected ? Colors.white : Colors.white54,
        ),
      ),
    );
  }

  // NEU: Dokumente-Upload (atomic placeholder)
  Future<void> _showDocumentSourceDialog() async {
    // Minimal: FilePicker für gängige Dokumente (pdf, txt, docx, pptx)
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt', 'docx', 'pptx', 'md', 'rtf'],
      );
      if (res == null || res.files.isEmpty) return;

      _isUploadingNotifier.value = true;
      _uploadProgressNotifier.value = 0;
      _uploadStatusNotifier.value = 'Dokumente werden hochgeladen...';

      int idx = 0;
      for (final picked in res.files) {
        final path = picked.path;
        if (path == null) {
          debugPrint('⚠️ Dokument ${idx + 1}: Kein Pfad verfügbar');
          continue;
        }
        final file = File(path);
        debugPrint(
          '📄 Dokument ${idx + 1}/${res.files.length}: ${p.basename(path)}',
        );

        final media = await _uploadDocumentFile(
          file,
          onProgress: (progress) {
            // Berechne Gesamt-Progress: vorherige Dateien + aktueller Upload
            final perFileWeight = 1.0 / res.files.length;
            final totalProgress =
                (idx * perFileWeight) + (progress * perFileWeight);
            _uploadProgressNotifier.value = (totalProgress * 100).toInt();
            _uploadStatusNotifier.value =
                'Dokument ${idx + 1}/${res.files.length} wird hochgeladen... ${(progress * 100).toInt()}%';
          },
        );
        if (media != null) {
          debugPrint(
            '✅ Dokument ${idx + 1} in Firestore gespeichert: ${media.id}',
          );
          // Lokal hinzufügen (ohne Thumbnail)
          _items.add(media);
          setState(() {});

          // SOFORT Crop-Dialog öffnen (User wählt 9:16 oder 16:9)
          _isUploadingNotifier.value = false;
          await _reopenCrop(media);
          _isUploadingNotifier.value = true;
        } else {
          debugPrint('❌ Dokument ${idx + 1} konnte nicht hochgeladen werden');
        }
        idx++;
      }

      _isUploadingNotifier.value = false;
      _uploadProgressNotifier.value = 100;
      _uploadStatusNotifier.value = '';
    } catch (e) {
      debugPrint('Dokumentauswahl fehlgeschlagen: $e');
    }
  }

  Future<AvatarMedia?> _uploadDocumentFile(
    File file, {
    Function(double)? onProgress,
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        debugPrint('❌ Kein User eingeloggt');
        return null;
      }

      final base = p.basename(file.path);
      final ext = p.extension(base).toLowerCase().replaceFirst('.', '');
      debugPrint('📝 Prüfe Dokument: $base (.$ext)');
      // Clientseitige Allowlist
      const allowed = ['pdf', 'txt', 'docx', 'pptx', 'md', 'rtf'];
      if (!allowed.contains(ext)) {
        debugPrint('❌ Blockiert: nicht erlaubte Dokument-Erweiterung: .$ext');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(buildErrorSnackBar('Dateityp nicht erlaubt.'));
        }
        return null;
      }

      // Magic-Bytes Validierung – blocke getarnte Dateien
      debugPrint('🔍 Magic-Bytes-Validierung für $base...');
      final isValidByMagic = await _validateDocumentFile(file);
      if (!isValidByMagic) {
        debugPrint('❌ Magic-Bytes-Validierung fehlgeschlagen für $base');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Dateiinhalt entspricht nicht dem Typ. Upload abgebrochen.',
              ),
            ),
          );
        }
        return null;
      }
      debugPrint('✅ Magic-Bytes-Validierung erfolgreich für $base');
      // Content-Type Mapping
      String contentType;
      switch (ext) {
        case 'pdf':
          contentType = 'application/pdf';
          break;
        case 'docx':
          contentType =
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
          break;
        case 'pptx':
          contentType =
              'application/vnd.openxmlformats-officedocument.presentationml.presentation';
          break;
        case 'rtf':
          contentType = 'text/rtf';
          break;
        case 'md':
        case 'txt':
          contentType = 'text/plain';
          break;
        default:
          contentType = 'application/octet-stream';
      }
      final ts = DateTime.now().millisecondsSinceEpoch;
      final storageRef = FirebaseStorage.instance.ref().child(
        'avatars/${widget.avatarId}/documents/${ts}_$base',
      );
      debugPrint('📤 Lade $base nach Storage hoch...');

      final uploadTask = storageRef.putFile(
        file,
        SettableMetadata(
          contentType: contentType,
          contentDisposition: 'attachment; filename="$base"',
          customMetadata: {'type': 'document', 'ext': ext},
        ),
      );

      // Upload-Fortschritt überwachen
      uploadTask.snapshotEvents.listen((snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        if (onProgress != null) {
          onProgress(progress);
        }
      });

      final task = await uploadTask;
      final url = await task.ref.getDownloadURL();
      debugPrint('✅ Storage-Upload erfolgreich: $url');

      // Firestore OHNE Thumbnail erstellen (User croppt manuell!)
      final doc = FirebaseFirestore.instance
          .collection('avatars')
          .doc(widget.avatarId)
          .collection('documents')
          .doc();

      debugPrint(
        '💾 Speichere in Firestore: avatars/${widget.avatarId}/documents/${doc.id}',
      );
      await doc.set({
        'id': doc.id,
        'avatarId': widget.avatarId,
        'type': 'document',
        'url': url,
        'thumbUrl': null, // User croppt manuell!
        'createdAt': ts,
        'durationMs': null,
        'aspectRatio': null, // Wird beim Crop gesetzt
        'tags': null,
        'originalFileName': base,
      });
      debugPrint('✅ Firestore-Eintrag erstellt (ohne Thumbnail): ${doc.id}');
      return AvatarMedia(
        id: doc.id,
        avatarId: widget.avatarId,
        type: AvatarMediaType.document,
        url: url,
        thumbUrl: null,
        createdAt: ts,
        durationMs: null,
        aspectRatio: null,
        tags: null,
        originalFileName: base,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ Dokument-Upload fehlgeschlagen: $e');
      debugPrint('Stack: $stackTrace');
      return null;
    }
  }

  // Upload-Dialog öffnen (je nach aktuellem Tab)
  void _showUploadDialog() {
    if (_isUploadingNotifier.value) return;
    if (_mediaTab == 'images') {
      _showImageSourceDialog();
    } else if (_mediaTab == 'videos') {
      _showVideoSourceDialog();
    } else if (_mediaTab == 'documents') {
      _showDocumentSourceDialog();
    } else {
      _pickAudio();
    }
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

    // Für Videos: Lade Controller und nutze ECHTE Dimensionen
    if (it.type == AvatarMediaType.video) {
      return FutureBuilder<VideoPlayerController?>(
        future: _videoControllerForThumb(it.url),
        builder: (ctx, snapshot) {
          double videoAR = aspectRatio; // Fallback
          if (snapshot.connectionState == ConnectionState.done &&
              snapshot.hasData &&
              snapshot.data != null &&
              snapshot.data!.value.isInitialized) {
            // Nutze ECHTE Video-Dimensionen
            videoAR = snapshot.data!.value.aspectRatio;
          }

          // Validierung: Falls videoAR ungültig, nutze Fallback
          if (videoAR <= 0 || videoAR.isNaN || videoAR.isInfinite) {
            videoAR = 16 / 9; // Fallback
          }

          bool isPortrait = videoAR < 1.0;
          double baseWidth = cardWidth;
          if (!isPortrait) {
            baseWidth = cardWidth * 2;
          }
          double actualHeight = baseWidth / videoAR;
          double actualWidth = baseWidth;

          return _buildMediaCardContent(
            it,
            actualWidth,
            actualHeight,
            isInPlaylist,
            usedInPlaylists,
            selected,
            videoController: snapshot.data,
          );
        },
      );
    }

    // Für Bilder/Dokumente: Nutze gespeichertes aspectRatio
    // Validierung: Falls aspectRatio ungültig, nutze Fallback
    if (aspectRatio <= 0 || aspectRatio.isNaN || aspectRatio.isInfinite) {
      aspectRatio = _portrait
          ? 9 / 16
          : 16 / 9; // Fallback basierend auf Portrait/Landscape Toggle
    }

    bool isPortrait = aspectRatio < 1.0;
    double baseWidth = cardWidth;
    if (!isPortrait) {
      baseWidth = cardWidth * 2;
    }
    double actualHeight = baseWidth / aspectRatio;
    double actualWidth = baseWidth;

    return _buildMediaCardContent(
      it,
      actualWidth,
      actualHeight,
      isInPlaylist,
      usedInPlaylists,
      selected,
    );
  }

  Widget _buildMediaCardContent(
    AvatarMedia it,
    double actualWidth,
    double actualHeight,
    bool isInPlaylist,
    List<Playlist> usedInPlaylists,
    bool selected, {
    VideoPlayerController? videoController,
  }) {
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
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: (it.type == AvatarMediaType.image)
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
                    : (it.type == AvatarMediaType.document)
                    ? _buildDocumentPreviewBackground(it)
                    : it.type == AvatarMediaType.video
                    ? (it.thumbUrl != null
                          ? Image.network(
                              it.thumbUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stack) {
                                // Fallback zu VideoPlayer wenn Thumb nicht lädt
                                return FutureBuilder<VideoPlayerController?>(
                                  future: _videoControllerForThumb(it.url),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                            ConnectionState.done &&
                                        snapshot.hasData &&
                                        snapshot.data != null) {
                                      final controller = snapshot.data!;
                                      if (controller.value.isInitialized) {
                                        final videoAR =
                                            controller.value.aspectRatio;
                                        return AspectRatio(
                                          aspectRatio: videoAR,
                                          child: VideoPlayer(controller),
                                        );
                                      }
                                    }
                                    return Container(color: Colors.black26);
                                  },
                                );
                              },
                            )
                          : FutureBuilder<VideoPlayerController?>(
                              future: _videoControllerForThumb(it.url),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                        ConnectionState.done &&
                                    snapshot.hasData &&
                                    snapshot.data != null) {
                                  final controller = snapshot.data!;
                                  if (controller.value.isInitialized) {
                                    final videoAR =
                                        controller.value.aspectRatio;
                                    return AspectRatio(
                                      aspectRatio: videoAR,
                                      child: VideoPlayer(controller),
                                    );
                                  }
                                }
                                return Container(color: Colors.black26);
                              },
                            ))
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          // Dark gradient background
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF1A1A1A), Color(0xFF0A0A0A)],
                              ),
                            ),
                          ),
                          // Statische Waveform als Hintergrund
                          Center(
                            child: CustomPaint(
                              size: Size(actualWidth * 0.8, actualHeight * 0.6),
                              painter: _StaticWaveformPainter(),
                            ),
                          ),
                          // Play/Pause/Reload Controls in der Mitte
                          Center(child: _buildAudioControls(it)),
                        ],
                      ),
              ),
            ),
            // Preis-Badge oben rechts (Bild/Video/Dokument): Override ODER globaler Preis wenn aktiviert
            if ((it.type == AvatarMediaType.image ||
                    it.type == AvatarMediaType.video ||
                    it.type == AvatarMediaType.document) &&
                !_isDeleteMode &&
                (it.price != null ||
                    (((_globalPricing[(it.type == AvatarMediaType.image
                                    ? 'image'
                                    : (it.type == AvatarMediaType.video
                                          ? 'video'
                                          : 'document'))]
                                as Map<String, dynamic>?)?['enabled']
                            as bool?) ??
                        false)))
              Positioned(
                right: 6,
                top: 6,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      // Popup öffnen
                      _openMediaPricingDialog(it);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFE91E63), // Magenta
                            AppColors.lightBlue, // Blue
                            Color(0xFF00E5FF), // Cyan
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                      child: Text(
                        (() {
                          final isFree = it.isFree ?? false;
                          if (isFree) return 'Kostenlos';

                          final typeKey = it.type == AvatarMediaType.image
                              ? 'image'
                              : (it.type == AvatarMediaType.video
                                    ? 'video'
                                    : 'document');
                          final overridePrice = it.price;
                          final overrideCur = _normalizeCurrencyToSymbol(
                            it.currency,
                          );
                          final gp =
                              _globalPricing[typeKey] as Map<String, dynamic>?;
                          final gpEnabled = (gp?['enabled'] as bool?) ?? false;
                          final gpPrice =
                              (gp?['price'] as num?)?.toDouble() ?? 0.0;
                          final gpCur = _normalizeCurrencyToSymbol(
                            gp?['currency'] as String?,
                          );

                          final effectivePrice =
                              overridePrice ?? (gpEnabled ? gpPrice : 0.0);
                          final symbol =
                              (overridePrice != null ? overrideCur : gpCur) ==
                                  '\$'
                              ? '\$'
                              : '€';
                          return '$symbol${effectivePrice.toStringAsFixed(2).replaceAll('.', ',')}';
                        })(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          height: 1.0,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
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
            // Cropping Icon unten links: nur für Bilder (Dokumente werden direkt nach Upload gecroppt)
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

            // Tag-Icon unten links (für Videos und Dokumente) ODER rechts oben (für Audio)
            if ((it.type == AvatarMediaType.video ||
                    it.type == AvatarMediaType.audio ||
                    it.type == AvatarMediaType.document) &&
                !_isDeleteMode)
              Positioned(
                left: it.type == AvatarMediaType.audio ? null : 6,
                right: it.type == AvatarMediaType.audio ? 6 : null,
                top: it.type == AvatarMediaType.audio ? 6 : null,
                bottom: it.type == AvatarMediaType.audio ? null : 6,
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

            // Video Thumbnail Button unten mitte (alle Videos)
            if (it.type == AvatarMediaType.video && !_isDeleteMode)
              Positioned(
                left: 0,
                right: 0,
                bottom: 6,
                child: Center(
                  child: InkWell(
                    onTap: () => _selectVideoThumbnail(it),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0x30000000),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0x66FFFFFF)),
                      ),
                      child: const Icon(
                        Icons.photo_camera,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ),

            // Delete Button unten rechts (für alle Medientypen)
            Positioned(
              right: 6,
              bottom: 6,
              child: InkWell(
                onTap: () {
                  setState(() {
                    if (selected) {
                      _selectedMediaIds.remove(it.id);
                    } else {
                      _selectedMediaIds.add(it.id);
                    }
                    // Delete-Mode aktiv nur solange mind. 1 Element selektiert ist
                    _isDeleteMode = _selectedMediaIds.isNotEmpty;
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

  // Video Thumbnail Auswahl Dialog
  Future<void> _selectVideoThumbnail(AvatarMedia media) async {
    if (media.type != AvatarMediaType.video) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _VideoThumbnailSelectorDialog(
        videoUrl: media.url,
        avatarId: widget.avatarId,
        mediaId: media.id,
        onComplete: () async {
          // WICHTIG: Video-Controller clearen damit neue Thumbs geladen werden
          for (final controller in _thumbControllers.values) {
            controller.dispose();
          }
          _thumbControllers.clear();

          // Reload nach erfolgreichem Thumbnail-Update
          await _load();

          // Extra: Force rebuild um neue Thumbs anzuzeigen
          if (mounted) setState(() {});
        },
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
                          buildSuccessSnackBar('Aus Playlist entfernt'),
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
    // Sammle Previews für Bestätigungsdialog
    final selectedMedia = _items
        .where((m) => _selectedMediaIds.contains(m.id))
        .toList(growable: false);

    // Vor dem Öffnen des Dialogs: laufende Audiowiedergabe kurz pausieren,
    // um konkurrierende Kommandos (Pause/Stop/Dispose) zu vermeiden
    bool pausedForDialog = false;
    try {
      if (_audioPlayer != null && _playingAudioUrl != null) {
        await _audioPlayer!.pause();
        pausedForDialog = true;
      }
    } catch (_) {}

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Medien löschen?'),
            actionsAlignment:
                MainAxisAlignment.spaceBetween, // Buttons weit auseinander
            content: SizedBox(
              width:
                  MediaQuery.of(context).size.width * 0.95, // responsive Breite
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 760,
                ), // Maximalbreite
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Möchtest du $count ${count == 1 ? 'Medium' : 'Medien'} wirklich löschen?',
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 170, // Erhöht für Play Controls + Zeit + Name
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: selectedMedia.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final m = selectedMedia[i];
                          final double h = 120.0;
                          final double ar =
                              (m.aspectRatio ??
                              (m.type == AvatarMediaType.document
                                  ? (9 / 16)
                                  : (16 / 9)));
                          Widget thumb;
                          if (m.type == AvatarMediaType.image) {
                            thumb = SizedBox(
                              height: h,
                              child: AspectRatio(
                                aspectRatio: ar,
                                child: Image.network(m.url, fit: BoxFit.cover),
                              ),
                            );
                          } else if (m.type == AvatarMediaType.video) {
                            // Im Bestätigungs-Popup KEIN VideoPlayer – nur statisches Thumbnail/Platzhalter
                            thumb = SizedBox(
                              height: h,
                              child: AspectRatio(
                                aspectRatio: ar,
                                child: (m.thumbUrl != null)
                                    ? Image.network(
                                        m.thumbUrl!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stack) =>
                                            Container(
                                              color: Colors.black26,
                                              child: const Icon(
                                                Icons.play_circle,
                                                color: Colors.white54,
                                              ),
                                            ),
                                      )
                                    : Container(
                                        color: Colors.black26,
                                        child: const Icon(
                                          Icons.play_circle,
                                          color: Colors.white54,
                                        ),
                                      ),
                              ),
                            );
                          } else if (m.type == AvatarMediaType.document) {
                            thumb = SizedBox(
                              height: h,
                              child: AspectRatio(
                                aspectRatio: ar,
                                child: _buildDocumentPreview(m),
                              ),
                            );
                          } else {
                            // Audio: Nur statischer Preview + Dateiname (keine Player/Status-Bezüge)
                            final audioFileName =
                                m.originalFileName ??
                                Uri.parse(
                                  m.url,
                                ).pathSegments.last.split('?').first;
                            thumb = SizedBox(
                              width: h * 2.0,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    height: h * 0.7,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: (m.thumbUrl != null)
                                          ? Image.network(
                                              m.thumbUrl!,
                                              fit: BoxFit.cover,
                                              width: double.infinity,
                                              errorBuilder:
                                                  (context, error, s) =>
                                                      Container(
                                                        color: Colors.black26,
                                                        child: const Icon(
                                                          Icons.audiotrack,
                                                          color: Colors.white54,
                                                        ),
                                                      ),
                                            )
                                          : Container(
                                              color: Colors.black26,
                                              child: const Icon(
                                                Icons.audiotrack,
                                                color: Colors.white54,
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    audioFileName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: thumb,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              LayoutBuilder(
                builder: (ctx2, cons) {
                  final bool stackVertical = cons.maxWidth < 380;

                  final Widget cancel = TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      overlayColor: Colors.transparent,
                    ),
                    child: Text(
                      'Abbrechen',
                      style: TextStyle(
                        color: Colors.grey.shade300,
                        fontSize: 14,
                      ),
                    ),
                  );

                  final Widget delete = TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [
                          Color(0xFFE91E63),
                          AppColors.lightBlue,
                          Color(0xFF00E5FF),
                        ],
                      ).createShader(bounds),
                      child: const Text(
                        'Löschen',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );

                  if (stackVertical) {
                    return SizedBox(
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: 44, child: cancel),
                          const SizedBox(height: 10),
                          SizedBox(height: 44, child: delete),
                        ],
                      ),
                    );
                  }

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [cancel, delete],
                  );
                },
              ),
            ],
          );
        },
      ),
    );

    // Timer entfernt – keine Dialog-Rebuild-Ticks mehr

    if (confirmed != true) {
      // Falls wir nur pausiert hatten: Wiedergabe fortsetzen
      if (pausedForDialog) {
        try {
          await _audioPlayer?.resume();
        } catch (_) {}
      }
      // Bei Abbrechen: Delete-Mode beenden
      setState(() {
        _isDeleteMode = false;
        _selectedMediaIds.clear();
      });
      return;
    }

    try {
      bool playerTouched = false;
      // Lösche alle selected Medien (robust, ohne auf _items.first zu fallen)
      for (final mediaId in _selectedMediaIds.toList()) {
        // Prüfe ob dieses Medium in der Liste existiert
        final int mediaIndex = _items.indexWhere((m) => m.id == mediaId);
        if (mediaIndex == -1) {
          continue; // bereits entfernt/neu geladen
        }
        final media = _items[mediaIndex];
        if (_playingAudioUrl == media.url || _currentAudioUrl == media.url) {
          // Merke: Player muss nach dem Löschen einmalig sauber entsorgt werden
          playerTouched = true;
          setState(() {
            _playingAudioUrl = null;
            _currentAudioUrl = null;
            _audioProgress.remove(media.url);
            _audioCurrentTime.remove(media.url);
            _audioTotalTime.remove(media.url);
          });
        }

        try {
          await _mediaSvc.delete(widget.avatarId, mediaId, media.type);
        } catch (_) {}
        // Lokalen Zustand sofort aktualisieren (kein Full-Reload)
        _items.removeWhere((m) => m.id == mediaId);
        _mediaToPlaylists.remove(mediaId);
      }
      setState(() {
        _selectedMediaIds.clear();
        _isDeleteMode = false;
      });
      // Falls das gelöschte Medium gerade spielte: Player sauber aufräumen (einmalig)
      if (playerTouched) {
        await _disposeAudioPlayers();
      }
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

  /// Minimaler Delete-Flow ohne jegliche Dialog-Previews/Timer/Player-Bezüge
  Future<void> _confirmDeleteSelectedMinimal() async {
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
            child: Text(
              'Abbrechen',
              style: TextStyle(color: Colors.grey.shade300),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [
                  Color(0xFFE91E63),
                  AppColors.lightBlue,
                  Color(0xFF00E5FF),
                ],
              ).createShader(bounds),
              child: const Text(
                'Löschen',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      setState(() {
        _isDeleteMode = false;
        _selectedMediaIds.clear();
      });
      return;
    }

    try {
      bool playerTouched = false;
      for (final mediaId in _selectedMediaIds.toList()) {
        final int mediaIndex = _items.indexWhere((m) => m.id == mediaId);
        if (mediaIndex == -1) {
          continue;
        }
        final media = _items[mediaIndex];
        if (_playingAudioUrl == media.url || _currentAudioUrl == media.url) {
          playerTouched = true;
          setState(() {
            _playingAudioUrl = null;
            _currentAudioUrl = null;
            _audioProgress.remove(media.url);
            _audioCurrentTime.remove(media.url);
            _audioTotalTime.remove(media.url);
          });
        }
        try {
          await _mediaSvc.delete(widget.avatarId, mediaId, media.type);
        } catch (_) {}
        _items.removeWhere((m) => m.id == mediaId);
        _mediaToPlaylists.remove(mediaId);
      }
      if (playerTouched) {
        await _disposeAudioPlayers();
      }
      setState(() {
        _selectedMediaIds.clear();
        _isDeleteMode = false;
      });
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

  /// Neue gekapselte Delete-Funktion für Bilder und Videos (wie in details_screen)
  /// - Zeigt Media-Vorschau im Dialog
  /// - Löscht Thumbnails aus Storage
  /// - Löscht Firestore-Dokumente
  /// - Löscht Originale aus Storage
  /// - Aktualisiert Avatar-Daten (imageUrls, videoUrls, heroVideoUrl)
  Future<void> _confirmDeleteSelectedComplete() async {
    // Selektierte Medien sammeln
    final selectedMedia = _items
        .where((m) => _selectedMediaIds.contains(m.id))
        .toList();
    final images = selectedMedia
        .where((m) => m.type == AvatarMediaType.image)
        .toList();
    final videos = selectedMedia
        .where((m) => m.type == AvatarMediaType.video)
        .toList();
    final documents = selectedMedia
        .where((m) => m.type == AvatarMediaType.document)
        .toList();
    final count = selectedMedia.length;

    if (count == 0) return;

    final loc = context.read<LocalizationService>();

    // Bestätigungsdialog MIT Media-Vorschau (wie in details_screen)
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$count ${count == 1 ? 'Medium' : 'Medien'} löschen?'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Bilder
                ...images.map(
                  (media) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      media.thumbUrl ?? media.url,
                      width: 54,
                      height: 96,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 54,
                        height: 96,
                        color: Colors.grey.shade800,
                        child: const Icon(Icons.image, color: Colors.white54),
                      ),
                    ),
                  ),
                ),
                // Videos
                ...videos.map(
                  (media) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 54,
                      height: 96,
                      child: media.thumbUrl != null
                          ? Image.network(
                              media.thumbUrl!,
                              width: 54,
                              height: 96,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    width: 54,
                                    height: 96,
                                    color: Colors.grey.shade800,
                                    child: const Icon(
                                      Icons.videocam,
                                      color: Colors.white54,
                                    ),
                                  ),
                            )
                          : Container(
                              width: 54,
                              height: 96,
                              color: Colors.grey.shade800,
                              child: const Icon(
                                Icons.videocam,
                                color: Colors.white54,
                              ),
                            ),
                    ),
                  ),
                ),
                // Dokumente
                ...documents.map(
                  (media) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 54,
                      height: 96,
                      child: media.thumbUrl != null
                          ? Image.network(
                              media.thumbUrl!,
                              width: 54,
                              height: 96,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    width: 54,
                                    height: 96,
                                    color: Colors.grey.shade800,
                                    child: const Icon(
                                      Icons.description,
                                      color: Colors.white54,
                                    ),
                                  ),
                            )
                          : Container(
                              width: 54,
                              height: 96,
                              color: Colors.grey.shade800,
                              child: const Icon(
                                Icons.description,
                                color: Colors.white54,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
            child: Text(loc.t('buttons.cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.white,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppColors.magenta, AppColors.lightBlue],
              ).createShader(bounds),
              child: const Text(
                'Löschen',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      setState(() {
        _isDeleteMode = false;
        _selectedMediaIds.clear();
      });
      return;
    }

    try {
      // Avatar-Daten laden
      final avatarService = AvatarService();
      final avatar = await avatarService.getAvatar(widget.avatarId);
      if (avatar == null) {
        throw Exception('Avatar nicht gefunden');
      }

      List<String> imageUrls = List.from(avatar.imageUrls);
      List<String> videoUrls = List.from(avatar.videoUrls);

      // BILDER löschen
      for (final media in images) {
        try {
          debugPrint('DEL img start: ${media.url}');
          // ERST: thumbUrl aus Firestore holen und löschen
          String? thumbUrl;
          try {
            debugPrint('DEL images query for avatar=${widget.avatarId}');
            final qs = await FirebaseFirestore.instance
                .collection('avatars')
                .doc(widget.avatarId)
                .collection('images')
                .where('url', isEqualTo: media.url)
                .get();
            debugPrint('DEL images docs: ${qs.docs.length}');
            for (final d in qs.docs) {
              final data = d.data();
              thumbUrl = (data['thumbUrl'] as String?);
              if (thumbUrl != null && thumbUrl.isNotEmpty) {
                debugPrint('DEL: Lösche Thumbnail: $thumbUrl');
                try {
                  await FirebaseStorageService.deleteFile(thumbUrl);
                  debugPrint('DEL: Thumbnail gelöscht ✓');
                } catch (e) {
                  debugPrint('DEL: Thumbnail-Fehler: $e');
                }
              }
              await d.reference.delete();
            }
          } catch (e) {
            debugPrint('DEL: Firestore-Fehler: $e');
          }
          // Original löschen
          await FirebaseStorageService.deleteFile(media.url);
          debugPrint('DEL img storage OK');
        } catch (e) {
          debugPrint('DEL img error: $e');
        }
        imageUrls.remove(media.url);
      }

      // VIDEOS löschen
      for (final media in videos) {
        try {
          debugPrint('🗑️ Lösche Video: ${media.url}');
          await FirebaseStorageService.deleteFile(media.url);
          final originalPath = FirebaseStorageService.pathFromUrl(media.url);
          if (originalPath.isNotEmpty) {
            final dir = p.dirname(originalPath); // avatars/<id>/videos
            final base = p.basenameWithoutExtension(originalPath);
            final prefix = '$dir/thumbs/${base}_';
            debugPrint('🗑️ Video-Thumbs Prefix: $prefix');
            try {
              await FirebaseStorageService.deleteByPrefix(prefix);
              debugPrint('🗑️ Video-Thumbs gelöscht: $prefix');
            } catch (e) {
              debugPrint('⚠️ Fehler beim Löschen der Video-Thumbs: $e');
            }
          }
          try {
            final qs = await FirebaseFirestore.instance
                .collection('avatars')
                .doc(widget.avatarId)
                .collection('videos')
                .where('url', isEqualTo: media.url)
                .get();
            for (final d in qs.docs) {
              await d.reference.delete();
              debugPrint('🗑️ Firestore Video-Doc gelöscht: ${d.id}');
            }
          } catch (e) {
            debugPrint('⚠️ Fehler beim Löschen des Video-Docs: $e');
          }
        } catch (e) {
          debugPrint('❌ Fehler beim Löschen des Videos: $e');
        }
        videoUrls.remove(media.url);
      }

      // DOKUMENTE löschen
      for (final media in documents) {
        try {
          debugPrint('📄 Lösche Dokument: ${media.url}');
          // Thumbnail löschen
          if (media.thumbUrl != null && media.thumbUrl!.isNotEmpty) {
            try {
              await FirebaseStorageService.deleteFile(media.thumbUrl!);
              debugPrint('📄 Dokument-Thumb gelöscht ✓');
            } catch (e) {
              debugPrint('⚠️ Fehler beim Löschen des Dokument-Thumbs: $e');
            }
          }
          // Original löschen
          await FirebaseStorageService.deleteFile(media.url);
          debugPrint('📄 Dokument Storage gelöscht ✓');
          // Firestore löschen
          try {
            final qs = await FirebaseFirestore.instance
                .collection('avatars')
                .doc(widget.avatarId)
                .collection('documents')
                .where('url', isEqualTo: media.url)
                .get();
            for (final d in qs.docs) {
              await d.reference.delete();
              debugPrint('📄 Firestore Dokument-Doc gelöscht: ${d.id}');
            }
          } catch (e) {
            debugPrint('⚠️ Fehler beim Löschen des Dokument-Docs: $e');
          }
        } catch (e) {
          debugPrint('❌ Fehler beim Löschen des Dokuments: $e');
        }
      }

      // Hero-Video prüfen und aktualisieren
      String? newHeroVideoUrl;
      try {
        final currentHero = avatar.training?['heroVideoUrl'] as String?;
        debugPrint(
          '🎬 Hero-Video-Check: currentHero=$currentHero, videoUrls=${videoUrls.length}',
        );

        // Prüfe ob Hero noch existiert
        final heroExists =
            currentHero != null && videoUrls.contains(currentHero);

        if (!heroExists) {
          if (videoUrls.isNotEmpty) {
            // Hero fehlt, aber Videos da → erstes Video als neues Hero merken
            newHeroVideoUrl = videoUrls.first;
            debugPrint('🎬 Neues Hero-Video wird gesetzt: $newHeroVideoUrl');
          } else {
            // Keine Videos mehr → heroVideoUrl wird gelöscht (null)
            newHeroVideoUrl = null;
            debugPrint('🎬 HeroVideoUrl wird gelöscht (keine Videos mehr)');
          }
        } else {
          // Hero existiert noch → behalten
          newHeroVideoUrl = currentHero;
        }
      } catch (e) {
        debugPrint('❌ Fehler bei Hero-Video-Check: $e');
      }

      // Avatar-Daten aktualisieren
      final tr = Map<String, dynamic>.from(avatar.training ?? {});
      if (newHeroVideoUrl != null) {
        tr['heroVideoUrl'] = newHeroVideoUrl;
        debugPrint(
          '🎬 Training: heroVideoUrl wird gesetzt auf $newHeroVideoUrl',
        );
      } else {
        // newHeroVideoUrl ist null → heroVideoUrl muss gelöscht werden
        tr.remove('heroVideoUrl');
        debugPrint('🎬 Training: heroVideoUrl wird entfernt');
      }

      // Profilbild prüfen (falls ein Bild gelöscht wurde, das als avatarImageUrl verwendet wird)
      String? newAvatarImageUrl = avatar.avatarImageUrl;
      if (newAvatarImageUrl != null && !imageUrls.contains(newAvatarImageUrl)) {
        newAvatarImageUrl = imageUrls.isNotEmpty ? imageUrls.first : null;
        debugPrint('🖼️ AvatarImageUrl wird aktualisiert: $newAvatarImageUrl');
      }

      final updated = avatar.copyWith(
        imageUrls: imageUrls,
        videoUrls: videoUrls,
        avatarImageUrl: newAvatarImageUrl,
        clearAvatarImageUrl: newAvatarImageUrl == null && imageUrls.isEmpty,
        training: tr,
        updatedAt: DateTime.now(),
      );
      final success = await avatarService.updateAvatar(updated);
      if (success) {
        debugPrint(
          '✅ Avatar nach Delete aktualisiert: ${videoUrls.length} Videos, heroVideoUrl=$newHeroVideoUrl',
        );
      }

      // Audio-Player aufräumen falls nötig
      bool playerTouched = false;
      for (final media in selectedMedia) {
        if (_playingAudioUrl == media.url || _currentAudioUrl == media.url) {
          playerTouched = true;
          setState(() {
            _playingAudioUrl = null;
            _currentAudioUrl = null;
            _audioProgress.remove(media.url);
            _audioCurrentTime.remove(media.url);
            _audioTotalTime.remove(media.url);
          });
        }
      }
      if (playerTouched) {
        await _disposeAudioPlayers();
      }

      // Lokale Listen aktualisieren
      _items.removeWhere((m) => _selectedMediaIds.contains(m.id));
      for (final mediaId in _selectedMediaIds) {
        _mediaToPlaylists.remove(mediaId);
      }

      setState(() {
        _selectedMediaIds.clear();
        _isDeleteMode = false;
      });

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
  // Caches für Dokument-Previews, um erneute Netzwerk-Loads zu vermeiden
  final Map<String, Future<Uint8List?>> _docPreviewImageFuture = {};
  final Map<String, Future<String?>> _docPreviewTextFuture = {};
  // Ermitteltes Seitenverhältnis der Dokument-Preview-Bilder (aus Bytes)
  final Map<String, double> _docAspectRatios = {};

  /// Dokument-Preview: PDF erste Seite als Bild; TXT/MD/RTF Snippet; PPTX/DOCX erste eingebettete Grafik
  Widget _buildDocumentPreview(AvatarMedia it) {
    final lower = (it.originalFileName ?? it.url).toLowerCase();
    if (lower.endsWith('.pdf')) {
      final f = _docPreviewImageFuture[it.url] ??= _fetchPdfPreviewBytes(
        it.url,
      );
      return FutureBuilder<Uint8List?>(
        future: f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          final data = snap.data;
          if (data == null || data.isEmpty) {
            return const Center(
              child: Icon(
                Icons.picture_as_pdf,
                color: Colors.white54,
                size: 40,
              ),
            );
          }
          return Image.memory(data, fit: BoxFit.cover);
        },
      );
    }
    if (lower.endsWith('.txt') ||
        lower.endsWith('.md') ||
        lower.endsWith('.rtf')) {
      final f = _docPreviewTextFuture[it.url] ??= _fetchTextSnippet(
        it.url,
        lower.endsWith('.rtf'),
      );
      return FutureBuilder<String?>(
        future: f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          final t = (snap.data ?? '');
          if (t.isEmpty) {
            return Container(color: Colors.black26);
          }
          return Container(
            color: const Color(0xFF111111),
            padding: const EdgeInsets.all(8),
            child: Text(
              t,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                height: 1.2,
              ),
              maxLines: 12,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      );
    }
    // PPTX: erste eingebettete Grafik als Vorschau
    if (lower.endsWith('.pptx')) {
      final f = _docPreviewImageFuture[it.url] ??= _fetchPptxPreviewBytes(
        it.url,
      );
      return FutureBuilder<Uint8List?>(
        future: f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          final img = snap.data;
          if (img == null) {
            return const Center(
              child: Icon(Icons.slideshow, color: Colors.white70, size: 40),
            );
          }
          return Image.memory(img, fit: BoxFit.cover);
        },
      );
    }
    // DOCX: erste eingebettete Grafik
    if (lower.endsWith('.docx')) {
      final f = _docPreviewImageFuture[it.url] ??= _fetchDocxPreviewBytes(
        it.url,
      );
      return FutureBuilder<Uint8List?>(
        future: f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          final img = snap.data;
          if (img == null) {
            return const Center(
              child: Icon(Icons.description, color: Colors.white70, size: 40),
            );
          }
          return Image.memory(img, fit: BoxFit.cover);
        },
      );
    }
    // RTF/DOCX/PPTX – Platzhalter-Icon
    return Container(
      color: Colors.black26,
      alignment: Alignment.center,
      child: const Icon(Icons.description, color: Colors.white70, size: 40),
    );
  }

  /// Dokument-Preview als Hintergrundbild (cover, centered) für PDF/PPTX/DOCX
  /// Fällt auf die normale Preview zurück, wenn keine Bildbytes verfügbar sind (z.B. TXT/RTF)
  Widget _buildDocumentPreviewBackground(AvatarMedia it) {
    final lower = (it.originalFileName ?? it.url).toLowerCase();
    Future<Uint8List?>? f;
    if (lower.endsWith('.pdf')) {
      f = _docPreviewImageFuture[it.url] ??= _fetchPdfPreviewBytes(it.url);
    } else if (lower.endsWith('.pptx')) {
      f = _docPreviewImageFuture[it.url] ??= _fetchPptxPreviewBytes(it.url);
    } else if (lower.endsWith('.docx')) {
      f = _docPreviewImageFuture[it.url] ??= _fetchDocxPreviewBytes(it.url);
    }

    if (f == null) {
      // Für Text-Formate etc. auf Standard-Preview zurückfallen
      return _buildDocumentPreview(it);
    }

    return FutureBuilder<Uint8List?>(
      future: f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final data = snap.data;
        if (data == null || data.isEmpty) {
          return _buildDocumentPreview(it);
        }
        // Hintergrundbild mit cover+center, Container sichtbar (blau) machen
        return Container(
          decoration: BoxDecoration(
            color: Colors.blueAccent.withValues(alpha: 0.15),
            image: DecorationImage(
              image: MemoryImage(data),
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }

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
      // Quelle beschaffen: Für Dokumente das generierte Preview-Bild verwenden
      Uint8List? bytes;
      if (media.type == AvatarMediaType.document) {
        final lower = (media.originalFileName ?? media.url).toLowerCase();
        if (lower.endsWith('.pdf')) {
          bytes = await _fetchPdfPreviewBytes(media.url);
        } else if (lower.endsWith('.pptx')) {
          bytes = await _fetchPptxPreviewBytes(media.url);
        } else if (lower.endsWith('.docx')) {
          bytes = await _fetchDocxPreviewBytes(media.url);
        } else {
          // Für reine Textformate (txt/md/rtf) kein Bild-Preview → Zuschneiden nicht möglich
          bytes = null;
        }
      } else {
        final source = await _downloadToTemp(media.url, suffix: '.png');
        bytes = await source?.readAsBytes();
      }

      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            buildErrorSnackBar('Kein Preview-Bild zum Zuschneiden verfügbar.'),
          );
        }
        return;
      }
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      // Bildmaße ermitteln, um Portrait/Landscape zu erkennen
      bool isPortraitImage = true;
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final img = frame.image;
        final ar = img.width / img.height;
        isPortraitImage = ar < 1.0;
        img.dispose();
      } catch (_) {}

      // Verwende das bestehende Crop-Dialog
      double currentAspect = _cropAspect;
      Uint8List? croppedBytes;
      final cropController =
          cyi.CropController(); // Neuer Controller für jeden Dialog
      bool isCropping = false;

      await showDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setLocal) => AlertDialog(
              contentPadding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.magenta, width: 3),
              ),
              content: SizedBox(
                width: isPortraitImage ? 520 : 480,
                height: isPortraitImage
                    ? (MediaQuery.of(ctx).size.height * 0.82)
                    : 560,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.crop, color: Colors.white70),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => setLocal(() => currentAspect = 9 / 16),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                gradient: currentAspect == 9 / 16
                                    ? const LinearGradient(
                                        colors: [
                                          Color(0xFFE91E63),
                                          AppColors.lightBlue,
                                          Color(0xFF00E5FF),
                                        ],
                                      )
                                    : null,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.white24,
                                  width: 2,
                                ),
                              ),
                              child: Text(
                                '9:16',
                                style: TextStyle(
                                  color: currentAspect == 9 / 16
                                      ? Colors.white
                                      : Colors.white70,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => setLocal(() => currentAspect = 16 / 9),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                gradient: currentAspect == 16 / 9
                                    ? const LinearGradient(
                                        colors: [
                                          Color(0xFFE91E63),
                                          AppColors.lightBlue,
                                          Color(0xFF00E5FF),
                                        ],
                                      )
                                    : null,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.white24,
                                  width: 2,
                                ),
                              ),
                              child: Text(
                                '16:9',
                                style: TextStyle(
                                  color: currentAspect == 16 / 9
                                      ? Colors.white
                                      : Colors.white70,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: cyi.Crop(
                        key: ValueKey(currentAspect),
                        controller: cropController,
                        image: bytes!,
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Abbrechen (light grey)
                          MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: TextButton(
                              onPressed: isCropping
                                  ? null
                                  : () => Navigator.pop(ctx),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 12,
                                ),
                              ),
                              child: Text(
                                'Abbrechen',
                                style: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          // Zuschneiden (disabled: GMBC text, enabled: white button + GMBC text)
                          TextButton(
                            onPressed: isCropping
                                ? null
                                : () {
                                    // Busy-Spinner aktivieren
                                    setLocal(() => isCropping = true);
                                    // Force crop auch wenn nicht bewegt wurde
                                    try {
                                      cropController.crop();
                                    } catch (e) {
                                      // Fallback: Croppe das ganze Bild
                                      croppedBytes = bytes;
                                      Navigator.of(ctx).pop();
                                    }
                                  },
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: isCropping
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : ShaderMask(
                                    shaderCallback: (bounds) =>
                                        const LinearGradient(
                                          colors: [
                                            Color(0xFFE91E63),
                                            AppColors.lightBlue,
                                            Color(0xFF00E5FF),
                                          ],
                                        ).createShader(bounds),
                                    child: const Text(
                                      'Zuschneiden',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
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
            ),
          );
        },
      );

      if (croppedBytes == null) return;

      final timestamp = DateTime.now().millisecondsSinceEpoch;

      if (media.type == AvatarMediaType.document) {
        // Upload als Thumb speichern und in Firestore verknüpfen
        final ref = FirebaseStorage.instance.ref().child(
          'avatars/${widget.avatarId}/documents/thumbs/${media.id}_$timestamp.jpg',
        );
        final task = await ref.putData(
          croppedBytes!,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        final thumbUrl = await task.ref.getDownloadURL();

        await FirebaseFirestore.instance
            .collection('avatars')
            .doc(widget.avatarId)
            .collection('documents')
            .doc(media.id)
            .set({
              'thumbUrl': thumbUrl,
              'aspectRatio': _cropAspect,
            }, SetOptions(merge: true));

        // lokal aktualisieren
        final idx = _items.indexWhere((m) => m.id == media.id);
        if (idx != -1) {
          _items[idx] = AvatarMedia(
            id: media.id,
            avatarId: media.avatarId,
            type: media.type,
            url: media.url,
            thumbUrl: thumbUrl,
            createdAt: media.createdAt,
            durationMs: media.durationMs,
            aspectRatio: _cropAspect,
            tags: media.tags,
            originalFileName: media.originalFileName,
            isFree: media.isFree,
            price: media.price,
            currency: media.currency,
          );
        }
        if (mounted) setState(() {});
        return;
      }

      // Bilder/Videos: vorhandenen bestehenden Re-Crop-Prozess beibehalten
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
      final newPath = '$baseDir/recrop_$timestamp$ext';

      final dir = await getTemporaryDirectory();
      final tempFile = File('${dir.path}/recrop_$timestamp$ext');
      await tempFile.writeAsBytes(croppedBytes!, flush: true);

      // KI-Bildanalyse nur für Bilder (nicht für Videos)
      List<String> newTags = [];
      if (media.type == AvatarMediaType.image) {
        try {
          newTags = await _visionSvc.analyzeImage(tempFile.path);
        } catch (_) {}
      }

      // ERST: Altes thumbUrl aus Firestore holen UND alte Files aus Storage löschen
      // (BEVOR Firestore geändert wird, wegen Storage Rules!)
      String? oldThumbUrl;
      try {
        debugPrint('RECROP: Hole altes thumbUrl aus Firestore');
        final collectionName = media.type == AvatarMediaType.image
            ? 'images'
            : 'videos';
        final doc = await FirebaseFirestore.instance
            .collection('avatars')
            .doc(widget.avatarId)
            .collection(collectionName)
            .doc(media.id)
            .get();
        if (doc.exists) {
          final data = doc.data();
          oldThumbUrl = (data?['thumbUrl'] as String?);
          debugPrint('RECROP: Altes thumbUrl gefunden: $oldThumbUrl');
        }

        debugPrint('RECROP: Lösche ALTE Files JETZT (vor Firestore-Update)');

        // 1) Explizit altes thumbUrl löschen (wichtig für Storage Rules!)
        if (oldThumbUrl != null && oldThumbUrl.isNotEmpty) {
          debugPrint('RECROP: Lösche altes Thumbnail: $oldThumbUrl');
          try {
            await FirebaseStorageService.deleteFile(oldThumbUrl);
            debugPrint('RECROP: Altes Thumbnail gelöscht ✓');
          } catch (e) {
            debugPrint('RECROP: Fehler beim Löschen: $e');
          }
        }

        // 2) ALLE weiteren Thumbnails zum alten Bild/Video löschen (falls mehrere existieren)
        final dir = p.dirname(originalPath); // avatars/<id>/images oder videos
        final thumbsDir = '$dir/thumbs';

        // Für Videos: media.id als Prefix (Cloud Function nutzt mediaId_timestamp.jpg)
        // Für Bilder: Dateiname als Prefix
        final searchPrefix = media.type == AvatarMediaType.video
            ? '${media.id}_'
            : p.basenameWithoutExtension(originalPath);

        debugPrint(
          'RECROP: Suche weitere Thumbnails in: $thumbsDir für Prefix: $searchPrefix',
        );
        try {
          final ref = FirebaseStorage.instance.ref().child(thumbsDir);
          final listResult = await ref.listAll();
          for (final item in listResult.items) {
            // Prüfe ob Dateiname mit searchPrefix beginnt
            if (item.name.startsWith(searchPrefix)) {
              debugPrint('RECROP: Lösche weiteres Thumbnail: ${item.fullPath}');
              try {
                await item.delete();
                debugPrint('RECROP: Weiteres Thumbnail gelöscht ✓');
              } catch (e) {
                debugPrint('RECROP: Fehler beim Löschen: $e');
              }
            }
          }
        } catch (e) {
          debugPrint('RECROP: Fehler beim Listen der Thumbnails: $e');
        }

        // Altes Original löschen
        debugPrint('RECROP: Lösche altes Original: ${media.url}');
        try {
          await FirebaseStorageService.deleteFile(media.url);
          debugPrint('RECROP: Altes Original gelöscht ✓');
        } catch (e) {
          debugPrint('RECROP: Original-Fehler: $e');
        }
      } catch (e) {
        debugPrint('RECROP: Fehler beim Löschen alter Dateien: $e');
      }

      // Upload neues recrop Image
      final upload = await FirebaseStorageService.uploadImage(
        tempFile,
        customPath: newPath,
      );

      if (upload != null && mounted) {
        // ERST neues Thumbnail erstellen, DANN Firestore updaten
        String? newThumbUrl;
        try {
          final mediaFolder = media.type == AvatarMediaType.image
              ? 'images'
              : 'videos';
          final thumbPath =
              'avatars/${widget.avatarId}/$mediaFolder/thumbs/recrop_${timestamp}.jpg';
          final imgBytes = await tempFile.readAsBytes();
          final decoded = img.decodeImage(imgBytes);
          if (decoded != null) {
            final resized = img.copyResize(decoded, width: 360);
            final jpg = img.encodeJpg(resized, quality: 70);
            final dir2 = await getTemporaryDirectory();
            final thumbFile = await File(
              '${dir2.path}/thumb_${timestamp}.jpg',
            ).create();
            await thumbFile.writeAsBytes(jpg, flush: true);
            newThumbUrl = await FirebaseStorageService.uploadImage(
              thumbFile,
              customPath: thumbPath,
            );
            debugPrint('RECROP: Neues Thumbnail erstellt: $newThumbUrl');
          }
        } catch (e) {
          debugPrint('RECROP: Fehler beim Thumbnail-Erstellen: $e');
        }

        // 1) Firestore: Media-Dokument DELETE + SET MIT thumbUrl (verhindert Cloud Function onCreate!)
        try {
          final collectionName = media.type == AvatarMediaType.image
              ? 'images'
              : 'videos';
          final docRef = FirebaseFirestore.instance
              .collection('avatars')
              .doc(widget.avatarId)
              .collection(collectionName)
              .doc(media.id);

          // Alte Daten für Neuanlage sichern
          final oldDoc = await docRef.get();
          final oldData = oldDoc.data() ?? {};
          final createdAt =
              (oldData['createdAt'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch;
          final existingTags = (oldData['tags'] as List?)?.cast<String>() ?? [];
          final finalTags = newTags.isNotEmpty ? newTags : existingTags;

          // Für Bilder: neues Crop-Aspect-Ratio verwenden
          // Für Videos: Original-Aspect-Ratio beibehalten (nur Thumbnail wird gecroppt)
          final newAspectRatio = media.type == AvatarMediaType.image
              ? _cropAspect
              : media.aspectRatio;

          // DELETE + SET (verhindert onCreate-Trigger!)
          try {
            await docRef.delete();
          } catch (_) {}

          await docRef.set({
            'avatarId': widget.avatarId,
            'type': media.type == AvatarMediaType.image ? 'image' : 'video',
            'url': upload,
            'thumbUrl': newThumbUrl, // Direkt das neue Thumbnail setzen!
            'createdAt': createdAt,
            'id': media.id,
            if (newAspectRatio != null) 'aspectRatio': newAspectRatio,
            if (finalTags.isNotEmpty) 'tags': finalTags,
            if (media.originalFileName != null)
              'originalFileName': media.originalFileName,
            if (media.durationMs != null) 'durationMs': media.durationMs,
            if (media.isFree != null) 'isFree': media.isFree,
            if (media.price != null) 'price': media.price,
            if (media.currency != null) 'currency': media.currency,
          });
          debugPrint(
            'RECROP: Firestore-Dokument ($collectionName) DELETE+SET mit thumbUrl',
          );
        } catch (e) {
          debugPrint('RECROP: Firestore-Update-Fehler: $e');
        }

        // 2) Firestore Avatar: imageUrls/videoUrls-Eintrag (falls vorhanden) von alt→neu ersetzen
        try {
          final avatarRef = FirebaseFirestore.instance
              .collection('avatars')
              .doc(widget.avatarId);
          final snap = await avatarRef.get();
          final data = snap.data();

          if (media.type == AvatarMediaType.image) {
            final List<dynamic>? arr = data != null
                ? data['imageUrls'] as List<dynamic>?
                : null;
            if (arr != null && arr.isNotEmpty) {
              final List<String> updated = arr
                  .map((e) => e.toString())
                  .toList();
              final idx = updated.indexOf(media.url);
              if (idx != -1) {
                updated[idx] = upload;
                await avatarRef.set({
                  'imageUrls': updated,
                }, SetOptions(merge: true));
                debugPrint('RECROP: Avatar imageUrls aktualisiert');
              }
            }
          } else if (media.type == AvatarMediaType.video) {
            final List<dynamic>? arr = data != null
                ? data['videoUrls'] as List<dynamic>?
                : null;
            if (arr != null && arr.isNotEmpty) {
              final List<String> updated = arr
                  .map((e) => e.toString())
                  .toList();
              final idx = updated.indexOf(media.url);
              if (idx != -1) {
                updated[idx] = upload;
                await avatarRef.set({
                  'videoUrls': updated,
                }, SetOptions(merge: true));
                debugPrint('RECROP: Avatar videoUrls aktualisiert');
              }
            }
          }
        } catch (e) {
          debugPrint('RECROP: Avatar-Update-Fehler: $e');
        }

        await _load();
        final mediaTypeName = media.type == AvatarMediaType.image
            ? 'Bild'
            : 'Video';
        ScaffoldMessenger.of(context).showSnackBar(
          buildSuccessSnackBar('$mediaTypeName erfolgreich neu zugeschnitten'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(buildErrorSnackBar('Fehler beim Zuschneiden: $e'));
      }
    }
  }

  Future<void> _openViewer(AvatarMedia media) async {
    // Audio: kein spezieller Viewer → Tags-Dialog
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
        globalPricing: _globalPricing,
        onPricingRequest: (m, refreshInViewer) async {
          await _openMediaPricingDialog(m);
          // Nach dem Dialog den aktualisierten Datensatz aus _items holen
          final updated = _items.firstWhere(
            (x) => x.id == m.id,
            orElse: () => m,
          );
          refreshInViewer(updated);
        },
        buildDocBackground: _buildDocumentPreviewBackground,
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
    final isFree = media.isFree ?? false;

    // Wenn EDITING: Zeige Input-Container mit GMBC-Gradient
    if (isEditing) {
      return Container(
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
            // LINKS: Input-Feld für Preis-Bearbeitung
            Expanded(child: _buildPriceField(media, isEditing)),
            // MITTE: "Zurück zu Global" Button (wenn individueller Preis gesetzt)
            if (media.price != null)
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () async {
                    // Zurück zu Global: price auf null setzen
                    try {
                      await FirebaseFirestore.instance
                          .collection('avatars')
                          .doc(widget.avatarId)
                          .collection(
                            _getCollectionNameForMediaType(media.type),
                          )
                          .doc(media.id)
                          .update({
                            'price': FieldValue.delete(),
                            'currency': FieldValue.delete(),
                          });

                      // Lokale Liste aktualisieren
                      final index = _items.indexWhere((m) => m.id == media.id);
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
                          price: null,
                          currency: null,
                        );
                      }

                      // Input schließen
                      _editingPriceMediaIds.remove(media.id);
                      setState(() {});
                    } catch (e) {
                      debugPrint('Fehler beim Zurücksetzen auf Global: $e');
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    height: 40,
                    alignment: Alignment.center,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh, size: 16, color: Colors.white70),
                        SizedBox(width: 4),
                        Text(
                          'Global',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // RECHTS: X-Button (Abbrechen) + Hook (Speichern)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // X-Button (Abbrechen)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      // Abbrechen ohne Speichern - alte Werte wiederherstellen
                      // Falls kein individueller Preis: Globalen Preis verwenden
                      final mediaTypeKey = media.type == AvatarMediaType.audio
                          ? 'audio'
                          : media.type == AvatarMediaType.image
                          ? 'image'
                          : media.type == AvatarMediaType.video
                          ? 'video'
                          : 'document';
                      final gp =
                          _globalPricing[mediaTypeKey] as Map<String, dynamic>?;
                      final gpPrice = (gp?['price'] as num?)?.toDouble() ?? 0.0;
                      final price = media.price ?? gpPrice;
                      final priceText = price
                          .toStringAsFixed(2)
                          .replaceAll('.', ',');
                      _priceControllers[media.id]?.text = priceText;
                      _tempCurrency[media.id] = media.currency ?? '\$';
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
                // Hook Icon (Speichern)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () async {
                      // Preis aus Input parsen
                      final inputText =
                          _priceControllers[media.id]?.text ?? '0,00';
                      final cleanText = inputText.replaceAll(',', '.');
                      final newPrice = double.tryParse(cleanText) ?? 0.0;
                      final newCurrency = _tempCurrency[media.id] ?? '\$';

                      // Firestore Update
                      try {
                        await FirebaseFirestore.instance
                            .collection('avatars')
                            .doc(widget.avatarId)
                            .collection(
                              _getCollectionNameForMediaType(media.type),
                            )
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
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFFE91E63), // Magenta
                            AppColors.lightBlue, // Blue
                            Color(0xFF00E5FF), // Cyan
                          ],
                        ),
                        borderRadius: BorderRadius.only(
                          bottomRight: Radius.circular(7),
                        ),
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 24,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // STANDARD-ANSICHT: Preis + "Kostenpflichtig/Kostenlos" Toggle + Credits + Edit-Stift
    // Berechne effektiven Preis (individuelle Überschreibung oder global)
    final mediaTypeKey = media.type == AvatarMediaType.audio
        ? 'audio'
        : media.type == AvatarMediaType.image
        ? 'image'
        : media.type == AvatarMediaType.video
        ? 'video'
        : 'document';
    final gp = _globalPricing[mediaTypeKey] as Map<String, dynamic>?;
    final gpEnabled = (gp?['enabled'] as bool?) ?? false;
    final gpPrice = (gp?['price'] as num?)?.toDouble() ?? 0.0;
    final gpCur = _normalizeCurrencyToSymbol(gp?['currency'] as String?);

    final overridePrice = media.price;
    final overrideCur = _normalizeCurrencyToSymbol(media.currency);

    // Wenn isFree: Preis ist immer 0,00
    final effectivePrice = isFree
        ? 0.0
        : (overridePrice ?? (gpEnabled ? gpPrice : 0.0));
    final effectiveCurrency = (overridePrice != null ? overrideCur : gpCur);
    final symbol = effectiveCurrency == '\$' ? '\$' : '€';

    // Credits berechnen (10 Cent = 1 Credit)
    final credits = isFree ? 0 : (effectivePrice * 10).ceil();

    // Ob individueller Preis gesetzt ist (für farbigen Punkt am Edit-Stift)
    final hasIndividualPrice = media.price != null;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0x20FFFFFF), // Leichter transparenter Hintergrund
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(7),
          bottomRight: Radius.circular(7),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Stack(
        children: [
          // MITTE (absolut zentriert): "Kostenpflichtig" / "Kostenlos" Toggle
          Positioned.fill(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () async {
                  // Toggle isFree
                  final newIsFree = !isFree;
                  try {
                    await FirebaseFirestore.instance
                        .collection('avatars')
                        .doc(widget.avatarId)
                        .collection(_getCollectionNameForMediaType(media.type))
                        .doc(media.id)
                        .update({'isFree': newIsFree});

                    // Lokale Liste aktualisieren
                    final index = _items.indexWhere((m) => m.id == media.id);
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
                        isFree: newIsFree,
                        price: media.price,
                        currency: media.currency,
                      );
                    }
                    setState(() {});
                  } catch (e) {
                    debugPrint('Fehler beim Toggle isFree: $e');
                  }
                },
                child: Center(
                  child: isFree
                      ? const Text(
                          'Kostenlos',
                          style: TextStyle(
                            color: Colors.white54, // lightgrey
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        )
                      : ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [
                              Color(0xFFE91E63), // Magenta
                              AppColors.lightBlue, // Blue
                              Color(0xFF00E5FF), // Cyan
                            ],
                          ).createShader(bounds),
                          child: const Text(
                            'Kostenpflichtig',
                            style: TextStyle(
                              color: Colors.white, // GMBC-Farbe
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                ),
              ),
            ),
          ),
          // LINKS: Preis-Anzeige (über Toggle-Layer)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '$symbol${effectivePrice.toStringAsFixed(2).replaceAll('.', ',')}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          // RECHTS: Credits (GMBC) + Edit-Stift (nur wenn NICHT kostenlos)
          if (!isFree)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Credits mit GMBC-Farbe und Diamant
                  if (gpEnabled || overridePrice != null) ...[
                    IgnorePointer(
                      child: ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [
                            Color(0xFFE91E63), // Magenta
                            AppColors.lightBlue, // Blue
                            Color(0xFF00E5FF), // Cyan
                          ],
                        ).createShader(bounds),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$credits',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 3),
                            const Icon(
                              Icons.diamond,
                              size: 12,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Edit-Stift mit optionalem farbigem Punkt (individueller Preis)
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          // Controller initialisieren beim Öffnen
                          if (!_priceControllers.containsKey(media.id)) {
                            final price = media.price ?? gpPrice;
                            final priceText = price
                                .toStringAsFixed(2)
                                .replaceAll('.', ',');
                            _priceControllers[media.id] = TextEditingController(
                              text: priceText,
                            );
                          }
                          // Temp-Currency setzen
                          _tempCurrency[media.id] =
                              media.currency ??
                              (gpCur.isNotEmpty ? gpCur : '\$');
                          _editingPriceMediaIds.add(media.id);
                        });
                      },
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: Colors.white70,
                          ),
                          // Farbiger Punkt (GMBC) oben rechts, wenn individueller Preis
                          if (hasIndividualPrice)
                            Positioned(
                              top: -2,
                              right: -2,
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFFE91E63), // Magenta
                                      AppColors.lightBlue, // Blue
                                      Color(0xFF00E5FF), // Cyan
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Öffnet Pricing-Dialog für Bild/Video
  Future<void> _openMediaPricingDialog(AvatarMedia media) async {
    // Edit-Mode State
    bool isEditing = false;
    TextEditingController? priceController;
    String? tempCurrency;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // WICHTIG: Aktuelles media aus _items holen (wegen Updates)
            final currentMedia = _items.firstWhere(
              (m) => m.id == media.id,
              orElse: () => media,
            );

            final String typeKey = currentMedia.type == AvatarMediaType.image
                ? 'image'
                : (currentMedia.type == AvatarMediaType.video
                      ? 'video'
                      : 'document');
            final gp = _globalPricing[typeKey] as Map<String, dynamic>?;
            final gpEnabled = (gp?['enabled'] as bool?) ?? false;
            final gpPrice = (gp?['price'] as num?)?.toDouble() ?? 0.0;
            final gpCur = _normalizeCurrencyToSymbol(
              gp?['currency'] as String?,
            );

            final overridePrice = currentMedia.price;
            final overrideCur = _normalizeCurrencyToSymbol(
              currentMedia.currency,
            );
            final isFree = currentMedia.isFree ?? false;

            final effectivePrice = isFree
                ? 0.0
                : (overridePrice ?? (gpEnabled ? gpPrice : 0.0));
            final effectiveCurrency = (overridePrice != null
                ? overrideCur
                : gpCur);
            final symbol = effectiveCurrency == '\$' ? '\$' : '€';

            final credits = isFree ? 0 : (effectivePrice * 10).ceil();
            final hasIndividualPrice = currentMedia.price != null;

            // Global Button sichtbar wenn: Edit-Mode UND Input != Global-Preis
            bool showGlobal = false;
            if (isEditing && priceController != null) {
              final inputText = priceController!.text;
              final cleanInput = inputText.replaceAll(',', '.');
              final inputPrice = double.tryParse(cleanInput) ?? 0.0;
              final inputCur = tempCurrency ?? '\$';

              showGlobal = (inputPrice != gpPrice) || (inputCur != gpCur);
            } else {
              showGlobal = overridePrice != null;
            }

            // Vorschauhöhe: wenn Global unten erscheint, 30px weniger
            final double previewHeight = 328 - (showGlobal ? 30 : 0);

            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              contentPadding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              content: SizedBox(
                width: 328,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header mit Close Button
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              currentMedia.type == AvatarMediaType.image
                                  ? 'Bildpreis'
                                  : 'Videopreis',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          // Close Button
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white70,
                              size: 24,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                    // Bild/Video mit 16:9 oder 9:16 Darstellung
                    (() {
                      final mediaAR = currentMedia.aspectRatio ?? (9 / 16);
                      final isLandscape = mediaAR >= 1.0;

                      Widget imageWidget;
                      if (currentMedia.type == AvatarMediaType.image) {
                        imageWidget = Image.network(
                          currentMedia.url,
                          fit: BoxFit.cover,
                        );
                      } else {
                        imageWidget = FutureBuilder<VideoPlayerController?>(
                          future: _videoControllerForThumb(currentMedia.url),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                    ConnectionState.done &&
                                snapshot.hasData &&
                                snapshot.data != null &&
                                snapshot.data!.value.isInitialized) {
                              final controller = snapshot.data!;
                              return FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: controller.value.size.width,
                                  height: controller.value.size.height,
                                  child: VideoPlayer(controller),
                                ),
                              );
                            }
                            return const Center(
                              child: Icon(
                                Icons.play_circle_outline,
                                size: 64,
                                color: Colors.white,
                              ),
                            );
                          },
                        );
                      }

                      // Für Landscape: volle Breite (328), 16:9-Höhe
                      if (isLandscape) {
                        return SizedBox(
                          width: 328,
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: ClipRRect(
                              borderRadius: BorderRadius.zero,
                              child: imageWidget,
                            ),
                          ),
                        );
                      }

                      // Für Portrait: volle Höhe (previewHeight), 9:16-Breite
                      return SizedBox(
                        height: previewHeight,
                        child: AspectRatio(
                          aspectRatio: 9 / 16,
                          child: ClipRRect(
                            borderRadius: BorderRadius.zero,
                            child: imageWidget,
                          ),
                        ),
                      );
                    })(),
                    // Pricing Box
                    ImageVideoPricingBox(
                      isFree: isFree,
                      effectivePrice: effectivePrice,
                      symbol: symbol,
                      credits: credits,
                      hasIndividualPrice: hasIndividualPrice,
                      showCredits: gpEnabled || overridePrice != null,
                      isEditing: isEditing,
                      priceController: priceController,
                      tempCurrency: tempCurrency,
                      showGlobalButton: showGlobal,
                      onToggleFree: () async {
                        // Toggle isFree
                        final newIsFree = !isFree;
                        try {
                          await FirebaseFirestore.instance
                              .collection('avatars')
                              .doc(widget.avatarId)
                              .collection(
                                _getCollectionNameForMediaType(
                                  currentMedia.type,
                                ),
                              )
                              .doc(currentMedia.id)
                              .update({'isFree': newIsFree});

                          // Lokale Liste aktualisieren
                          final index = _items.indexWhere(
                            (m) => m.id == currentMedia.id,
                          );
                          if (index != -1) {
                            _items[index] = AvatarMedia(
                              id: currentMedia.id,
                              avatarId: currentMedia.avatarId,
                              type: currentMedia.type,
                              url: currentMedia.url,
                              thumbUrl: currentMedia.thumbUrl,
                              createdAt: currentMedia.createdAt,
                              durationMs: currentMedia.durationMs,
                              aspectRatio: currentMedia.aspectRatio,
                              tags: currentMedia.tags,
                              originalFileName: currentMedia.originalFileName,
                              isFree: newIsFree,
                              price: currentMedia.price,
                              currency: currentMedia.currency,
                            );
                          }
                          setState(() {});
                          setDialogState(() {});
                        } catch (e) {
                          debugPrint('Fehler beim Toggle isFree: $e');
                        }
                      },
                      onEdit: () {
                        // Edit-Mode aktivieren
                        setDialogState(() {
                          isEditing = true;
                          // Controller initialisieren wenn nicht vorhanden
                          if (priceController == null) {
                            final price = currentMedia.price ?? gpPrice;
                            final priceText = price
                                .toStringAsFixed(2)
                                .replaceAll('.', ',');
                            priceController = TextEditingController(
                              text: priceText,
                            );
                          }
                          tempCurrency =
                              currentMedia.currency ??
                              (gpCur.isNotEmpty ? gpCur : '\$');
                        });
                      },
                      onCancel: () {
                        // Abbrechen - zurück zu Standard-Mode
                        setDialogState(() {
                          isEditing = false;
                          priceController?.dispose();
                          priceController = null;
                        });
                      },
                      onSave: () async {
                        // Preis speichern
                        debugPrint('💰 SAVE PRICE START');
                        final inputText = priceController?.text ?? '0,00';
                        final cleanText = inputText.replaceAll(',', '.');
                        final newPrice = double.tryParse(cleanText) ?? 0.0;
                        final newCurrency = tempCurrency ?? '\$';

                        debugPrint(
                          '💰 Input: $inputText → Price: $newPrice, Currency: $newCurrency',
                        );
                        debugPrint(
                          '💰 Media: ${currentMedia.id}, Type: ${currentMedia.type}',
                        );
                        final collectionName = _getCollectionNameForMediaType(
                          currentMedia.type,
                        );
                        debugPrint('💰 Collection: $collectionName');

                        try {
                          debugPrint('💰 Firestore update STARTING...');
                          await FirebaseFirestore.instance
                              .collection('avatars')
                              .doc(widget.avatarId)
                              .collection(collectionName)
                              .doc(currentMedia.id)
                              .update({
                                'price': newPrice,
                                'currency': newCurrency,
                              });
                          debugPrint('💰 Firestore update SUCCESS');

                          // Lokale Liste aktualisieren
                          final index = _items.indexWhere(
                            (m) => m.id == currentMedia.id,
                          );
                          if (index != -1) {
                            _items[index] = AvatarMedia(
                              id: currentMedia.id,
                              avatarId: currentMedia.avatarId,
                              type: currentMedia.type,
                              url: currentMedia.url,
                              thumbUrl: currentMedia.thumbUrl,
                              createdAt: currentMedia.createdAt,
                              durationMs: currentMedia.durationMs,
                              aspectRatio: currentMedia.aspectRatio,
                              tags: currentMedia.tags,
                              originalFileName: currentMedia.originalFileName,
                              isFree: currentMedia.isFree,
                              price: newPrice,
                              currency: newCurrency,
                            );
                          }

                          setState(() {});
                          setDialogState(() {
                            isEditing = false;
                            priceController?.dispose();
                            priceController = null;
                          });

                          debugPrint('💰 About to pop dialog...');
                          // Schließe nur Pricing-Dialog (Viewer bleibt offen)
                          Navigator.of(context).pop();
                          debugPrint('💰 Dialog popped!');

                          // Erfolgs-Snackbar
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '✅ Preis gespeichert: $newCurrency${newPrice.toStringAsFixed(2)}',
                                  style: const TextStyle(color: Colors.white),
                                ),
                                backgroundColor: Colors.green,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        } catch (e, stackTrace) {
                          debugPrint('❌ FEHLER beim Speichern: $e');
                          debugPrint('❌ StackTrace: $stackTrace');

                          // Fehler-Snackbar anzeigen
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '❌ FEHLER: $e',
                                  style: const TextStyle(color: Colors.white),
                                ),
                                backgroundColor: Colors.red,
                                duration: const Duration(seconds: 5),
                              ),
                            );
                          }
                        }
                      },
                      onCurrencyChanged: (newCur) {
                        setDialogState(() {
                          tempCurrency = newCur;
                        });
                      },
                      onPriceChanged: () {
                        setDialogState(() {
                          // Trigger rebuild um showGlobal neu zu berechnen
                        });
                      },
                      onGlobal: () async {
                        // Zurück zu Global-Preis
                        try {
                          await FirebaseFirestore.instance
                              .collection('avatars')
                              .doc(widget.avatarId)
                              .collection(
                                _getCollectionNameForMediaType(
                                  currentMedia.type,
                                ),
                              )
                              .doc(currentMedia.id)
                              .update({
                                'price': FieldValue.delete(),
                                'currency': FieldValue.delete(),
                              });

                          // Lokale Liste aktualisieren
                          final index = _items.indexWhere(
                            (m) => m.id == currentMedia.id,
                          );
                          if (index != -1) {
                            _items[index] = AvatarMedia(
                              id: currentMedia.id,
                              avatarId: currentMedia.avatarId,
                              type: currentMedia.type,
                              url: currentMedia.url,
                              thumbUrl: currentMedia.thumbUrl,
                              createdAt: currentMedia.createdAt,
                              durationMs: currentMedia.durationMs,
                              aspectRatio: currentMedia.aspectRatio,
                              tags: currentMedia.tags,
                              originalFileName: currentMedia.originalFileName,
                              isFree: currentMedia.isFree,
                              price: null,
                              currency: null,
                            );
                          }

                          setState(() {});
                          setDialogState(() {
                            isEditing = false;
                            priceController?.dispose();
                            priceController = null;
                          });
                        } catch (e) {
                          debugPrint('Fehler beim Zurücksetzen: $e');
                        }
                      },
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

  /// Preis-Feld: Zeigt Preis + Credits oder Input
  Widget _buildPriceField(AvatarMedia media, bool isEditing) {
    // Falls kein individueller Preis: Globalen Preis verwenden
    final mediaTypeKey = media.type == AvatarMediaType.audio
        ? 'audio'
        : media.type == AvatarMediaType.image
        ? 'image'
        : media.type == AvatarMediaType.video
        ? 'video'
        : 'document';
    final gp = _globalPricing[mediaTypeKey] as Map<String, dynamic>?;
    final gpPrice = (gp?['price'] as num?)?.toDouble() ?? 0.0;
    final price = media.price ?? gpPrice;
    final priceText = price.toStringAsFixed(2).replaceAll('.', ',');
    final credits = (price / 0.1).round(); // 10 Cent = 1 Credit
    final currency = media.currency ?? '\$';

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
              // Credits-Anzeige (wie Audio-Pricing)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$credits',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.diamond, size: 12, color: Colors.white),
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
          // Waveform Thumbnail aus DB (0.5 opacity)
          if (media.thumbUrl != null)
            Positioned(
              left: 20,
              right: 20,
              top: 0,
              bottom: 32,
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Opacity(
                    opacity: 0.5,
                    child: Image.network(
                      media.thumbUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.black26,
                        child: const Icon(
                          Icons.audiotrack,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // Progress-Waveform ÜBER dem Thumbnail
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
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
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
                        size: 20,
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
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0x50000000),
                          ),
                          child: const Icon(
                            Icons.replay,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  // Symmetrischer Spacer + unsichtbarer Platzhalter für exakte Zentrierung
                  const SizedBox(width: 8),
                  Opacity(
                    opacity: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0x50000000),
                      ),
                      child: const Icon(
                        Icons.replay,
                        size: 16,
                        color: Colors.white,
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

    // Fallback je nach Typ
    if (tags.isEmpty) {
      if (media.type == AvatarMediaType.audio) {
        tags.add('audio');
      } else if (media.type == AvatarMediaType.video)
        tags.add('video');
      else if (media.type == AvatarMediaType.image)
        tags.add('image');
      else if (media.type == AvatarMediaType.document)
        tags.add('document');
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
                                // Abbrechen als einfacher Text-Link
                                MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 12,
                                      ),
                                    ),
                                    child: Text(
                                      'Abbrechen',
                                      style: TextStyle(
                                        color: Colors.grey.shade400,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                                // Speichern mit weißem Background wenn aktiv
                                TextButton(
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
                                            media.type,
                                            tags: newTags,
                                          );
                                          await _load();
                                          Navigator.pop(ctx);

                                          if (mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              buildSuccessSnackBar(
                                                '${newTags.length} Tags gespeichert',
                                              ),
                                            );
                                          }
                                        }
                                      : null,
                                  style: TextButton.styleFrom(
                                    backgroundColor: hasChanged
                                        ? Colors.white
                                        : Colors.transparent,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: ShaderMask(
                                    shaderCallback: (bounds) =>
                                        const LinearGradient(
                                          colors: [
                                            Color(0xFFE91E63),
                                            AppColors.lightBlue,
                                            Color(0xFF00E5FF),
                                          ],
                                        ).createShader(bounds),
                                    child: Text(
                                      'Speichern',
                                      style: TextStyle(
                                        color: hasChanged
                                            ? Colors.white
                                            : Colors.white30,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // Media Preview - Audio im Audio-Card-Style
                            if (media.type == AvatarMediaType.audio)
                              _buildAudioPreviewForDialog(media)
                            else
                              Center(
                                child: SizedBox(
                                  child: media.type == AvatarMediaType.video
                                      ? (media.thumbUrl != null
                                            ? ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: Image.network(
                                                  media.thumbUrl!,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, stack) {
                                                    // Fallback zu VideoPlayer
                                                    return FutureBuilder<
                                                      VideoPlayerController?
                                                    >(
                                                      future:
                                                          _videoControllerForThumb(
                                                            media.url,
                                                          ),
                                                      builder: (context, snapshot) {
                                                        if (snapshot.connectionState ==
                                                                ConnectionState
                                                                    .done &&
                                                            snapshot.hasData &&
                                                            snapshot.data !=
                                                                null) {
                                                          final controller =
                                                              snapshot.data!;
                                                          if (controller
                                                              .value
                                                              .isInitialized) {
                                                            return AspectRatio(
                                                              aspectRatio:
                                                                  controller
                                                                      .value
                                                                      .aspectRatio,
                                                              child:
                                                                  VideoPlayer(
                                                                    controller,
                                                                  ),
                                                            );
                                                          }
                                                        }
                                                        return Container(
                                                          color: Colors.black26,
                                                        );
                                                      },
                                                    );
                                                  },
                                                ),
                                              )
                                            : FutureBuilder<
                                                VideoPlayerController?
                                              >(
                                                future:
                                                    _videoControllerForThumb(
                                                      media.url,
                                                    ),
                                                builder: (context, snapshot) {
                                                  if (snapshot.connectionState ==
                                                          ConnectionState
                                                              .done &&
                                                      snapshot.hasData &&
                                                      snapshot.data != null) {
                                                    final controller =
                                                        snapshot.data!;
                                                    if (controller
                                                        .value
                                                        .isInitialized) {
                                                      return AspectRatio(
                                                        aspectRatio: controller
                                                            .value
                                                            .aspectRatio,
                                                        child: VideoPlayer(
                                                          controller,
                                                        ),
                                                      );
                                                    }
                                                  }
                                                  return Container(
                                                    color: Colors.black26,
                                                  );
                                                },
                                              ))
                                      : LayoutBuilder(
                                          builder: (context, cons) {
                                            final ar =
                                                media.aspectRatio ?? (9 / 16);
                                            final maxH = ar < 1.0
                                                ? 294.0
                                                : 224.0; // Portrait höher als Landscape (30% kleiner)
                                            return ConstrainedBox(
                                              constraints: BoxConstraints(
                                                maxHeight: maxH,
                                              ),
                                              child: AspectRatio(
                                                aspectRatio: ar,
                                                child:
                                                    media.type ==
                                                        AvatarMediaType.document
                                                    ? _buildDocumentPreviewBackground(
                                                        media,
                                                      )
                                                    : Image.network(
                                                        media.url,
                                                        fit: BoxFit.cover,
                                                      ),
                                              ),
                                            );
                                          },
                                        ),
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
                                      : media.type == AvatarMediaType.document
                                      ? 'Dokument-Tags'
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
              // OBERER CONTAINER: Waveform + Controls
              SizedBox(
                height: 78,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Stack(
                    children: [
                      // Waveform Thumbnail aus DB (0.5 opacity)
                      if (it.thumbUrl != null)
                        Positioned.fill(
                          left: 8,
                          right: 8,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Opacity(
                              opacity: 0.5,
                              child: Image.network(
                                it.thumbUrl!,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    Container(
                                      color: Colors.black26,
                                      child: const Icon(
                                        Icons.audiotrack,
                                        color: Colors.white54,
                                      ),
                                    ),
                              ),
                            ),
                          ),
                        ),
                      // Progress-Overlay (LIGHTBLUE)
                      Positioned.fill(
                        left: 8,
                        right: 8,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
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
                      // Play/Pause + Restart Controls (links)
                      Positioned(
                        left: 8,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () => _toggleAudioPlayback(it),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFFE91E63),
                                        AppColors.lightBlue,
                                        Color(0xFF00E5FF),
                                      ],
                                    ),
                                  ),
                                  child: Icon(
                                    isPlaying ? Icons.pause : Icons.play_arrow,
                                    size: 24,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              if (progress > 0.0 || isPlaying)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: GestureDetector(
                                    onTap: () => _restartAudio(it),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Color(0x40FFFFFF),
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
                      // Tag + Delete Icons (rechts) - HORIZONTAL - DELETE ZUERST!
                      Positioned(
                        right: 8,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // DELETE ICON ZUERST (ganz rechts)
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    if (selected) {
                                      _selectedMediaIds.remove(it.id);
                                    } else {
                                      _selectedMediaIds.add(it.id);
                                    }
                                    // Delete-Mode nur aktiv, wenn mind. 1 Element ausgewählt ist
                                    _isDeleteMode =
                                        _selectedMediaIds.isNotEmpty;
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
                              // TAG ICON LINKS DAVON
                              if (!_isDeleteMode) const SizedBox(width: 4),
                              if (!_isDeleteMode)
                                InkWell(
                                  onTap: () => _showTagsDialog(it),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(
                                        0x30000000,
                                      ), // Wie Trash
                                      border: Border.all(
                                        color: const Color(0x66FFFFFF),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.label_outline,
                                      color: Colors.white, // Weiß ohne Gradient
                                      size: 14,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      // Playlist Icon (oben links)
                      if (isInPlaylist && !_isDeleteMode)
                        Positioned(
                          left: 6,
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
                  bottom: 0,
                  top: 5,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                    Text(
                      '${_formatDuration(currentTime)} / ${_formatDuration(totalTime)}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (it.tags != null && it.tags!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Color(0xFFE91E63),
                            AppColors.lightBlue,
                            Color(0xFF00E5FF),
                          ],
                          stops: [0.0, 0.5, 1.0],
                        ).createShader(bounds),
                        child: Text(
                          it.tags!.join(', '),
                          style: const TextStyle(
                            color: Colors.white,
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
              const SizedBox(height: 15),
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
                      // Transparent für noch nicht abgespielte Striche
                      Colors.transparent,
                      Colors.transparent,
                      Colors.transparent,
                    ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      }),
    );
  }

  /// Audio Controls (Play/Pause/Reload) - zentriert auf Waveform
  Widget _buildAudioControls(AvatarMedia it) {
    final isPlaying = _playingAudioUrl == it.url;
    final progress = _audioProgress[it.url] ?? 0.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Play/Pause Button (größer, da zentral)
        GestureDetector(
          onTap: () => _toggleAudioPlayback(it),
          child: Container(
            padding: const EdgeInsets.all(16),
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
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              size: 32,
              color: Colors.white,
            ),
          ),
        ),
        // Reload Button (nur wenn bereits gespielt)
        if (progress > 0.0 || isPlaying) ...[
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => _restartAudio(it),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.6),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: const Icon(Icons.replay, size: 20, color: Colors.white),
            ),
          ),
        ],
      ],
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

  /// Aktualisiert Preis-Einstellungen für ein Media-Element
  Future<void> _updateMediaPrice(
    AvatarMedia media, {
    required bool isFree,
    double? price,
  }) async {
    try {
      // Aktualisiere lokal
      final updatedMedia = AvatarMedia(
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
        isFree: isFree,
        price: isFree ? null : price,
      );

      // Aktualisiere in Firestore
      await FirebaseFirestore.instance
          .collection('avatars')
          .doc(media.avatarId)
          .collection(_getCollectionNameForMediaType(media.type))
          .doc(media.id)
          .update({
            'isFree': isFree,
            if (price != null && !isFree) 'price': price,
            if (isFree) 'price': FieldValue.delete(),
          });

      // Aktualisiere Liste
      setState(() {
        final index = _items.indexWhere((m) => m.id == media.id);
        if (index != -1) {
          _items[index] = updatedMedia;
        }
      });
    } catch (e) {
      debugPrint('Fehler beim Aktualisieren des Preises: $e');
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
            await _mediaSvc.update(
              widget.avatarId,
              image.id,
              image.type,
              tags: tags,
            );
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
  final Map<String, dynamic> globalPricing;
  final Future<void> Function(AvatarMedia, void Function(AvatarMedia))
  onPricingRequest;
  final Widget Function(AvatarMedia)? buildDocBackground;

  const _MediaViewerDialog({
    required this.initialMedia,
    required this.allMedia,
    required this.initialIndex,
    required this.onCropRequest,
    required this.globalPricing,
    required this.onPricingRequest,
    this.buildDocBackground,
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

  @override
  void didUpdateWidget(_MediaViewerDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Wenn allMedia sich ändert, aktualisiere _currentMedia
    // Suche das Medium mit der gleichen ID (falls es aktualisiert wurde)
    final updatedMedia = widget.allMedia.firstWhere(
      (m) => m.id == _currentMedia.id,
      orElse: () => widget.allMedia[_currentIndex],
    );
    if (updatedMedia != _currentMedia) {
      _currentMedia = updatedMedia;
    }
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
          // Media Content (Image, Document, Video)
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
          else if (_currentMedia.type == AvatarMediaType.document)
            AspectRatio(
              aspectRatio: _currentMedia.aspectRatio ?? (9 / 16),
              child: (widget.buildDocBackground != null)
                  ? widget.buildDocBackground!(_currentMedia)
                  : Image.network(_currentMedia.url, fit: BoxFit.contain),
            )
          else
            _VideoDialog(
              key: ValueKey(_currentMedia.id), // Key für Rebuild bei Navigation
              url: _currentMedia.url,
            ),

          // Preis-Badge unten mittig (nur Bild/Video)
          if ((_currentMedia.type == AvatarMediaType.image ||
              _currentMedia.type == AvatarMediaType.video))
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Center(child: _buildViewerPriceBadge(_currentMedia)),
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

  Widget _buildViewerPriceBadge(AvatarMedia it) {
    final typeKey = it.type == AvatarMediaType.image
        ? 'image'
        : (it.type == AvatarMediaType.video ? 'video' : 'document');
    final gp = widget.globalPricing[typeKey] as Map<String, dynamic>?;
    final gpEnabled = (gp?['enabled'] as bool?) ?? false;
    final gpPrice = (gp?['price'] as num?)?.toDouble() ?? 0.0;
    final gpCur = (gp?['currency'] as String?) ?? 'EUR';

    final overridePrice = it.price;
    final overrideCur = it.currency ?? 'EUR';
    final isFree = it.isFree ?? false;

    final effectivePrice = overridePrice ?? (gpEnabled ? gpPrice : null);
    if (effectivePrice == null && !isFree) return const SizedBox.shrink();

    String sym(String c) {
      final u = c.toUpperCase();
      return (u == 'USD' || c == '\$' || u == 'US\$')
          ? String.fromCharCode(0x24)
          : String.fromCharCode(0x20AC);
    }

    final symbol = sym(overridePrice != null ? overrideCur : gpCur);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onPricingRequest(it, (updated) {
          // Refresh in Viewer: ersetze _currentMedia, falls gleiche ID
          if (updated.id == _currentMedia.id) {
            setState(() {
              _currentMedia = updated;
            });
          }
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFFE91E63),
                AppColors.lightBlue,
                Color(0xFF00E5FF),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white, width: 1),
          ),
          child: Text(
            isFree
                ? 'Kostenlos'
                : '$symbol${effectivePrice!.toStringAsFixed(2).replaceAll('.', ',')}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.0,
              letterSpacing: 0,
            ),
          ),
        ),
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

// Video Thumbnail Selector Dialog Widget
class _VideoThumbnailSelectorDialog extends StatefulWidget {
  final String videoUrl;
  final String avatarId;
  final String mediaId;
  final VoidCallback onComplete;

  const _VideoThumbnailSelectorDialog({
    required this.videoUrl,
    required this.avatarId,
    required this.mediaId,
    required this.onComplete,
  });

  @override
  State<_VideoThumbnailSelectorDialog> createState() =>
      _VideoThumbnailSelectorDialogState();
}

class _VideoThumbnailSelectorDialogState
    extends State<_VideoThumbnailSelectorDialog> {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  bool _isGenerating = false;
  double _currentPosition = 0.0;
  String _currentTimeLabel = '0:00';
  bool _showInfo = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );
      await _controller!.initialize();
      setState(() {
        _isLoading = false;
      });

      // Listen to position changes
      _controller!.addListener(() {
        if (mounted && _controller!.value.isInitialized) {
          final pos = _controller!.value.position.inMilliseconds.toDouble();
          final duration = _controller!.value.duration.inMilliseconds
              .toDouble();
          setState(() {
            _currentPosition = duration > 0 ? pos / duration : 0.0;
            _currentTimeLabel = _formatDuration(_controller!.value.position);
          });
        }
      });
    } catch (e) {
      debugPrint('❌ Video-Initialisierung fehlgeschlagen: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _generateThumbnail() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    setState(() {
      _isGenerating = true;
    });

    try {
      final timeInSeconds = _controller!.value.position.inSeconds;

      // ERST: Alte Thumbnails löschen (BEVOR Cloud Function neues erstellt!)
      try {
        debugPrint('🗑️ Lösche alte Video-Thumbnails für: ${widget.mediaId}');
        final thumbsPath = 'avatars/${widget.avatarId}/videos/thumbs';
        final ref = FirebaseStorage.instance.ref().child(thumbsPath);
        final listResult = await ref.listAll();
        for (final item in listResult.items) {
          // Lösche alle Thumbnails mit mediaId-Prefix
          if (item.name.startsWith('${widget.mediaId}_')) {
            debugPrint('🗑️ Lösche: ${item.fullPath}');
            try {
              await item.delete();
              debugPrint('🗑️ Gelöscht ✓');
            } catch (e) {
              debugPrint('⚠️ Fehler beim Löschen: $e');
            }
          }
        }
      } catch (e) {
        debugPrint('⚠️ Fehler beim Listen/Löschen der Thumbnails: $e');
      }

      // Call Cloud Function
      final response = await http.post(
        Uri.parse(
          'https://us-central1-sunriza26.cloudfunctions.net/extractVideoFrameAtPosition',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'avatarId': widget.avatarId,
          'mediaId': widget.mediaId,
          'videoUrl': widget.videoUrl,
          'timeInSeconds': timeInSeconds,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              buildSuccessSnackBar('Vorschaubild erfolgreich erstellt!'),
            );
            widget.onComplete();
            Navigator.pop(context);
          }
        } else {
          throw Exception(data['error'] ?? 'Unbekannter Fehler');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Thumbnail-Generierung fehlgeschlagen: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(buildErrorSnackBar('Fehler: $e'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxWidth: 1100,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [AppColors.magenta, AppColors.lightBlue],
                        ).createShader(bounds),
                        child: const Text(
                          'Vorschaubild',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'wählen',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white54,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 26,
                            height: 26,
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
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              iconSize: 16,
                              tooltip: 'Info',
                              icon: const Icon(
                                Icons.help_outline,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                setState(() {
                                  _showInfo = !_showInfo;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Info Box (inline, wenn _showInfo true)
              if (_showInfo)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFE91E63),
                          AppColors.lightBlue,
                          Color(0xFF00E5FF),
                        ],
                        stops: [0.0, 0.6, 1.0],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Spule zu dem gewünschten Bild im Video und tippe oben auf "Verwenden".',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              setState(() {
                                _showInfo = false;
                              });
                            },
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [
                                  Color(0xFFE91E63),
                                  AppColors.lightBlue,
                                  Color(0xFF00E5FF),
                                ],
                              ).createShader(bounds),
                              child: const Text(
                                'Schließen',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Video Player mit Overlay-Play unten rechts
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(80.0),
                    child: CircularProgressIndicator(color: AppColors.magenta),
                  ),
                )
              else if (_controller != null && _controller!.value.isInitialized)
                AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        VideoPlayer(_controller!),
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                if (_controller!.value.isPlaying) {
                                  _controller!.pause();
                                } else {
                                  _controller!.play();
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(22),
                            child: Container(
                              width: 36,
                              height: 36,
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
                              child: Icon(
                                _controller!.value.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                        // Verwenden-Button oben mittig im Bild
                        Positioned(
                          top: 12,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: TextButton(
                              onPressed: _isGenerating
                                  ? null
                                  : _generateThumbnail,
                              style: TextButton.styleFrom(
                                backgroundColor: _isGenerating
                                    ? Colors.grey
                                    : Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: _isGenerating
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : ShaderMask(
                                      shaderCallback: (bounds) =>
                                          const LinearGradient(
                                            colors: [
                                              Color(0xFFE91E63),
                                              AppColors.lightBlue,
                                              Color(0xFF00E5FF),
                                            ],
                                          ).createShader(bounds),
                                      child: const Text(
                                        'Verwenden',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Container(
                  height: 300,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.error_outline,
                      color: Colors.white54,
                      size: 64,
                    ),
                  ),
                ),

              const SizedBox(height: 20),

              const SizedBox(height: 12),

              // Seek Bar
              if (_controller != null && _controller!.value.isInitialized)
                Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppColors.magenta,
                        inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
                        thumbColor: AppColors.lightBlue,
                        overlayColor: AppColors.magenta.withValues(alpha: 0.2),
                        trackHeight: 4.0,
                      ),
                      child: Slider(
                        value: _currentPosition.clamp(0.0, 1.0),
                        min: 0.0,
                        max: 1.0,
                        onChanged: (value) {
                          if (_controller!.value.isInitialized) {
                            final duration = _controller!.value.duration;
                            final newPosition = duration * value;
                            _controller!.seekTo(newPosition);
                          }
                        },
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _currentTimeLabel,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          _formatDuration(_controller!.value.duration),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

              // Keine unteren Hinweise – Info über (i)-Button im Header
            ],
          ),
        ),
      ),
    );
  }
}

// CustomPainter für statische Waveform (WIE Original-Thumbnail!)
class _StaticWaveformPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.square;

    // Wie Original: Sehr dünn, sehr eng, viele Bars
    final barWidth = 1.0;
    final spacing = 1.5;
    final totalBars = (size.width / (barWidth + spacing)).floor();

    // Fixed seed für konsistentes Aussehen (wie ein echtes Audio-Thumbnail)
    final random = Random(12345);

    // Generiere Waveform-Muster mit realistischer Variation
    for (int i = 0; i < totalBars; i++) {
      final x = i * (barWidth + spacing);

      // Realistische Höhenverteilung (wie echte Audio-Wellen)
      double heightFactor;
      final randomVal = random.nextDouble();

      // Meistens mittlere bis niedrige Höhen (wie echte Audioformen)
      if (randomVal < 0.05) {
        // 5% sehr hohe Peaks
        heightFactor = 0.85 + random.nextDouble() * 0.15;
      } else if (randomVal < 0.15) {
        // 10% hohe Peaks
        heightFactor = 0.65 + random.nextDouble() * 0.2;
      } else if (randomVal < 0.40) {
        // 25% mittlere Höhen
        heightFactor = 0.4 + random.nextDouble() * 0.25;
      } else if (randomVal < 0.70) {
        // 30% niedrig-mittlere Höhen
        heightFactor = 0.25 + random.nextDouble() * 0.15;
      } else {
        // 30% sehr niedrige Höhen
        heightFactor = 0.1 + random.nextDouble() * 0.15;
      }

      final barHeight = size.height * heightFactor;
      final y1 = (size.height - barHeight) / 2;
      final y2 = y1 + barHeight;

      canvas.drawLine(Offset(x, y1), Offset(x, y2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
