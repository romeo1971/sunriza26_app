import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui' as ui;
import 'package:crop_your_image/crop_your_image.dart' as cyi;
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import 'package:flutter/services.dart';
import '../data/countries.dart';
import '../models/avatar_data.dart';
import '../services/avatar_service.dart';
import '../services/bithuman_service.dart';
import '../services/elevenlabs_service.dart';
import '../services/env_service.dart';
import '../services/firebase_storage_service.dart';
import '../services/geo_service.dart';
import '../services/localization_service.dart';
import '../services/media_service.dart';
import '../services/video_trim_service.dart';
import '../models/media_models.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_bottom_nav_bar.dart';
// import '../widgets/video_player_widget.dart'; // Jetzt in VideoMediaSection Widget
import '../widgets/custom_text_field.dart';
import '../widgets/custom_date_field.dart';
import '../widgets/custom_dropdown.dart';
import '../widgets/expansion_tiles/dynamics_expansion_tile.dart';
import '../widgets/expansion_tiles/greeting_text_expansion_tile.dart';
import '../widgets/expansion_tiles/social_media_expansion_tile.dart';
import '../widgets/expansion_tiles/texts_expansion_tile.dart';
import '../widgets/expansion_tiles/voice_selection_expansion_tile.dart';
import '../widgets/expansion_tiles/person_data_expansion_tile.dart';
import '../widgets/media/details/details_media_navigation_bar.dart';
import '../widgets/media/details/details_image_media_section.dart';
import '../widgets/media/details/details_video_media_section.dart';

// Custom Gradient Thumb für Slider
class GradientSliderThumbShape extends SliderComponentShape {
  final double thumbRadius;

  const GradientSliderThumbShape({this.thumbRadius = 8.0});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(thumbRadius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    // ignore: deprecated_member_use
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [AppColors.magenta, AppColors.lightBlue],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromCircle(center: center, radius: thumbRadius));

    canvas.drawCircle(center, thumbRadius, paint);
  }
}

// Sticky Navigation Bar Delegate
// ignore: unused_element
class _StickyNavBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _StickyNavBarDelegate({required this.child});

  @override
  double get minExtent => 60;

  @override
  double get maxExtent => 60;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(_StickyNavBarDelegate oldDelegate) {
    return false;
  }
}

class _NamedItem {
  final String name;
  final Widget widget;
  const _NamedItem({required this.name, required this.widget});
}

class AvatarDetailsScreen extends StatefulWidget {
  const AvatarDetailsScreen({super.key});

  @override
  State<AvatarDetailsScreen> createState() => _AvatarDetailsScreenState();
}

class _AvatarDetailsScreenState extends State<AvatarDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _mediaSvc = MediaService();
  final _db = FirebaseDatabase.instance;
  final _firstNameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _cityController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _countryController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _deathDateController = TextEditingController();
  final _regionInputController = TextEditingController();
  bool _regionEditing = true;
  String? _role;

  DateTime? _birthDate;
  DateTime? _deathDate;
  int? _calculatedAge;

  AvatarData? _avatarData;
  bool _slugPulse = false;
  Timer? _slugPulseTimer;
  String? get _avatarSlug {
    // Lokaler Cache hat Vorrang (sofortige UI-Aktualisierung nach Speichern)
    if (_slugCache != null && _slugCache!.isNotEmpty) return _slugCache;
    final a = _avatarData;
    if (a == null) return null;
    try {
      return (a as dynamic).slug as String?;
    } catch (_) {
      return null;
    }
  }
  String? _slugCache;
  String? _pendingAvatarId; // für Navigation mit nur avatarId
  final List<String> _imageUrls = [];
  final List<String> _videoUrls = [];
  final List<String> _textFileUrls = [];
  final Map<String, String> _mediaOriginalNames = {}; // URL -> originalFileName
  bool _mediaOriginalNamesLoaded = false; // verhindert kurzzeitigen Zahlennamen
  final Map<String, bool> _isRecropping =
      {}; // URL -> isRecropping (Loading Spinner)
  final Map<String, int> _imageDurations =
      {}; // URL -> duration in seconds (default 60)
  bool _isImageLoopMode = true; // Kreislauf (true) oder Ende (false)
  bool _isTimelineEnabled = true; // Timeline generell aktiviert/deaktiviert
  final Map<String, bool> _imageActive =
      {}; // URL -> aktiv (true) oder inaktiv (false)
  final Map<String, bool> _imageExplorerVisible =
      {}; // URL -> Explorer-Sichtbarkeit
  final Map<String, bool> _videoAudioEnabled =
      {}; // URL -> Audio ON (true) oder OFF (false) ✅
  final TextEditingController _textAreaController = TextEditingController();

  // Live Avatar State
  bool _isGeneratingLiveAvatar = false;
  String? _liveAvatarAgentId;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _avatarDocSubscription;

  // Timeline-Daten in Firebase speichern
  Future<void> _saveTimelineData() async {
    if (_avatarData == null) return;

    // WICHTIG: Hero-Image (Index 0) ist IMMER aktiv & sichtbar!
    if (_imageUrls.isNotEmpty) {
      final heroUrl = _imageUrls[0];
      _imageActive[heroUrl] = true;
      _imageExplorerVisible[heroUrl] = true;
    }

    // Sicherstellen, dass ALLE Bilder eine Duration haben (Min: 60 Sekunden = 1 Minute)
    for (final url in _imageUrls) {
      final current = _imageDurations[url];
      if (current == null || current < 60) {
        _imageDurations[url] = 60; // Minimum 1 Minute
      }
    }

    try {
      await FirebaseFirestore.instance
          .collection('avatars')
          .doc(_avatarData!.id)
          .update({
            'imageTimeline': {
              'durations': _imageDurations,
              'loopMode': _isImageLoopMode,
              'enabled': _isTimelineEnabled,
              'active': _imageActive,
              'explorerVisible': _imageExplorerVisible,
            },
          });
      debugPrint('✅ Timeline-Daten gespeichert (Hero immer aktiv & sichtbar)');
    } catch (e) {
      debugPrint('❌ Fehler beim Speichern der Timeline-Daten: $e');
    }
  }

  // Video-Audio Toggle + Firestore speichern ✅
  void _toggleVideoAudio(String url) async {
    if (_avatarData == null) return;

    setState(() {
      _videoAudioEnabled[url] = !(_videoAudioEnabled[url] ?? false);
    });

    try {
      await FirebaseFirestore.instance
          .collection('avatars')
          .doc(_avatarData!.id)
          .update({'videoAudioEnabled': _videoAudioEnabled});
      debugPrint(
        '✅ Video-Audio-Toggle gespeichert: $url → ${_videoAudioEnabled[url]}',
      );
    } catch (e) {
      debugPrint('❌ Fehler beim Speichern Video-Audio: $e');
    }
  }

  // Hero-Image setzen (ZENTRAL) - garantiert immer active & visible
  void _setHeroImage(String url) {
    _profileImageUrl = url;
    _imageActive[url] = true;
    _imageExplorerVisible[url] = true;
    debugPrint('✅ Hero-Image gesetzt (immer aktiv & sichtbar): $url');
  }

  // Hero-Image & imageUrls in Firebase speichern
  Future<void> _saveHeroImageAndUrls() async {
    if (_avatarData == null) return;

    // WICHTIG: Hero-Image (Index 0) ist IMMER aktiv & sichtbar!
    if (_imageUrls.isNotEmpty) {
      final heroUrl = _imageUrls[0];
      _imageActive[heroUrl] = true;
      _imageExplorerVisible[heroUrl] = true;
    }

    try {
      await FirebaseFirestore.instance
          .collection('avatars')
          .doc(_avatarData!.id)
          .update({
            'avatarImageUrl': _profileImageUrl,
            'imageUrls': _imageUrls,
          });
      debugPrint(
        '✅ Hero-Image & imageUrls gespeichert: ${_imageUrls.length} Bilder, Hero: $_profileImageUrl',
      );
    } catch (e) {
      debugPrint('❌ Fehler beim Speichern von Hero-Image & imageUrls: $e');
    }
  }

  // Timeline-Daten aus Firebase laden
  Future<void> _loadTimelineData(String avatarId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('avatars')
          .doc(avatarId)
          .get();
      if (doc.exists && doc.data() != null) {
        // Timeline-Daten laden
        final timeline = doc.data()!['imageTimeline'] as Map<String, dynamic>?;
        if (timeline != null) {
          // Durations laden (URL -> Sekunden)
          final durationsMap = timeline['durations'] as Map<String, dynamic>?;
          if (durationsMap != null) {
            _imageDurations.clear();
            durationsMap.forEach((key, value) {
              if (value is int) {
                // WICHTIG: Mindestens 60 Sekunden (1 Minute)
                final duration = value < 60 ? 60 : value;
                _imageDurations[key] = duration;
              }
            });
          }
          // LoopMode laden
          final loopMode = timeline['loopMode'];
          if (loopMode is bool) {
            _isImageLoopMode = loopMode;
          }
          // Timeline Enabled laden
          final enabled = timeline['enabled'];
          if (enabled is bool) {
            _isTimelineEnabled = enabled;
          }
          // Active-Status laden
          final activeMap = timeline['active'] as Map<String, dynamic>?;
          if (activeMap != null) {
            _imageActive.clear();
            activeMap.forEach((key, value) {
              if (value is bool) {
                _imageActive[key] = value;
              }
            });
          }
          // Explorer-Sichtbarkeit laden
          final explorerVisibleMap =
              timeline['explorerVisible'] as Map<String, dynamic>?;
          if (explorerVisibleMap != null) {
            _imageExplorerVisible.clear();
            explorerVisibleMap.forEach((key, value) {
              if (value is bool) {
                _imageExplorerVisible[key] = value;
              }
            });
          }

          // WICHTIG: Hero-Image (Index 0) ist IMMER aktiv & sichtbar!
          if (_imageUrls.isNotEmpty) {
            final heroUrl = _imageUrls[0];
            _imageActive[heroUrl] = true;
            _imageExplorerVisible[heroUrl] = true;
            debugPrint('✅ Hero-Image IMMER aktiv & sichtbar: $heroUrl');
          }

          debugPrint(
            '✅ Timeline-Daten geladen: ${_imageDurations.length} Bilder, Loop: $_isImageLoopMode, Enabled: $_isTimelineEnabled',
          );
        }

        // Video-Audio-Settings laden ✅
        final videoAudioMap =
            doc.data()!['videoAudioEnabled'] as Map<String, dynamic>?;
        if (videoAudioMap != null) {
          _videoAudioEnabled.clear();
          videoAudioMap.forEach((key, value) {
            if (value is bool) {
              _videoAudioEnabled[key] = value;
            }
          });
          debugPrint(
            '✅ Video-Audio-Settings geladen: ${_videoAudioEnabled.length} Videos',
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Fehler beim Laden der Timeline-Daten: $e');
    }
  }

  final TextEditingController _textFilterController = TextEditingController();
  // Chunking-Einstellungen (UI)
  double _targetTokens = 400; // Empfehlung: 200–500 (bis 1000)
  double _overlapPercent = 15; // Empfehlung: 10–20%
  double _minChunkTokens = 100; // Empfehlung: 50–100
  // Paging für Textdateien
  static const int _textFilesPageSize = 7;
  int _textFilesPage = 0;
  bool _textFilesExpanded = true;
  String _textFilter = '';
  final TextEditingController _greetingController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final AvatarService _avatarService = AvatarService();
  final List<File> _newImageFiles = [];
  final List<File> _newVideoFiles = [];
  final List<File> _newTextFiles = [];
  final List<File> _newAudioFiles = [];
  String? _activeAudioUrl; // ausgewählte Stimmprobe
  String? _profileImageUrl; // Hero-Image
  String? _profileLocalPath; // Hero-Image (lokal, noch nicht hochgeladen)
  bool _isSaving = false;
  VideoPlayerController? _inlineVideoController; // Inline-Player für Videos
  // Inline-Vorschaubild nicht nötig, Thumbnails entstehen in den Tiles per FutureBuilder
  final Map<String, Uint8List> _videoThumbCache = {};
  String? _currentInlineUrl; // merkt die aktuell dargestellte Hero-Video-URL
  // bool _autoVideoHeroApplied = false;
  final Set<String> _selectedRemoteImages = {};
  final Set<String> _selectedLocalImages = {};
  final Set<String> _selectedRemoteVideos = {};
  final Set<String> _selectedLocalVideos = {};
  bool _isDeleteMode = false;
  bool _isDirty = false;
  // Rect? _cropArea; // ungenutzt
  // Medien-Tab: 'images' oder 'videos'
  String _mediaTab = 'images';
  // Hero-View-Mode: 'grid' (Kacheln) oder 'list' (drag&drop sortierbar)
  String _heroViewMode = 'grid';
  // List View expanded/collapsed
  bool _isListViewExpanded = false;
  // Cache für Video-Provider-Auswahl, verhindert Zurückspringen nach Fehlern/Reloads
  // String? _cachedVideoProvider; // entfernt (nur BitHuman)
  // ElevenLabs Voice-Parameter (per Avatar speicherbar)
  double _voiceStability = 0.25;
  double _voiceSimilarity = 0.9;
  double _voiceTempo = 1.0; // 0.5 .. 1.5
  String _voiceDialect = 'de-DE';
  // ElevenLabs Voices
  List<Map<String, dynamic>> _elevenVoices = [];
  String? _selectedVoiceId;
  bool _voicesLoading = false;
  bool _useOwnVoice =
      false; // true = eigene Stimme (cloneVoiceId), false = externe (ElevenLabs)

  // Dynamics Parameter ✨ - PRO DYNAMICS-ID!
  final Map<String, double> _drivingMultipliers = {
    'basic': 0.41,
  }; // dynamicsId -> value
  final Map<String, double> _animationScales = {'basic': 2.0};
  final Map<String, int> _sourceMaxDims = {
    'basic': 1600,
  }; // Auto-berechnet aus Hero-Image!
  final Map<String, bool> _flagsNormalizeLip = {'basic': true};
  final Map<String, bool> _flagsPasteback = {'basic': true};
  final Map<String, String> _animationRegions = {'basic': 'all'};
  Map<String, Map<String, dynamic>> _dynamicsData = {}; // dynamicsId -> data
  final Set<String> _generatingDynamics =
      {}; // Set der gerade generierenden IDs
  final Map<String, int> _dynamicsTimeRemaining = {}; // dynamicsId -> seconds
  final Map<String, Timer?> _dynamicsTimers = {}; // dynamicsId -> Timer
  double _heroVideoDuration = 0; // Hero-Video Dauer in Sekunden
  bool _heroVideoTooLong = false; // Hero-Video > 10 Sek
  bool get _hasNoClonedVoice {
    try {
      final v = _avatarData?.training?['voice'] as Map<String, dynamic>?;
      final a = (v?['elevenVoiceId'] as String?)?.trim() ?? '';
      final b = (v?['cloneVoiceId'] as String?)?.trim() ?? '';
      return a.isEmpty && b.isEmpty;
    } catch (_) {
      return true;
    }
  }

  final Set<String> _refreshingImages = {};
  late final List<String> _countryOptions;

  Widget _buildChunkingControls() {
    // Empfehlungen: target 800–1200, overlap 50–150, minChunk ca. 60–80% target
    final double minAllowed = 200;
    final double maxAllowed = 2000;
    // minChunkTokens nicht größer als targetTokens
    if (_minChunkTokens > _targetTokens) _minChunkTokens = _targetTokens;
    final double recommendedMin = (_targetTokens * 0.7).clamp(1, _targetTokens);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // target_tokens
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              context.read<LocalizationService>().t(
                'avatars.details.chunk.targetTokens',
              ),
              style: const TextStyle(color: Colors.white70),
            ),
            Text(
              _targetTokens.round().toString(),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.magenta.withValues(
              alpha: 0.8,
            ), // GMBC Magenta
            inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
            overlayColor: AppColors.magenta.withValues(alpha: 0.2),
            thumbShape: const GradientSliderThumbShape(
              thumbRadius: 8.0,
            ), // GMBC Kugel
            trackHeight: 4.0,
            showValueIndicator: ShowValueIndicator.onDrag,
            valueIndicatorColor: Colors.white,
            valueIndicatorTextStyle: const TextStyle(
              color: AppColors.magenta,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Slider(
            min: minAllowed,
            max: maxAllowed,
            divisions: ((maxAllowed - minAllowed) / 50).round(),
            value: _targetTokens.clamp(minAllowed, maxAllowed),
            label: _targetTokens.round().toString(),
            onChanged: (v) => setState(() {
              _targetTokens = v;
              // minChunk sinnvoll nachführen (mind. 60% target, nicht größer als target)
              final double min60 = (_targetTokens * 0.6);
              if (_minChunkTokens < min60) _minChunkTokens = min60;
              if (_minChunkTokens > _targetTokens) {
                _minChunkTokens = _targetTokens;
              }
            }),
          ),
        ),
        const SizedBox(height: 6),
        // overlap (Prozent)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              context.read<LocalizationService>().t(
                'avatars.details.chunk.overlap',
              ),
              style: const TextStyle(color: Colors.white70),
            ),
            Text(
              '${_overlapPercent.round()}%',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.magenta.withValues(
              alpha: 0.8,
            ), // GMBC Magenta
            inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
            overlayColor: AppColors.magenta.withValues(alpha: 0.2),
            thumbShape: const GradientSliderThumbShape(
              thumbRadius: 8.0,
            ), // GMBC Kugel
            trackHeight: 4.0,
            showValueIndicator: ShowValueIndicator.onDrag,
            valueIndicatorColor: Colors.white,
            valueIndicatorTextStyle: const TextStyle(
              color: AppColors.magenta,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Slider(
            min: 0,
            max: 40,
            divisions: 40,
            value: _overlapPercent.clamp(0, 40),
            label: '${_overlapPercent.round()}%',
            onChanged: (v) => setState(() => _overlapPercent = v),
          ),
        ),
        const SizedBox(height: 6),
        // min_chunk_tokens
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              context.read<LocalizationService>().t(
                'avatars.details.chunk.minSize',
              ),
              style: const TextStyle(color: Colors.white70),
            ),
            Text(
              _minChunkTokens.round().toString(),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.magenta.withValues(
              alpha: 0.8,
            ), // GMBC Magenta
            inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
            overlayColor: AppColors.magenta.withValues(alpha: 0.2),
            thumbShape: const GradientSliderThumbShape(
              thumbRadius: 8.0,
            ), // GMBC Kugel
            trackHeight: 4.0,
            showValueIndicator: ShowValueIndicator.onDrag,
            valueIndicatorColor: Colors.white,
            valueIndicatorTextStyle: const TextStyle(
              color: AppColors.magenta,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Slider(
            min: 1,
            max: _targetTokens,
            divisions: (_targetTokens / 10).round().clamp(1, 1000000),
            value: _minChunkTokens.clamp(1, _targetTokens),
            label: _minChunkTokens.round().toString(),
            onChanged: (v) => setState(() => _minChunkTokens = v),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          context.read<LocalizationService>().t(
            'avatars.details.chunk.recommendation',
            params: {'min': recommendedMin.round().toString()},
          ),
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ],
    );
  }

  bool _isTestingVoice = false;
  final AudioPlayer _voiceTestPlayer = AudioPlayer();
  bool _isGeneratingAvatar = false;
  // Entfernt: dispose hier, da es unten bereits eine vollständige dispose()-Methode gibt

  bool get _regionCanApply {
    final input = _regionInputController.text.trim();
    if (input.isEmpty) return false;

    final hasDigits = RegExp(r'^\d{4,6}$').hasMatch(input);
    if (hasDigits && _countryController.text.trim().isEmpty) {
      _countryController.text = 'Deutschland';
    }

    return _countryController.text.trim().isNotEmpty;
  }

  // Berechne Start-Zeit für ein Image (basierend auf akkumulierter Duration)
  String _getImageStartTime(int index) {
    int totalSeconds = 0;
    for (int i = 0; i < index; i++) {
      if (i < _imageUrls.length) {
        final url = _imageUrls[i];
        // Nur aktive Bilder zählen für die Timeline
        if (_imageActive[url] ?? true) {
          totalSeconds += _imageDurations[url] ?? 60;
        }
      }
    }
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // Berechne die Gesamt-Endzeit aller aktiven Bilder
  String _getTotalEndTime() {
    int totalSeconds = 0;
    for (int i = 0; i < _imageUrls.length; i++) {
      final url = _imageUrls[i];
      if (_imageActive[url] ?? true) {
        totalSeconds += _imageDurations[url] ?? 60;
      }
    }
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  // Explorer-Info-Dialog anzeigen
  Future<void> _showExplorerInfoDialog({bool forceShow = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenInfo = prefs.getBool('hasSeenExplorerInfo') ?? false;

    // forceShow: true → Info-Button (immer zeigen, startet Bildungskreislauf neu)
    // forceShow: false → Auge-Klick (nur beim ersten Mal)
    if (!forceShow && hasSeenInfo) return;

    // Info-Button → Reset der Einstellung, damit Bildungskreislauf neu startet
    if (forceShow) {
      await prefs.setBool('hasSeenExplorerInfo', false);
    }
    if (!mounted) return;

    bool dontShowAgain = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Stack(
            children: [
              const Center(
                child: Text(
                  'Startseiten-Galerie',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Positioned(
                top: -8,
                right: -8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  children: [
                    WidgetSpan(
                      child: ShaderMask(
                        shaderCallback: (bounds) => Theme.of(context)
                            .extension<AppGradients>()!
                            .magentaBlue
                            .createShader(bounds),
                        child: const Text(
                          'Aktivierte Bilder',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            height: 1.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const TextSpan(
                      text:
                          '\nrotieren auf Deiner Startseite\nim 2-Sekunden-Takt.\n\n'
                          'Das verhindert schnelles Wegswipen (Nutzer verlässt Seite) '
                          'und motiviert Besucher, mit Dir in Kontakt zu treten.\n\n'
                          'Mehr Bilder = mehr Interesse!',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Großes Auge-Icon mit GMBC Gradient
              ShaderMask(
                shaderCallback: (bounds) => Theme.of(
                  context,
                ).extension<AppGradients>()!.magentaBlue.createShader(bounds),
                child: const Icon(
                  Icons.visibility,
                  size: 125,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              // Checkbox
              InkWell(
                onTap: () {
                  setDialogState(() => dontShowAgain = !dontShowAgain);
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        gradient: dontShowAgain
                            ? Theme.of(
                                context,
                              ).extension<AppGradients>()!.magentaBlue
                            : null,
                        border: Border.all(
                          color: dontShowAgain
                              ? Colors.transparent
                              : Colors.grey,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: dontShowAgain
                          ? const Icon(
                              Icons.check,
                              size: 12,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        'Diesen Dialog nicht mehr anzeigen',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            Center(
              child: ElevatedButton(
                onPressed: () async {
                  final nav = Navigator.of(context);
                  if (dontShowAgain) {
                    await prefs.setBool('hasSeenExplorerInfo', true);
                  }
                  nav.pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: ShaderMask(
                  shaderCallback: (bounds) => Theme.of(
                    context,
                  ).extension<AppGradients>()!.magentaBlue.createShader(bounds),
                  child: const Text(
                    'Verstanden',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Lade OriginalFileNames aus Firestore Media-Docs
  Future<void> _loadMediaOriginalNames(String avatarId) async {
    try {
      final mediaList = await _mediaSvc.list(avatarId);
      if (!mounted) return;
      setState(() {
        _mediaOriginalNames.clear();
        for (final media in mediaList) {
          if (media.originalFileName != null &&
              media.originalFileName!.isNotEmpty) {
            _mediaOriginalNames[media.url] = media.originalFileName!;
          }
        }
        _mediaOriginalNamesLoaded = true;
      });
    } catch (e) {
      debugPrint('❌ Fehler beim Laden der OriginalFileNames: $e');
    }
  }

  void _updateDirty() {
    final current = _avatarData;
    if (current == null) {
      if (mounted) setState(() => _isDirty = false);
      return;
    }

    bool dirty = false;

    // Textfelder
    if (_firstNameController.text.trim() != current.firstName) dirty = true;
    if ((_nicknameController.text.trim()) != (current.nickname ?? '')) {
      dirty = true;
    }
    if ((_lastNameController.text.trim()) != (current.lastName ?? '')) {
      dirty = true;
    }
    if ((_cityController.text.trim()) != (current.city ?? '')) {
      dirty = true;
    }
    if ((_postalCodeController.text.trim()) != (current.postalCode ?? '')) {
      dirty = true;
    }
    if ((_countryController.text.trim()) != (current.country ?? '')) {
      dirty = true;
    }
    // Begrüßungstext
    final currentGreeting = current.greetingText ?? '';
    if (_greetingController.text.trim() != currentGreeting) dirty = true;

    // Dates (nur Datum vergleichen)
    bool sameDate(DateTime? a, DateTime? b) {
      if (a == null && b == null) return true;
      if (a == null || b == null) return false;
      return a.year == b.year && a.month == b.month && a.day == b.day;
    }

    if (!sameDate(_birthDate, current.birthDate)) dirty = true;
    if (!sameDate(_deathDate, current.deathDate)) dirty = true;

    // Hero-Image / Profilbild geändert
    final baselineHero = current.avatarImageUrl;
    if ((_profileImageUrl ?? '') != (baselineHero ?? '')) dirty = true;

    // Neue lokale Dateien oder Freitext
    if (_newImageFiles.isNotEmpty ||
        _newVideoFiles.isNotEmpty ||
        _newTextFiles.isNotEmpty ||
        _newAudioFiles.isNotEmpty) {
      dirty = true;
    }
    if (_textAreaController.text.trim().isNotEmpty) dirty = true;

    if (mounted) setState(() => _isDirty = dirty);
  }

  @override
  void initState() {
    super.initState();
    _countryOptions =
        countries
            .map((entry) => entry['name'] ?? '')
            .where((name) => name.isNotEmpty)
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    // Falls bereits ein Land existiert (z. B. aus Auto-Resolve), auf Optionsnamen normalisieren
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final raw = _countryController.text.trim();
      if (raw.isEmpty) return;
      String? normalized;
      for (final entry in countries) {
        final name = (entry['name'] ?? '').toString().trim();
        final code = (entry['code'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        if (raw.toLowerCase() == name.toLowerCase() ||
            raw.toLowerCase() == code.toLowerCase()) {
          normalized = name;
          break;
        }
      }
      if (normalized != null && normalized != raw) {
        if (mounted) {
          setState(() {
            _countryController.text = normalized!;
          });
        }
      }
    });
    // Empfange AvatarData von der vorherigen Seite
    _firstNameController.addListener(_updateDirty);
    _nicknameController.addListener(_updateDirty);
    _lastNameController.addListener(_updateDirty);
    _cityController.addListener(_updateDirty);
    _postalCodeController.addListener(_updateDirty);
    _countryController.addListener(_updateDirty);
    _textAreaController.addListener(_updateDirty);
    _greetingController.addListener(_updateDirty);
    _textFilterController.addListener(() {
      final v = _textFilterController.text.trim();
      if (v != _textFilter) {
        setState(() {
          _textFilter = v;
          _textFilesPage = 0;
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final args = ModalRoute.of(context)?.settings.arguments;
      String? avatarIdFromArgs;
      if (args is AvatarData) {
        _applyAvatar(args);
        avatarIdFromArgs = args.id;
      } else if (args is Map && args['avatarId'] is String) {
        avatarIdFromArgs = (args['avatarId'] as String).trim();
      } else if (args is String) {
        avatarIdFromArgs = args.trim();
      }

      // Fallback: Browser-Reload (Web) oder verlorene Navigation → letzte Avatar-ID aus SharedPreferences
      if ((avatarIdFromArgs == null || avatarIdFromArgs.isEmpty) &&
          kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        avatarIdFromArgs = prefs.getString('lastAvatarDetailsId');
      }

      if (avatarIdFromArgs != null && avatarIdFromArgs.isNotEmpty) {
        _pendingAvatarId = avatarIdFromArgs;
        _fetchLatest(avatarIdFromArgs);
        // Für spätere Reloads merken
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('lastAvatarDetailsId', avatarIdFromArgs);
        } catch (_) {}
      }

      _loadElevenVoices();
    });
    // Einfacher Puls-Effekt (Opacity/Scale) für den Slug-Link
    _slugPulseTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (mounted) setState(() => _slugPulse = !_slugPulse);
    });
  }

  @override
  void dispose() {
    _slugPulseTimer?.cancel();
    _avatarDocSubscription?.cancel();
    _firstNameController.dispose();
    _nicknameController.dispose();
    _lastNameController.dispose();
    _cityController.dispose();
    _postalCodeController.dispose();
    _countryController.dispose();
    _birthDateController.dispose();
    _deathDateController.dispose();
    _regionInputController.dispose();
    _inlineVideoController?.dispose();
    // Audio-Testplayer sauber beenden
    try {
      _voiceTestPlayer.stop();
    } catch (_) {}
    try {
      _voiceTestPlayer.dispose();
    } catch (_) {}
    // Thumbnail-Controller aufräumen
    for (final controller in _thumbControllers.values) {
      controller.dispose();
    }
    _thumbControllers.clear();
    // Dynamics Timer aufräumen (ALLE Timer!)
    for (final timer in _dynamicsTimers.values) {
      timer?.cancel();
    }
    _dynamicsTimers.clear();
    super.dispose();
  }

  Future<void> _createSlugFlow() async {
    if (_avatarData == null) return;
    final TextEditingController ctrl = TextEditingController();
    // Vorschlag aus Vorname/Nickname/Nachname
    final parts = <String>[];
    if ((_avatarData!.nickname ?? '').trim().isNotEmpty) {
      parts.add(_avatarData!.nickname!.trim());
    } else {
      parts.add(_avatarData!.firstName.trim());
      if ((_avatarData!.lastName ?? '').trim().isNotEmpty) {
        parts.add(_avatarData!.lastName!.trim());
      }
    }
    ctrl.text = _slugify(parts.join(' '));

    List<String> _buildSuggestions() {
      final String first = _avatarData!.firstName.trim();
      final String? nick = (_avatarData!.nickname ?? '').trim().isNotEmpty ? _avatarData!.nickname!.trim() : null;
      final String? last = (_avatarData!.lastName ?? '').trim().isNotEmpty ? _avatarData!.lastName!.trim() : null;
      final s = <String>{};
      if (nick != null) s.add(_slugify(nick));
      if (first.isNotEmpty && last != null) s.add(_slugify('$first $last'));
      if (first.isNotEmpty && nick != null) s.add(_slugify('$first $nick'));
      if (last != null) s.add(_slugify(last));
      if (s.isEmpty) s.add(_slugify(first));
      return s.take(3).toList();
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool available = false;
        bool checked = false;
        bool checking = false;
        List<String> suggestions = _buildSuggestions();
        return StatefulBuilder(
          builder: (ctx2, setDlg) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: ShaderMask(
              shaderCallback: (b) => Theme.of(ctx2).extension<AppGradients>()!.magentaBlue.createShader(b),
              child: const Text('Avatar URL anlegen', style: TextStyle(color: Colors.white)),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Wähle deinen eindeutigen Namen (nur einmal festlegbar):',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: suggestions.map((s) {
                    return InkWell(
                      onTap: () {
                        ctrl.text = s;
                        setDlg(() {
                          checked = false;
                          available = false;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: Theme.of(ctx2).extension<AppGradients>()!.magentaBlue,
                        ),
                        child: Text(s, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    labelStyle: TextStyle(color: Colors.white70),
                    hintText: 'z. B. ralf-matten',
                    hintStyle: TextStyle(color: Colors.white38),
                  ),
                  onChanged: (v) {
                    final s = _slugify(v);
                    if (s != v) {
                      final pos = TextSelection.collapsed(offset: s.length);
                      ctrl.value = TextEditingValue(text: s, selection: pos);
                    }
                    setDlg(() {
                      checked = false;
                      available = false;
                    });
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: checking
                          ? null
                          : () async {
                              final slug = _slugify(ctrl.text);
                              if (slug.isEmpty) return;
                              setDlg(() {
                                checking = true;
                                checked = false;
                                available = false;
                              });
                              final fs = FirebaseFirestore.instance;
                              try {
                                final q = await fs.collection('slugs').doc(slug).get();
                                setDlg(() {
                                  checking = false;
                                  checked = true;
                                  available = !q.exists || (q.data()?['avatarId'] == _avatarData!.id);
                                });
                              } catch (_) {
                                // Fallback bei fehlender Berechtigung → als nicht verfügbar markieren
                                setDlg(() {
                                  checking = false;
                                  checked = true;
                                  available = false;
                                });
                              }
                            },
                      child: checking ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Prüfen'),
                    ),
                    const SizedBox(width: 10),
                    if (checked && available)
                      const Text('Verfügbar', style: TextStyle(color: Color(0xFF00FF94), fontWeight: FontWeight.w700))
                    else if (checked && !available)
                      const Text('Schon vergeben', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                // URL vollständig anzeigen (Zeilenumbruch erlaubt) + Copy-Icon rechts (aktiv erst nach erfolgreicher Prüfung)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: SelectableText(
                        'https://www.hauau.de/#/avatar/${ctrl.text}',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                    IconButton(
                      tooltip: (checked && available) ? 'URL kopieren' : 'Bitte zuerst prüfen',
                      onPressed: (checked && available)
                          ? () async {
                              final url = 'https://www.hauau.de/#/avatar/${ctrl.text}';
                              await Clipboard.setData(ClipboardData(text: url));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Kopiert')),
                                );
                              }
                            }
                          : null,
                      icon: (checked && available)
                          ? ShaderMask(
                              shaderCallback: (b) => Theme.of(context)
                                  .extension<AppGradients>()!
                                  .magentaBlue
                                  .createShader(b),
                              child: const Icon(Icons.copy, color: Colors.white, size: 18),
                            )
                          : const Icon(Icons.copy, color: Colors.white24, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text('Achtung: Diese URL ist endgültig und kann später NICHT geändert werden.',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx2, false),
                child: const Text('Abbrechen'),
              ),
              ElevatedButton(
                onPressed: (checked && available)
                    ? () async {
                        final slug = _slugify(ctrl.text);
                        if (slug.isEmpty) return;
                        final fs = FirebaseFirestore.instance;
                        try {
                          await fs.runTransaction((tx) async {
                            final slugRef = fs.collection('slugs').doc(slug);
                            final snap = await tx.get(slugRef);
                            if (snap.exists && snap.data()?['avatarId'] != _avatarData!.id) {
                              throw Exception('exists');
                            }
                            tx.set(slugRef, {'avatarId': _avatarData!.id});
                            tx.set(
                              fs.collection('avatars').doc(_avatarData!.id),
                              {
                                'slug': slug,
                                'updatedAt': DateTime.now().millisecondsSinceEpoch,
                              },
                              SetOptions(merge: true),
                            );
                          });
                          if (mounted) {
                            setState(() {
                              _slugCache = slug;
                              _avatarData = _avatarData!.copyWith(updatedAt: DateTime.now());
                            });
                          }
                          Navigator.pop(ctx2, true);
                        } catch (_) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Dieser Name wurde soeben vergeben. Bitte anderen wählen.')),
                            );
                          }
                        }
                      }
                    : null,
                child: const Text('Sichern'),
              ),
            ],
          ),
        );
      },
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Avatar URL gespeichert')),
      );
    }
  }

  Future<void> _showSlugInfo() async {
    final s = _avatarSlug;
    if (s == null || s.isEmpty) return;
    final url = 'https://www.hauau.de/#/avatar/$s';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Avatar URL', style: TextStyle(color: Colors.white)),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Text(url, style: const TextStyle(color: Colors.white70), overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              tooltip: 'In Zwischenablage kopieren',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Kopiert')),
                  );
                }
              },
              icon: ShaderMask(
                shaderCallback: (b) => Theme.of(ctx).extension<AppGradients>()!.magentaBlue.createShader(b),
                child: const Icon(Icons.copy, color: Colors.white),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen')),
        ],
      ),
    );
  }

  Future<void> _fetchLatest(String id) async {
    final latest = await _avatarService.getAvatar(id);
    if (latest != null && mounted) {
      _applyAvatar(latest);
    }
  }

  Future<void> _applyAvatar(AvatarData data) async {
    setState(() {
      _avatarData = data;
      _firstNameController.text = data.firstName;
      _nicknameController.text = data.nickname ?? '';
      _lastNameController.text = data.lastName ?? '';
      _cityController.text = data.city ?? '';
      _postalCodeController.text = data.postalCode ?? '';
      _countryController.text = data.country ?? '';
      // Nach dem Laden: Ländewert an Optionsliste angleichen (Name/Code → exakter Optionsname)
      // Country ggf. auf Optionsnamen normalisieren (Name/Code → Name)
      final rawCountry = _countryController.text.trim();
      if (rawCountry.isNotEmpty) {
        for (final entry in countries) {
          final name = (entry['name'] ?? '').toString().trim();
          final code = (entry['code'] ?? '').toString().trim();
          if (name.isEmpty) continue;
          if (rawCountry.toLowerCase() == name.toLowerCase() ||
              rawCountry.toLowerCase() == code.toLowerCase()) {
            _countryController.text = name;
            break;
          }
        }
      }
      _birthDate = data.birthDate;
      _deathDate = data.deathDate;
      _calculatedAge = data.calculatedAge;
      _role = data.role;

      _birthDateController.text = _birthDate != null
          ? _formatDate(_birthDate!)
          : '';
      _deathDateController.text = _deathDate != null
          ? _formatDate(_deathDate!)
          : '';

      _imageUrls
        ..clear()
        ..addAll(data.imageUrls);
      _videoUrls
        ..clear()
        ..addAll(data.videoUrls);
      _textFileUrls
        ..clear()
        ..addAll(data.textFileUrls);
      _profileImageUrl =
          data.avatarImageUrl ??
          (_imageUrls.isNotEmpty ? _imageUrls.first : null);

      // Recropping-Status zurücksetzen (wichtig nach Hot Reload)
      _isRecropping.clear();

      // WICHTIG: Hero-Image MUSS an Position 0 sein!
      if (_profileImageUrl != null && _imageUrls.isNotEmpty) {
        final heroUrl = _profileImageUrl!;
        if (_imageUrls.contains(heroUrl) && _imageUrls[0] != heroUrl) {
          _imageUrls.remove(heroUrl);
          _imageUrls.insert(0, heroUrl);
          debugPrint('✅ Hero-Image an Position 0 verschoben: $heroUrl');
        }
      }

      // WICHTIG: Hero-Video MUSS an Position 0 sein!
      final heroVideoUrl = _getHeroVideoUrl();
      if (heroVideoUrl != null && _videoUrls.isNotEmpty) {
        if (_videoUrls.contains(heroVideoUrl) &&
            _videoUrls[0] != heroVideoUrl) {
          _videoUrls.remove(heroVideoUrl);
          _videoUrls.insert(0, heroVideoUrl);
          debugPrint('✅ Hero-Video an Position 0 verschoben: $heroVideoUrl');
        }
      }

      _profileLocalPath = null;
      // aktive Stimme aus training.voice.activeUrl lesen (falls vorhanden)
      final voice = (data.training != null) ? data.training!['voice'] : null;
      _activeAudioUrl = (voice is Map && voice['activeUrl'] is String)
          ? voice['activeUrl'] as String
          : (data.audioUrls.isNotEmpty ? data.audioUrls.first : null);
      if (voice is Map) {
        final st = voice['stability'];
        final si = voice['similarity'];
        final tp = voice['tempo'];
        final dl = voice['dialect'];
        // final vid = voice['elevenVoiceId']; // keine Vorauswahl setzen
        if (st is num) _voiceStability = st.toDouble();
        if (st is String) {
          final v = double.tryParse(st);
          if (v != null) _voiceStability = v;
        }
        if (si is num) _voiceSimilarity = si.toDouble();
        if (si is String) {
          final v = double.tryParse(si);
          if (v != null) _voiceSimilarity = v;
        }
        if (tp is num) _voiceTempo = tp.toDouble();
        if (tp is String) {
          final v = double.tryParse(tp);
          if (v != null) _voiceTempo = v;
        }
        if (dl is String && dl.trim().isNotEmpty) {
          _voiceDialect = dl.trim();
        }
        // Slider-State + Dropdown-Auswahl initialisieren
        try {
          final cloneId = (voice['cloneVoiceId'] as String?)?.trim();
          final elevenId = (voice['elevenVoiceId'] as String?)?.trim();
          final useOwnVoiceFlag = (voice['useOwnVoice'] as bool?);

          // Harte Benutzerwahl hat Vorrang
          if (useOwnVoiceFlag == true) {
            _useOwnVoice = true;
            _selectedVoiceId = null;
          } else {
            // Prüfe: Ist elevenVoiceId == cloneVoiceId? → Eigene Stimme aktiv
            final computedOwn =
                (cloneId != null && cloneId.isNotEmpty && elevenId == cloneId);
            // Behalte Benutzerzustand, wenn keine externe Stimme gesetzt ist
            if (_useOwnVoice && (elevenId == null || elevenId.isEmpty)) {
              _useOwnVoice = true;
              _selectedVoiceId = null;
            } else {
              _useOwnVoice = computedOwn;
              _selectedVoiceId = computedOwn ? null : elevenId;
            }
          }
        } catch (_) {
          // Bei Parsing-Problemen Benutzerzustand nicht überschreiben
        }
      }
      _isDirty = false;
    });
    // OriginalFileNames aus Firestore laden - AWAIT!
    await _loadMediaOriginalNames(data.id);
    // Timeline-Daten laden
    await _loadTimelineData(data.id);
    // 🎭 Dynamics-Daten laden ✨
    await _loadDynamicsData(data.id);
    // Starte Realtime-Listener für Dynamics-Status
    _startDynamicsListener(data.id);
    // 🚀 Live Avatar Agent ID laden
    await _loadLiveAvatarData(data.id);
    // 🎬 Hero-Video Dauer prüfen (Max 10 Sek für Dynamics)
    await _checkHeroVideoDuration();
    if (!mounted) return;
    // Greeting vorbelegen
    final locSvc = context.read<LocalizationService>();
    _greetingController.text =
        _avatarData?.greetingText?.trim().isNotEmpty == true
        ? _avatarData!.greetingText!
        : locSvc.t('avatars.details.defaultGreeting');
    // Hero-Video in Großansicht initialisieren
    _initInlineFromHero();
    // Kein Autogenerieren mehr – Generierung erfolgt nur auf Nutzeraktion
  }

  // Obsolet: Rundes Avatarbild oben wurde entfernt (Hintergrundbild reicht aus)

  // Hero-Media Navigation (außerhalb ScrollView, direkt unter AppBar)
  Widget _buildHeroMediaNav() {
    return MediaNavigationBar(
      currentTab: _mediaTab,
      currentViewMode: _heroViewMode,
      imageCount: _imageUrls.length,
      slug: _avatarSlug,
      onCreateSlug: _createSlugFlow,
      onShowSlug: _showSlugInfo,
      onCopySlug: () async {
        final s = _avatarSlug;
        if (s == null || s.isEmpty) return;
        final url = 'https://www.hauau.de/#/avatar/$s';
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kopiert')));
        }
      },
      onTabChanged: (tab) => setState(() => _mediaTab = tab),
      onUpload: () {
        // Zur Klick-Zeit entscheiden welcher Upload-Handler aufgerufen wird
        if (_mediaTab == 'images') {
          _onAddImages();
        } else {
          _onAddVideos();
        }
      },
      onInfoPressed: () async {
        await _showExplorerInfoDialog(forceShow: true);
      },
      onViewModeToggle: () {
        setState(() {
          _heroViewMode = _heroViewMode == 'grid' ? 'list' : 'grid';
        });
      },
    );
  }

  // Hero-Media Content (innerhalb ScrollView)
  Widget _buildMediaContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info-Text (2px kleiner)
        Text(
          context.read<LocalizationService>().t('avatars.details.mediaHint'),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 12, // 2px kleiner (Standard ist ~14px)
          ),
        ),

        const SizedBox(height: 12),

        // Medienbereich (gelber Rahmen-Bereich) – show/hide
        if (_mediaTab == 'images')
          DetailsImageMediaSection(
            // View Mode
            heroViewMode: _heroViewMode,
            isListViewExpanded: _isListViewExpanded,
            // Images
            imageUrls: _imageUrls,
            profileImageUrl: _profileImageUrl,
            profileLocalPath: _profileLocalPath,
            // Timeline State
            imageActive: _imageActive,
            imageDurations: _imageDurations,
            imageExplorerVisible: _imageExplorerVisible,
            isImageLoopMode: _isImageLoopMode,
            isTimelineEnabled: _isTimelineEnabled,
            // Delete Mode
            isDeleteMode: _isDeleteMode,
            selectedRemoteImages: _selectedRemoteImages,
            selectedLocalImages: _selectedLocalImages,
            isGeneratingAvatar: _isGeneratingAvatar,
            avatarData: _avatarData,
            isRecropping: _isRecropping,
            // Callbacks
            onExpansionChanged: (expanded) {
              setState(() {
                _isListViewExpanded = expanded;
              });
            },
            onLoopModeToggle: () {
              setState(() {
                _isImageLoopMode = !_isImageLoopMode;
              });
              _saveTimelineData();
            },
            onTimelineEnabledToggle: () {
              setState(() {
                _isTimelineEnabled = !_isTimelineEnabled;
              });
              _saveTimelineData();
            },
            onReorder: (oldIndex, newIndex) async {
              final currentHero = _profileImageUrl;
              setState(() {
                if (oldIndex < newIndex) {
                  newIndex -= 1;
                }
                final item = _imageUrls.removeAt(oldIndex);
                _imageUrls.insert(newIndex, item);
                if (newIndex == 0 &&
                    item != currentHero &&
                    _imageUrls.isNotEmpty) {
                  _setHeroImage(_imageUrls[0]);
                }
                if (oldIndex == 0 &&
                    item == currentHero &&
                    _imageUrls.isNotEmpty) {
                  _setHeroImage(_imageUrls[0]);
                }
              });
              await _saveTimelineData();
              await _saveHeroImageAndUrls();
            },
            onImageActiveTap: (url) {
              setState(() {
                final currentActive = _imageActive[url] ?? true;
                _imageActive[url] = !currentActive;
              });
              _saveTimelineData();
            },
            onExplorerVisibleTap: (url) async {
              await _showExplorerInfoDialog();
              setState(() {
                final currentVisible = _imageExplorerVisible[url] ?? false;
                _imageExplorerVisible[url] = !currentVisible;
              });
              await _saveTimelineData();
            },
            onDurationChanged: (url, minutes) {
              setState(() {
                _imageDurations[url] = minutes * 60;
              });
              _saveTimelineData();
            },
            onDeleteModeCancel: () {
              setState(() {
                _isDeleteMode = false;
                _selectedRemoteImages.clear();
                _selectedLocalImages.clear();
              });
            },
            onDeleteConfirm: _confirmDeleteSelectedImages,
            onGenerateAvatar: _handleGenerateAvatar,
            onSetHeroImage: _setHeroImage,
            onCropImage: _onImageRecrop,
            // Helper functions
            fileNameFromUrl: _fileNameFromUrl,
            getTotalEndTime: _getTotalEndTime,
            getImageStartTime: _getImageStartTime,
            handleImageError: _handleImageError,
            buildHeroImageThumbNetwork: _buildHeroImageThumbNetwork,
          )
        else
          DetailsVideoMediaSection(
            // Videos
            videoUrls: (() {
              final heroUrl = _getHeroVideoUrl();
              final list = List<String>.from(_videoUrls);
              if (heroUrl != null && heroUrl.isNotEmpty && !list.contains(heroUrl)) {
                list.insert(0, heroUrl);
              }
              return list;
            })(),
            inlineVideoController: _inlineVideoController,
            // Audio State
            videoAudioEnabled: _videoAudioEnabled,
            // Delete Mode
            isDeleteMode: _isDeleteMode,
            selectedRemoteVideos: _selectedRemoteVideos,
            selectedLocalVideos: _selectedLocalVideos,
            // Callbacks
            getHeroVideoUrl: _getHeroVideoUrl,
            playNetworkInline: _playNetworkInline,
            thumbnailForRemote: _thumbnailForRemote,
            toggleVideoAudio: _toggleVideoAudio,
            setHeroVideo: _setHeroVideo,
            onDeleteModeCancel: () {
              setState(() {
                _isDeleteMode = false;
                _selectedRemoteVideos.clear();
                _selectedLocalVideos.clear();
              });
            },
            onDeleteConfirm: _confirmDeleteSelectedImages,
            onTrashIconTap: (url) {
              setState(() {
                _isDeleteMode = true;
                if (_selectedRemoteVideos.contains(url)) {
                  _selectedRemoteVideos.remove(url);
                } else {
                  _selectedRemoteVideos.add(url);
                }
              });
            },
            // Video Controller Helper
            videoControllerForThumb: _videoControllerForThumb,
            // Original-Dateiname Resolver
            fileNameFromUrl: _fileNameFromUrl,
            // Trim Hero-Video
            onTrimHeroVideo: _showTrimDialogForHeroVideo,
            // Trim beliebiges Video
            onTrimVideo: (url) => _showTrimDialogForVideo(url),
          ),
        const SizedBox.shrink(),

        const SizedBox(height: 12),

        // Aufklappbare Sektionen (Texte, Audio, Stimmeinstellungen)
        Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.white24,
            listTileTheme: const ListTileThemeData(
              iconColor: AppColors.magenta, // GMBC
            ),
          ),
          child: Column(
            children: [
              // Begrüßungstext
              GreetingTextExpansionTile(
                greetingController: _greetingController,
                currentVoiceId:
                    _avatarData?.training?['voice']?['elevenVoiceId']
                        as String?,
                isTestingVoice: _isTestingVoice,
                onTestVoice: _testVoicePlayback,
                onChanged: _updateDirty,
                roleDropdown: _buildRoleDropdown(),
              ),
              const SizedBox(height: 12),

              // 🎭 DYNAMICS (Live Avatar Animation) ✨
              _buildDynamicsSection(),

              const SizedBox(height: 12),
              // Texte & Freitext
              TextsExpansionTile(
                onAddTexts: _onAddTexts,
                textAreaController: _textAreaController,
                onChanged: _updateDirty,
                chunkingParams: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      context.read<LocalizationService>().t(
                        'avatars.details.chunkingLabel',
                      ),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildChunkingControls(),
                  const SizedBox(height: 12),
                  if (_textFileUrls.isNotEmpty || _newTextFiles.isNotEmpty)
                    _buildTextFilesList(),
                ],
              ),
              const SizedBox(height: 12),
              // Audio (Stimmauswahl) inkl. Stimmeinstellungen
              VoiceSelectionExpansionTile(
                voiceSelectWidget: _buildVoiceSelect(),
                onAddAudio: _useOwnVoice ? _onAddAudio : null,
                audioFilesList:
                    _useOwnVoice && _avatarData?.audioUrls.isNotEmpty == true
                    ? _buildAudioFilesList()
                    : null,
                voiceParamsWidget: _buildVoiceParams(),
                hasVoiceId:
                    ((_avatarData?.training?['voice']?['elevenVoiceId'])
                            as String?)
                        ?.trim()
                        .isNotEmpty ==
                    true,
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }
  // Tab-Button für Hero-Navigation - ERSETZT durch MediaTabButton Widget
  /* AUSKOMMENTIERT - Widget wird nun verwendet
  */

  Widget _buildRoleDropdown() {
    final items = <Map<String, String>>[
      {'key': 'explicit', 'label': 'Explicit Content'},
      {'key': 'live_coach', 'label': 'Live Coach'},
      {'key': 'trauer', 'label': 'Trauerbegleitung'},
      {'key': 'love_coach', 'label': 'Love Coach'},
      {'key': 'verkaeufer', 'label': 'Verkäufer'},
      {'key': 'berater', 'label': 'Berater'},
      {'key': 'freund', 'label': 'Freund'},
      {'key': 'lehrer_coach', 'label': 'Lehrer/Coach'},
      {'key': 'pfarrer', 'label': 'Pfarrer (Beichte)'},
      {'key': 'psychiater', 'label': 'Psychiater'},
      {'key': 'seelsorger', 'label': 'Seelsorger'},
      {'key': 'medizinisch', 'label': 'Medizinischer Berater'},
    ];
    return CustomDropdown<String>(
      label: 'Rolle',
      value: _role,
      items: items
          .map(
            (e) => DropdownMenuItem(
              value: e['key'],
              child: Text(
                e['label']!,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          )
          .toList(),
      onChanged: (v) async {
        setState(() => _role = v);
        await _saveRoleImmediately(v);
      },
    );
  }

  // 🎭 Dynamics Section (Live Avatar Animation) ✨
  Widget _buildDynamicsSection() {
    return DynamicsExpansionTile(
      heroVideoUrl: _getHeroVideoUrl(),
      heroVideoTooLong: _heroVideoTooLong,
      heroVideoDuration: _heroVideoDuration,
      heroImageUrl: _getHeroImageUrl(),
      heroAudioUrl: _getHeroAudioUrl(),
      onGenerateLiveAvatar: _generateLiveAvatar,
      isGeneratingLiveAvatar: _isGeneratingLiveAvatar,
      liveAvatarAgentId: _liveAvatarAgentId,
      dynamicsData: _dynamicsData,
      drivingMultipliers: _drivingMultipliers,
      animationScales: _animationScales,
      sourceMaxDims: _sourceMaxDims,
      flagsNormalizeLip: _flagsNormalizeLip,
      flagsPasteback: _flagsPasteback,
      generatingDynamics: _generatingDynamics,
      dynamicsTimeRemaining: _dynamicsTimeRemaining,
      onShowVideoTrimDialog: _showVideoTrimDialog,
      onSwitchToVideos: () => setState(() => _mediaTab = 'videos'),
      onResetDefaults: (id) => _resetToDefaults(id),
      onDrivingMultiplierChanged: (id, v) =>
          setState(() => _drivingMultipliers[id] = v),
      onAnimationScaleChanged: (id, v) =>
          setState(() => _animationScales[id] = v),
      // onSourceMaxDimChanged entfernt - Wert wird automatisch berechnet
      onFlagNormalizeLipChanged: (id, v) =>
          setState(() => _flagsNormalizeLip[id] = v),
      onFlagPastebackChanged: (id, v) =>
          setState(() => _flagsPasteback[id] = v),
      onGenerate: (id) => _generateDynamics(id),
      onCancelGeneration: (id) => _cancelDynamicsGeneration(id),
      onDeleteDynamics: (id) => _deleteDynamicsVideo(id),
      onShowCreateDynamicsDialog: _showCreateDynamicsDialog,
      buildSlider: _buildSlider,
      dynamicsEnabled:
          (_avatarData?.training?['dynamicsEnabled'] as bool?) ?? true,
      lipsyncEnabled:
          (_avatarData?.training?['lipsyncEnabled'] as bool?) ?? true,
      onToggleDynamics: (v) async {
        if (_avatarData == null) return;
        final training = Map<String, dynamic>.from(_avatarData!.training ?? {});
        training['dynamicsEnabled'] = v;
        final updated = _avatarData!.copyWith(
          training: training,
          updatedAt: DateTime.now(),
        );
        final ok = await _avatarService.updateAvatar(updated);
        if (ok && mounted) await _applyAvatar(updated);
      },
      onToggleLipsync: (v) async {
        if (_avatarData == null) return;
        final training = Map<String, dynamic>.from(_avatarData!.training ?? {});
        training['lipsyncEnabled'] = v;
        final updated = _avatarData!.copyWith(
          training: training,
          updatedAt: DateTime.now(),
        );
        final ok = await _avatarService.updateAvatar(updated);
        if (ok && mounted) await _applyAvatar(updated);
      },
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required String valueLabel,
    String? recommendation,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
            ),
            Text(
              valueLabel,
              style: const TextStyle(
                color: AppColors.lightBlue,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            thumbShape: const GradientSliderThumbShape(thumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              activeColor: AppColors.lightBlue,
              inactiveColor: Colors.white.withValues(alpha: 0.2),
              onChanged: onChanged,
            ),
          ),
        ),
        if (recommendation != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              recommendation,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildMediaNavRow() {
    final id = _avatarData?.id;
    if (id == null || id.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildNavIconButton(
            icon: Icons.photo_library,
            label: context.read<LocalizationService>().t('gallery.title'),
            onTap: () {
              Navigator.pushNamed(
                context,
                '/media-gallery',
                arguments: {'avatarId': id},
              );
            },
          ),
          Container(
            width: 1,
            height: 48,
            color: Colors.white.withValues(alpha: 0.1),
          ),
          _buildNavIconButton(
            icon: Icons.queue_music,
            label: context.read<LocalizationService>().t('playlists.title'),
            onTap: () {
              Navigator.pushNamed(
                context,
                '/playlist-list',
                arguments: {'avatarId': id},
              );
            },
          ),
          Container(
            width: 1,
            height: 48,
            color: Colors.white.withValues(alpha: 0.1),
          ),
          _buildNavIconButton(
            icon: Icons.collections,
            label: context.read<LocalizationService>().t('sharedMoments.title'),
            onTap: () {
              Navigator.pushNamed(
                context,
                '/moments',
                arguments: {'avatarId': id},
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavIconButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.white.withValues(alpha: 0.15),
          splashColor: Colors.white.withValues(alpha: 0.25),
          highlightColor: Colors.white.withValues(alpha: 0.1),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: Colors.white.withValues(alpha: 0.9),
                  size: 24,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Autogenerieren entfernt – Nutzer klickt bewusst „Avatar generieren" nach Hero-Image‑Wechsel

  Widget _buildVoiceSelect() {
    if (_voicesLoading) {
      return const LinearProgressIndicator(minHeight: 3);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Text(
        //   context.read<LocalizationService>().t(
        //     'avatars.details.elevenVoiceSelectTitle',
        //   ),
        //   style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
        // ),
        const SizedBox(height: 8),
        // Slider: Stimme klonen vs. Externe Stimmen (GMBC Style)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _useOwnVoice ? 'Eigene Stimme' : 'Externe Stimme',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () async {
                  setState(() => _useOwnVoice = !_useOwnVoice);
                  await _saveVoiceMode();
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _useOwnVoice ? 'Eigene' : 'Externe',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 6),
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [AppColors.magenta, AppColors.lightBlue],
                        ).createShader(bounds),
                        child: Icon(
                          _useOwnVoice
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Dropdown nur wenn "Externe Stimme" aktiv
        if (!_useOwnVoice)
          CustomDropdown<String>(
            label: 'ElevenLabs Stimme',
            value: _selectedVoiceId,
            hint: 'Stimme wählen',
            items: _elevenVoices.map((v) {
              final id = (v['voice_id'] ?? v['voiceId'] ?? '') as String;
              final name = (v['name'] ?? 'Stimme') as String;
              return DropdownMenuItem<String>(
                value: id,
                child: Text(name, style: const TextStyle(color: Colors.white)),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) _onSelectVoice(val);
            },
          ),
        const SizedBox.shrink(),
      ],
    );
  }

  Future<void> _saveVoiceMode() async {
    // Speichert die Slider-Auswahl (useOwnVoice) und setzt entsprechend elevenVoiceId
    if (_avatarData == null) return;
    try {
      final existing = Map<String, dynamic>.from(_avatarData!.training ?? {});
      final voice = Map<String, dynamic>.from(existing['voice'] ?? {});

      if (_useOwnVoice) {
        // Eigene Stimme: cloneVoiceId → elevenVoiceId kopieren
        final cloneId = (voice['cloneVoiceId'] as String?)?.trim() ?? '';
        if (cloneId.isNotEmpty) {
          voice['elevenVoiceId'] = cloneId;
        }
        voice['useOwnVoice'] = true; // Benutzerwahl PERSISTIEREN
      } else {
        // Externe Stimme: erste Stimme vorauswählen, falls nichts gewählt
        if (_selectedVoiceId == null || _selectedVoiceId!.isEmpty) {
          if (_elevenVoices.isNotEmpty) {
            final firstId =
                (_elevenVoices.first['voice_id'] ??
                        _elevenVoices.first['voiceId'] ??
                        '')
                    as String;
            if (firstId.isNotEmpty) {
              _selectedVoiceId = firstId;
              voice['elevenVoiceId'] = firstId;
            }
          }
        } else {
          voice['elevenVoiceId'] = _selectedVoiceId;
        }
        voice['useOwnVoice'] = false; // Benutzerwahl PERSISTIEREN
      }

      existing['voice'] = voice;
      final updated = _avatarData!.copyWith(
        training: existing,
        updatedAt: DateTime.now(),
      );
      final ok = await _avatarService.updateAvatar(updated);
      if (!mounted) return;
      if (ok) {
        // Lokale Kopie aktualisieren OHNE _applyAvatar (vermeidet Slider-Reset)
        _avatarData = updated;
      }
    } catch (_) {}
  }

  Future<void> _onSelectVoice(String? voiceId) async {
    setState(() {
      _selectedVoiceId = voiceId;
      _isDirty = false;
    });
    // Auswahl sofort in training.voice.elevenVoiceId persistieren
    if (_avatarData == null) return;
    try {
      final existing = Map<String, dynamic>.from(_avatarData!.training ?? {});
      final voice = Map<String, dynamic>.from(existing['voice'] ?? {});

      if ((voiceId ?? '').isNotEmpty) {
        voice['elevenVoiceId'] = voiceId;
      }

      existing['voice'] = voice;
      final updated = _avatarData!.copyWith(
        training: existing,
        updatedAt: DateTime.now(),
      );
      final ok = await _avatarService.updateAvatar(updated);
      if (!mounted) return;
      if (ok) {
        _applyAvatar(updated);
        _showSystemSnack(
          context.read<LocalizationService>().t(
            'avatars.details.voiceSelectionSaved',
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showSystemSnack(
        context.read<LocalizationService>().t(
          'avatars.details.saveError',
          params: {'msg': '$e'},
        ),
      );
    }
  }

  Future<T?> _showBlockingProgress<T>({
    required String title,
    required String message,
    Future<T> Function()? task,
    ValueListenable<double>? progress,
  }) async {
    if (!mounted) return null;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(message)),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 12),
              ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (context, value, _) {
                  final clamped = value.clamp(0.0, 1.0);
                  final percent = (clamped * 100).toStringAsFixed(0);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(value: clamped),
                      const SizedBox(height: 6),
                      Text('$percent%'),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
    try {
      final r = await (task != null ? task() : Future.value(null));
      return r;
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _loadElevenVoices() async {
    try {
      setState(() => _voicesLoading = true);
      await ElevenLabsService.initialize();
      final voices = await ElevenLabsService.getVoices();
      if (voices != null && mounted) {
        setState(() => _elevenVoices = voices);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _voicesLoading = false);
    }
  }

  // ignore: unused_element
  String? _voicePreviewUrlFor(String id) {
    try {
      final v = _elevenVoices.firstWhere(
        (e) => (e['voice_id'] ?? e['voiceId'] ?? '') == id,
        orElse: () => {},
      );
      final url = v['preview_url'] as String?;
      return (url != null && url.isNotEmpty) ? url : null;
    } catch (_) {
      return null;
    }
  }

  // ============================================================================
  // ============================================================================

  Widget _buildTextFilesList() {
    // Kombiniere Remote- und lokale Textdateien
    final List<_NamedItem> items = [];

    // Remote URLs aus Firestore
    for (final url in _textFileUrls) {
      final name = _fileNameFromUrl(url);
      items.add(
        _NamedItem(
          name: name,
          widget: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description, color: Colors.white70),
            title: Text(
              name,
              style: const TextStyle(color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: context.read<LocalizationService>().t(
                    'avatars.details.openTooltip',
                  ),
                  icon: const Icon(Icons.open_in_new, color: Colors.white70),
                  onPressed: () => _openUrl(url),
                ),
                IconButton(
                  tooltip: context.read<LocalizationService>().t(
                    'avatars.details.deleteTooltip',
                  ),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                  ),
                  onPressed: () => _confirmDeleteRemoteText(url),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Lokale (neu hinzugefügte) Textdateien – noch nicht hochgeladen
    for (final f in _newTextFiles) {
      final name = pathFromLocalFile(f.path);
      items.add(
        _NamedItem(
          name: name,
          widget: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.description_outlined,
              color: Colors.white54,
            ),
            title: Text(
              name,
              style: const TextStyle(color: Colors.white70),
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: context.read<LocalizationService>().t(
                    'avatars.details.showTooltip',
                  ),
                  icon: const Icon(
                    Icons.visibility_outlined,
                    color: Colors.white70,
                  ),
                  onPressed: () => _openLocalFile(f),
                ),
                IconButton(
                  tooltip: context.read<LocalizationService>().t(
                    'avatars.details.removeTooltip',
                  ),
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => _confirmDeleteLocalText(f),
                ),
              ],
            ),
          ),
        ),
      );
    }
    // Filter anwenden (case-insensitiv, einfache contains auf Dateiname)
    final String q = _textFilter.toLowerCase();
    final List<_NamedItem> filtered = q.isEmpty
        ? items
        : items.where((e) => e.name.toLowerCase().contains(q)).toList();

    // Paging anwenden
    final int total = filtered.length;
    final int pages = (total / _textFilesPageSize).ceil().clamp(1, 1000000);
    if (_textFilesPage >= pages) _textFilesPage = pages - 1;
    final int start = _textFilesPage * _textFilesPageSize;
    final int end = (start + _textFilesPageSize).clamp(0, total);
    final List<Widget> pageTiles = (total > 0)
        ? filtered.sublist(start, end).map((e) => e.widget).toList()
        : const <Widget>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              context.read<LocalizationService>().t(
                'avatars.details.textFilesTitle',
              ),
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
            Row(
              children: [
                if (total > _textFilesPageSize)
                  IconButton(
                    tooltip: context.read<LocalizationService>().t(
                      'avatars.details.prevPageTooltip',
                    ),
                    icon: const Icon(Icons.chevron_left, color: Colors.white70),
                    onPressed: (_textFilesPage > 0)
                        ? () => setState(() => _textFilesPage--)
                        : null,
                  ),
                if (total > _textFilesPageSize)
                  Text(
                    total == 0 ? '0/0' : '${_textFilesPage + 1}/$pages',
                    style: const TextStyle(color: Colors.white54),
                  ),
                if (total > _textFilesPageSize)
                  IconButton(
                    tooltip: context.read<LocalizationService>().t(
                      'avatars.details.nextPageTooltip',
                    ),
                    icon: const Icon(
                      Icons.chevron_right,
                      color: Colors.white70,
                    ),
                    onPressed: (_textFilesPage < pages - 1)
                        ? () => setState(() => _textFilesPage++)
                        : null,
                  ),
                IconButton(
                  tooltip: _textFilesExpanded
                      ? context.read<LocalizationService>().t(
                          'avatars.details.collapseList',
                        )
                      : context.read<LocalizationService>().t(
                          'avatars.details.expandList',
                        ),
                  icon: Icon(
                    _textFilesExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white70,
                  ),
                  onPressed: () => setState(() {
                    _textFilesExpanded = !_textFilesExpanded;
                  }),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        CustomTextField(
          label: context.read<LocalizationService>().t(
            'avatars.details.textFileFilterLabel',
          ),
          controller: _textFilterController,
          hintText: context.read<LocalizationService>().t(
            'avatars.details.textFileFilterHint',
          ),
          suffixIcon: (_textFilter.isNotEmpty)
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white54),
                  onPressed: () {
                    _textFilterController.clear();
                    FocusScope.of(context).unfocus();
                  },
                )
              : null,
        ),
        const SizedBox(height: 6),
        if (_textFilesExpanded) ...pageTiles,
        if (_textFilesExpanded && total > _textFilesPageSize)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                context.read<LocalizationService>().t(
                  'avatars.details.rangeOfTotal',
                  params: {
                    'start': '${start + 1}',
                    'end': '$end',
                    'total': '$total',
                  },
                ),
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
  Widget _buildAudioFilesList() {
    final List<Widget> tiles = [];

    // Remote Audios
    for (final url in (_avatarData?.audioUrls ?? const [])) {
      tiles.add(
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.audiotrack, color: Colors.white70),
          title: Text(
            _fileNameFromUrl(url),
            style: const TextStyle(color: Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: context.read<LocalizationService>().t(
                  'avatars.details.selectAsVoiceTooltip',
                ),
                icon: Icon(
                  _activeAudioUrl == url ? Icons.star : Icons.star_border,
                  color: _activeAudioUrl == url ? Colors.amber : Colors.white70,
                ),
                onPressed: () async {
                  setState(() {
                    _activeAudioUrl = url;
                  });
                  await _saveActiveAudioSelection(url);
                },
              ),
              IconButton(
                tooltip: context.read<LocalizationService>().t(
                  'avatars.details.playTooltip',
                ),
                icon: const Icon(Icons.play_arrow, color: Colors.white70),
                onPressed: () => _openUrl(url),
              ),
              IconButton(
                tooltip: context.read<LocalizationService>().t(
                  'avatars.details.deleteTooltip',
                ),
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(
                        context.read<LocalizationService>().t(
                          'avatars.details.confirmDeleteAudioTitle',
                        ),
                      ),
                      content: Text(
                        context.read<LocalizationService>().t(
                          'avatars.details.confirmDeleteAudioContent',
                          params: {'name': _fileNameFromUrl(url)},
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                          ),
                          child: Text(
                            context.read<LocalizationService>().t(
                              'avatars.details.cancel',
                            ),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.white,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: ShaderMask(
                            shaderCallback: (bounds) => Theme.of(context)
                                .extension<AppGradients>()!
                                .magentaBlue
                                .createShader(bounds),
                            child: Text(
                              context.read<LocalizationService>().t(
                                'avatars.details.delete',
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    // Media-Dokument löschen (triggert Cloud Function für Storage-Cleanup)
                    final mediaList = await _mediaSvc.list(_avatarData!.id);
                    final mediaDoc = mediaList.firstWhere(
                      (m) => m.url == url,
                      orElse: () => AvatarMedia(
                        id: '',
                        avatarId: '',
                        type: AvatarMediaType.audio,
                        url: '',
                        createdAt: 0,
                      ),
                    );
                    if (mediaDoc.id.isNotEmpty) {
                      // Media-Doc existiert → Cloud Function übernimmt Storage-Cleanup
                      await _mediaSvc.delete(
                        _avatarData!.id,
                        mediaDoc.id,
                        mediaDoc.type,
                      );
                    } else {
                      // Kein Media-Doc → manuell Storage löschen (alte Uploads)
                      await FirebaseStorageService.deleteFile(url);
                    }
                    // URL aus Avatar-Dokument entfernen
                    _avatarData!.audioUrls.remove(url);
                    await _persistTextFileUrls();
                    setState(() {});
                  }
                },
              ),
            ],
          ),
        ),
      );
    }

    // Lokale Audios
    for (final f in _newAudioFiles) {
      tiles.add(
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.upload_file, color: Colors.amber),
          title: Text(
            '${pathFromLocalFile(f.path)} ${context.read<LocalizationService>().t('avatars.details.newSuffix')}',
            style: const TextStyle(color: Colors.white70),
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            tooltip: context.read<LocalizationService>().t(
              'avatars.details.removeTooltip',
            ),
            icon: const Icon(Icons.close, color: Colors.white54),
            onPressed: () {
              setState(() {
                _newAudioFiles.remove(f);
                _updateDirty();
              });
            },
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // const Text(
        //   '',
        //   style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
        // ),
        const SizedBox(height: 6),
        ...tiles,
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: _isSaving
                    ? null
                    : _hasNoClonedVoice
                    ? const LinearGradient(
                        colors: [
                          Color(0xFFBDBDBD),
                          Color(0xFFFFFFFF),
                        ], // Light grey + white
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      )
                    : const LinearGradient(
                        colors: [
                          AppColors.magenta,
                          AppColors.lightBlue,
                        ], // GMBC wie Upload-Buttons
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _onCloneVoice,
                icon: _hasNoClonedVoice
                    ? ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (bounds) => Theme.of(context)
                            .extension<AppGradients>()!
                            .magentaBlue
                            .createShader(bounds),
                        child: const Icon(
                          Icons.auto_fix_high,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.auto_fix_high, color: Colors.white),
                label: _hasNoClonedVoice
                    ? ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (bounds) => Theme.of(context)
                            .extension<AppGradients>()!
                            .magentaBlue
                            .createShader(bounds),
                        child: Text(
                          _isSaving
                              ? context.read<LocalizationService>().t(
                                  'avatars.details.cloningInProgress',
                                )
                              : context.read<LocalizationService>().t(
                                  'avatars.details.cloneVoiceButton',
                                ),
                          style: const TextStyle(color: Colors.white),
                        ),
                      )
                    : Text(
                        _isSaving
                            ? context.read<LocalizationService>().t(
                                'avatars.details.cloningInProgress',
                              )
                            : context.read<LocalizationService>().t(
                                'avatars.details.cloneVoiceButton',
                              ),
                        style: const TextStyle(color: Colors.white),
                      ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isSaving ? Colors.grey : Colors.transparent,
                  foregroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (((_avatarData?.training?['voice']?['elevenVoiceId'] as String?)
                    ?.trim()
                    .isNotEmpty ??
                false))
              IconButton(
                tooltip: context.read<LocalizationService>().t(
                  'avatars.details.readGreetingTooltip',
                ),
                icon: const Icon(Icons.volume_up, color: Colors.white),
                onPressed: _isTestingVoice ? null : _testVoicePlayback,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildVoiceParams() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.read<LocalizationService>().t(
            'avatars.details.voiceSettingsTitle',
          ),
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                context.read<LocalizationService>().t(
                  'avatars.details.stability',
                ),
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppColors.magenta.withValues(
                    alpha: 0.8,
                  ), // GMBC Magenta
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                  overlayColor: AppColors.magenta.withValues(
                    alpha: 0.2,
                  ), // GMBC Magenta overlay
                  trackHeight: 4.0,
                  thumbShape: const GradientSliderThumbShape(
                    thumbRadius: 8.0,
                  ), // GMBC Kugel
                  showValueIndicator: ShowValueIndicator.onDrag,
                  valueIndicatorColor: Colors.white,
                  valueIndicatorTextStyle: const TextStyle(
                    color: AppColors.magenta,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Slider(
                  value: _voiceStability.clamp(0.0, 1.0),
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  label: _voiceStability.toStringAsFixed(2),
                  onChanged: (v) => setState(() => _voiceStability = v),
                  onChangeEnd: (_) => _saveVoiceParams(),
                ),
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                _voiceStability.toStringAsFixed(2),
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
        Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                context.read<LocalizationService>().t(
                  'avatars.details.similarity',
                ),
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppColors.magenta.withValues(
                    alpha: 0.8,
                  ), // GMBC Magenta
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                  overlayColor: AppColors.magenta.withValues(
                    alpha: 0.2,
                  ), // GMBC Magenta overlay
                  trackHeight: 4.0,
                  thumbShape: const GradientSliderThumbShape(
                    thumbRadius: 8.0,
                  ), // GMBC Kugel
                  showValueIndicator: ShowValueIndicator.onDrag,
                  valueIndicatorColor: Colors.white,
                  valueIndicatorTextStyle: const TextStyle(
                    color: AppColors.magenta,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Slider(
                  value: _voiceSimilarity.clamp(0.0, 1.0),
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  label: _voiceSimilarity.toStringAsFixed(2),
                  onChanged: (v) => setState(() => _voiceSimilarity = v),
                  onChangeEnd: (_) => _saveVoiceParams(),
                ),
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                _voiceSimilarity.toStringAsFixed(2),
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                context.read<LocalizationService>().t('avatars.details.tempo'),
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppColors.magenta.withValues(
                    alpha: 0.8,
                  ), // GMBC Magenta
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                  overlayColor: AppColors.magenta.withValues(
                    alpha: 0.2,
                  ), // GMBC Magenta overlay
                  trackHeight: 4.0,
                  thumbShape: const GradientSliderThumbShape(
                    thumbRadius: 8.0,
                  ), // GMBC Kugel
                  showValueIndicator: ShowValueIndicator.onDrag,
                  valueIndicatorColor: Colors.white,
                  valueIndicatorTextStyle: const TextStyle(
                    color: AppColors.magenta,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Slider(
                  value: _voiceTempo.clamp(0.5, 1.5),
                  min: 0.5,
                  max: 1.5,
                  divisions: 20,
                  label: _voiceTempo.toStringAsFixed(2),
                  onChanged: (v) => setState(() => _voiceTempo = v),
                  onChangeEnd: (_) => _saveVoiceParams(),
                ),
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                _voiceTempo.toStringAsFixed(2),
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),
        CustomDropdown<String>(
          label: context.read<LocalizationService>().t(
            'avatars.details.dialect',
          ),
          value: _voiceDialect,
          items: [
            DropdownMenuItem(
              value: 'de-DE',
              child: Text(
                context.read<LocalizationService>().t(
                  'avatars.details.dialect.de-DE',
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ),
            DropdownMenuItem(
              value: 'de-AT',
              child: Text(
                context.read<LocalizationService>().t(
                  'avatars.details.dialect.de-AT',
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ),
            DropdownMenuItem(
              value: 'de-CH',
              child: Text(
                context.read<LocalizationService>().t(
                  'avatars.details.dialect.de-CH',
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ),
            DropdownMenuItem(
              value: 'en-US',
              child: Text(
                context.read<LocalizationService>().t(
                  'avatars.details.dialect.en-US',
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ),
            DropdownMenuItem(
              value: 'en-GB',
              child: Text(
                context.read<LocalizationService>().t(
                  'avatars.details.dialect.en-GB',
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _voiceDialect = v);
            _saveVoiceParams();
          },
        ),

        const SizedBox.shrink(),
      ],
    );
  }

  Future<void> _saveVoiceParams() async {
    if (_avatarData == null) return;
    final existing = Map<String, dynamic>.from(_avatarData!.training ?? {});
    final voice = Map<String, dynamic>.from(existing['voice'] ?? {});
    voice['stability'] = double.parse(_voiceStability.toStringAsFixed(2));
    voice['similarity'] = double.parse(_voiceSimilarity.toStringAsFixed(2));
    voice['tempo'] = double.parse(_voiceTempo.toStringAsFixed(2));
    voice['dialect'] = _voiceDialect;
    existing['voice'] = voice;
    final updated = _avatarData!.copyWith(
      training: existing,
      updatedAt: DateTime.now(),
      role: _role ?? _avatarData!.role,
    );
    final ok = await _avatarService.updateAvatar(updated);
    if (ok && mounted) {
      _applyAvatar(updated);
      _showSystemSnack(
        context.read<LocalizationService>().t(
          'avatars.details.voiceSettingsSaved',
        ),
      );
    }
  }

  Future<void> _saveRoleImmediately(String? newRole) async {
    if (_avatarData == null) return;

    try {
      // 1. Firestore Update (role wird in training.needsRetrain berücksichtigt)
      final existing = Map<String, dynamic>.from(_avatarData!.training ?? {});
      existing['needsRetrain'] =
          true; // ← Wichtig! Triggert Re-Training mit neuer Rolle

      final updated = _avatarData!.copyWith(
        role: newRole,
        training: existing,
        updatedAt: DateTime.now(),
      );
      final ok = await _avatarService.updateAvatar(updated);

      if (ok && mounted) {
        _applyAvatar(updated);
        _showSystemSnack(
          'Rolle gespeichert - wird beim nächsten Training berücksichtigt',
        );
      }
    } catch (e) {
      if (mounted) {
        _showSystemSnack('Fehler beim Speichern der Rolle: $e');
      }
    }
  }

  Future<void> _testVoicePlayback() async {
    try {
      // TTS nutzt eigene Basis‑URL, unabhängig von Memory‑API
      final base = EnvService.ttsApiBaseUrl();
      if (base == null || base.isEmpty) {
        _showSystemSnack(
          context.read<LocalizationService>().t(
            'avatars.details.backendUrlMissing',
          ),
        );
        return;
      }
      final isCf = EnvService.ttsIsCloudFunctions(base);
      final path = EnvService.ttsEndpointPath(base);
      String? voiceId;
      // Slider-Auswahl berücksichtigen
      if (_useOwnVoice) {
        voiceId = (_avatarData?.training?['voice']?['cloneVoiceId'] as String?)
            ?.trim();
      } else if ((_selectedVoiceId ?? '').isNotEmpty) {
        voiceId = _selectedVoiceId?.trim();
      } else {
        try {
          voiceId =
              (_avatarData?.training?['voice']?['elevenVoiceId'] as String?)
                  ?.trim();
        } catch (_) {}
      }
      if (voiceId == null || voiceId.isEmpty) {
        _showSystemSnack(
          context.read<LocalizationService>().t(
            'avatars.details.noClonedVoice',
          ),
        );
        return;
      }

      final uri = Uri.parse('$base$path');
      // Begrüßungstext immer verwenden
      final greeting = (_greetingController.text.trim().isNotEmpty)
          ? _greetingController.text.trim()
          : (_avatarData?.greetingText?.trim().isNotEmpty == true
                ? _avatarData!.greetingText!.trim()
                : context.read<LocalizationService>().t(
                    'avatars.details.defaultGreeting',
                  ));

      final payload = <String, dynamic>{
        'text': greeting,
        if (isCf) 'voiceId': voiceId else 'voice_id': voiceId,
        'stability': double.parse(_voiceStability.toStringAsFixed(2)),
        'similarity': double.parse(_voiceSimilarity.toStringAsFixed(2)),
        'speed': double.parse(_voiceTempo.toStringAsFixed(2)),
        'dialect': _voiceDialect,
      };

      setState(() => _isTestingVoice = true);
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final Uint8List bytes = isCf
            ? res.bodyBytes
            : (() {
                final data = jsonDecode(res.body) as Map<String, dynamic>;
                final b64 = (data['audio_b64'] as String?) ?? '';
                return base64Decode(b64);
              })();
        final dir = await getTemporaryDirectory();
        final file = File(
          '${dir.path}/voice_test_${DateTime.now().millisecondsSinceEpoch}.mp3',
        );
        await file.writeAsBytes(bytes, flush: true);
        await _voiceTestPlayer.setFilePath(file.path);
        await _voiceTestPlayer.play();
        if (!mounted) return;
      } else {
        if (!mounted) return;
        final detail = (res.body.isNotEmpty) ? ' ${res.body}' : '';
        _showSystemSnack(
          context.read<LocalizationService>().t(
            'avatars.details.ttsFailed',
            params: {'code': res.statusCode.toString(), 'detail': detail},
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showSystemSnack(
        context.read<LocalizationService>().t(
          'avatars.details.testError',
          params: {'msg': '$e'},
        ),
      );
    } finally {
      if (mounted) setState(() => _isTestingVoice = false);
    }
  }

  Future<void> _saveActiveAudioSelection(String url) async {
    try {
      if (_avatarData == null) return;
      final Map<String, dynamic> training = Map<String, dynamic>.from(
        _avatarData!.training ?? {},
      );
      final Map<String, dynamic> voice = Map<String, dynamic>.from(
        training['voice'] ?? {},
      );
      voice['activeUrl'] = url;
      voice['candidates'] = List<String>.from(_avatarData!.audioUrls);
      training['voice'] = voice;
      final updated = _avatarData!.copyWith(
        training: training,
        updatedAt: DateTime.now(),
      );
      final ok = await _avatarService.updateAvatar(updated);
      if (!mounted) return;
      if (ok) {
        _applyAvatar(updated);
        _showSystemSnack(
          context.read<LocalizationService>().t(
            'avatars.details.voiceSampleSaved',
          ),
        );
      } else {
        _showSystemSnack(
          context.read<LocalizationService>().t(
            'avatars.details.voiceSampleSaveFailed',
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showSystemSnack(
        context.read<LocalizationService>().t(
          'avatars.details.saveError',
          params: {'msg': '$e'},
        ),
      );
    }
  }
  Future<void> _onCloneVoice() async {
    if (_avatarData == null) return;
    if (_isSaving) {
      _showSystemSnack(
        context.read<LocalizationService>().t(
          'avatars.details.cloningAlreadyInProgress',
        ),
      );
      return;
    }

    // SOFORT setState um Button zu disabled
    setState(() => _isSaving = true);

    // Altes Verhalten: Wenn noch lokale Audios vorhanden, erst speichern lassen
    if (_newAudioFiles.isNotEmpty) {
      setState(() => _isSaving = false);
      _showSystemSnack(
        context.read<LocalizationService>().t(
          'avatars.details.saveFirstThenClone',
        ),
      );
      return;
    }
    final audios = List<String>.from(_avatarData!.audioUrls);
    if (audios.isEmpty) {
      setState(() => _isSaving = false);
      _showSystemSnack(
        context.read<LocalizationService>().t('avatars.details.noAudioSample'),
      );
      return;
    }
    // EXPLIZIT NUR die markierte Probe verwenden (keine implizite Reihenfolge)
    List<String> selected = [];
    if (_activeAudioUrl != null &&
        _activeAudioUrl!.isNotEmpty &&
        audios.contains(_activeAudioUrl)) {
      selected = [_activeAudioUrl!];
    } else if (audios.isNotEmpty) {
      // Fallback: erste vorhandene (explizit)
      selected = [audios.first];
    }
    if (selected.isEmpty) {
      setState(() => _isSaving = false);
      _showSystemSnack(
        context.read<LocalizationService>().t(
          'avatars.details.markAudioWithStar',
        ),
      );
      return;
    }
    try {
      await _showBlockingProgress(
        title: context.read<LocalizationService>().t(
          'avatars.details.cloningTitle',
        ),
        message: context.read<LocalizationService>().t(
          'avatars.details.cloningWaitMessage',
        ),
        task: () async {
          final uid = FirebaseAuth.instance.currentUser!.uid;
          final base = dotenv.env['MEMORY_API_BASE_URL'];
          if (base == null || base.isEmpty) {
            _showSystemSnack(
              context.read<LocalizationService>().t(
                'avatars.details.backendUrlMissing',
              ),
            );
            return;
          }
          final uri = Uri.parse('$base/avatar/voice/create');
          final Map<String, dynamic> payload = {
            'user_id': uid,
            'avatar_id': _avatarData!.id,
            // nur explizit ausgewählte Probe (max 1–3 erlaubt, hier 1)
            'audio_urls': selected.take(3).toList(),
            // kanonischer Name wie im Backend: avatar_{avatar_id}
            'name': 'avatar_${_avatarData!.id}',
          };
          // Dialekt/Tempo/Stability/Similarity mitsenden, wenn vorhanden
          try {
            final v = _avatarData?.training?['voice'] as Map<String, dynamic>?;
            final tempo = (v?['tempo'] as num?)?.toDouble();
            final dialect = v?['dialect'] as String?;
            final stability = (v?['stability'] as num?)?.toDouble();
            final similarity = (v?['similarity'] as num?)?.toDouble();
            if (tempo != null) payload['tempo'] = tempo;
            if (dialect != null && dialect.isNotEmpty) {
              payload['dialect'] = dialect;
            }
            if (stability != null) payload['stability'] = stability;
            if (similarity != null) payload['similarity'] = similarity;
          } catch (_) {}
          // Wenn bereits eine Stimme existiert: voice_id mitsenden → bestehende Stimme updaten, NICHT neu anlegen
          try {
            final raw =
                (_avatarData?.training?['voice']?['cloneVoiceId'] ??
                        _avatarData?.training?['voice']?['elevenVoiceId'])
                    as String?;
            final id = raw?.trim();
            if (id != null && id.isNotEmpty && id != '__CLONE__') {
              payload['voice_id'] = id;
            }
          } catch (_) {}

          http.Response res;
          try {
            res = await http
                .post(
                  uri,
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode(payload),
                )
                .timeout(const Duration(seconds: 45));
          } on TimeoutException {
            if (!mounted) return;
            _showSystemSnack(
              context.read<LocalizationService>().t(
                'avatars.details.cloneTimeout',
              ),
            );
            return;
          }
          if (res.statusCode >= 200 && res.statusCode < 300) {
            final data = jsonDecode(res.body) as Map<String, dynamic>;
            final voiceId = data['voice_id'] as String?;
            if (voiceId != null && voiceId.isNotEmpty) {
              // training.voice.* konsistent setzen: IMMER beide Felder auf neue Klon-ID
              final existingVoice = (_avatarData!.training != null)
                  ? Map<String, dynamic>.from(
                      _avatarData!.training!['voice'] ?? {},
                    )
                  : <String, dynamic>{};

              // Nach Klonen: IMMER beide IDs auf die neue voiceId setzen
              existingVoice['elevenVoiceId'] = voiceId;
              existingVoice['cloneVoiceId'] = voiceId;
              existingVoice['activeUrl'] = _activeAudioUrl;
              existingVoice['candidates'] = _avatarData!.audioUrls;

              debugPrint(
                '🔥 Klonen erfolgreich: elevenVoiceId=$voiceId, cloneVoiceId=$voiceId',
              );
              debugPrint('🔥 existingVoice nach Setzen: $existingVoice');

              final updated = _avatarData!.copyWith(
                training: {
                  ...(_avatarData!.training ?? {}),
                  'voice': existingVoice,
                },
                updatedAt: DateTime.now(),
              );
              final ok = await _avatarService.updateAvatar(updated);
              if (!mounted) return;
              if (ok) {
                // Nach Klonen: Slider auf "Eigene Stimme" setzen (VOR _applyAvatar)
                setState(() {
                  _useOwnVoice = true;
                  _isDirty = false;
                });
                _applyAvatar(updated);
                _showSystemSnack(
                  context.read<LocalizationService>().t(
                    'avatars.details.voiceClonedSaved',
                  ),
                );
              } else {
                _showSystemSnack(
                  context.read<LocalizationService>().t(
                    'avatars.details.saveVoiceIdFailed',
                  ),
                );
              }
            } else {
              if (!mounted) return;
              _showSystemSnack(
                context.read<LocalizationService>().t(
                  'avatars.details.elevenNoVoiceId',
                ),
              );
            }
          } else {
            if (!mounted) return;
            final detail = (res.body.isNotEmpty) ? ' ${res.body}' : '';
            _showSystemSnack(
              context.read<LocalizationService>().t(
                'avatars.details.cloneFailed',
                params: {'code': res.statusCode.toString(), 'detail': detail},
              ),
            );
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      _showSystemSnack(
        context.read<LocalizationService>().t(
          'avatars.details.cloneError',
          params: {'msg': '$e'},
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _fileNameFromUrl(String url) {
    // Verhindert kurzzeitig den technischen Pfad (Zahlenname), bis Mapping geladen ist
    if (!_mediaOriginalNamesLoaded) {
      return '';
    }

    // 1. Prüfe ob OriginalFileName in Map vorhanden (aus Firestore Media-Docs)
    if (_mediaOriginalNames.containsKey(url)) {
      return _mediaOriginalNames[url]!;
    }
    // 2. Fallback: Aus URL extrahieren
    try {
      final uri = Uri.parse(url);
      // Bei Firebase-Download-URLs ist das letzte Segment URL-encodiert (z.B. avatars%2F...%2Ffile.txt)
      final lastSegment = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : uri.path;
      final decoded = Uri.decodeComponent(lastSegment);
      final fileName = decoded.split('/').isNotEmpty
          ? decoded.split('/').last
          : decoded;
      return fileName.isNotEmpty ? fileName : url;
    } catch (_) {
      return url;
    }
  }

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

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openLocalFile(File f) async {
    final uri = Uri.file(f.path);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  void _showSystemSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmDeleteLocalText(File f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          context.read<LocalizationService>().t(
            'avatars.details.confirmRemoveFileTitle',
          ),
        ),
        content: Text(
          context.read<LocalizationService>().t(
            'avatars.details.confirmRemoveFileContent',
            params: {'name': pathFromLocalFile(f.path)},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
            child: Text(
              context.read<LocalizationService>().t('avatars.details.cancel'),
            ),
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
              shaderCallback: (bounds) => Theme.of(
                context,
              ).extension<AppGradients>()!.magentaBlue.createShader(bounds),
              child: Text(
                context.read<LocalizationService>().t('avatars.details.delete'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() => _newTextFiles.remove(f));
    }
  }

  Future<void> _confirmDeleteRemoteText(String url) async {
    final locSvc = context.read<LocalizationService>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(locSvc.t('avatars.details.confirmDeleteFileTitle')),
        content: Text(
          locSvc.t(
            'avatars.details.confirmDeleteFileContent',
            params: {'name': _fileNameFromUrl(url)},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
            child: Text(locSvc.t('avatars.details.cancel')),
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
              shaderCallback: (bounds) => Theme.of(
                context,
              ).extension<AppGradients>()!.magentaBlue.createShader(bounds),
              child: Text(
                locSvc.t('avatars.details.delete'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      // Fortschritts-Notifier entfernt (nicht genutzt)
      await _showBlockingProgress<void>(
        title: locSvc.t('avatars.details.deletingTitle'),
        message: _fileNameFromUrl(url),
        progress: null, // kein Prozent für Delete
        task: () async {
          final deleted = await FirebaseStorageService.deleteFile(url);
          if (!deleted) {
            if (!mounted) return;
            _showSystemSnack(locSvc.t('avatars.details.deleteFailed'));
            return;
          }
          // Pinecone: zugehörige Chunks löschen (OR: file_url / file_path / file_name)
          try {
            final uid = FirebaseAuth.instance.currentUser!.uid;
            final avatarId = _avatarData!.id;
            // Fire-and-forget, UI nicht blockieren
            // ignore: unawaited_futures
            _triggerMemoryDelete(
              userId: uid,
              avatarId: avatarId,
              fileUrl: url,
              fileName: _fileNameFromUrl(url),
              filePath: _storagePathFromUrl(url),
            );
          } catch (_) {}
          _textFileUrls.remove(url);
          if (!mounted) return;
          setState(() {});
          final ok = await _persistTextFileUrls();
          if (!ok) {
            if (!mounted) return;
            _showSystemSnack(locSvc.t('avatars.details.firestoreUpdateFailed'));
          }
        },
      );
    }
  }

  Future<bool> _persistTextFileUrls() async {
    if (_avatarData == null) return false;
    final allImages = [..._imageUrls];
    final allVideos = [..._videoUrls];
    final allTexts = [..._textFileUrls];
    // Altes Verhalten: Audio nicht hier mitschreiben (nur beim großen Save)
    // final List<String> allAudios = List<String>.from(
    //   _avatarData?.audioUrls ?? const <String>[],
    // );

    final totalDocuments =
        allImages.length +
        allVideos.length +
        allTexts.length +
        // allAudios.length +
        (_avatarData!.writtenTexts.length);

    // WICHTIG: Bestehendes training-Objekt mergen, nicht überschreiben!
    final existingTraining = _avatarData!.training ?? {};
    final training = {
      ...existingTraining, // Bestehende Felder beibehalten (z.B. heroVideoUrl, heroImageUrl, voice, dynamics)
      'status': 'pending',
      'startedAt': null,
      'finishedAt': null,
      'lastRunAt': null,
      'progress': 0.0,
      'totalDocuments': totalDocuments,
      'totalFiles': {
        'texts': allTexts.length,
        'images': allImages.length,
        'videos': allVideos.length,
        'others': 0,
      },
      'totalChunks': 0,
      'chunkSize': 0,
      'totalTokens': 0,
      'vector': null,
      'lastError': null,
      'jobId': null,
      'needsRetrain': true,
    };

    final updated = _avatarData!.copyWith(
      textFileUrls: allTexts,
      imageUrls: allImages,
      videoUrls: allVideos,
      // audioUrls: allAudios,
      avatarImageUrl: _profileImageUrl,
      training: training,
      updatedAt: DateTime.now(),
    );
    final ok = await _avatarService.updateAvatar(updated);
    if (ok) {
      _applyAvatar(updated);
    }
    return ok;
  }

  /// Erstellt ein media-Dokument via MediaService (triggert serverseitige Thumb-Generierung)
  Future<void> _addMediaDoc(
    String url,
    AvatarMediaType type, {
    String? originalFileName,
    bool? voiceClone,
  }) async {
    if (_avatarData == null) return;

    await Future.delayed(const Duration(milliseconds: 10));
    final ts = DateTime.now().millisecondsSinceEpoch;
    final media = AvatarMedia(
      id: ts.toString(),
      avatarId: _avatarData!.id,
      type: type,
      url: url,
      createdAt: ts,
      originalFileName: originalFileName,
      voiceClone: voiceClone,
    );
    await _mediaSvc.add(_avatarData!.id, media);

    // Name im UI immer als originalFileName anzeigen (falls vorhanden)
    if (originalFileName != null && originalFileName.isNotEmpty) {
      _mediaOriginalNames[url] = originalFileName;
    }
  }

  String pathFromLocalFile(String p) {
    try {
      final parts = p.split('/');
      return parts.isNotEmpty ? parts.last : p;
    } catch (_) {
      return p;
    }
  }

  String _slugify(String input) {
    var text = input.trim().toLowerCase();
    // Verwende die ersten ~3 Schlüsselwörter (max.)
    final words = text
        .replaceAll(RegExp(r"[\n\r\t_]+"), ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(3)
        .toList();
    var slug = words.join('-');
    // Nur a-z0-9- erlauben
    slug = slug.replaceAll(RegExp(r"[^a-z0-9-]+"), '');
    slug = slug.replaceAll(RegExp(r"-+"), '-');
    slug = slug.replaceAll(RegExp(r"(^-+|-+$)"), '');
    if (slug.length > 32) slug = slug.substring(0, 32);
    if (slug.isEmpty) slug = 'text';
    return slug;
  }

  String _uniqueFileName(String desired, Set<String> existing) {
    if (!existing.contains(desired)) {
      existing.add(desired);
      return desired;
    }
    final int dot = desired.lastIndexOf('.');
    final String base = dot > 0 ? desired.substring(0, dot) : desired;
    final String ext = dot > 0 ? desired.substring(dot) : '';
    int i = 2;
    String cand = '';
    do {
      cand = '${base}_$i$ext';
      i++;
    } while (existing.contains(cand));
    existing.add(cand);
    return cand;
  }

  String _buildProfileTextContent({
    required String firstName,
    String? lastName,
    String? nickname,
    DateTime? birthDate,
    DateTime? deathDate,
    int? calculatedAge,
  }) {
    final List<String> lines = [];
    final String fullName = [
      firstName,
      if (lastName != null && lastName.isNotEmpty) lastName,
    ].join(' ').trim();
    if (fullName.isNotEmpty) lines.add('Name: $fullName');
    if (nickname != null && nickname.isNotEmpty) {
      lines.add('Spitzname: $nickname');
    }
    if (birthDate != null) lines.add('Geburtsdatum: ${_formatDate(birthDate)}');
    if (deathDate != null) lines.add('Sterbedatum: ${_formatDate(deathDate)}');
    if (calculatedAge != null) lines.add('Alter (berechnet): $calculatedAge');
    return lines.join('\n');
  }

  // ignore: unused_element
  Widget _imageThumbNetwork(String url, bool isHero) {
    final selected = _selectedRemoteImages.contains(url);
    return GestureDetector(
      onTap: () async {
        if (_isDeleteMode) {
          setState(() {
            if (selected) {
              _selectedRemoteImages.remove(url);
            } else {
              _selectedRemoteImages.add(url);
            }
          });
        } else {
          setState(() {
            _setHeroImage(url);
            _updateDirty();
          });
          // Hero-Image sofort persistent speichern
          await _persistTextFileUrls();
        }
      },
      onLongPress: () => setState(() {
        // Long-Press nur im Löschmodus relevant
        if (_isDeleteMode) {
          if (selected) {
            _selectedRemoteImages.remove(url);
          } else {
            _selectedRemoteImages.add(url);
          }
        }
      }),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              key: ValueKey(url),
              errorBuilder: (context, error, stack) {
                _handleImageError(url);
                return Container(
                  color: Colors.black26,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.image_not_supported,
                    color: Colors.white54,
                  ),
                );
              },
            ),
          ),
          if (isHero)
            const Positioned(
              top: 4,
              left: 4,
              child: Text('⭐', style: TextStyle(fontSize: 16)),
            ),
          // Crop-Icon unten links (nur wenn nicht im Delete-Modus)
          if (!_isDeleteMode)
            Positioned(
              left: 6,
              bottom: 6,
              child: InkWell(
                onTap: () => _onImageRecrop(url),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0x30000000),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0x66FFFFFF)),
                  ),
                  child: const Icon(Icons.crop, color: Colors.white, size: 16),
                ),
              ),
            ),
          // Delete-Icon unten rechts
          Positioned(
            right: 6,
            bottom: 6,
            child: InkWell(
              onTap: () {
                setState(() {
                  _isDeleteMode = true;
                  if (selected) {
                    _selectedRemoteImages.remove(url);
                  } else {
                    _selectedRemoteImages.add(url);
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: selected ? null : const Color(0x30000000),
                  gradient: selected
                      ? Theme.of(context).extension<AppGradients>()!.magentaBlue
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
    );
  }
  // Hero-Image Thumbnail mit GMBC Border 2px nur für Hero-Image
  Widget _buildHeroImageThumbNetwork(String url, bool isHero) {
    final selected = _selectedRemoteImages.contains(url);

    final Widget imageContent = Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(isHero ? 10 : 12),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            key: ValueKey(url),
            errorBuilder: (context, error, stack) {
              _handleImageError(url);
              return Container(
                color: Colors.black26,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.image_not_supported,
                  color: Colors.white54,
                ),
              );
            },
          ),
        ),
        if (isHero)
          const Positioned(
            top: 4,
            left: 4,
            child: Text('⭐', style: TextStyle(fontSize: 16)),
          ),
        // Crop-Icon unten links (nur wenn nicht im Delete-Modus)
        if (!_isDeleteMode)
          Positioned(
            left: 6,
            bottom: 6,
            child: InkWell(
              onTap: () => _onImageRecrop(url),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0x30000000),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x66FFFFFF)),
                ),
                child: const Icon(Icons.crop, color: Colors.white, size: 16),
              ),
            ),
          ),
        // Delete-Icon unten rechts
        Positioned(
          right: 6,
          bottom: 6,
          child: InkWell(
            onTap: () {
              setState(() {
                _isDeleteMode = true;
                if (selected) {
                  _selectedRemoteImages.remove(url);
                } else {
                  _selectedRemoteImages.add(url);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: selected ? null : const Color(0x30000000),
                gradient: selected
                    ? Theme.of(context).extension<AppGradients>()!.magentaBlue
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
    );

    return MouseRegion(
      cursor: isHero && !_isDeleteMode
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: isHero && !_isDeleteMode
            ? null
            : () async {
                if (_isDeleteMode) {
                  setState(() {
                    if (selected) {
                      _selectedRemoteImages.remove(url);
                    } else {
                      _selectedRemoteImages.add(url);
                    }
                  });
                } else {
                  setState(() {
                    _setHeroImage(url);
                    _updateDirty();
                  });
                  // Hero-Image sofort persistent speichern
                  await _persistTextFileUrls();
                }
              },
        onLongPress: () => setState(() {
          // Long-Press nur im Löschmodus relevant
          if (_isDeleteMode) {
            if (selected) {
              _selectedRemoteImages.remove(url);
            } else {
              _selectedRemoteImages.add(url);
            }
          }
        }),
        child: isHero
            ? Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFE91E63),
                      AppColors.lightBlue,
                      Color(0xFF00E5FF),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: const EdgeInsets.all(2),
                child: imageContent,
              )
            : imageContent,
      ),
    );
  }

  // _imageThumbFile wurde im neuen Layout nicht mehr benötigt
  String? _getHeroVideoUrl() {
    // Strikte Logik: NUR training.heroVideoUrl zählt (kein Fallback auf _videoUrls)
    try {
      final v = (_avatarData?.training?['heroVideoUrl'] as String?)?.trim();
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}
    return null;
  }

  String? _getHeroImageUrl() {
    if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
      return _profileImageUrl;
    }
    if (_imageUrls.isNotEmpty) return _imageUrls.first;
    return null;
  }

  String? _getHeroAudioUrl() {
    // Aktive Audio URL als Hero-Audio verwenden
    if (_activeAudioUrl != null && _activeAudioUrl!.isNotEmpty) {
      return _activeAudioUrl;
    }
    // Fallback: Erstes Audio aus avatarData
    final audioUrls = _avatarData?.audioUrls ?? [];
    if (audioUrls.isNotEmpty) return audioUrls.first;
    return null;
  }

  // 🚀 Live Avatar Daten aus Firestore laden
  Future<void> _loadLiveAvatarData(String avatarId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('avatars')
          .doc(avatarId)
          .get();

      if (!doc.exists) return;

      final data = doc.data();
      if (data == null) return;

      final liveAvatar = data['liveAvatar'];
      if (liveAvatar is Map) {
        final agentId = (liveAvatar['agentId'] as String?)?.trim();
        if (agentId != null && agentId.isNotEmpty) {
          setState(() {
            _liveAvatarAgentId = agentId;
          });
          debugPrint('✅ Live Avatar Agent ID geladen: $agentId');
        }
      }
    } catch (e) {
      debugPrint('❌ Fehler beim Laden der Live Avatar Daten: $e');
    }
  }

  /// Berechnet optimalen source-max-dim Wert basierend auf Hero-Image-Dimensionen
  /// Logik: Nimmt die größere Dimension (Höhe oder Breite) und rundet auf nächste 512px
  Future<void> _autoCalculateSourceMaxDim(String dynamicsId) async {
    final heroImageUrl = _getHeroImageUrl();
    if (heroImageUrl == null) return;

    try {
      debugPrint('📏 Berechne optimalen source-max-dim für: $heroImageUrl');

      // Lade Image und hole Dimensionen
      final completer = Completer<ui.Image>();
      final imageStream = NetworkImage(
        heroImageUrl,
      ).resolve(ImageConfiguration.empty);

      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (ImageInfo info, bool _) {
          completer.complete(info.image);
          imageStream.removeListener(listener);
        },
        onError: (exception, stackTrace) {
          debugPrint('❌ Fehler beim Laden des Hero-Images: $exception');
          completer.completeError(exception);
          imageStream.removeListener(listener);
        },
      );

      imageStream.addListener(listener);
      final image = await completer.future;

      final width = image.width;
      final height = image.height;
      final maxDim = width > height ? width : height;

      // Runde auf nächste 512px, min 512, max 2048
      int optimal;
      if (maxDim <= 768) {
        optimal = 512;
      } else if (maxDim <= 1280) {
        optimal = 1024;
      } else if (maxDim <= 1792) {
        optimal = 1600;
      } else {
        optimal = 2048;
      }

      setState(() {
        _sourceMaxDims[dynamicsId] = optimal;
      });

      debugPrint('✅ source-max-dim berechnet: ${width}x$height → $optimal px');
      debugPrint('💡 Empfehlung: $optimal (basierend auf Bild-Größe)');
    } catch (e) {
      debugPrint('❌ Fehler beim Berechnen von source-max-dim: $e');
      // Fallback auf 1600
      setState(() {
        _sourceMaxDims[dynamicsId] = 1600;
      });
    }
  }

  Future<void> _setHeroVideo(String url) async {
    if (_avatarData == null) return;

    // Prüfe ob Basic Dynamics Video existiert
    final hasBasicDynamicsVideo = _dynamicsData['basic']?['video_url'] != null;

    if (hasBasicDynamicsVideo) {
      // Warnung anzeigen
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('⚠️ Neues Hero-Video?'),
          content: const Text(
            'Durch das Setzen eines neuen Hero-Videos wird das generierte Basic Dynamics Video gelöscht.\n\n'
            'Möchtest du fortfahren?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
              child: const Text('Fortfahren'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      // Lösche NUR Basic Dynamics Video und setze Status auf 'pending'
      try {
        final batch = <String, dynamic>{};

        // Nur 'basic' Dynamics
        if (_dynamicsData['basic']?['video_url'] != null) {
          batch['dynamics.basic.video_url'] = FieldValue.delete();
        }
        batch['dynamics.basic.status'] = 'pending';

        if (batch.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('avatars')
              .doc(_avatarData!.id)
              .update(batch);
        }

        setState(() {
          _dynamicsData['basic']?['video_url'] = null;
          _dynamicsData['basic']?['status'] = 'pending';
        });

        debugPrint('✅ Basic Dynamics Video gelöscht, Status auf pending');
      } catch (e) {
        debugPrint('❌ Fehler beim Löschen Basic Dynamics Video: $e');
      }
    } else {
      // Auch wenn kein Video vorhanden ist, setze Status auf 'pending'
      try {
        await FirebaseFirestore.instance
            .collection('avatars')
            .doc(_avatarData!.id)
            .update({'dynamics.basic.status': 'pending'});

        setState(() {
          _dynamicsData['basic']?['status'] = 'pending';
        });

        debugPrint('✅ Basic Dynamics Status auf pending gesetzt');
      } catch (e) {
        debugPrint('❌ Fehler beim Setzen Status: $e');
      }
    }

    try {
      final tr = Map<String, dynamic>.from(_avatarData!.training ?? {});
      tr['heroVideoUrl'] = url;
      debugPrint('🎯 _setHeroVideo -> $url');
      final updated = _avatarData!.copyWith(
        training: tr,
        updatedAt: DateTime.now(),
      );
      final ok = await _avatarService.updateAvatar(updated);
      debugPrint('🎯 updateAvatar returned $ok');
      if (ok) {
        _applyAvatar(updated);
        await _initInlineFromHero();
        if (!mounted) return;
        _showSystemSnack(
          context.read<LocalizationService>().t('avatars.details.heroVideoSet'),
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showSystemSnack(
        context.read<LocalizationService>().t(
          'avatars.details.setHeroVideoError',
          params: {'msg': '$e'},
        ),
      );
    }
  }

  Future<void> _clearInlinePlayer() async {
    try {
      await _inlineVideoController?.pause();
    } catch (_) {}
    try {
      await _inlineVideoController?.dispose();
    } catch (_) {}
    _inlineVideoController = null;
    if (mounted) setState(() {});
  }

  Future<void> _initInlineFromHero() async {
    final hero = _getHeroVideoUrl();
    debugPrint('🎬 _initInlineFromHero hero=$hero');
    if (hero == null || hero.isEmpty) {
      await _clearInlinePlayer();
      return;
    }
    // Immer neu initialisieren (nach Reload kann Controller null sein)
    // Frische Download-URL sichern (kann ablaufen)
    final fresh = await _refreshDownloadUrl(hero) ?? hero;
    debugPrint('🎬 _initInlineFromHero fresh=$fresh');
    try {
      await _clearInlinePlayer();
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(fresh));
      await ctrl.initialize();
      await ctrl.setLooping(false); // kein Looping in Großansicht
      // nicht auto-play; zeigt erstes Frame
      _inlineVideoController = ctrl;
      _currentInlineUrl = hero;
      debugPrint('✅ Hero-Video erfolgreich initialisiert');
      if (mounted) setState(() {});
    } catch (e) {
      // Bei Fehler: Controller freigeben und auf Thumbnail-Fallback lassen
      debugPrint('❌ Hero-Video init fehlgeschlagen: $e');
      await _clearInlinePlayer();
    }
  }

  // _deleteRemoteVideo ungenutzt entfernt

  // ============================================================================
  // ============================================================================

  // _videoThumbLocal ungenutzt entfernt

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

  Future<void> _playNetworkInline(String url) async {
    try {
      await _inlineVideoController?.dispose();
      final fresh = await _refreshDownloadUrl(url) ?? url;
      final controller = VideoPlayerController.networkUrl(Uri.parse(fresh));
      await controller.initialize();
      await controller.setLooping(false);
      controller.addListener(() async {
        try {
          final v = controller.value;
          if (v.isInitialized &&
              !v.isPlaying &&
              v.position >= v.duration &&
              v.duration > Duration.zero) {
            // Abspielende beendet → Inline-Player räumen, Thumbnail sichtbar
            await _clearInlinePlayer();
          }
        } catch (_) {}
      });
      await controller.play();
      if (!mounted) return;
      setState(() => _inlineVideoController = controller);
    } catch (e) {
      if (!mounted) return;
      _showSystemSnack(
        context.read<LocalizationService>().t(
          'avatars.details.videoLoadFailed',
        ),
      );
    }
  }

  // Lokales Video im großen Player abspielen
  Future<void> _playLocalInline(File file) async {
    try {
      await _inlineVideoController?.dispose();
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) return;
      setState(() => _inlineVideoController = controller);
    } catch (e) {
      if (!mounted) return;
      _showSystemSnack(
        context.read<LocalizationService>().t(
          'avatars.details.localVideoLoadFailed',
        ),
      );
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

  Future<void> _handleGenerateAvatar() async {
    if (_avatarData == null) return;
    if (_isGeneratingAvatar) return;
    setState(() => _isGeneratingAvatar = true);
    try {
      // Nur BitHuman verwenden
      final base = dotenv.env['BITHUMAN_BASE_URL']?.trim();
      if (base == null || base.isEmpty) {
        _showSystemSnack(
          context.read<LocalizationService>().t(
            'avatars.details.bithumanBaseUrlMissing',
          ),
        );
        return;
      }

      // Bildquelle (BitHuman)
      File? imageFile;
      if ((_profileLocalPath ?? '').isNotEmpty) {
        final f = File(_profileLocalPath!);
        if (await f.exists()) imageFile = f;
      }
      imageFile ??= await _downloadToTemp(
        _profileImageUrl ?? _avatarData!.avatarImageUrl ?? '',
        suffix: '.png',
      );
      if (!mounted) return;
      if (imageFile == null) {
        _showSystemSnack(
          context.read<LocalizationService>().t('avatars.details.noImageFound'),
        );
        return;
      }

      // Audioquelle (BitHuman)
      File? audioFile;
      String? audioUrl = _activeAudioUrl;
      if ((audioUrl == null || audioUrl.isEmpty) &&
          _avatarData!.audioUrls.isNotEmpty) {
        audioUrl = _avatarData!.audioUrls.first;
      }
      if (audioUrl == null || audioUrl.isEmpty) {
        if (!mounted) return;
        _showSystemSnack(
          context.read<LocalizationService>().t(
            'avatars.details.noAudioSample',
          ),
        );
        return;
      }
      audioFile = await _downloadToTemp(audioUrl, suffix: '.mp3');
      if (!mounted) return;
      if (audioFile == null) {
        _showSystemSnack(
          context.read<LocalizationService>().t(
            'avatars.details.audioLoadFailed',
          ),
        );
        return;
      }

      final locSvc = context.read<LocalizationService>();
      await _showBlockingProgress<void>(
        title: locSvc.t('avatars.details.generatingAvatarTitle'),
        message: locSvc.t('avatars.details.processingImageAudio'),
        task: () async {
          // 1) Figure sicherstellen (nur wenn noch nicht vorhanden)
          String? figureId;
          String? modelHash;
          try {
            final bh =
                _avatarData?.training?['bithuman'] as Map<String, dynamic>?;
            figureId = (bh?['figureId'] as String?)?.trim();
            modelHash = (bh?['modelHash'] as String?)?.trim();
          } catch (_) {}
          if ((figureId == null || figureId.isEmpty) && imageFile != null) {
            final figUri = Uri.parse('$base/figure/create');
            final m = http.MultipartRequest('POST', figUri);
            m.files.add(
              await http.MultipartFile.fromPath('image', imageFile.path),
            );
            final fRes = await m.send();
            if (fRes.statusCode >= 200 && fRes.statusCode < 300) {
              final body = await fRes.stream.bytesToString();
              final data = jsonDecode(body) as Map<String, dynamic>;
              figureId = (data['figure_id'] as String?)?.trim();
              modelHash = (data['runtime_model_hash'] as String?)?.trim();
              // in Firestore speichern
              final tr = Map<String, dynamic>.from(_avatarData!.training ?? {});
              final bh = Map<String, dynamic>.from(tr['bithuman'] ?? {});
              if ((figureId ?? '').isNotEmpty) bh['figureId'] = figureId;
              if ((modelHash ?? '').isNotEmpty) bh['modelHash'] = modelHash;
              tr['bithuman'] = bh;
              final updated = _avatarData!.copyWith(
                training: tr,
                updatedAt: DateTime.now(),
                role: _role ?? _avatarData!.role,
              );
              final ok = await _avatarService.updateAvatar(updated);
              if (ok) _applyAvatar(updated);
            } else {
              final b = await fRes.stream.bytesToString();
              throw Exception(
                'Figure create fehlgeschlagen: ${fRes.statusCode} ${b.isNotEmpty ? b : ''}',
              );
            }
          }

          final uri = Uri.parse('$base/generate-avatar');
          final req = http.MultipartRequest('POST', uri);
          req.files.add(
            await http.MultipartFile.fromPath('image', imageFile!.path),
          );
          req.files.add(
            await http.MultipartFile.fromPath('audio', audioFile!.path),
          );
          if ((figureId ?? '').isNotEmpty) req.fields['figure_id'] = figureId!;
          if ((modelHash ?? '').isNotEmpty) {
            req.fields['runtime_model_hash'] = modelHash!;
          }
          final streamed = await req.send();
          if (streamed.statusCode >= 200 && streamed.statusCode < 300) {
            final bytes = await streamed.stream.toBytes();
            final dir = await getTemporaryDirectory();
            final out = File(
              '${dir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.mp4',
            );
            await out.writeAsBytes(bytes, flush: true);
            // Sofort lokal anzeigen
            await _playLocalInline(out);
            // Hochladen
            final path =
                'avatars/${_avatarData!.id}/videos/${DateTime.now().millisecondsSinceEpoch}_gen.mp4';
            final url = await FirebaseStorageService.uploadVideo(
              out,
              customPath: path,
            );
            if (url != null) {
              setState(() {
                _videoUrls.insert(0, url);
              });
              // Sofort persistieren (Firestore aktualisieren)
              await _persistTextFileUrls();
            }
            if (!mounted) return;
            _showSystemSnack(
              context.read<LocalizationService>().t(
                'avatars.details.avatarVideoCreated',
              ),
            );
          } else {
            final body = await streamed.stream.bytesToString();
            if (!mounted) return;
            _showSystemSnack(
              'Generierung fehlgeschlagen: ${streamed.statusCode} ${body.isNotEmpty ? body : ''}',
            );
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      _showSystemSnack(
        context.read<LocalizationService>().t(
          'avatars.details.errorGeneric',
          params: {'msg': '$e'},
        ),
      );
    } finally {
      if (mounted) setState(() => _isGeneratingAvatar = false);
    }
  }

  Future<VideoPlayerController?> _createThumbController(String url) async {
    try {
      final fresh = await _refreshDownloadUrl(url) ?? url;
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(fresh));
      await ctrl.initialize();
      await ctrl.setLooping(false);
      // Nicht abspielen - nur erstes Frame zeigen
      return ctrl;
    } catch (e) {
      debugPrint('🎬 Thumb controller error: $e');
      return null;
    }
  }

  Future<VideoPlayerController?> _createLocalThumbController(
    String filePath,
  ) async {
    try {
      final ctrl = VideoPlayerController.file(File(filePath));
      await ctrl.initialize();
      await ctrl.setLooping(false);
      // Nicht abspielen - nur erstes Frame zeigen
      return ctrl;
    } catch (e) {
      debugPrint('🎬 Local thumb controller error: $e');
      return null;
    }
  }

  Future<Uint8List?> _thumbnailForRemote(String url) async {
    try {
      debugPrint('🎬 start thumbnail for $url');
      if (_videoThumbCache.containsKey(url)) return _videoThumbCache[url];
      debugPrint('🎬 cache miss -> $url');
      var effectiveUrl = url;
      debugPrint('🎬 Thumbnail für: $effectiveUrl');
      var res = await http.get(Uri.parse(effectiveUrl));
      debugPrint('🎬 Response: ${res.statusCode}');
      if (res.statusCode != 200) {
        final fresh = await _refreshDownloadUrl(url);
        debugPrint('🎬 refresh download -> $fresh');
        if (fresh != null) {
          effectiveUrl = fresh;
          res = await http.get(Uri.parse(effectiveUrl));
          debugPrint('🎬 Fresh Response: ${res.statusCode}');
          if (res.statusCode != 200) return null;
          // Cache frische URL direkt ablegen, damit Thumbs stabil sind
          final idx = _videoUrls.indexOf(url);
          if (idx >= 0) _videoUrls[idx] = fresh;
          // kein persist hier, damit UI flott bleibt; persist passiert beim Speichern
        } else {
          debugPrint('🎬 Refresh failed');
          return null;
        }
      }
      final tmp = await File(
        '${Directory.systemTemp.path}/thumb_${DateTime.now().microsecondsSinceEpoch}.mp4',
      ).create();
      await tmp.writeAsBytes(res.bodyBytes);
      final data = await vt.VideoThumbnail.thumbnailData(
        video: tmp.path,
        imageFormat: vt.ImageFormat.JPEG,
        maxWidth: 360,
        quality: 60,
      );
      debugPrint('🎬 Thumbnail data: ${data?.length ?? 0} bytes');
      if (data != null) _videoThumbCache[url] = data;
      try {
        // optional: Tempdatei löschen
        await tmp.delete();
      } catch (_) {}
      return data;
    } catch (e) {
      debugPrint('🎬 Thumbnail error: $e');
      return null;
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

  // _thumbnailForLocal ungenutzt entfernt
  // _bigMediaButton entfällt im neuen Layout

  Future<File?> _cropToPortrait916(File input) async {
    try {
      final bytes = await input.readAsBytes();
      final cropController = cyi.CropController();
      Uint8List? result;

      if (!mounted) return null;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          backgroundColor: Colors.black,
          clipBehavior: Clip.hardEdge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: LayoutBuilder(
            builder: (dCtx, _) {
              final sz = MediaQuery.of(dCtx).size;
              final double dlgW = (sz.width * 0.9).clamp(320.0, 900.0);
              final double dlgH = (sz.height * 0.9).clamp(480.0, 1200.0);
              return SizedBox(
                width: dlgW,
                height: dlgH,
                child: Column(
                  children: [
                    Expanded(
                      child: cyi.Crop(
                        controller: cropController,
                        image: bytes,
                        aspectRatio: 9 / 16,
                        withCircleUi: false,
                        baseColor: Colors.black,
                        maskColor: Colors.black38,
                        onCropped: (cropped) {
                          if (cropped is cyi.CropSuccess) {
                            result = cropped.croppedImage;
                          }
                          Navigator.pop(ctx);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                result = null;
                                Navigator.pop(ctx);
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
                                  color: Colors.grey.shade800,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  child: Center(
                                    child: Text(
                                      'Abbrechen',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                cropController.crop();
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
                                    colors: [
                                      Color(0xFFE91E63),
                                      AppColors.lightBlue,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  child: Center(
                                    child: Text(
                                      'Zuschneiden',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
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
              );
            },
          ),
        ),
      );

      if (result == null) return null;
      final dir = await getTemporaryDirectory();
      final tmp = await File(
        '${dir.path}/crop_${DateTime.now().millisecondsSinceEpoch}.png',
      ).create(recursive: true);
      await tmp.writeAsBytes(result!, flush: true);
      return tmp;
    } catch (_) {
      return null;
    }
  }

  /// Gemeinsame Nachbearbeitung nach einem erfolgreichen Recrop‑Upload
  Future<String> _handleRecropFinalize(String oldUrl, String newUrl) async {
    // ERST: Altes thumbUrl aus Firestore holen UND alte Files aus Storage löschen
    // (BEVOR Firestore geändert wird, wegen Storage Rules!)
    String? oldThumbUrl;
    String? savedOriginalFileName;
    try {
      final avatarId = _avatarData!.id;
      final qs = await FirebaseFirestore.instance
          .collection('avatars')
          .doc(avatarId)
          .collection('images')
          .where('url', isEqualTo: oldUrl)
          .get();
      debugPrint('RECROP: Query ergab ${qs.docs.length} Dokumente');
      for (final d in qs.docs) {
        final data = d.data();
        debugPrint('RECROP: Dokument-Daten: ${data.keys.join(", ")}');
        oldThumbUrl = (data['thumbUrl'] as String?);
        savedOriginalFileName = (data['originalFileName'] as String?);
      }

      // Timeline-Daten vorbereiten (OHNE setState - kein UI rebuild!)
      final oldDuration = _imageDurations[oldUrl];
      final oldActive = _imageActive[oldUrl];
      final oldExplorerVisible = _imageExplorerVisible[oldUrl];

      if (oldDuration != null) {
        _imageDurations[newUrl] = oldDuration;
      }
      if (oldActive != null) {
        _imageActive[newUrl] = oldActive;
      }
      if (oldExplorerVisible != null) {
        _imageExplorerVisible[newUrl] = oldExplorerVisible;
      }

      // Altes Image aus Storage löschen (inkl. Thumb)
      final originalPath = FirebaseStorageService.pathFromUrl(oldUrl);
      if (originalPath.isNotEmpty) {
        await FirebaseStorageService.deleteFile(oldUrl);
      }
      if (oldThumbUrl != null && oldThumbUrl.isNotEmpty) {
        await FirebaseStorageService.deleteFile(oldThumbUrl);
      }

      // Firestore updaten (neue URL + ggf. originalFileName beibehalten)
      final qs2 = await FirebaseFirestore.instance
          .collection('avatars')
          .doc(_avatarData!.id)
          .collection('images')
          .where('url', isEqualTo: oldUrl)
          .get();
      for (final d in qs2.docs) {
        await d.reference.update({
          'url': newUrl,
          if (savedOriginalFileName != null)
            'originalFileName': savedOriginalFileName,
        });
      }

      if (mounted) {
        // Lokale Listen/State aktualisieren
        _imageUrls.remove(oldUrl);
        _imageUrls.add(newUrl);
        if (_profileImageUrl == oldUrl) {
          _profileImageUrl = newUrl;
        }
        // originalFileName-Mapping im UI aktualisieren
        if (savedOriginalFileName != null &&
            savedOriginalFileName.isNotEmpty) {
          _mediaOriginalNames.remove(oldUrl);
          _mediaOriginalNames[newUrl] = savedOriginalFileName;
        }
      }
    } catch (e) {
      debugPrint('RECROP: Fehler bei Finalisierung: $e');
    }

    // CRITICAL: imageUrls & Hero-Image auch im Avatar-Dokument speichern,
    // damit nach erneutem Öffnen keine alten/broken URLs verwendet werden.
    try {
      await _saveHeroImageAndUrls();
      debugPrint(
        'RECROP: _saveHeroImageAndUrls nach Finalisierung ausgeführt (imageUrls persistent).',
      );
      if (_avatarData != null) {
        await _loadMediaOriginalNames(_avatarData!.id);
        debugPrint(
          'RECROP: _loadMediaOriginalNames nach Finalisierung ausgeführt (Mapping URL → originalFileName aktualisiert).',
        );
      }
    } catch (e) {
      debugPrint('RECROP: Fehler bei Persistierung von Hero/imageUrls: $e');
    }

    return newUrl;
  }

  /// Web‑Variante: interaktives 9:16‑Cropping auf Basis von Bytes
  Future<Uint8List?> _cropBytesToPortraitWeb(Uint8List input) async {
    try {
      // Versuche, das Bild vorab in ein kompatibles Format (JPEG) zu bringen.
      // WICHTIG: HEIC u.ä. werden vom image-Package nicht unterstützt → dann abbrechen.
      Uint8List effectiveBytes;
      img.Image? decoded;
      try {
        decoded = img.decodeImage(input);
      } catch (_) {
        decoded = null;
      }
      if (decoded == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Dieses Bildformat wird im Web-Cropping nicht unterstützt (z.B. HEIC). '
                'Bitte JPEG/PNG verwenden oder mobil zuschneiden.',
              ),
            ),
          );
        }
        return null;
      }

      // Leicht verkleinern, damit der Crop-Dialog schneller reagiert
      const int maxSize = 2048;
      img.Image resized = decoded;
      if (decoded.width > maxSize || decoded.height > maxSize) {
        resized = img.copyResize(
          decoded,
          width: decoded.width > decoded.height ? maxSize : null,
          height: decoded.height >= decoded.width ? maxSize : null,
        );
      }
      effectiveBytes = Uint8List.fromList(
        img.encodeJpg(resized, quality: 95),
      );

      final cropController = cyi.CropController();
      Uint8List? result;

      if (!mounted) return null;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          backgroundColor: Colors.black,
          clipBehavior: Clip.hardEdge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: LayoutBuilder(
            builder: (dCtx, _) {
              final sz = MediaQuery.of(dCtx).size;
              final double dlgW = (sz.width * 0.9).clamp(320.0, 900.0);
              final double dlgH = (sz.height * 0.9).clamp(480.0, 1200.0);
              return SizedBox(
                width: dlgW,
                height: dlgH,
                child: Column(
                  children: [
                    Expanded(
                      child: cyi.Crop(
                        controller: cropController,
                        image: effectiveBytes,
                        aspectRatio: 9 / 16,
                        withCircleUi: false,
                        baseColor: Colors.black,
                        maskColor: Colors.black38,
                        onCropped: (cropped) {
                          if (cropped is cyi.CropSuccess) {
                            result = cropped.croppedImage;
                          }
                          Navigator.pop(ctx);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                result = null;
                                Navigator.pop(ctx);
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
                                  color: Colors.grey.shade800,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  child: Center(
                                    child: Text(
                                      'Abbrechen',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                cropController.crop();
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
                                  gradient: Theme.of(dCtx)
                                      .extension<AppGradients>()!
                                      .magentaBlue,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  child: Center(
                                    child: Text(
                                      'Zuschneiden',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          ),
        ),
      );

      return result;
    } catch (_) {
      return null;
    }
  }

  Future<void> _onAddImages() async {
    debugPrint('🖼️ _onAddImages START');

    // Web: eigener Pfad mit FilePicker + Byte-Upload (kein dart:io / ImagePicker)
    if (kIsWeb) {
      try {
        if (_avatarData == null) {
          debugPrint('🖼️ Web: _avatarData == null → Abbruch');
          return;
        }

        debugPrint('🖼️ Web: Öffne FilePicker für Bilder (Mehrfachauswahl)');
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: true,
          withData: true,
        );

        if (result == null || result.files.isEmpty) {
          debugPrint('🖼️ Web: keine Bilder ausgewählt');
          return;
        }

        setState(() => _isDirty = true);
        final String avatarId = _avatarData!.id;
        int uploadedCount = 0;

        for (int i = 0; i < result.files.length; i++) {
          final file = result.files[i];
          final Uint8List? bytes = file.bytes;
          if (bytes == null) {
            debugPrint('🖼️ Web: Bild ${i + 1} ohne Bytes → skip');
            continue;
          }

          final String originalName = file.name;
          String ext = p.extension(originalName).toLowerCase();
          if (ext.isEmpty ||
              (ext != '.png' && ext != '.jpg' && ext != '.jpeg' && ext != '.webp')) {
            ext = '.jpg';
          }
          final safeName =
              originalName.isEmpty ? 'image_$i$ext' : originalName;

          // Interaktives Cropping wie auf iPhone, aber auf Bytes‑Basis
          Uint8List? uploadBytes = await _cropBytesToPortraitWeb(bytes);
          if (uploadBytes == null) {
            debugPrint('🖼️ Web: Cropping abgebrochen → Bild übersprungen');
            continue;
          }

          final String path =
              'avatars/$avatarId/images/${DateTime.now().millisecondsSinceEpoch}_web$i$ext';
          debugPrint('🖼️ Web: Starte Upload Bild ${i + 1}: $path');

          final url = await FirebaseStorageService.uploadImageBytes(
            uploadBytes,
            fileName: safeName,
            customPath: path,
          );
          debugPrint('🖼️ Web: Upload Bild ${i + 1} Ergebnis: $url');

          if (url != null) {
            uploadedCount++;
            if (!mounted) return;
            setState(() {
              _imageUrls.insert(0, url);
              _imageDurations[url] = 60; // Default 1 Minute
              _imageActive[url] = true; // Default: aktiv
              if (_profileImageUrl == null || _profileImageUrl!.isEmpty) {
                _setHeroImage(url);
              }
            });

            // Sofort persistieren (Firestore aktualisieren)
            await _persistTextFileUrls();
            // Timeline-Daten speichern
            await _saveTimelineData();
            // Media-Doc anlegen → triggert Thumb-Generierung
            await _addMediaDoc(
              url,
              AvatarMediaType.image,
              originalFileName: originalName,
            );
          } else {
            debugPrint('❌ Web: Bild ${i + 1} Upload fehlgeschlagen!');
          }
        }

        if (mounted && uploadedCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$uploadedCount Bilder erfolgreich hochgeladen',
              ),
            ),
          );
        }
      } catch (e, stack) {
        debugPrint('❌ Web: Fehler in _onAddImages: $e');
        debugPrint('Stack: $stack');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Fehler beim Bild-Upload im Web: $e'),
            ),
          );
        }
      }
      return;
    }

    ImageSource? source;
    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      source = ImageSource.gallery; // Kamera nicht unterstützen auf Desktop
      debugPrint('🖼️ Platform: Desktop → Galerie');
    } else {
      source = await _chooseSource(
        context.read<LocalizationService>().t(
          'avatars.details.chooseImageSourceTitle',
        ),
      );
      debugPrint('🖼️ Mobile source gewählt: $source');
      if (source == null) {
        debugPrint('🖼️ Keine Quelle gewählt → Abbruch');
        return;
      }
    }
    if (source == ImageSource.gallery) {
      debugPrint('🖼️ Öffne Galerie-Picker (Multi)...');
      final files = await _picker.pickMultiImage(
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
      debugPrint('🖼️ ${files.length} Bilder ausgewählt');

      if (files.isNotEmpty && _avatarData != null) {
        setState(() => _isDirty = true);
        final String avatarId = _avatarData!.id;
        debugPrint('🖼️ Starte Upload von ${files.length} Bildern...');

        for (int i = 0; i < files.length; i++) {
          debugPrint(
            '🖼️ Verarbeite Bild ${i + 1}/${files.length}: ${files[i].path}',
          );
          File f = File(files[i].path);
          // Interaktives Cropping 9:16
          final cropped = await _cropToPortrait916(f);
          if (cropped != null) {
            // Nutzer hat zugeschnitten → diesen Crop übernehmen, KEIN Auto‑Crop mehr
            f = cropped;
          } else {
            // Nur wenn kein manueller Crop erfolgte: Fallback 9:16‑Auto‑Crop
            try {
              final bytes = await f.readAsBytes();
              final src = img.decodeImage(bytes);
              if (src != null) {
                final int w = src.width;
                final int h = src.height;
                final double targetRatio = 9 / 16; // Portrait 9:16
                double curRatio = w / h;
                int cw = w;
                int ch = h;
                if ((curRatio - targetRatio).abs() > 0.01) {
                  if (curRatio > targetRatio) {
                    // zu breit → links/rechts beschneiden
                    cw = (h * targetRatio).round();
                  } else {
                    // zu hoch → oben/unten beschneiden
                    ch = (w / targetRatio).round();
                  }
                  final int x = ((w - cw) / 2).round();
                  final int y = ((h - ch) / 2).round();
                  final croppedAuto = img.copyCrop(
                    src,
                    x: x,
                    y: y,
                    width: cw,
                    height: ch,
                  );
                  final jpg = img.encodeJpg(croppedAuto, quality: 90);
                  final tmp = await File(
                    '${f.path}.portrait.jpg',
                  ).create(recursive: true);
                  await tmp.writeAsBytes(jpg, flush: true);
                  f = tmp;
                }
              }
            } catch (_) {}
          }
          // Vorschau sofort auf lokales, gecropptes Bild setzen
          if (mounted) {
            setState(() {
              _profileLocalPath = f.path;
            });
          }

          /// Liefert den exakten Options-Namen aus [_countryOptions],
          /// wenn der übergebene Wert entweder Landesname oder ISO-Code ist.
          // ignore: unused_element
          String? normalizeCountryOption(String value) {
            if (value.isEmpty) return null;
            // Map: Name/Code vergleichen, korrekten Namen zurückgeben
            for (final entry in countries) {
              final name = (entry['name'] ?? '').toString().trim();
              final code = (entry['code'] ?? '').toString().trim();
              if (name.isEmpty) continue;
              if (value.toLowerCase() == name.toLowerCase() ||
                  value.toLowerCase() == code.toLowerCase()) {
                return name;
              }
            }
            // Falls kein direkter Treffer, aber Liste enthält den String exakt
            if (_countryOptions.contains(value)) return value;
            return null;
          }

          // Endung passend zur Datei wählen (png bei Cropping, sonst jpg)
          String ext = p.extension(f.path).toLowerCase();
          if (ext.isEmpty ||
              (ext != '.png' && ext != '.jpg' && ext != '.jpeg')) {
            ext = '.jpg';
          }
          final String path =
              'avatars/$avatarId/images/${DateTime.now().millisecondsSinceEpoch}_$i$ext';
          debugPrint('🖼️ Starte Upload Bild ${i + 1}: $path');
          final url = await FirebaseStorageService.uploadImage(
            f,
            customPath: path,
          );
          debugPrint('🖼️ Upload Bild ${i + 1} Ergebnis: $url');

          if (url != null) {
            if (!mounted) return;
            setState(() {
              _imageUrls.insert(0, url);
              _imageDurations[url] = 60; // Default 1 Minute
              _imageActive[url] = true; // Default: aktiv
              if (_profileImageUrl == null || _profileImageUrl!.isEmpty) {
                _setHeroImage(url);
              }
              _profileLocalPath = null; // nach Upload auf Remote wechseln
            });
            debugPrint(
              '🖼️ Bild ${i + 1} zu Liste hinzugefügt, persistiere...',
            );
            // Sofort persistieren (Firestore aktualisieren)
            await _persistTextFileUrls();
            // WICHTIG: Timeline-Daten speichern (incl. Duration!)
            await _saveTimelineData();
            // Media-Doc anlegen → triggert Thumb-Generierung
            final origName = files[i].name;
            await _addMediaDoc(
              url,
              AvatarMediaType.image,
              originalFileName: origName,
            );
            debugPrint('🖼️ Bild ${i + 1} erfolgreich gespeichert!');
          } else {
            debugPrint('❌ Bild ${i + 1} Upload fehlgeschlagen!');
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${files.length} Bilder erfolgreich hochgeladen'),
            ),
          );
        }
      } else {
        debugPrint('🖼️ Keine Bilder ausgewählt oder Avatar-Daten fehlen');
      }
    } else {
      final x = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
      if (x != null && _avatarData != null) {
        setState(() => _isDirty = true);
        final String avatarId = _avatarData!.id;
        File f = File(x.path);
        final cropped = await _cropToPortrait916(f);
        if (cropped != null) {
          f = cropped;
        }
        // Sofort lokale Vorschau anzeigen
        if (mounted) {
          setState(() {
            _profileLocalPath = f.path;
          });
        }
        String ext = p.extension(f.path).toLowerCase();
        if (ext.isEmpty || (ext != '.png' && ext != '.jpg' && ext != '.jpeg')) {
          ext = '.jpg';
        }
        final String path =
            'avatars/$avatarId/images/${DateTime.now().millisecondsSinceEpoch}_cam$ext';
        final url = await FirebaseStorageService.uploadImage(
          f,
          customPath: path,
        );
        if (url != null) {
          if (!mounted) return;
          setState(() {
            _imageUrls.insert(0, url);
            _imageDurations[url] = 60; // Default 1 Minute
            if (_profileImageUrl == null || _profileImageUrl!.isEmpty) {
              _setHeroImage(url);
            }
            _profileLocalPath = null;
          });
          // Sofort persistieren (Firestore aktualisieren)
          await _persistTextFileUrls();
          // WICHTIG: Timeline-Daten speichern (incl. Duration!)
          await _saveTimelineData();
          // Media-Doc anlegen → triggert Thumb-Generierung
          final origName = x.name;
          await _addMediaDoc(
            url,
            AvatarMediaType.image,
            originalFileName: origName,
          );
        }
      }
    }
  }

  Future<void> _onAddVideos() async {
    debugPrint('🎬 _onAddVideos START');

    try {
      // Direkt FilePicker für Desktop & Web (Mehrfachauswahl)
      if (kIsWeb ||
          Platform.isMacOS ||
          Platform.isWindows ||
          Platform.isLinux) {
        debugPrint('🎬 Platform: Desktop/Web → Galerie (Mehrfachauswahl)');
        // Galerie: Mehrfachauswahl mit FilePicker
        debugPrint('🎬 Öffne Galerie-Picker (Mehrfachauswahl)...');
        final result = await FilePicker.platform.pickFiles(
          type: FileType.video,
          allowMultiple: true,
        );

        if (result == null || result.files.isEmpty) {
          debugPrint('🎬 Keine Videos ausgewählt');
          return;
        }

        setState(() => _isDirty = true);
        final String avatarId = _avatarData!.id;
        int baseTimestamp = DateTime.now().millisecondsSinceEpoch;

        for (int i = 0; i < result.files.length; i++) {
          final file = result.files[i];
          if (file.path == null) continue;

          try {
            final File f = File(file.path!);
            final String origName = p.basename(file.path!);
            final timestamp = baseTimestamp + i;
            final String path =
                'avatars/$avatarId/videos/${timestamp}_$origName';

            debugPrint(
              '🎬 Starte Upload ${i + 1}/${result.files.length}: $path',
            );
            final url = await FirebaseStorageService.uploadVideo(
              f,
              customPath: path,
            );

            if (url != null) {
              if (!mounted) return;
              final hasNoHeroVideo =
                  _getHeroVideoUrl() == null || _getHeroVideoUrl()!.isEmpty;
              setState(() {
                _videoUrls.add(url);
              });
              await _persistTextFileUrls();
              await _addMediaDoc(
                url,
                AvatarMediaType.video,
                originalFileName: origName,
              );
              // Nur wenn noch KEIN Hero-Video existiert → erstes Video als Hero setzen
              if (hasNoHeroVideo && _videoUrls.length == 1) {
                await _setHeroVideo(url);
              }
            } else {
              debugPrint('❌ Upload ${i + 1} fehlgeschlagen: url ist null');
            }
          } catch (e) {
            debugPrint('❌ Fehler bei Video ${i + 1}: $e');
          }
        }

        if (mounted) {
          final scaffoldMessenger = ScaffoldMessenger.of(context);
          // Timeline neu laden für korrekte Anzeige
          await _loadTimelineData(_avatarData!.id);

          // UI aktualisieren, damit Hero-Stern angezeigt wird
          setState(() {});

          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(
                '${result.files.length} Videos erfolgreich hochgeladen',
              ),
            ),
          );
        }
      } else {
        // Mobile: Dialog für Kamera/Galerie
        debugPrint('🎬 Mobile: Zeige Quellen-Dialog');
        final source = await _chooseSource('Videoquelle wählen');
        debugPrint('🎬 Mobile source gewählt: $source');

        if (source == null) {
          debugPrint('🎬 Keine Quelle gewählt → Abbruch');
          return;
        }

        if (source == ImageSource.gallery) {
          // Mobile Galerie: Mehrfachauswahl
          debugPrint('🎬 Mobile Galerie: Mehrfachauswahl');
          final result = await FilePicker.platform.pickFiles(
            type: FileType.video,
            allowMultiple: true,
          );

          if (result == null || result.files.isEmpty) {
            debugPrint('🎬 Keine Videos ausgewählt');
            return;
          }

          setState(() => _isDirty = true);
          final String avatarId = _avatarData!.id;
          int baseTimestamp = DateTime.now().millisecondsSinceEpoch;

          for (int i = 0; i < result.files.length; i++) {
            final file = result.files[i];
            if (file.path == null) continue;

            try {
              final File f = File(file.path!);
              final String origName = p.basename(file.path!);
              final timestamp = baseTimestamp + i;
              final String path =
                  'avatars/$avatarId/videos/${timestamp}_$origName';

              debugPrint(
                '🎬 Mobile: Starte Upload ${i + 1}/${result.files.length}: $path',
              );
              final url = await FirebaseStorageService.uploadVideo(
                f,
                customPath: path,
              );

              if (url != null) {
                if (!mounted) return;
                final hasNoHeroVideo =
                    _getHeroVideoUrl() == null || _getHeroVideoUrl()!.isEmpty;
                setState(() {
                  _videoUrls.add(url);
                });
                await _persistTextFileUrls();
                await _addMediaDoc(
                  url,
                  AvatarMediaType.video,
                  originalFileName: origName,
                );
                // Nur wenn noch KEIN Hero-Video existiert → erstes Video als Hero setzen
                if (hasNoHeroVideo && _videoUrls.length == 1) {
                  await _setHeroVideo(url);
                }
              }
            } catch (e) {
              debugPrint('❌ Mobile: Fehler bei Video ${i + 1}: $e');
            }
          }

          if (mounted) {
            final scaffoldMessenger = ScaffoldMessenger.of(context);
            // Timeline neu laden für korrekte Anzeige
            await _loadTimelineData(_avatarData!.id);

            // UI aktualisieren, damit Hero-Stern angezeigt wird
            setState(() {});

            scaffoldMessenger.showSnackBar(
              SnackBar(
                content: Text(
                  '${result.files.length} Videos erfolgreich hochgeladen',
                ),
              ),
            );
          }
        } else {
          // Mobile Kamera: Nur 1 Video
          debugPrint('🎬 Öffne Kamera...');
          final x = await _picker.pickVideo(
            source: ImageSource.camera,
            maxDuration: const Duration(minutes: 5),
          );
          debugPrint('🎬 Video aufgenommen: ${x?.path}');

          if (x != null && _avatarData != null) {
            setState(() => _isDirty = true);
            final String avatarId = _avatarData!.id;
            final File f = File(x.path);
            final String path =
                'avatars/$avatarId/videos/${DateTime.now().millisecondsSinceEpoch}_cam.mp4';

            debugPrint('🎬 Starte Upload: $path');
            final url = await FirebaseStorageService.uploadVideo(
              f,
              customPath: path,
            );
            debugPrint('🎬 Upload abgeschlossen: $url');

            if (url != null) {
              if (!mounted) return;
              final hasNoHeroVideo =
                  _getHeroVideoUrl() == null || _getHeroVideoUrl()!.isEmpty;
              setState(() {
                _videoUrls.add(url);
              });
              await _persistTextFileUrls();
              final origName = x.name;
              await _addMediaDoc(
                url,
                AvatarMediaType.video,
                originalFileName: origName,
              );
              // Nur wenn noch KEIN Hero-Video existiert → erstes Video als Hero setzen
              if (hasNoHeroVideo && _videoUrls.length == 1) {
                await _setHeroVideo(url);
              }

              if (mounted) {
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                // Timeline neu laden für korrekte Anzeige
                await _loadTimelineData(_avatarData!.id);

                // UI aktualisieren, damit Hero-Stern angezeigt wird
                setState(() {});

                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('Video erfolgreich hochgeladen'),
                  ),
                );
              }
            } else {
              debugPrint('❌ Upload fehlgeschlagen: url ist null');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Video-Upload fehlgeschlagen')),
                );
              }
            }
          } else {
            debugPrint('🎬 Kein Video aufgenommen oder Avatar-Daten fehlen');
          }
        }
      }
    } catch (e, stack) {
      debugPrint('❌ FEHLER bei Video-Upload: $e');
      debugPrint('Stack: $stack');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler beim Video-Upload: $e')));
      }
    }
  }

  Future<void> _onAddTexts() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'md', 'rtf'],
      allowMultiple: true,
    );
    if (result != null) {
      setState(() {
        for (final f in result.files) {
          if (f.path != null) _newTextFiles.add(File(f.path!));
        }
        _updateDirty();
      });
    }
  }

  Future<void> _onAddAudio() async {
    final locSvc = context.read<LocalizationService>();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'wav', 'aac'],
      allowMultiple: true,
    );
    if (result != null && _avatarData != null) {
      final String avatarId = _avatarData!.id;
      final List<String> uploaded = [];
      final progress = ValueNotifier<double>(0.0);
      await _showBlockingProgress<void>(
        title: locSvc.t('avatars.details.uploadAudioTitle'),
        message: result.files.length == 1
            ? locSvc.t(
                'avatars.details.fileSavingMessage',
                params: {'name': result.files.first.name},
              )
            : locSvc.t(
                'avatars.details.filesSavingMessage',
                params: {'count': '${result.files.length}'},
              ),
        progress: progress,
        task: () async {
          for (int i = 0; i < result.files.length; i++) {
            final sel = result.files[i];
            if (sel.path == null) continue;
            final file = File(sel.path!);
            final String base = p.basename(file.path);
            final String audioPath =
                'avatars/$avatarId/audio/${DateTime.now().millisecondsSinceEpoch}_$i$base';
            final url = await FirebaseStorageService.uploadWithProgress(
              file,
              'audio',
              customPath: audioPath,
              onProgress: (v) {
                // Multi-Datei Fortschritt
                final perFileWeight = 1.0 / result.files.length;
                progress.value = (i * perFileWeight) + (v * perFileWeight);
              },
            );
            if (url != null) {
              uploaded.add(url);
              // Media-Doc anlegen mit originalFileName + voiceClone Flag
              final origName = sel.name;
              await _addMediaDoc(
                url,
                AvatarMediaType.audio,
                originalFileName: origName,
                voiceClone: true, // Voice Clone Audio
              );
            }
          }

          if (uploaded.isNotEmpty) {
            if (!mounted) return;
            // Lokalen State aktualisieren
            setState(() {
              final current = List<String>.from(_avatarData!.audioUrls);
              current.addAll(uploaded);
              _avatarData = _avatarData!.copyWith(audioUrls: current);
              _activeAudioUrl ??= uploaded.first;
            });

            // Sofort persistent speichern (nur Audio-URLs, keine weiteren Felder anfassen)
            final updated = _avatarData!.copyWith(
              audioUrls: List<String>.from(_avatarData!.audioUrls),
              updatedAt: DateTime.now(),
            );
            final ok = await _avatarService.updateAvatar(updated);
            if (ok) _applyAvatar(updated);
          }
        },
      );

      if (!mounted) return;
      if (uploaded.isNotEmpty) {
        _showSystemSnack(
          uploaded.length == 1
              ? locSvc.t('avatars.details.audioUploadedSingle')
              : locSvc.t(
                  'avatars.details.audioUploadedMulti',
                  params: {'count': '${uploaded.length}'},
                ),
        );
      }
    }
  }

  Future<ImageSource?> _chooseSource(String title) async {
    return await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(
                context.read<LocalizationService>().t(
                  'avatars.details.galleryTitle',
                ),
              ),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: Text(
                context.read<LocalizationService>().t(
                  'avatars.details.cameraTitle',
                ),
              ),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildInputFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Vorname (Pflichtfeld) + isPublic Toggle
        Row(
          children: [
            Expanded(
              child: CustomTextField(
                label: context.read<LocalizationService>().t(
                  'avatars.details.firstNameLabel',
                ),
                controller: _firstNameController,
                hintText: context.read<LocalizationService>().t(
                  'avatars.details.firstNameHint',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return context.read<LocalizationService>().t(
                      'avatars.details.firstNameRequired',
                    );
                  }
                  return null;
                },
                onChanged: (_) => _updateDirty(),
              ),
            ),
            const SizedBox(width: 8),
            // firstNamePublic Toggle
            Tooltip(
              message: (_avatarData?.firstNamePublic ?? false)
                  ? 'Wird im Chat angezeigt'
                  : 'Wird nicht im Chat angezeigt',
              child: GestureDetector(
                onTap: () async {
                  final newValue = !(_avatarData?.firstNamePublic ?? false);
                  if (_avatarData != null) {
                    setState(() {
                      _avatarData = _avatarData!.copyWith(
                        firstNamePublic: newValue,
                      );
                    });

                    // Sofort speichern
                    final success = await _avatarService.updateAvatar(
                      _avatarData!,
                    );
                    if (success && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: Colors.white,
                          content: ShaderMask(
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (bounds) => Theme.of(context)
                                .extension<AppGradients>()!
                                .magentaBlue
                                .createShader(bounds),
                            child: Text(
                              newValue
                                  ? '✓ Vorname wird im Chat angezeigt'
                                  : '✓ Vorname wird nicht im Chat angezeigt',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: (_avatarData?.firstNamePublic ?? false)
                        ? const LinearGradient(
                            colors: [
                              Color(0xFFE91E63),
                              AppColors.lightBlue,
                              Color(0xFF00E5FF),
                            ],
                          )
                        : null,
                    color: (_avatarData?.firstNamePublic ?? false)
                        ? null
                        : Colors.white.withValues(alpha: 0.1),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    (_avatarData?.firstNamePublic ?? false)
                        ? Icons.visibility
                        : Icons.visibility_off,
                    size: 24,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Spitzname (optional) + nicknamePublic Toggle
        Row(
          children: [
            Expanded(
              child: CustomTextField(
                label: context.read<LocalizationService>().t(
                  'avatars.details.nicknameLabel',
                ),
                controller: _nicknameController,
                hintText: context.read<LocalizationService>().t(
                  'avatars.details.nicknameHint',
                ),
                onChanged: (_) => _updateDirty(),
              ),
            ),
            const SizedBox(width: 8),
            // nicknamePublic Toggle
            Tooltip(
              message: (_avatarData?.nicknamePublic ?? false)
                  ? 'Wird im Chat angezeigt'
                  : 'Wird nicht im Chat angezeigt',
              child: GestureDetector(
                onTap: () async {
                  final newValue = !(_avatarData?.nicknamePublic ?? false);
                  if (_avatarData != null) {
                    setState(() {
                      _avatarData = _avatarData!.copyWith(
                        nicknamePublic: newValue,
                      );
                    });

                    // Sofort speichern
                    final success = await _avatarService.updateAvatar(
                      _avatarData!,
                    );
                    if (success && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: Colors.white,
                          content: ShaderMask(
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (bounds) => Theme.of(context)
                                .extension<AppGradients>()!
                                .magentaBlue
                                .createShader(bounds),
                            child: Text(
                              newValue
                                  ? '✓ Nickname wird im Chat angezeigt'
                                  : '✓ Nickname wird nicht im Chat angezeigt',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: (_avatarData?.nicknamePublic ?? false)
                        ? const LinearGradient(
                            colors: [
                              Color(0xFFE91E63),
                              AppColors.lightBlue,
                              Color(0xFF00E5FF),
                            ],
                          )
                        : null,
                    color: (_avatarData?.nicknamePublic ?? false)
                        ? null
                        : Colors.white.withValues(alpha: 0.1),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    (_avatarData?.nicknamePublic ?? false)
                        ? Icons.visibility
                        : Icons.visibility_off,
                    size: 24,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Nachname (optional) + lastNamePublic Toggle
        Row(
          children: [
            Expanded(
              child: CustomTextField(
                label: context.read<LocalizationService>().t(
                  'avatars.details.lastNameLabel',
                ),
                controller: _lastNameController,
                hintText: context.read<LocalizationService>().t(
                  'avatars.details.lastNameHint',
                ),
                onChanged: (_) => _updateDirty(),
              ),
            ),
            const SizedBox(width: 8),
            // lastNamePublic Toggle
            Tooltip(
              message: (_avatarData?.lastNamePublic ?? false)
                  ? 'Wird im Chat angezeigt'
                  : 'Wird nicht im Chat angezeigt',
              child: GestureDetector(
                onTap: () async {
                  final newValue = !(_avatarData?.lastNamePublic ?? false);
                  if (_avatarData != null) {
                    setState(() {
                      _avatarData = _avatarData!.copyWith(
                        lastNamePublic: newValue,
                      );
                    });

                    // Sofort speichern
                    final success = await _avatarService.updateAvatar(
                      _avatarData!,
                    );
                    if (success && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: Colors.white,
                          content: ShaderMask(
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (bounds) => Theme.of(context)
                                .extension<AppGradients>()!
                                .magentaBlue
                                .createShader(bounds),
                            child: Text(
                              newValue
                                  ? '✓ Nachname wird im Chat angezeigt'
                                  : '✓ Nachname wird nicht im Chat angezeigt',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: (_avatarData?.lastNamePublic ?? false)
                        ? const LinearGradient(
                            colors: [
                              Color(0xFFE91E63),
                              AppColors.lightBlue,
                              Color(0xFF00E5FF),
                            ],
                          )
                        : null,
                    color: (_avatarData?.lastNamePublic ?? false)
                        ? null
                        : Colors.white.withValues(alpha: 0.1),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    (_avatarData?.lastNamePublic ?? false)
                        ? Icons.visibility
                        : Icons.visibility_off,
                    size: 24,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Adresse - immer sichtbar
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _regionEditing
              ? [
                  CustomTextField(
                    label: context.read<LocalizationService>().t(
                      'regionSearchLabel',
                    ),
                    controller: _regionInputController,
                    hintText: context.read<LocalizationService>().t(
                      'regionSearchHint',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  _buildCountryDropdown(),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _regionCanApply
                          ? _confirmRegionSelection
                          : null,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.magenta, // GMBC
                      ),
                      child: Text(
                        context.read<LocalizationService>().t(
                          'regionApplyLink',
                        ),
                        style: TextStyle(
                          color: _regionCanApply
                              ? AppColors
                                    .magenta // GMBC
                              : Colors.white24,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      context.read<LocalizationService>().t('regionHint'),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  // Alte Adresse NICHT anzeigen im Editing-Modus
                ]
              : [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            (_cityController.text.trim().isEmpty &&
                                    _postalCodeController.text.trim().isEmpty &&
                                    _countryController.text.trim().isEmpty)
                                ? 'Deine Adresse'
                                : _buildRegionSummary(),
                            style: TextStyle(
                              color:
                                  (_cityController.text.trim().isEmpty &&
                                      _postalCodeController.text
                                          .trim()
                                          .isEmpty &&
                                      _countryController.text.trim().isEmpty)
                                  ? Colors.white38
                                  : Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.white70),
                          tooltip: context.read<LocalizationService>().t(
                            'regionEditTooltip',
                          ),
                          onPressed: () {
                            setState(() {
                              _regionEditing = true;
                              // Vorauswahl: Gespeicherte Werte in Input-Feld laden
                              final parts = <String>[];
                              if (_postalCodeController.text
                                  .trim()
                                  .isNotEmpty) {
                                parts.add(_postalCodeController.text.trim());
                              }
                              if (_cityController.text.trim().isNotEmpty) {
                                parts.add(_cityController.text.trim());
                              }
                              _regionInputController.text = parts.join(', ');
                              // Land bleibt in _countryController
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
        ),

        const SizedBox(height: 16),

        // Geburtsdatum (optional)
        CustomDateField(
          label: context.read<LocalizationService>().t(
            'avatars.details.birthDateLabel',
          ),
          selectedDate: _birthDate,
          onDateSelected: (date) {
            setState(() {
              _birthDate = date;
              _birthDateController.text = date != null
                  ? '${date.day}.${date.month}.${date.year}'
                  : '';
              _calculateAge();
            });
            _updateDirty();
          },
          lastDate: DateTime.now(),
          allowClear: true,
        ),

        const SizedBox(height: 16),

        // Sterbedatum (optional)
        CustomDateField(
          label: context.read<LocalizationService>().t(
            'avatars.details.deathDateLabel',
          ),
          selectedDate: _deathDate,
          onDateSelected: (date) {
            setState(() {
              _deathDate = date;
              _deathDateController.text = date != null
                  ? '${date.day}.${date.month}.${date.year}'
                  : '';
              _calculateAge();
            });
            _updateDirty();
          },
          firstDate: _birthDate,
          lastDate: DateTime.now(),
          allowClear: true,
        ),

        const SizedBox(height: 16),

        // Berechnetes Alter anzeigen
        if (_calculatedAge != null) _buildAgeDisplay(),
      ],
    );
  }

  Widget _buildPersonDataTile() {
    return PersonDataExpansionTile(
      inputFieldsWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildInputFields(),
          const SizedBox(height: 12),
          _buildDeleteAvatarTile(),
        ],
      ),
    );
  }

  Widget _buildDeleteAvatarTile() {
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.white24,
        listTileTheme: const ListTileThemeData(iconColor: AppColors.magenta),
      ),
      child: ExpansionTile(
      initiallyExpanded: false,
      leading: const Icon(Icons.delete_forever, color: Colors.red),
      title: const Text('Avatar löschen', style: TextStyle(color: Colors.red)),
      subtitle: const Text(
        'Den Avatar vollständig löschen – inklusive aller Verknüpfungen.',
        style: TextStyle(color: Colors.white70),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Achtung: Dieser Vorgang entfernt alle Avatardaten, Medien, Playlists und Timeline‑Einträge. Deine gespeicherten Momente bleiben erhalten.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _confirmDeleteAvatar,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    foregroundColor: Colors.red,
                  ),
                  child: const Text('Avatar endgültig löschen'),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
    );
  }

  Future<void> _confirmDeleteAvatar() async {
    final ok1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Avatar löschen?'),
        content: const Text('Willst du diesen Avatar wirklich vollständig löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ja, löschen')),
        ],
      ),
    );
    if (ok1 != true) return;

    final ok2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wirklich endgültig löschen?'),
        content: const Text('Dieser Vorgang kann nicht rückgängig gemacht werden.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Endgültig löschen', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok2 != true) return;

    try {
      final id = _avatarData?.id;
      if (id == null) return;
      final success = await AvatarService().deleteAvatar(id);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Avatar gelöscht')));
        Navigator.pushNamedAndRemoveUntil(context, '/avatar-list', (r) => false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Löschen fehlgeschlagen')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Widget _buildAgeDisplay() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      child: Text(
        context.read<LocalizationService>().t(
          'avatars.details.calculatedAge',
          params: {'age': _calculatedAge?.toString() ?? ''},
        ),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w300,
          color: Colors.white.withValues(alpha: 0.5),
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  // Speichern-Button entfernt – Save via Diskette in der AppBar

  void _calculateAge() {
    if (_birthDate != null) {
      final endDate = _deathDate ?? DateTime.now();
      final age = endDate.year - _birthDate!.year;
      final monthDiff = endDate.month - _birthDate!.month;

      if (monthDiff < 0 || (monthDiff == 0 && endDate.day < _birthDate!.day)) {
        _calculatedAge = age - 1;
      } else {
        _calculatedAge = age;
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }
  void _saveAvatarDetails() {
    if (!_formKey.currentState!.validate() || _avatarData == null) return;
    if (_isSaving) return;
    setState(() => _isSaving = true);

    () async {
      try {
        // 0) Freitext lokal als Datei anlegen (nicht in der Liste anzeigen)
        final locSvc = context.read<LocalizationService>();
        final freeText = _textAreaController.text.trim();
        String? freeTextLocalFileName;
        File? freeTextLocalFile;
        if (freeText.isNotEmpty) {
          final slug = _slugify(freeText);
          final ts = DateTime.now().millisecondsSinceEpoch;
          // Dateiname: nur bis zu 3 Schlüsselwörter, kein Spitzname-Präfix
          String filename = '${slug}_$ts.txt';
          // Kollisionen vermeiden innerhalb der aktuellen Session-Liste
          final existingNames = <String>{
            ..._textFileUrls.map(_fileNameFromUrl),
            ..._newTextFiles.map((f) => pathFromLocalFile(f.path)),
          };
          filename = _uniqueFileName(filename, existingNames);
          final tmp = await File(
            '${Directory.systemTemp.path}/$filename',
          ).create();
          await tmp.writeAsString(freeText);
          freeTextLocalFile = tmp;
          freeTextLocalFileName = filename;
          _textAreaController.clear();
        }

        // 1) Upload neue Dateien und URLs sammeln
        final avatarId = _avatarData!.id;
        final allImages = [..._imageUrls];
        final allVideos = [..._videoUrls];
        final allTexts = [..._textFileUrls];

        // Upload Images einzeln (mit Fortschritt)
        final imgProgress = ValueNotifier<double>(0.0);
        if (_newImageFiles.isNotEmpty) {
          await _showBlockingProgress<void>(
            title: locSvc.t('avatars.details.uploadImagesTitle'),
            message: locSvc.t(
              'avatars.details.filesSavingMessage',
              params: {'count': '${_newImageFiles.length}'},
            ),
            progress: imgProgress,
            task: () async {
              for (int i = 0; i < _newImageFiles.length; i++) {
                final f = _newImageFiles[i];
                final url = await FirebaseStorageService.uploadWithProgress(
                  f,
                  'images',
                  customPath:
                      'avatars/$avatarId/images/${DateTime.now().millisecondsSinceEpoch}_$i.jpg',
                  onProgress: (v) {
                    final perFile = 1.0 / _newImageFiles.length;
                    imgProgress.value = (i * perFile) + (v * perFile);
                  },
                );
                if (url != null) {
                  allImages.add(url);
                  if (mounted) {
                    setState(() => _imageUrls.add(url));
                  }
                }
              }
            },
          );
        }

        // Upload Videos einzeln (mit Fortschritt)
        final vidProgress = ValueNotifier<double>(0.0);
        if (_newVideoFiles.isNotEmpty) {
          await _showBlockingProgress<void>(
            title: locSvc.t('avatars.details.uploadVideosTitle'),
            message: locSvc.t(
              'avatars.details.filesSavingMessage',
              params: {'count': '${_newVideoFiles.length}'},
            ),
            progress: vidProgress,
            task: () async {
              for (int i = 0; i < _newVideoFiles.length; i++) {
                final f = _newVideoFiles[i];
                final url = await FirebaseStorageService.uploadWithProgress(
                  f,
                  'videos',
                  customPath:
                      'avatars/$avatarId/videos/${DateTime.now().millisecondsSinceEpoch}_$i.mp4',
                  onProgress: (v) {
                    final perFile = 1.0 / _newVideoFiles.length;
                    vidProgress.value = (i * perFile) + (v * perFile);
                  },
                );
                if (url != null) {
                  allVideos.add(url);
                  if (mounted) {
                    setState(() => _videoUrls.add(url));
                  }
                }
              }
            },
          );
        }

        // Upload Text Files
        String? freeTextUploadedUrl;
        String? freeTextUploadedPath;
        String? freeTextUploadedName;
        // a) profile.txt mit Basisdaten immer aktualisieren (nicht in Liste)
        final String profilePath = 'avatars/$avatarId/texts/profile.txt';
        final String profileContent = _buildProfileTextContent(
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim().isEmpty
              ? null
              : _lastNameController.text.trim(),
          nickname: _nicknameController.text.trim().isEmpty
              ? null
              : _nicknameController.text.trim(),
          birthDate: _birthDate,
          deathDate: _deathDate,
          calculatedAge: _calculatedAge,
        );
        final File profileTmp = await File(
          '${Directory.systemTemp.path}/profile_${DateTime.now().millisecondsSinceEpoch}.txt',
        ).create();
        await profileTmp.writeAsString(profileContent);
        await FirebaseStorageService.uploadTextFile(
          profileTmp,
          customPath: profilePath,
        );

        // b) Freitext als sichtbare Datei hochladen (in Liste aufnehmen)
        if (freeTextLocalFile != null && freeTextLocalFileName != null) {
          final storageCopyPath =
              'avatars/$avatarId/texts/$freeTextLocalFileName';
          final copyUrl = await FirebaseStorageService.uploadTextFile(
            freeTextLocalFile,
            customPath: storageCopyPath,
          );
          if (copyUrl != null) {
            allTexts.add(copyUrl);
            freeTextUploadedUrl = copyUrl;
            freeTextUploadedPath = storageCopyPath;
            freeTextUploadedName = freeTextLocalFileName;
          }
        }

        // c) sonstige neue Textdateien hochladen (sichtbar) mit Fortschritt
        final txtProgress = ValueNotifier<double>(0.0);
        if (_newTextFiles.isNotEmpty) {
          await _showBlockingProgress<void>(
            title: locSvc.t('avatars.details.uploadTextsTitle'),
            message: locSvc.t(
              'avatars.details.filesSavingMessage',
              params: {'count': '${_newTextFiles.length}'},
            ),
            progress: txtProgress,
            task: () async {
              for (int i = 0; i < _newTextFiles.length; i++) {
                final baseName = p.basename(_newTextFiles[i].path);
                final safeName = baseName.endsWith('.txt')
                    ? baseName
                    : '$baseName.txt';
                final storagePath = 'avatars/$avatarId/texts/$safeName';
                final url = await FirebaseStorageService.uploadWithProgress(
                  _newTextFiles[i],
                  'texts',
                  customPath: storagePath,
                  onProgress: (v) {
                    final perFile = 1.0 / _newTextFiles.length;
                    txtProgress.value = (i * perFile) + (v * perFile);
                  },
                );
                if (url != null) {
                  allTexts.add(url);
                  if (mounted) {
                    setState(() => _textFileUrls.add(url));
                  }
                }
              }
            },
          );
        }

        // Upload Audio Files einzeln (wird gespeichert und im Avatar geführt)
        final List<String> allAudios = List<String>.from(
          _avatarData?.audioUrls ?? const <String>[],
        );
        for (int i = 0; i < _newAudioFiles.length; i++) {
          final String base = p.basename(_newAudioFiles[i].path);
          final String audioPath =
              'avatars/$avatarId/audio/${DateTime.now().millisecondsSinceEpoch}_$i$base';
          final url = await FirebaseStorageService.uploadAudio(
            _newAudioFiles[i],
            customPath: audioPath,
          );
          if (url != null) allAudios.add(url);
        }

        // 3) Profilbild setzen, falls noch nicht gewählt
        String? avatarImageUrl = _profileImageUrl;
        if (avatarImageUrl == null && allImages.isNotEmpty) {
          avatarImageUrl = allImages.first;
        }

        // 3b) Training-Counts aktualisieren
        // Voice-Map aufbauen: bestehenden elevenVoiceId erhalten oder Auswahl verwenden
        String? existingVoiceId;
        try {
          existingVoiceId =
              (_avatarData?.training?['voice']?['elevenVoiceId'] as String?)
                  ?.trim();
        } catch (_) {}

        final totalDocuments =
            allImages.length +
            allVideos.length +
            allTexts.length +
            (_avatarData!.writtenTexts.length);
        // ElevenLabs Voice-ID bestimmen
        final Map<String, dynamic> prevVoice = Map<String, dynamic>.from(
          _avatarData?.training?['voice'] ?? {},
        );
        final String? cloneVoiceId = (prevVoice['cloneVoiceId'] as String?)
            ?.trim();
        String? chosenVoiceId;
        if (_selectedVoiceId == '__CLONE__') {
          // explizit Klon nutzen
          chosenVoiceId = cloneVoiceId ?? existingVoiceId;
        } else if ((_selectedVoiceId ?? '').isNotEmpty) {
          chosenVoiceId = _selectedVoiceId;
        } else {
          chosenVoiceId = existingVoiceId;
        }

        final training = {
          'status': 'pending',
          'startedAt': null,
          'finishedAt': null,
          'lastRunAt': null,
          'progress': 0.0,
          'totalDocuments': totalDocuments,
          'totalFiles': {
            'texts': allTexts.length,
            'images': allImages.length,
            'videos': allVideos.length,
            'others': 0,
          },
          'totalChunks': 0,
          'chunkSize': 0,
          'totalTokens': 0,
          'vector': null,
          'lastError': null,
          'jobId': null,
          'needsRetrain': true,
          'voice': {
            'activeUrl': _activeAudioUrl,
            'candidates': allAudios,
            if ((chosenVoiceId)?.isNotEmpty == true)
              'elevenVoiceId': chosenVoiceId,
          },
        };

        // 4) Avatar updaten
        debugPrint('💾 SAVING ADDRESS:');
        debugPrint('  City: "${_cityController.text.trim()}"');
        debugPrint('  PostalCode: "${_postalCodeController.text.trim()}"');
        debugPrint('  Country: "${_countryController.text.trim()}"');

        final updated = _avatarData!.copyWith(
          firstName: _firstNameController.text.trim(),
          nickname: _nicknameController.text.trim().isEmpty
              ? null
              : _nicknameController.text.trim(),
          lastName: _lastNameController.text.trim().isEmpty
              ? null
              : _lastNameController.text.trim(),
          city: _cityController.text.trim().isEmpty
              ? null
              : _cityController.text.trim(),
          postalCode: _postalCodeController.text.trim().isEmpty
              ? null
              : _postalCodeController.text.trim(),
          country: _countryController.text.trim().isEmpty
              ? null
              : _countryController.text.trim(),
          birthDate: _birthDate,
          deathDate: _deathDate,
          calculatedAge: _calculatedAge,
          updatedAt: DateTime.now(),
          imageUrls: allImages,
          videoUrls: allVideos,
          textFileUrls: allTexts,
          audioUrls: allAudios,
          avatarImageUrl: avatarImageUrl,
          training: training,
          greetingText: _greetingController.text.trim(),
          role: _role,
        );

        bool ok = false;
        await _showBlockingProgress<void>(
          title: locSvc.t('avatars.details.savingTitle'),
          message: locSvc.t('avatars.details.savingData'),
          task: () async {
            debugPrint('💾 Updated object city: "${updated.city}"');
            debugPrint('💾 Updated object postalCode: "${updated.postalCode}"');
            debugPrint('💾 Updated object country: "${updated.country}"');
            debugPrint('💾 Calling avatarService.updateAvatar...');
            ok = await _avatarService.updateAvatar(updated);
            debugPrint('💾 updateAvatar returned: $ok');
          },
        );
        if (!mounted) return;
        if (ok) {
          if (!mounted) return;
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(
                context.read<LocalizationService>().t(
                  'avatars.details.savedTitle',
                ),
              ),
              content: Text(
                context.read<LocalizationService>().t(
                  'avatars.details.dataSavedSuccessfully',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    context.read<LocalizationService>().t('avatars.details.ok'),
                  ),
                ),
              ],
            ),
          );
          // Lokale Daten aktualisieren
          _applyAvatar(updated);
          if (!mounted) return;

          // 5) Nach erfolgreichem Speichern: Kombinierten Text an Memory-API senden (fire-and-forget)
          final String uid = FirebaseAuth.instance.currentUser!.uid;
          // kombiniere Freitext + Inhalte der neuen Textdateien
          String combinedText = '';
          if (freeText.isNotEmpty) {
            combinedText += '$freeText\n\n';
          }
          for (final f in _newTextFiles) {
            try {
              final content = await f.readAsString();
              if (content.trim().isNotEmpty) {
                combinedText += '${content.trim()}\n\n';
              }
            } catch (_) {}
          }
          // Texte in Speicher übernehmen – immer mit modalem Spinner
          await _showBlockingProgress<void>(
            title: locSvc.t('avatars.details.savingTitle'),
            message: locSvc.t('avatars.details.textsTransferMessage'),
            task: () async {
              if (combinedText.trim().isNotEmpty) {
                try {
                  await _triggerMemoryInsert(
                    userId: uid,
                    avatarId: updated.id,
                    fullText: combinedText,
                    fileUrl: freeTextUploadedUrl,
                    fileName: freeTextUploadedName,
                    filePath: freeTextUploadedPath,
                    source: 'app',
                  );
                } catch (e) {
                  // ignore
                }
              }
              // Immer: profile.txt als Chunks in Pinecone aktualisieren (stable file)
              try {
                await _triggerMemoryInsert(
                  userId: uid,
                  avatarId: updated.id,
                  fullText: profileContent,
                  fileName: 'profile.txt',
                  filePath: profilePath,
                  source: 'profile',
                );
              } catch (e) {
                // ignore
              }
            },
          );
          if (!mounted) return;
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(
                context.read<LocalizationService>().t(
                  'avatars.details.textsSavedTitle',
                ),
              ),
              content: Text(
                context.read<LocalizationService>().t(
                  'avatars.details.textsSavedContent',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    context.read<LocalizationService>().t('avatars.details.ok'),
                  ),
                ),
              ],
            ),
          );
          // Jetzt lokale Textdateien leeren (nachdem wir sie gelesen/gesendet haben)
          _newTextFiles.clear();
          _newAudioFiles.clear();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.read<LocalizationService>().t(
                  'avatars.details.saveFailed',
                ),
              ),
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.read<LocalizationService>().t(
                'avatars.details.error',
                params: {'msg': e.toString()},
              ),
            ),
          ),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isSaving = false;
            _isDirty = false;
          });
        }
      }
    }();
  }

  String _pineconeApiBaseUrl() {
    return EnvService.pineconeApiBaseUrl();
  }

  Future<void> _triggerMemoryInsert({
    required String userId,
    required String avatarId,
    required String fullText,
    String? fileUrl,
    String? fileName,
    String? filePath,
    String? source,
  }) async {
    final base = _pineconeApiBaseUrl();
    if (base.isEmpty) {
      // Kein Backend: überspringen
      return;
    }
    final uri = Uri.parse('$base/avatar/memory/insert');
    final Map<String, dynamic> payload = {
      'user_id': userId,
      'avatar_id': avatarId,
      'full_text': fullText,
      'source': source ?? 'app',
      // Chunking-Parameter aus UI übergeben
      'target_tokens': _targetTokens.round(),
      'overlap': (_targetTokens * (_overlapPercent / 100.0)).round(),
      'min_chunk_tokens': _minChunkTokens.round(),
      if (fileUrl != null) 'file_url': fileUrl,
      if (fileName != null) 'file_name': fileName,
      if (filePath != null) 'file_path': filePath,
    };
    try {
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (mounted) {
          _showSystemSnack(
            'Memory insert fehlgeschlagen (${res.statusCode}): ${res.body}',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showSystemSnack('Memory insert Fehler: $e');
      }
    }
  }

  Future<void> _fallbackDebugUpsert({
    required String userId,
    required String avatarId,
    String? note,
  }) async {
    final base = _pineconeApiBaseUrl();
    if (base.isEmpty) return;
    try {
      final uri = Uri.parse('$base/debug/upsert');
      await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'avatar_id': avatarId,
          if (note != null) 'text': note,
        }),
      );
    } catch (_) {}
  }

  Future<void> _triggerMemoryDelete({
    required String userId,
    required String avatarId,
    String? fileUrl,
    String? fileName,
    String? filePath,
  }) async {
    final base = _pineconeApiBaseUrl();
    if (base.isEmpty) return; // kein Backend erreichbar → still weiter
    final uri = Uri.parse('$base/avatar/memory/delete/by-file');
    final Map<String, dynamic> payload = {
      'user_id': userId,
      'avatar_id': avatarId,
      if (fileUrl != null) 'file_url': fileUrl,
      if (fileName != null) 'file_name': fileName,
      if (filePath != null) 'file_path': filePath,
    };
    try {
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 6));
      // optional: Status prüfen, aber UI nicht blockieren
      if (res.statusCode < 200 || res.statusCode >= 300) {
        // nur loggen/snacken wenn nötig – hier bewusst still
      }
    } on TimeoutException {
      // Backend langsam/offline – UI nicht blockieren
    } catch (_) {
      // Fehler beim Löschen ignorieren (lokal schon entfernt)
    }
  }
  Future<void> _confirmDeleteSelectedImages() async {
    final total =
        _selectedRemoteImages.length +
        _selectedLocalImages.length +
        _selectedRemoteVideos.length +
        _selectedLocalVideos.length;
    if (total == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          context.read<LocalizationService>().t(
            'avatars.details.deleteSelectedTitle',
            params: {'total': total.toString()},
          ),
        ),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._selectedRemoteImages.map(
                  (u) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      u,
                      width: 54,
                      height: 96,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                ..._selectedRemoteVideos.map(
                  (u) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 54,
                      height: 96,
                      child: FutureBuilder<VideoPlayerController?>(
                        future: _createThumbController(u),
                        builder: (context, snapshot) {
                          if (snapshot.hasData && snapshot.data != null) {
                            return VideoPlayer(snapshot.data!);
                          }
                          return Container(
                            color: Colors.black26,
                            child: const Icon(
                              Icons.videocam,
                              color: Colors.white70,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                ..._selectedLocalVideos.map(
                  (filePath) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 54,
                      height: 96,
                      child: FutureBuilder<VideoPlayerController?>(
                        future: _createLocalThumbController(filePath),
                        builder: (context, snapshot) {
                          if (snapshot.hasData && snapshot.data != null) {
                            return VideoPlayer(snapshot.data!);
                          }
                          return Container(
                            color: Colors.black26,
                            child: const Icon(
                              Icons.videocam,
                              color: Colors.white70,
                            ),
                          );
                        },
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
            child: Text(
              context.read<LocalizationService>().t('avatars.details.cancel'),
            ),
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
              shaderCallback: (bounds) => Theme.of(
                context,
              ).extension<AppGradients>()!.magentaBlue.createShader(bounds),
              child: Text(
                context.read<LocalizationService>().t('avatars.details.delete'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    // Remote löschen (Bilder) + zugehörige Thumbs und evtl. Media-Dokumente
    for (final url in _selectedRemoteImages) {
      try {
        debugPrint('DEL img start: $url');
        final avatarId = _avatarData!.id;

        // ALLE Thumbnails zum Bild löschen (nicht nur das eine aus Firestore!)
        final originalPath = FirebaseStorageService.pathFromUrl(url);
        if (originalPath.isNotEmpty) {
          final dir = p.dirname(originalPath); // avatars/<id>/images
          final base = p.basenameWithoutExtension(originalPath);
          // Lösche ALLE thumbs die mit diesem Basename beginnen
          final thumbsDir = '$dir/thumbs';
          debugPrint(
            'DEL: Suche alle Thumbnails in: $thumbsDir für Basis: $base',
          );
          try {
            final ref = FirebaseStorage.instance.ref().child(thumbsDir);
            final listResult = await ref.listAll();
            for (final item in listResult.items) {
              // Prüfe ob Dateiname mit base beginnt
              if (item.name.startsWith(base)) {
                debugPrint('DEL: Lösche Thumbnail: ${item.fullPath}');
                try {
                  await item.delete();
                  debugPrint('DEL: Thumbnail gelöscht ✓');
                } catch (e) {
                  debugPrint('DEL: Fehler beim Löschen: $e');
                }
              }
            }
          } catch (e) {
            debugPrint('DEL: Fehler beim Listen der Thumbnails: $e');
          }
        }

        // Original löschen
        debugPrint('DEL: Lösche altes Original: $url');
        try {
          await FirebaseStorageService.deleteFile(url);
          debugPrint('DEL: Altes Original gelöscht ✓');
        } catch (e) {
          debugPrint('DEL: Original-Fehler: $e');
        }

        // Firestore-Dokument löschen
        try {
          debugPrint('DEL images query for avatar=$avatarId');
          final qs = await FirebaseFirestore.instance
              .collection('avatars')
              .doc(avatarId)
              .collection('images')
              .where('url', isEqualTo: url)
              .get();
          debugPrint('DEL images docs: ${qs.docs.length}');
          for (final d in qs.docs) {
            debugPrint('DEL: Lösche Firestore-Dokument: ${d.id}');
            await d.reference.delete();
            debugPrint('DEL: Firestore-Dokument gelöscht ✓');
          }
        } catch (e) {
          debugPrint('DEL: Firestore-Fehler: $e');
        }

        debugPrint('DEL img storage OK');
      } catch (e) {
        debugPrint('DEL img ERROR: $e');
      }

      // URLs und Maps aufräumen
      _imageUrls.remove(url);
      _mediaOriginalNames.remove(url);
      _imageDurations.remove(url);
      _imageActive.remove(url);
      _imageExplorerVisible.remove(url);

      if (_profileImageUrl == url) {
        if (_imageUrls.isNotEmpty) {
          _setHeroImage(_imageUrls.first);
        } else {
          _profileImageUrl = null;
        }
      }
    }
    // Remote löschen (Videos) + Thumbs und Media-Dokumente
    bool heroDeleted = false;
    final String? currentHeroAtStart = _getHeroVideoUrl();
    String urlNoQuery(String u) {
      final i = u.indexOf('?');
      return i == -1 ? u : u.substring(0, i);
    }
    for (final url in _selectedRemoteVideos) {
      try {
        debugPrint('🗑️ Lösche Video: $url');
        await FirebaseStorageService.deleteFile(url);
        final originalPath = FirebaseStorageService.pathFromUrl(url);
        if (originalPath.isNotEmpty) {
          final dir = p.dirname(originalPath); // avatars/<id>/videos
          final base = p.basenameWithoutExtension(originalPath);
          final prefix = '$dir/thumbs/${base}_';
          debugPrint('🗑️ Video-Thumbs gelöscht: $prefix');
          try {
            await FirebaseStorageService.deleteByPrefix(prefix);
            debugPrint('🗑️ Video-Thumbs gelöscht: $prefix');
          } catch (e) {
            debugPrint('⚠️ Fehler beim Löschen der Video-Thumbs: $e');
          }
        }
        try {
          final avatarId = _avatarData!.id;
          final qs = await FirebaseFirestore.instance
              .collection('avatars')
              .doc(avatarId)
              .collection('videos')
              .where('url', isEqualTo: url)
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
      final removed = _videoUrls.remove(url);
      if (currentHeroAtStart != null && urlNoQuery(url) == urlNoQuery(currentHeroAtStart)) {
        heroDeleted = true;
      }
      debugPrint(
        '🗑️ Video aus Liste entfernt: $removed (verbleibend: ${_videoUrls.length})',
      );
    }
    // Falls Hero-URL noch gesetzt ist, aber nicht mehr in der Liste vorkommt (wegen Token/Query-Unterschieden),
    // sicherheitshalber als gelöscht markieren
    if (!heroDeleted && currentHeroAtStart != null) {
      final stillPresent = _videoUrls.any((v) => urlNoQuery(v) == urlNoQuery(currentHeroAtStart));
      if (!stillPresent) {
        heroDeleted = true;
      }
    }
    // Hero-Video-Status nach Delete: Wenn das gelöschte Video das Hero war → Firestore-Feld leeren
    // Local entfernen (Bilder)
    _newImageFiles.removeWhere((f) => _selectedLocalImages.contains(f.path));
    // Local entfernen (Videos)
    _newVideoFiles.removeWhere((f) => _selectedLocalVideos.contains(f.path));
    _selectedRemoteImages.clear();
    _selectedLocalImages.clear();
    _selectedRemoteVideos.clear();
    _selectedLocalVideos.clear();
    // Persistiere Änderungen sofort (Storage + Firestore)
    // WICHTIG: imageUrls, videoUrls, heroVideoUrl UND textFileUrls müssen aktualisiert werden!
    final tr = Map<String, dynamic>.from(_avatarData!.training ?? {});
    if (heroDeleted) {
      tr['heroVideoUrl'] = null;
      debugPrint('🎬 Training: heroVideoUrl auf null gesetzt (Hero gelöscht)');
    } else {
      // Hero nicht betroffen → Wert beibehalten
      final currentHeroVideo = _getHeroVideoUrl();
      if (currentHeroVideo != null && currentHeroVideo.isNotEmpty) {
        tr['heroVideoUrl'] = currentHeroVideo;
      }
    }

    final updated = _avatarData!.copyWith(
      imageUrls: [..._imageUrls],
      videoUrls: [..._videoUrls],
      textFileUrls: [..._textFileUrls],
      avatarImageUrl: _profileImageUrl,
      clearAvatarImageUrl: _profileImageUrl == null && _imageUrls.isEmpty,
      training: tr,
      updatedAt: DateTime.now(),
    );
    final success = await _avatarService.updateAvatar(updated);
    if (success) {
      _applyAvatar(updated);
      debugPrint(
        '✅ Avatar nach Delete aktualisiert: ${_videoUrls.length} Videos, heroVideoUrl=${(_avatarData!.training?['heroVideoUrl'])}',
      );
      // Timeline-Daten persistieren (imageDurations, imageActive, imageExplorerVisible)
      await _saveTimelineData();
      debugPrint('✅ Timeline-Daten nach Delete gespeichert');
    }
    _isDeleteMode = false;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final backgroundImage = _profileImageUrl ?? _avatarData?.avatarImageUrl;
    final isEmbed = ((ModalRoute.of(context)?.settings.arguments is Map)
            ? ((ModalRoute.of(context)?.settings.arguments as Map)['embed'] == true)
            : false);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.watch<LocalizationService>().t('avatars.details.appbarTitle'),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            // Zurück zu "Meine Avatare" (mit Footer Navigation)
            Navigator.pop(context);
          },
        ),
        actions: [
          if (_isDirty)
            IconButton(
              tooltip: context.read<LocalizationService>().t(
                'avatars.details.saveTooltip',
              ),
              onPressed: _isSaving ? null : _saveAvatarDetails,
              icon: ShaderMask(
                shaderCallback: (bounds) => Theme.of(
                  context,
                ).extension<AppGradients>()!.magentaBlue.createShader(bounds),
                child: Icon(
                  Icons.save_outlined,
                  color: _isSaving ? Colors.grey : Colors.white,
                  size: 21.4,
                ),
              ),
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          // Datenwelt initial: KEIN Fallback-Bild mehr, nur schwarzer Hintergrund.
          color: Colors.black,
          image: (backgroundImage != null)
              ? DecorationImage(
                  image: NetworkImage(backgroundImage),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    Colors.black.withValues(alpha: 0.7),
                    BlendMode.darken,
                  ),
                )
              : null,
        ),
        child: Column(
          children: [
            // Hero-Media Navigation (außerhalb des ScrollView-Paddings)
            _buildHeroMediaNav(),
            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMediaContent(),
                      const SizedBox(height: 6),
                      _buildPersonDataTile(),
                      const SizedBox(height: 12),
                      if (_avatarData?.id != null)
                        SocialMediaExpansionTile(avatarId: _avatarData!.id),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: (_avatarData?.id != null && !isEmbed)
          ? AvatarBottomNavBar(
              avatarId: _avatarData!.id,
              currentScreen: 'details',
            )
          : null,
    );
  }

  Future<void> _onImageRecrop(String url, [String? tempPath]) async {
    // Recropping-Status setzen → UI zeigt Loading Spinner
    if (mounted) {
      setState(() => _isRecropping[url] = true);
    }

    try {
      // WEB: Eigener Pfad – kein _downloadToTemp, nur HTTP + Byte-Cropping
      if (kIsWeb) {
        try {
          final resp = await http.get(Uri.parse(url));
          if (resp.statusCode != 200) {
            throw Exception('HTTP ${resp.statusCode}');
          }
          final croppedBytes =
              await _cropBytesToPortraitWeb(resp.bodyBytes);
          if (croppedBytes == null) {
            if (mounted) {
              setState(() => _isRecropping.remove(url));
            }
            return;
          }

          final avatarIdNew = _avatarData!.id;
          final ts = DateTime.now().millisecondsSinceEpoch;
          const cropExt = '.jpg';
          final newPath = 'avatars/$avatarIdNew/images/$ts$cropExt';

          String newUrl;
          try {
            debugPrint('RECROP WEB: Starte Upload nach: $newPath');
            final ref = FirebaseStorage.instance.ref().child(newPath);
            await ref.putData(
              croppedBytes,
              SettableMetadata(contentType: 'image/jpeg'),
            );
            newUrl = await ref.getDownloadURL();
            debugPrint('RECROP WEB: Upload erfolgreich! URL: $newUrl');
          } catch (e) {
            if (!mounted) return;
            debugPrint('RECROP WEB: Upload FEHLER: $e');
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(
              SnackBar(content: Text('Upload fehlgeschlagen: $e')),
            );
            return;
          }

          if (mounted) {
            // Cache für alte URL leeren
            PaintingBinding.instance.imageCache.evict(NetworkImage(url));
          }

          // Ab hier gleiche Logik wie unten (Timeline/Firestore‑Update) – deshalb
          // in gemeinsamen Block springen:
          url = await _handleRecropFinalize(url, newUrl);
          return;
        } finally {
          if (mounted) {
            setState(() => _isRecropping.remove(url));
          }
        }
      }

      // NICHT Web: bestehender File-basierter Flow
      File? source;
      if (tempPath != null && tempPath.isNotEmpty) {
        final f = File(tempPath);
        if (await f.exists()) source = f;
      }
      source ??= await _downloadToTemp(url, suffix: '.png');
      if (!mounted) return;
      if (source == null) {
        if (mounted) {
          setState(() => _isRecropping.remove(url));
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bild konnte nicht geladen werden.')),
        );
        return;
      }

      final newCrop = await _cropToPortrait916(source);
      if (newCrop == null) {
        if (mounted) {
          setState(() => _isRecropping.remove(url));
        }
        return;
      }
      final bytes = await newCrop.readAsBytes();
      final dir = await getTemporaryDirectory();
      final cached = await File(
        '${dir.path}/reCrop_${DateTime.now().millisecondsSinceEpoch}.png',
      ).create(recursive: true);
      await cached.writeAsBytes(bytes, flush: true);
      // Gecropptes Bild NUR anzeigen, wenn es das Hero-Image ist!
      if (mounted && _profileImageUrl == url) {
        setState(() => _profileLocalPath = cached.path);
      }

      final originalPath = FirebaseStorageService.pathFromUrl(url);
      if (originalPath.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Speicherpfad konnte nicht ermittelt werden.'),
          ),
        );
        return;
      }
      final ts = DateTime.now().millisecondsSinceEpoch;
      final origExt = p.extension(originalPath).isNotEmpty
          ? p.extension(originalPath)
          : '.jpg';
      // Verwende die tatsächliche Extension des gecroppten Files, nicht zwingend die des Originals
      final cropExt = p.extension(cached.path).isNotEmpty
          ? p.extension(cached.path)
          : origExt;
      final avatarIdNew = _avatarData!.id;
      final newPath = 'avatars/$avatarIdNew/images/$ts$cropExt';

      // Upload recrop direkt mit korrektem Content-Type
      String newUrl;
      try {
        debugPrint('RECROP: Starte Upload nach: $newPath');
        final ref = FirebaseStorage.instance.ref().child(newPath);
        final bytesUp = await cached.readAsBytes();
        debugPrint('RECROP: Bytes gelesen: ${bytesUp.length}');
        final ct = cropExt.toLowerCase() == '.png' ? 'image/png' : 'image/jpeg';
        await ref.putData(bytesUp, SettableMetadata(contentType: ct));
        newUrl = await ref.getDownloadURL();
        debugPrint('RECROP: Upload erfolgreich! URL: $newUrl');
      } catch (e) {
        if (!mounted) return;
        debugPrint('RECROP: Upload FEHLER: $e');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload fehlgeschlagen: $e')));
        return;
      }
      if (mounted) {
        // Cache für alte URL leeren
        PaintingBinding.instance.imageCache.evict(NetworkImage(url));

        // ERST: Altes thumbUrl aus Firestore holen UND alte Files aus Storage löschen
        // (BEVOR Firestore geändert wird, wegen Storage Rules!)
        String? oldThumbUrl;
        String? savedOriginalFileName;
        try {
          final avatarId = _avatarData!.id;
          final qs = await FirebaseFirestore.instance
              .collection('avatars')
              .doc(avatarId)
              .collection('images')
              .where('url', isEqualTo: url)
              .get();
          debugPrint('RECROP: Query ergab ${qs.docs.length} Dokumente');
          for (final d in qs.docs) {
            final data = d.data();
            debugPrint('RECROP: Dokument-Daten: ${data.keys.join(", ")}');
            oldThumbUrl = (data['thumbUrl'] as String?);
            savedOriginalFileName = (data['originalFileName'] as String?);
            debugPrint('RECROP: Altes thumbUrl gefunden: $oldThumbUrl');
            debugPrint(
              'RECROP: originalFileName gefunden: $savedOriginalFileName',
            );
          }

          // Timeline-Daten vorbereiten (OHNE setState - kein UI rebuild!)
          final oldDuration = _imageDurations[url];
          final oldActive = _imageActive[url];
          final oldExplorerVisible = _imageExplorerVisible[url];

          if (oldDuration != null) {
            _imageDurations[newUrl] = oldDuration;
          }
          if (oldActive != null) {
            _imageActive[newUrl] = oldActive;
          }
          if (oldExplorerVisible != null) {
            _imageExplorerVisible[newUrl] = oldExplorerVisible;
          }

          // Alte Einträge aus Maps entfernen
          _imageDurations.remove(url);
          _imageActive.remove(url);
          _imageExplorerVisible.remove(url);
          _mediaOriginalNames.remove(url);

          await _persistTextFileUrls();
          await _saveTimelineData();

          debugPrint('RECROP: Lösche ALTE Files JETZT (vor Firestore-Update)');
          // ALLE Thumbnails zum alten Bild löschen (nicht nur das eine aus Firestore!)
          final originalPath = FirebaseStorageService.pathFromUrl(url);
          if (originalPath.isNotEmpty) {
            final dir = p.dirname(originalPath); // avatars/<id>/images
            final base = p.basenameWithoutExtension(originalPath);
            // Lösche ALLE thumbs die mit diesem Basename beginnen
            final thumbsDir = '$dir/thumbs';
            debugPrint(
              'RECROP: Suche alle Thumbnails in: $thumbsDir für Basis: $base',
            );
            try {
              final ref = FirebaseStorage.instance.ref().child(thumbsDir);
              final listResult = await ref.listAll();
              for (final item in listResult.items) {
                // Prüfe ob Dateiname mit base beginnt
                if (item.name.startsWith(base)) {
                  debugPrint('RECROP: Lösche Thumbnail: ${item.fullPath}');
                  try {
                    await item.delete();
                    debugPrint('RECROP: Thumbnail gelöscht ✓');
                  } catch (e) {
                    debugPrint('RECROP: Fehler beim Löschen: $e');
                  }
                }
              }
            } catch (e) {
              debugPrint('RECROP: Fehler beim Listen der Thumbnails: $e');
            }
          }
          // Altes Original löschen
          debugPrint('RECROP: Lösche altes Original: $url');
          try {
            await FirebaseStorageService.deleteFile(url);
            debugPrint('RECROP: Altes Original gelöscht ✓');
          } catch (e) {
            debugPrint('RECROP: Original-Fehler: $e');
          }
          // ERST Thumbnail erstellen, DANN Firestore mit thumbUrl updaten
          String? newThumbUrl;
          try {
            final thumbPath = 'avatars/$avatarIdNew/images/thumbs/$ts.jpg';
            final imgBytes = await cached.readAsBytes();
            final decoded = img.decodeImage(imgBytes);
            if (decoded != null) {
              final resized = img.copyResize(decoded, width: 360);
              final jpg = img.encodeJpg(resized, quality: 70);
              final dir2 = await getTemporaryDirectory();
              final thumbFile = await File(
                '${dir2.path}/thumb_$ts.jpg',
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

          // JETZT Firestore updaten MIT thumbUrl (verhindert auto-Generierung!)
          double? ar;
          try {
            ar = await _calculateAspectRatio(File(cached.path));
          } catch (_) {}
          // Verwende den BEREITS in setState gesetzten originalFileName für NEUE URL!
          final finalOriginalFileName =
              _mediaOriginalNames[newUrl] ?? savedOriginalFileName;
          debugPrint(
            'RECROP: Firestore update mit originalFileName: $finalOriginalFileName (aus _mediaOriginalNames[newUrl])',
          );

          for (final d in qs.docs) {
            final data = d.data();
            final createdAt =
                (data['createdAt'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch;
            final tags = (data['tags'] as List?)?.cast<String>();
            final avatarIdField = (data['avatarId'] as String?) ?? avatarId;
            debugPrint('RECROP: Lösche altes Firestore-Dokument: ${d.id}');
            try {
              await d.reference.delete();
              debugPrint('RECROP: Altes Firestore-Dokument gelöscht ✓');
            } catch (e) {
              debugPrint('RECROP: Fehler beim Löschen des alten Dokuments: $e');
            }
            debugPrint(
              'RECROP: Erstelle neues Firestore-Dokument mit newUrl: $newUrl, originalFileName: $finalOriginalFileName',
            );
            await d.reference.set({
              'avatarId': avatarIdField,
              'type': 'image',
              'url': newUrl,
              'thumbUrl': newThumbUrl, // Direkt das neue Thumbnail setzen!
              'createdAt': createdAt,
              if (ar != null) 'aspectRatio': ar,
              if (tags != null) 'tags': tags,
              if (finalOriginalFileName != null)
                'originalFileName': finalOriginalFileName,
            });
            debugPrint(
              'RECROP: Firestore-Dokument erstellt ✓ (ID: ${d.id}, url: $newUrl, originalFileName: $finalOriginalFileName)',
            );
          }

          // originalFileName direkt setzen (OHNE extra setState!)
          if (finalOriginalFileName != null) {
            _mediaOriginalNames[newUrl] = finalOriginalFileName;
          }
          debugPrint(
            'RECROP: _mediaOriginalNames[newUrl] = $finalOriginalFileName',
          );

          // Prüfen ob es das Hero-Image ist (BEVOR _setHeroImage aufgerufen wird)
          final wasHeroImage = (_profileImageUrl == url);

          // JETZT ERST URL wechseln → EIN EINZIGES setState() für ALLES!
          if (mounted) {
            setState(() {
              final index = _imageUrls.indexOf(url);
              if (index != -1) {
                _imageUrls[index] = newUrl;
              }
              if (wasHeroImage) {
                _setHeroImage(newUrl);
                // _profileLocalPath BEHALTEN bis Bild geladen ist (kein Flicker!)
                // ExtendedImage.network lädt im Hintergrund, dann ersetzt es cached
              }
              // Recropping-Status entfernen → UI zeigt wieder Namen
              _isRecropping.remove(url);
              debugPrint(
                'RECROP: UI rebuild - URL + originalFileName gleichzeitig gesetzt, Loading Spinner aus',
              );
            });
          }

          // CRITICAL: Neue URL in Firestore speichern (für Hot Reload!)
          await _saveHeroImageAndUrls();
          debugPrint(
            'RECROP: imageUrls mit neuer URL in Firestore gespeichert',
          );

          // Media-OriginalNames neu laden (um sicherzustellen dass newUrl → originalFileName mapping da ist)
          await _loadMediaOriginalNames(avatarId);
          debugPrint('RECROP: _mediaOriginalNames neu geladen aus Firestore');

          // _profileLocalPath nach 2 Sekunden auf null setzen (Bild sollte geladen sein)
          if (wasHeroImage && mounted) {
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) {
                setState(() => _profileLocalPath = null);
              }
            });
          }
        } catch (_) {}

        // Temp-Datei nach 3 Sekunden löschen (nach _profileLocalPath = null)
        Future.delayed(const Duration(seconds: 3), () async {
          try {
            await cached.delete();
          } catch (_) {}
        });
      }
    } catch (e) {
      if (!mounted) return;
      // Recropping-Status entfernen bei Fehler
      setState(() => _isRecropping.remove(url));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Zuschneiden fehlgeschlagen: $e')));
    }
  }

  Future<void> _handleImageError(String url) async {
    if (_refreshingImages.contains(url)) return;
    _refreshingImages.add(url);
    try {
      final fresh = await _refreshDownloadUrl(url);
      if (fresh != null && fresh.isNotEmpty && fresh != url && mounted) {
        setState(() {
          final idx = _imageUrls.indexOf(url);
          if (idx != -1) {
            _imageUrls[idx] = fresh;
          }
          if (_profileImageUrl == url) _profileImageUrl = fresh;
        });
        await _persistTextFileUrls();
      }
    } catch (_) {
    } finally {
      _refreshingImages.remove(url);
    }
  }

  // Berechnet das Seitenverhältnis (width/height) aus Bildbytes einer Datei
  Future<double?> _calculateAspectRatio(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final ar = image.width / image.height;
      image.dispose();
      return ar;
    } catch (_) {
      return null;
    }
  }

  Widget _buildCountryDropdown() {
    final loc = context.read<LocalizationService>();
    final currentValue = _countryController.text.trim();
    final resolvedValue = _resolveCountryOptionName(currentValue);

    return CustomDropdown<String>(
      label: loc.t('avatars.details.countryLabel'),
      value: resolvedValue,
      items: _countryOptions
          .map(
            (c) => DropdownMenuItem<String>(
              value: c,
              child: Text(c, style: const TextStyle(color: Colors.white)),
            ),
          )
          .toList(),
      onChanged: (value) {
        setState(() {
          _countryController.text = value ?? '';
        });
        _updateDirty();
      },
      hint: loc.t('avatars.details.countryDropdownHint'),
    );
  }
  // Liefert den exakten Optionsnamen aus _countryOptions für Eingaben wie
  // ISO-Code (DE), englischen Namen (Germany) oder deutsche Bezeichnung (Deutschland)
  String? _resolveCountryOptionName(String raw) {
    if (raw.isEmpty) return null;
    // Direkter Treffer
    if (_countryOptions.contains(raw)) return raw;
    final lower = raw.toLowerCase();
    // Bekannte deutsche Aliase → englische Optionsnamen
    if (lower == 'deutschland') return 'Germany';
    if (lower == 'vereinigte staaten' || lower == 'usa') return 'United States';
    if (lower == 'vereinigtes königreich' ||
        lower == 'grossbritannien' ||
        lower == 'großbritannien') {
      return 'United Kingdom';
    }
    // ISO-Code oder Name matchen
    for (final entry in countries) {
      final name = (entry['name'] ?? '').toString().trim();
      final code = (entry['code'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      if (lower == name.toLowerCase() || lower == code.toLowerCase()) {
        return name;
      }
    }
    return null;
  }

  Future<void> _confirmRegionSelection() async {
    // Eingabe bereinigen: abschließende Kommata/Spaces entfernen
    final raw = _regionInputController.text.trim().replaceAll(
      RegExp(r'[,\s]+$'),
      '',
    );
    if (raw.isEmpty) return;

    // Prüfe ob Land bereits gesetzt ist
    final selectedCountry = _countryController.text.trim();

    // WENN kein Land → Popup mit Aufforderung
    if (selectedCountry.isEmpty) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Land fehlt'),
          content: const Text(
            'Bitte gib das zugehörige Land ein (z.B. Deutschland).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // Versuche Adresse aufzulösen
    final result = await _resolveRegion(raw);
    String city = result['city'] ?? '';
    final postal = result['postal'] ?? '';
    final country = result['country'] ?? '';
    final countryCode = (result['countryCode'] ?? '').toUpperCase();
    final hasResult = city.isNotEmpty || postal.isNotEmpty;

    // WENN kein Match → Popup mit Fehlermeldung
    if (!hasResult) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Keine Adresse gefunden'),
          content: const Text(
            'Zu den eingegebenen Werten gibt es leider keine Adresse. Bitte überprüfe deine Eingabe.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // Validierung: Eingabe-PLZ/Stadt vs. Resolver – mindestens eine Komponente muss passen
    final inputPostal = _extractPostalFromRaw(raw);
    final inputCityRaw = _extractCityFromRaw(raw);
    final normInputCity = _normalizeCityForCompare(inputCityRaw);
    final normResolvedCity = _normalizeCityForCompare(city);

    // Länder-spezifische Plausibilitäten (DE: 5-stellige PLZ)
    final isDE =
        country.toLowerCase() == 'deutschland' ||
        country.toLowerCase() == 'germany' ||
        country.toUpperCase() == 'DE';
    if (isDE && inputPostal.isNotEmpty && inputPostal.length != 5) {
      await _showRegionError('Ungültige PLZ für Deutschland.');
      return;
    }

    // Länderweite PLZ-Validierung (z. B. BD = 4-stellig)
    if (!_postalValidForCountry(inputPostal, countryCode)) {
      await _showRegionError('Die PLZ passt nicht zum gewählten Land.');
      return;
    }

    // Zusätzliche Kreuzprüfung: Wenn sowohl PLZ als auch City eingegeben wurden,
    // müssen beide zum Resolver passen.
    if (inputPostal.isNotEmpty && inputCityRaw.isNotEmpty) {
      final bothMatch =
          (inputPostal == postal) &&
          (normInputCity == normResolvedCity || normResolvedCity.isEmpty);
      if (!bothMatch) {
        await _showRegionError('Die Stadt passt nicht zur PLZ.');
        return;
      }
    } else {
      // Mindestens eine Komponente muss passen
      // Kanonische City für PLZ aus Geo-Service (gebietsabhängig)
      String canonicalCity = '';
      if (postal.isNotEmpty) {
        canonicalCity =
            (await GeoService.lookupCityForPostal(postal, country)) ?? '';
      }
      // Wenn PLZ im gewählten Land ungültig ist → Abbruch
      if (postal.isNotEmpty && canonicalCity.isEmpty) {
        await _showRegionError('Die PLZ passt nicht zum gewählten Land.');
        return;
      }

      if (inputPostal.isNotEmpty && inputCityRaw.isNotEmpty) {
        // Beide eingegeben → beide müssen zum Resolver passen
        final bothMatch =
            (inputPostal == postal) &&
            (canonicalCity.isEmpty
                ? (normInputCity == normResolvedCity ||
                      normResolvedCity.isEmpty)
                : (_normalizeCityForCompare(inputCityRaw) ==
                      _normalizeCityForCompare(canonicalCity)));
        if (!bothMatch) {
          await _showRegionError('Die Stadt passt nicht zur PLZ.');
          return;
        }
      } else {
        // Mindestens eine Komponente muss passen (City gegen kanonisch, falls vorhanden)
        final postalOk =
            inputPostal.isEmpty || (postal.isNotEmpty && inputPostal == postal);
        final cityCompare = canonicalCity.isNotEmpty ? canonicalCity : city;
        final cityOk =
            normInputCity.isEmpty ||
            _normalizeCityForCompare(cityCompare).isEmpty ||
            normInputCity == _normalizeCityForCompare(cityCompare);
        if (!(postalOk || cityOk)) {
          await _showRegionError('Die Stadt passt nicht zur PLZ.');
          return;
        }
      }
    }

    // WENN Match gefunden und validiert → DIREKT SPEICHERN ohne Bestätigungs-Dialog
    setState(() {
      _cityController.text = city;
      _postalCodeController.text = postal;
      if (country.isNotEmpty) {
        _countryController.text = country;
      }
      _regionInputController.clear();
      _regionEditing = false;
    });
    _updateDirty();
  }

  Future<void> _showRegionError(String message) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adresse unplausibel'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _extractPostalFromRaw(String raw) {
    final m = RegExp(r'\b\d{4,10}\b').firstMatch(raw);
    return m?.group(0) ?? '';
  }

  String _extractCityFromRaw(String raw) {
    String s = raw.replaceAll(RegExp(r'\b\d+\b'), '');
    s = s.replaceAll(',', ' ').trim();
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s;
  }

  String _normalizeCityForCompare(String s) {
    var t = s.toLowerCase().trim();
    // deutsche Umlaute/ß normalisieren
    t = t
        .replaceAll('ä', 'ae')
        .replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue')
        .replaceAll('ß', 'ss');
    // Sonderzeichen entfernen
    t = t.replaceAll(RegExp(r'[^a-z\s]'), '');
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    return t;
  }

  bool _postalValidForCountry(String postal, String countryCode) {
    if (postal.isEmpty) return true;
    switch (countryCode) {
      case 'DE':
        return RegExp(r'^\d{5}$').hasMatch(postal);
      case 'BD':
        return RegExp(r'^\d{4}$').hasMatch(postal);
      case 'US':
        return RegExp(r'^\d{5}(?:-\d{4})?$').hasMatch(postal);
      default:
        // Fallback: 3-10 Ziffern zulassen
        return RegExp(r'^\d{3,10}$').hasMatch(postal);
    }
  }

  Future<Map<String, String>> _resolveRegion(String rawInput) async {
    final raw = rawInput.trim().replaceAll(RegExp(r'[,\s]+$'), '');
    final selectedCountry = _countryController.text.trim();
    if (raw.isEmpty || selectedCountry.isEmpty) {
      return {'city': '', 'postal': '', 'country': selectedCountry};
    }

    String normalizedCountry = selectedCountry;
    String countryCode = selectedCountry;
    for (final entry in countries) {
      final entryName = (entry['name'] ?? '').trim();
      final entryCode = (entry['code'] ?? '').trim();
      if (entryName.toLowerCase() == selectedCountry.toLowerCase() ||
          entryCode.toLowerCase() == selectedCountry.toLowerCase()) {
        normalizedCountry = entryName;
        countryCode = entryCode;
        break;
      }
    }

    String postal = '';
    String city = '';

    // Erlaube Trennung per Komma oder Space, akzeptiere evtl. nachfolgende Kommata
    final postalCityRegex = RegExp(r'^(\d{3,10})[,\s]+(.+)$');
    final postalOnlyRegex = RegExp(r'^(\d{3,10})[,\s]*$');

    if (postalCityRegex.hasMatch(raw)) {
      final match = postalCityRegex.firstMatch(raw);
      postal = match?.group(1) ?? '';
      city = match?.group(2) ?? '';
    } else if (postalOnlyRegex.hasMatch(raw)) {
      postal = raw;
    } else {
      // Nur als City übernehmen, wenn Buchstaben enthalten sind
      city = RegExp(r'[A-Za-zÄÖÜäöüß]').hasMatch(raw) ? raw : '';
    }

    if (postal.isNotEmpty && city.isEmpty) {
      final foundCity = await GeoService.lookupCityForPostal(
        postal,
        normalizedCountry,
      );
      if (foundCity != null && foundCity.isNotEmpty) {
        city = foundCity;
      }
    } else if (city.isNotEmpty && postal.isEmpty) {
      final foundPostal = await GeoService.lookupPostalForCity(
        city,
        normalizedCountry,
      );
      if (foundPostal != null && foundPostal.isNotEmpty) {
        postal = foundPostal;
      }
    }

    // City bereinigen: nur Buchstaben/Leerzeichen, Ränder trimmen
    final cleanCity = city
        .replaceAll(RegExp(r'^[^A-Za-zÄÖÜäöüß]+'), '')
        .replaceAll(RegExp(r'[^A-Za-zÄÖÜäöüß\s]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return {
      'city': cleanCity,
      'postal': postal.trim(),
      'country': normalizedCountry,
      'countryCode': countryCode,
    };
  }

  String _buildRegionSummary() {
    final parts = <String>[];
    if (_postalCodeController.text.trim().isNotEmpty) {
      parts.add(_postalCodeController.text.trim());
    }
    if (_cityController.text.trim().isNotEmpty) {
      parts.add(_cityController.text.trim());
    }
    if (_countryController.text.trim().isNotEmpty) {
      parts.add(_countryController.text.trim());
    }
    return parts.isEmpty
        ? context.read<LocalizationService>().t('regionSummaryPlaceholder')
        : parts.join(', ');
  }

  // 🎭 Dynamics Methoden ✨

  // _formatCountdown jetzt in DynamicsExpansionTile Widget
  /*
  String _formatCountdown(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
  */

  Future<void> _checkHeroVideoDuration() async {
    final heroVideoUrl = _getHeroVideoUrl();
    if (heroVideoUrl == null || heroVideoUrl.isEmpty) {
      setState(() {
        _heroVideoDuration = 0;
        _heroVideoTooLong = false;
      });
      return;
    }

    try {
      // Versuche Video-Dauer auszulesen
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(heroVideoUrl),
      );
      await controller.initialize();
      final duration = controller.value.duration.inSeconds.toDouble();
      controller.dispose();

      setState(() {
        _heroVideoDuration = duration;
        _heroVideoTooLong = duration > 10;
      });

      debugPrint('🎬 Hero-Video Dauer: ${duration}s (Max: 10s)');
    } catch (e) {
      debugPrint('❌ Fehler beim Auslesen der Video-Dauer: $e');
      setState(() {
        _heroVideoDuration = 0;
        _heroVideoTooLong = false;
      });
    }
  }

  void _resetToDefaults(String dynamicsId) {
    setState(() {
      _drivingMultipliers[dynamicsId] = 0.41;
      _animationScales[dynamicsId] = 2.0;
      _sourceMaxDims[dynamicsId] = 1600; // Fallback, wird gleich neu berechnet
      _flagsNormalizeLip[dynamicsId] = true;
      _flagsPasteback[dynamicsId] = true;
      _animationRegions[dynamicsId] = 'all';
    });

    // 🎯 Auto-berechne optimalen source-max-dim
    _autoCalculateSourceMaxDim(dynamicsId);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '✅ Standard-Parameter für "${_dynamicsData[dynamicsId]?['name'] ?? dynamicsId}" wiederhergestellt',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _loadDynamicsParameters(String dynamicsId) {
    final data = _dynamicsData[dynamicsId];
    if (data != null && data['parameters'] != null) {
      final params = data['parameters'] as Map<String, dynamic>;
      setState(() {
        _drivingMultipliers[dynamicsId] =
            (params['driving_multiplier'] as num?)?.toDouble() ?? 0.41;
        _animationScales[dynamicsId] =
            (params['scale'] as num?)?.toDouble() ?? 1.7;
        _sourceMaxDims[dynamicsId] = (params['source_max_dim'] as int?) ?? 2048;
        _flagsNormalizeLip[dynamicsId] =
            (params['flag_normalize_lip'] as bool?) ?? true;
        _flagsPasteback[dynamicsId] =
            (params['flag_pasteback'] as bool?) ?? true;
        _animationRegions[dynamicsId] =
            (params['animation_region'] as String?) ?? 'all';
      });
    }
  }

  Future<void> _restoreGeneratingTimer(String dynamicsId) async {
    if (_avatarData == null) return;

    try {
      final snapshot = await _db
          .ref('avatars/${_avatarData!.id}/dynamics/$dynamicsId/generating')
          .get();

      if (!snapshot.exists) return;

      final data = snapshot.value as Map?;
      if (data == null) return;

      final startTime = data['startTime'] as int?;
      final duration = data['duration'] as int? ?? 210;

      if (startTime == null) return;

      // Berechne verbleibende Zeit
      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsed = ((now - startTime) / 1000).floor(); // Sekunden
      final remaining = duration - elapsed;

      if (remaining <= 0) {
        // Zeit ist abgelaufen - cleanup
        _db
            .ref('avatars/${_avatarData!.id}/dynamics/$dynamicsId/generating')
            .remove();
        return;
      }

      // Stelle Timer wieder her
      setState(() {
        _generatingDynamics.add(dynamicsId);
        _dynamicsTimeRemaining[dynamicsId] = remaining;
      });

      _dynamicsTimers[dynamicsId]?.cancel();
      _dynamicsTimers[dynamicsId] = Timer.periodic(const Duration(seconds: 1), (
        timer,
      ) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() {
          final rem = _dynamicsTimeRemaining[dynamicsId] ?? 0;
          if (rem > 0) {
            _dynamicsTimeRemaining[dynamicsId] = rem - 1;
          }

          if (rem <= 0) {
            timer.cancel();
            _generatingDynamics.remove(dynamicsId);
            _db
                .ref(
                  'avatars/${_avatarData!.id}/dynamics/$dynamicsId/generating',
                )
                .remove();
            _loadDynamicsData(_avatarData!.id);
          }
        });
      });

      debugPrint('⏳ Timer für "$dynamicsId" wiederhergestellt: ${remaining}s');
    } catch (e) {
      debugPrint('❌ Fehler beim Wiederherstellen Timer: $e');
    }
  }

  Future<void> _deleteDynamicsVideo(String dynamicsId) async {
    if (_avatarData == null) return;

    final dynamicsName =
        (_dynamicsData[dynamicsId]?['name'] as String?) ??
        (dynamicsId == 'basic' ? 'Basic' : dynamicsId);

    // Bestätigung
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Video löschen?'),
        content: Text(
          'Möchtest du das generierte Video für "$dynamicsName" wirklich löschen?\n\n'
          '${dynamicsId == 'basic' ? 'Im Chat wird dann nur das Hero-Image angezeigt.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Lösche Video-URL aus Firestore
      await FirebaseFirestore.instance
          .collection('avatars')
          .doc(_avatarData!.id)
          .update({
            'dynamics.$dynamicsId.video_url': FieldValue.delete(),
            'dynamics.$dynamicsId.status': 'pending',
          });

      // Aktualisiere lokalen State
      setState(() {
        _dynamicsData[dynamicsId]?['video_url'] = null;
        _dynamicsData[dynamicsId]?['status'] = 'pending';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Video für "$dynamicsName" gelöscht'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Fehler beim Löschen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Löschen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _cancelDynamicsGeneration(String dynamicsId) {
    if (!_generatingDynamics.contains(dynamicsId)) return;

    // Timer stoppen
    _dynamicsTimers[dynamicsId]?.cancel();
    _dynamicsTimers.remove(dynamicsId);

    // Lösche generating-Status aus Firebase
    if (_avatarData != null) {
      _db
          .ref('avatars/${_avatarData!.id}/dynamics/$dynamicsId/generating')
          .remove();
    }

    // Status zurücksetzen
    setState(() {
      _generatingDynamics.remove(dynamicsId);
      _dynamicsTimeRemaining.remove(dynamicsId);
    });

    final dynamicsName =
        (_dynamicsData[dynamicsId]?['name'] as String?) ??
        (dynamicsId == 'basic' ? 'Basic' : dynamicsId);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('⚠️ Generierung von "$dynamicsName" abgebrochen'),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // 🚀 Live Avatar mit bitHuman generieren
  Future<void> _generateLiveAvatar(String model) async {
    if (_avatarData == null) return;

    // Verhindere mehrfaches Starten
    if (_isGeneratingLiveAvatar) {
      debugPrint('⚠️ Live Avatar wird bereits generiert');
      return;
    }

    final heroImageUrl = _getHeroImageUrl();
    final heroAudioUrl = _getHeroAudioUrl();

    if (heroImageUrl == null || heroImageUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bitte zuerst ein Hero-Image hochladen.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    if (heroAudioUrl == null || heroAudioUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bitte zuerst eine Hero-Audio hochladen.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() => _isGeneratingLiveAvatar = true);

    try {
      debugPrint('🚀 Starte bitHuman Agent Generierung...');
      debugPrint('   Hero-Image: $heroImageUrl');
      debugPrint('   Hero-Audio: $heroAudioUrl');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🚀 Live Avatar wird generiert... (1-3 Minuten)'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 3),
          ),
        );
      }

      // BitHuman Agent erstellen (mit gewähltem Model)
      debugPrint('🎬 Creating Agent with model: $model');
      final agentId = await BitHumanService.createAgent(
        imageUrl: heroImageUrl,
        audioUrl: heroAudioUrl,
        prompt: 'Du bist ${_avatarData!.firstName} ${_avatarData!.lastName}. ' 
                'Antworte in einem freundlichen und hilfsbereiten Ton.',
      );

      if (agentId != null && agentId.isNotEmpty) {
        debugPrint('✅ Live Avatar Agent erfolgreich erstellt: $agentId');

        // Agent ID speichern
        setState(() => _liveAvatarAgentId = agentId);

        // Warte bis Agent ready & hole finales Model von API
        await BitHumanService.waitForAgent(agentId);
        final agentStatus = await BitHumanService.getAgentStatus(agentId);
        final finalModel = model; // User-Auswahl nutzen (API gibt model zurück, ist aber optional)
        
        debugPrint('📝 Saving Agent: ID=$agentId, Model=$finalModel');

        // In Firebase speichern
        try {
          await FirebaseFirestore.instance
              .collection('avatars')
              .doc(_avatarData!.id)
              .update({
                'liveAvatar': {
                  'agentId': agentId,
                  'model': finalModel, // ← Von UI gewähltes Model!
                  'createdAt': FieldValue.serverTimestamp(),
                },
              });
          debugPrint('✅ Agent ID in Firebase gespeichert (model=$finalModel)');
        } catch (e) {
          debugPrint('❌ Fehler beim Speichern der Agent ID: $e');
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Live Avatar erfolgreich erstellt!\nAgent ID: $agentId'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } else {
        debugPrint('❌ Agent-Generierung fehlgeschlagen');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Live Avatar Generierung fehlgeschlagen. Bitte erneut versuchen.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Fehler bei Live Avatar Generierung: $e');
      debugPrint('   StackTrace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Fehler: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingLiveAvatar = false);
      }
    }
  }
  Future<void> _generateDynamics(String dynamicsId) async {
    if (_avatarData == null) return;

    // Verhindere mehrfaches Starten
    if (_generatingDynamics.contains(dynamicsId)) {
      debugPrint('⚠️ Dynamics "$dynamicsId" wird bereits generiert');
      return;
    }

    // Prüfe zwingend: heroVideoUrl vorhanden
    final heroVideoUrl = _getHeroVideoUrl();
    if (heroVideoUrl == null || heroVideoUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Bitte zuerst ein Hero-Video hochladen und definieren.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() => _generatingDynamics.add(dynamicsId));

    try {
      // 🎯 Starte Countdown-Timer (geschätzt 120 Sekunden mit GPU)
      final estimatedSeconds = 120;
      setState(() => _dynamicsTimeRemaining[dynamicsId] = estimatedSeconds);

      _dynamicsTimers[dynamicsId]?.cancel();
      _dynamicsTimers[dynamicsId] = Timer.periodic(const Duration(seconds: 1), (
        timer,
      ) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          final remaining = _dynamicsTimeRemaining[dynamicsId] ?? 0;
          if (remaining > 0) {
            _dynamicsTimeRemaining[dynamicsId] = remaining - 1;
          }
        });
      });

      if (mounted) {
        final dynamicsName =
            (_dynamicsData[dynamicsId]?['name'] as String?) ??
            (dynamicsId == 'basic' ? 'Basic' : dynamicsId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '⏳ Dynamics "$dynamicsName" wird generiert...\n'
              '🚀 Mit GPU: ca. 60-120 Sekunden!',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // 🚀 Sende Request an Modal.com (läuft asynchron!)
      final response = await http
          .post(
            Uri.parse(
              'https://romeo1971--sunriza-dynamics-api-generate-dynamics.modal.run',
            ),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'avatar_id': _avatarData!.id,
              'dynamics_id': dynamicsId,
              'parameters': {
                'driving_multiplier': _drivingMultipliers[dynamicsId] ?? 0.41,
                'scale': _animationScales[dynamicsId] ?? 1.7,
                'source_max_dim': _sourceMaxDims[dynamicsId] ?? 1600,
                'animation_region': _animationRegions[dynamicsId] ?? 'all',
              },
            }),
          )
          .timeout(const Duration(minutes: 10));

      // Backend antwortet jetzt asynchron mit {status: "generating"}
      // → Timer NICHT stoppen; wir warten auf Firestore-Update
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);

        if (responseData['status'] == 'success') {
          // Seltener Fall (Synchron-Erfolg)
          _dynamicsTimers[dynamicsId]?.cancel();
          debugPrint('✅ Dynamics Video erstellt');

          // Fertig! Entferne aus generierenden
          setState(() => _generatingDynamics.remove(dynamicsId));

          // Lade Dynamics-Daten neu
          await _loadDynamicsData(_avatarData!.id);

          if (mounted) {
            final dynamicsName =
                (_dynamicsData[dynamicsId]?['name'] as String?) ??
                (dynamicsId == 'basic' ? 'Basic' : dynamicsId);

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '✅ Dynamics "$dynamicsName" fertig! 🎉\n'
                  '🚀 Generiert in ${estimatedSeconds - (_dynamicsTimeRemaining[dynamicsId] ?? 0)} Sekunden!',
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        } else if (responseData['status'] == 'generating') {
          // Normalfall: Job läuft im Hintergrund – Timer weiterlaufen lassen
          if (mounted) {
            final dynamicsName =
                (_dynamicsData[dynamicsId]?['name'] as String?) ??
                (dynamicsId == 'basic' ? 'Basic' : dynamicsId);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '🚀 Dynamics "$dynamicsName" gestartet. Ich melde mich, sobald es fertig ist.',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
              ),
            );
          }
          return; // Timer zählt weiter bis Firestore ready meldet
        } else {
          throw Exception('Fehler: ${responseData['error']}');
        }
      } else {
        throw Exception('Backend error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Dynamics Generation Error ($dynamicsId): $e');
      if (mounted) {
        // Nur bei Fehler aus Set entfernen
        setState(() => _generatingDynamics.remove(dynamicsId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler bei "$dynamicsId": $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    // KEIN finally - Timer übernimmt das Management von _generatingDynamics
  }

  Future<void> _showCreateDynamicsDialog() async {
    final controller = TextEditingController();
    final icons = {
      'Lachen': '😄',
      'Herz': '❤️',
      'Traurig': '😢',
      'Daumen hoch': '👍',
      'Überrascht': '😮',
      'Wütend': '😠',
    };

    String? selectedIcon;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text(
            'Neue Dynamics anlegen',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Name (z.B. Lachen)',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.magenta),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Oder wähle ein Preset:',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: icons.entries.map((e) {
                  final isSelected = selectedIcon == e.key;
                  return GestureDetector(
                    onTap: () {
                      setDialogState(() {
                        selectedIcon = e.key;
                        controller.text = e.key;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.magenta.withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.magenta
                              : Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(e.value, style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 4),
                          Text(
                            e.key,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(ctx, {'name': name, 'icon': selectedIcon});
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.magenta,
              ),
              child: const Text('Anlegen'),
            ),
          ],
        ),
      ),
    );

    if (result != null && result['name'] != null && _avatarData != null) {
      try {
        final dynamicsId = result['name']!.toLowerCase().replaceAll(' ', '_');
        final newDynamicsData = {
          'name': result['name'],
          'icon': result['icon'],
          'status': 'pending',
          'parameters': {
            'driving_multiplier': 0.41,
            'scale': 1.7,
            'source_max_dim': 2048,
            'flag_normalize_lip': true,
            'flag_pasteback': true,
            'animation_region': 'all',
          },
        };

        // Firestore persistieren
        await FirebaseFirestore.instance
            .collection('avatars')
            .doc(_avatarData!.id)
            .update({'dynamics.$dynamicsId': newDynamicsData});

        setState(() {
          _dynamicsData[dynamicsId] = newDynamicsData;
          // Setze Default-Parameter für neue Dynamics
          _drivingMultipliers[dynamicsId] = 0.41;
          _animationScales[dynamicsId] = 2.0;
          _sourceMaxDims[dynamicsId] = 1600; // Wird automatisch berechnet
          _flagsNormalizeLip[dynamicsId] = true;
          _flagsPasteback[dynamicsId] = true;
          _animationRegions[dynamicsId] = 'all';
        });

        // 🎯 Auto-berechne optimalen source-max-dim für neue Dynamics
        _autoCalculateSourceMaxDim(dynamicsId);

        // Hinweis: Video hochladen
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Dynamics "${result['name']}" angelegt! Bitte Parameter anpassen und generieren.',
              ),
              duration: const Duration(seconds: 4),
              backgroundColor: AppColors.primaryGreen,
            ),
          );
        }
      } catch (e) {
        debugPrint('❌ Fehler beim Anlegen der Dynamics: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Fehler beim Anlegen: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _loadDynamicsData(String avatarId) async {
    // Lade Dynamics-Daten aus Firestore
    try {
      final doc = await FirebaseFirestore.instance
          .collection('avatars')
          .doc(avatarId)
          .get();

      if (!doc.exists) return;

      final data = doc.data();
      if (data == null) return;

      final dynamics = data['dynamics'] as Map<String, dynamic>?;
      if (dynamics == null || dynamics.isEmpty) return;

      setState(() {
        _dynamicsData = Map<String, Map<String, dynamic>>.from(
          dynamics.map((k, v) {
            final dynamicsMap = Map<String, dynamic>.from(v as Map);
            // Setze Default-Status auf 'pending', falls nicht vorhanden
            if (!dynamicsMap.containsKey('status') ||
                dynamicsMap['status'] == null) {
              dynamicsMap['status'] = 'pending';
            }
            return MapEntry(k, dynamicsMap);
          }),
        );

        // Lade Parameter für ALLE Dynamics
        for (final dynamicsId in _dynamicsData.keys) {
          _loadDynamicsParameters(dynamicsId);
        }
      });

      debugPrint('✅ Dynamics-Daten geladen: ${_dynamicsData.keys.join(', ')}');

      // 🚀 Modal.com: Timer-Restore nicht mehr nötig (synchrone Generierung)
      // for (final dynamicsId in _dynamicsData.keys) {
      //   _restoreGeneratingTimer(dynamicsId);
      // }

      // 🎯 Auto-berechne optimalen source-max-dim für alle Dynamics
      for (final dynamicsId in _dynamicsData.keys) {
        await _autoCalculateSourceMaxDim(dynamicsId);
      }
    } catch (e) {
      debugPrint('❌ Fehler beim Laden der Dynamics-Daten: $e');
    }
  }

  // Hinweis: initState existiert bereits weiter oben und setzt alles auf.
  // Zusätzliche Initialisierung erfolgt in _applyAvatar(), wo wir den Listener starten.

  void _startDynamicsListener(String avatarId) {
    _avatarDocSubscription?.cancel();
    _avatarDocSubscription = FirebaseFirestore.instance
        .collection('avatars')
        .doc(avatarId)
        .snapshots()
        .listen((snap) {
      final data = snap.data();
      if (data == null) return;
      final dynamics = data['dynamics'] as Map<String, dynamic>?;
      if (dynamics == null) return;
      final basic = dynamics['basic'] as Map<String, dynamic>?;
      if (basic == null) return;

      final status = basic['status'] as String?;
      if (status == 'ready') {
        // Stoppe eventuell laufenden Timer und entferne aus Set
        _dynamicsTimers['basic']?.cancel();
        _generatingDynamics.remove('basic');
        // Lade Daten neu, damit URLs/Chunks im UI erscheinen
        _loadDynamicsData(avatarId);
        setState(() {});
      }
    });
  }

  

  // Alias für Widget-Callback (Hero-Video)
  void _showTrimDialogForHeroVideo() {
    _showVideoTrimDialog();
  }

  // Trim beliebiges Video aus der Galerie
  Future<void> _showTrimDialogForVideo(String videoUrl) async {
    if (_avatarData == null) return;

    // Nutze VideoTrimService für Trim-Dialog + Trimming
    final newVideoUrl = await VideoTrimService.showTrimDialogAndTrim(
      context: context,
      videoUrl: videoUrl,
      avatarId: _avatarData!.id,
    );

    if (newVideoUrl != null) {
      // Ersetze NUR das getrimmte Video – gleiche Position beibehalten
      final oldIdx = _videoUrls.indexOf(videoUrl);
      setState(() {
        if (oldIdx >= 0) {
          _videoUrls[oldIdx] = newVideoUrl;
        } else {
          // Fallback: falls nicht gefunden, vorn einfügen
          _videoUrls.insert(0, newVideoUrl);
        }
      });

      // Altes Video in Storage löschen (best effort)
      await VideoTrimService.deleteVideo(
        avatarId: _avatarData!.id,
        videoUrl: videoUrl,
      );

      // Persistiere atomar: altes raus, neues rein
      try {
        final ref = FirebaseFirestore.instance
            .collection('avatars')
            .doc(_avatarData!.id);
        final batch = FirebaseFirestore.instance.batch();
        batch.update(ref, {
          'videoUrls': FieldValue.arrayRemove([videoUrl]),
        });
        batch.update(ref, {
          'videoUrls': FieldValue.arrayUnion([newVideoUrl]),
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        });
        await batch.commit();
        // Lokal spiegeln
        setState(() {
          _avatarData = _avatarData!.copyWith(
            videoUrls: List<String>.from(_videoUrls),
            updatedAt: DateTime.now(),
          );
        });
      } catch (e) {
        debugPrint(
          '❌ Firestore-Update videoUrls (normal trim) fehlgeschlagen: $e',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Video getrimmt!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _showVideoTrimDialog() async {
    final heroVideoUrl = _getHeroVideoUrl();
    if (heroVideoUrl == null) return;

    double startTime = 0.0;
    double endTime = 10.0; // Max 10 Sekunden
    final maxDuration = _heroVideoDuration;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Row(
            children: [
              Icon(Icons.content_cut, color: AppColors.magenta),
              SizedBox(width: 8),
              Text('Video trimmen', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Wähle 0-10 Sekunden aus dem ${maxDuration.toStringAsFixed(1)}s Video:',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                ),
                const SizedBox(height: 20),

                // Range Slider
                RangeSlider(
                  values: RangeValues(startTime, endTime),
                  min: 0,
                  max: maxDuration,
                  divisions: (maxDuration * 10).round(),
                  activeColor: AppColors.lightBlue,
                  inactiveColor: Colors.white.withValues(alpha: 0.2),
                  labels: RangeLabels(
                    '${startTime.toStringAsFixed(1)}s',
                    '${endTime.toStringAsFixed(1)}s',
                  ),
                  onChanged: (values) {
                    setDialogState(() {
                      startTime = values.start;
                      endTime = values.end.clamp(startTime, startTime + 10);
                      // Max 10 Sekunden Differenz
                      if (endTime - startTime > 10) {
                        endTime = startTime + 10;
                      }
                    });
                  },
                ),

                const SizedBox(height: 8),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Start: ${startTime.toStringAsFixed(1)}s',
                      style: const TextStyle(
                        color: AppColors.lightBlue,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      'Ende: ${endTime.toStringAsFixed(1)}s',
                      style: const TextStyle(
                        color: AppColors.lightBlue,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '✂️ Neue Länge: ${(endTime - startTime).toStringAsFixed(1)}s',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await _trimAndSaveHeroVideo(heroVideoUrl, startTime, endTime);
              },
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Trimmen & Speichern'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.magenta,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _trimAndSaveHeroVideo(
    String videoUrl,
    double start,
    double end,
  ) async {
    if (_avatarData == null) return;

    // Nutze VideoTrimService
    final newVideoUrl = await VideoTrimService.trimVideo(
      context: context,
      videoUrl: videoUrl,
      avatarId: _avatarData!.id,
      start: start,
      end: end,
    );

    if (newVideoUrl == null) return; // Abbruch oder Fehler

    try {
      // Neues Video zu lokaler Liste hinzufügen
      setState(() {
        if (!_videoUrls.contains(newVideoUrl)) {
          _videoUrls.insert(0, newVideoUrl);
        }
      });

      // Als Hero-Video setzen
      await _setHeroVideo(newVideoUrl);

      // Altes Video löschen (nach Success!)
      await VideoTrimService.deleteVideo(
        avatarId: _avatarData!.id,
        videoUrl: videoUrl,
      );

      // Aus lokaler Liste entfernen
      setState(() {
        _videoUrls.remove(videoUrl);
      });

      // Persistiere NUR videoUrls und heroVideoUrl gezielt (kein Whole-Object)
      try {
        await FirebaseFirestore.instance
            .collection('avatars')
            .doc(_avatarData!.id)
            .update({
              'videoUrls': _videoUrls,
              'training.heroVideoUrl': newVideoUrl,
              'updatedAt': DateTime.now().millisecondsSinceEpoch,
            });
        // Lokal in _avatarData widerspiegeln
        setState(() {
          final tr = Map<String, dynamic>.from(_avatarData!.training ?? {});
          tr['heroVideoUrl'] = newVideoUrl;
          _avatarData = _avatarData!.copyWith(
            videoUrls: List<String>.from(_videoUrls),
            training: tr,
            updatedAt: DateTime.now(),
          );
        });
      } catch (e) {
        debugPrint(
          '❌ Firestore-Update videoUrls/heroVideoUrl fehlgeschlagen: $e',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Video getrimmt und als Hero-Video gesetzt!'),
            backgroundColor: Colors.green,
          ),
        );

        // Video-Dauer neu prüfen
        await _checkHeroVideoDuration();
      }
    } catch (e) {
      debugPrint('❌ Post-Trim Fehler: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Video getrimmt, aber Fehler bei Hero-Set: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }
}

// _CropFramePainter ungenutzt entfernt