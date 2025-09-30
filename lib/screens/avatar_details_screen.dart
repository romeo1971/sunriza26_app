import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crop_your_image/crop_your_image.dart' as cyi;
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import '../data/countries.dart';
import '../models/avatar_data.dart';
import '../services/avatar_service.dart';
import '../services/elevenlabs_service.dart';
import '../services/env_service.dart';
import '../services/firebase_storage_service.dart';
import '../services/geo_service.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import '../widgets/video_player_widget.dart';

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
  final List<String> _imageUrls = [];
  final List<String> _videoUrls = [];
  final List<String> _textFileUrls = [];
  final TextEditingController _textAreaController = TextEditingController();
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
  // bool _autoVideoCrownApplied = false;
  final Set<String> _selectedRemoteImages = {};
  final Set<String> _selectedLocalImages = {};
  final Set<String> _selectedRemoteVideos = {};
  final Set<String> _selectedLocalVideos = {};
  bool _isDeleteMode = false;
  bool _isDirty = false;
  // Rect? _cropArea; // ungenutzt
  // Medien-Tab: 'images' oder 'videos'
  String _mediaTab = 'images';
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
        Slider(
          min: minAllowed,
          max: maxAllowed,
          divisions: ((maxAllowed - minAllowed) / 50).round(),
          value: _targetTokens.clamp(minAllowed, maxAllowed),
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
        Slider(
          min: 0,
          max: 40,
          divisions: 40,
          value: _overlapPercent.clamp(0, 40),
          onChanged: (v) => setState(() => _overlapPercent = v),
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
        Slider(
          min: 1,
          max: _targetTokens,
          divisions: (_targetTokens / 10).round().clamp(1, 1000000),
          value: _minChunkTokens.clamp(1, _targetTokens),
          onChanged: (v) => setState(() => _minChunkTokens = v),
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

  double _mediaWidth(BuildContext context) {
    final double available =
        MediaQuery.of(context).size.width -
        32; // 16px Seitenabstand links/rechts
    double w = (available - 16) / 2; // Abstand zwischen den Spalten
    if (w < 220) w = 220;
    if (w > 360) w = 360;
    return w;
  }

  bool get _regionCanApply {
    final input = _regionInputController.text.trim();
    if (input.isEmpty) return false;

    final hasDigits = RegExp(r'^\d{4,6}$').hasMatch(input);
    if (hasDigits && _countryController.text.trim().isEmpty) {
      _countryController.text = 'Deutschland';
    }

    return _countryController.text.trim().isNotEmpty;
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
    final baselineCrown = current.avatarImageUrl;
    if ((_profileImageUrl ?? '') != (baselineCrown ?? '')) dirty = true;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is AvatarData) {
        _applyAvatar(args);
        // Frische Daten aus Firestore nachladen, um veraltete Argumente zu ersetzen
        _fetchLatest(args.id);
      }
      _loadElevenVoices();
    });
  }

  Future<void> _fetchLatest(String id) async {
    final latest = await _avatarService.getAvatar(id);
    if (latest != null && mounted) {
      _applyAvatar(latest);
    }
  }

  void _applyAvatar(AvatarData data) {
    setState(() {
      _avatarData = data;
      _firstNameController.text = data.firstName;
      _nicknameController.text = data.nickname ?? '';
      _lastNameController.text = data.lastName ?? '';
      _cityController.text = data.city ?? '';
      _postalCodeController.text = data.postalCode ?? '';
      _countryController.text = data.country ?? '';
      _birthDate = data.birthDate;
      _deathDate = data.deathDate;
      _calculatedAge = data.calculatedAge;

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
        // WICHTIG: keine Vorauswahl im Dropdown – Nutzer entscheidet aktiv
        _selectedVoiceId = null;
      }
      _isDirty = false;
    });
    // Greeting vorbelegen
    _greetingController.text =
        _avatarData?.greetingText?.trim().isNotEmpty == true
        ? _avatarData!.greetingText!
        : context.read<LocalizationService>().t(
            'avatars.details.defaultGreeting',
          );
    // Hero-Video in Großansicht initialisieren
    _initInlineFromCrown();
    // Kein Autogenerieren mehr – Generierung erfolgt nur auf Nutzeraktion
  }

  // Obsolet: Rundes Avatarbild oben wurde entfernt (Hintergrundbild reicht aus)

  Widget _buildMediaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Opener-Text oberhalb des Medienbereichs
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            context.read<LocalizationService>().t('avatars.details.mediaHint'),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
          ),
        ),

        const SizedBox(height: 12),

        // Navigation-Chips entfernt – lokale Buttons über dem großen Medienbereich vorhanden

        // Medienbereich (gelber Rahmen-Bereich) – show/hide
        if (_mediaTab == 'images')
          _buildImagesRowLayout(_mediaWidth(context))
        else
          _buildVideosRowLayout(_mediaWidth(context)),
        const SizedBox.shrink(),

        const SizedBox(height: 16),

        // Aufklappbare Sektionen (Texte, Audio, Stimmeinstellungen)
        Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.white24,
            listTileTheme: const ListTileThemeData(iconColor: Colors.white70),
          ),
          child: Column(
            children: [
              // Begrüßungstext
              ExpansionTile(
                initiallyExpanded: false,
                collapsedBackgroundColor: Colors.white.withValues(alpha: 0.04),
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.read<LocalizationService>().t('greetingText'),
                      style: const TextStyle(color: Colors.white),
                    ),
                    if (((_avatarData?.training?['voice']?['elevenVoiceId']
                                as String?)
                            ?.trim()
                            .isNotEmpty ??
                        false))
                      IconButton(
                        icon: const Icon(
                          Icons.volume_up,
                          color: Colors.white,
                          size: 20,
                        ),
                        tooltip: context.read<LocalizationService>().t(
                          'avatars.details.voiceTestTooltip',
                        ),
                        onPressed: _isTestingVoice ? null : _testVoicePlayback,
                      ),
                  ],
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 12.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _greetingController,
                          maxLines: 3,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: context.read<LocalizationService>().t(
                              'avatars.details.greetingHint',
                            ),
                          ),
                          onChanged: (_) => _updateDirty(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Texte & Freitext
              ExpansionTile(
                initiallyExpanded: false,
                collapsedBackgroundColor: Colors.white.withValues(alpha: 0.04),
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                title: Text(
                  context.read<LocalizationService>().t('texts'),
                  style: const TextStyle(color: Colors.white),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _onAddTexts,
                            style: ElevatedButton.styleFrom(
                              alignment: Alignment.centerLeft,
                              backgroundColor: AppColors.accentGreenDark,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  context.read<LocalizationService>().t(
                                    'avatars.details.textUploadTitle',
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  context.read<LocalizationService>().t(
                                    'avatars.details.textUploadSubtitle',
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w300,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            context.read<LocalizationService>().t(
                              'avatars.details.freeTextLabel',
                            ),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _textAreaController,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: context.read<LocalizationService>().t(
                              'avatars.details.freeTextHint',
                            ),
                            hintStyle: const TextStyle(color: Colors.white54),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.06),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppColors.accentGreenDark,
                              ),
                            ),
                          ),
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 12),
                        // Chunking Parameter
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
                        if (_textFileUrls.isNotEmpty ||
                            _newTextFiles.isNotEmpty)
                          _buildTextFilesList(),
                        const SizedBox(height: 16),
                        _buildRoleDropdown(),
                        const SizedBox(height: 16),
                        _buildMediaNavRow(),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Audio (Stimmauswahl) inkl. Stimmeinstellungen
              ExpansionTile(
                initiallyExpanded: false,
                collapsedBackgroundColor: Colors.white.withValues(alpha: 0.04),
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                title: Text(
                  context.read<LocalizationService>().t('voiceSelection'),
                  style: const TextStyle(color: Colors.white),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ElevenLabs Voice Auswahl
                        _buildVoiceSelect(),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _onAddAudio,
                            style: ElevatedButton.styleFrom(
                              alignment: Alignment.centerLeft,
                              backgroundColor: AppColors.accentGreenDark,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  context.read<LocalizationService>().t(
                                    'avatars.details.audioUploadTitle',
                                  ),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  context.read<LocalizationService>().t(
                                    'avatars.details.audioUploadSubtitle',
                                  ),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w300,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_avatarData?.audioUrls.isNotEmpty == true)
                          _buildAudioFilesList(),

                        const SizedBox(height: 12),
                        // Stimmeinstellungen (nur anzeigen, wenn ein Klon/Voice-ID vorhanden ist)
                        if (((_avatarData?.training?['voice']?['elevenVoiceId'])
                                    as String?)
                                ?.trim()
                                .isNotEmpty ==
                            true)
                          _buildVoiceParams(),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Rolle', style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _role,
          dropdownColor: const Color(0xFF1C1C1E),
          items: items
              .map(
                (e) =>
                    DropdownMenuItem(value: e['key'], child: Text(e['label']!)),
              )
              .toList(),
          onChanged: (v) => setState(() => _role = v),
          decoration: const InputDecoration(
            filled: true,
            fillColor: Color(0x22FFFFFF),
            border: OutlineInputBorder(borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaNavRow() {
    final id = _avatarData?.id;
    if (id == null || id.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        ElevatedButton.icon(
          onPressed: () {
            Navigator.pushNamed(
              context,
              '/media-gallery',
              arguments: {'avatarId': id},
            );
          },
          icon: const Icon(Icons.photo_library),
          label: Text(context.read<LocalizationService>().t('gallery.title')),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: () {
            Navigator.pushNamed(
              context,
              '/playlist-list',
              arguments: {'avatarId': id},
            );
          },
          icon: const Icon(Icons.queue_music),
          label: Text(context.read<LocalizationService>().t('playlists.title')),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: () {
            Navigator.pushNamed(
              context,
              '/shared-moments',
              arguments: {'avatarId': id},
            );
          },
          icon: const Icon(Icons.collections),
          label: Text(
            context.read<LocalizationService>().t('sharedMoments.title'),
          ),
        ),
      ],
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
        Text(
          context.read<LocalizationService>().t(
            'avatars.details.elevenVoiceSelectTitle',
          ),
          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              dropdownColor: Colors.black87,
              value: _selectedVoiceId,
              hint: Text(
                context.read<LocalizationService>().t(
                  'avatars.details.voiceSelectLabel',
                ),
                style: TextStyle(color: Colors.white70),
              ),
              items: () {
                final String? cloneId =
                    (_avatarData?.training?['voice']?['elevenVoiceId']
                            as String?)
                        ?.trim();
                final List<DropdownMenuItem<String>> items = [];
                // Erste Option: MEIN VOICE KLON (nur als explizite Auswahl)
                items.add(
                  DropdownMenuItem<String>(
                    value: '__CLONE__',
                    child: Text(
                      context.read<LocalizationService>().t(
                        'avatars.details.myVoiceCloneLabel',
                      ),
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                );
                // Danach Standardstimmen, ohne Duplikat zur Clone-ID
                for (final v in _elevenVoices) {
                  final id = (v['voice_id'] ?? v['voiceId'] ?? '') as String;
                  if (cloneId != null && cloneId.isNotEmpty && id == cloneId) {
                    continue; // Duplikat vermeiden
                  }
                  items.add(
                    DropdownMenuItem<String>(
                      value: id,
                      child: Text(
                        (v['name'] ??
                                context.read<LocalizationService>().t(
                                  'avatars.details.voiceFallbackName',
                                ))
                            as String,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  );
                }
                return items;
              }(),
              onChanged: (val) {
                if (val == '__CLONE__') {
                  // Nur Auswahl markieren – tatsächliche ID bleibt die gespeicherte Clone-ID
                  _onSelectVoice('__CLONE__');
                } else {
                  _onSelectVoice(val); // setzt _isDirty = true
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton(
            onPressed:
                (_selectedVoiceId != null &&
                    _voicePreviewUrlFor(_selectedVoiceId!) != null)
                ? () async {
                    final url = _voicePreviewUrlFor(_selectedVoiceId!);
                    if (url != null) {
                      final uri = Uri.parse(url);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    }
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentGreenDark,
              foregroundColor: Colors.white,
            ),
            child: Text(
              context.read<LocalizationService>().t(
                'avatars.details.previewListenButton',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _onSelectVoice(String? voiceId) async {
    setState(() {
      _selectedVoiceId = voiceId;
      _isDirty = true; // Diskette sichtbar
    });
    // Speichern erfolgt über Diskette, nicht sofort
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

  Widget _buildImagesRowLayout([double? mediaW]) {
    final List<String> remoteFour = _imageUrls.take(4).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (ctx, cons) {
          const double spacing =
              16.0; // Abstand zwischen großem Bild und Galerie
          const double minThumbWidth = 120.0;
          const double gridSpacing = 12.0; // zwischen den Thumbs
          const double navBtnH = 40.0; // Höhe der lokalen Navigation / Upload
          // Rechts mindestens 2 Thumbs: 2 * min + Zwischenabstand
          final double minRightWidth = (2 * minThumbWidth) + gridSpacing;
          double leftW = cons.maxWidth - spacing - minRightWidth;
          // Begrenze links sinnvoll
          if (leftW > 240) leftW = 240;
          if (leftW < 160) leftW = 160;
          // Hero-Image im 9:16 Portrait‑Format (mobil)
          final double leftH = leftW * (16 / 9);
          final double totalH = navBtnH + 8 + leftH;

          return SizedBox(
            height: totalH,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero-Image links GROSS (responsive)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Navigation: Links Icons (Bild/Video), rechts Upload‑Icon
                    SizedBox(
                      width: leftW,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: navBtnH,
                                height: navBtnH,
                                child: ElevatedButton(
                                  onPressed: () =>
                                      setState(() => _mediaTab = 'images'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _mediaTab == 'images'
                                        ? AppColors.accentGreenDark
                                        : Colors.transparent,
                                    foregroundColor: Colors.white,
                                    shadowColor: Colors.transparent,
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: BorderSide(
                                        color: _mediaTab == 'images'
                                            ? AppColors.accentGreenDark
                                            : Colors.white24,
                                      ),
                                    ),
                                  ),
                                  child: const Icon(Icons.image, size: 20),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: navBtnH,
                                height: navBtnH,
                                child: ElevatedButton(
                                  onPressed: () =>
                                      setState(() => _mediaTab = 'videos'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _mediaTab == 'videos'
                                        ? AppColors.accentGreenDark
                                        : Colors.transparent,
                                    foregroundColor: Colors.white,
                                    shadowColor: Colors.transparent,
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: BorderSide(
                                        color: _mediaTab == 'videos'
                                            ? AppColors.accentGreenDark
                                            : Colors.white24,
                                      ),
                                    ),
                                  ),
                                  child: const Icon(Icons.videocam, size: 20),
                                ),
                              ),
                            ],
                          ),
                          // Rechts nur Upload‑Icon für aktuellen Tab (hier: Bilder)
                          SizedBox(
                            width: navBtnH,
                            height: navBtnH,
                            child: (_mediaTab == 'images')
                                ? ElevatedButton(
                                    onPressed: (_imageUrls.length >= 4)
                                        ? null
                                        : _onAddImages,
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
                                      child: const Center(
                                        child: Icon(
                                          Icons.file_upload,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: leftW,
                      height: leftH,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.black.withValues(alpha: 0.05),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Stack(
                          clipBehavior: Clip.hardEdge,
                          children: [
                            Positioned.fill(
                              child: _profileLocalPath != null
                                  ? Image.file(
                                      File(_profileLocalPath!),
                                      fit: BoxFit.cover,
                                    )
                                  : (_profileImageUrl != null
                                        ? Image.network(
                                            _profileImageUrl!,
                                            fit: BoxFit.cover,
                                            key: ValueKey(_profileImageUrl!),
                                            errorBuilder:
                                                (context, error, stack) {
                                                  _handleImageError(
                                                    _profileImageUrl!,
                                                  );
                                                  return Container(
                                                    color: Colors.black26,
                                                    alignment: Alignment.center,
                                                    child: const Icon(
                                                      Icons.image_not_supported,
                                                      color: Colors.white54,
                                                      size: 48,
                                                    ),
                                                  );
                                                },
                                          )
                                        : Container(
                                            color: Colors.white12,
                                            child: const Icon(
                                              Icons.person,
                                              color: Colors.white54,
                                              size: 64,
                                            ),
                                          )),
                            ),
                            if (_profileImageUrl != null)
                              Positioned(
                                left: 12,
                                right: 12,
                                bottom: 12,
                                child: ElevatedButton(
                                  onPressed: () async {
                                    if (_avatarData == null ||
                                        _isGeneratingAvatar) {
                                      return;
                                    }
                                    await _handleGenerateAvatar();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black,
                                    foregroundColor: Colors.white,
                                    alignment: Alignment.center,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    minimumSize: const Size.fromHeight(0),
                                    elevation: 0,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: Text(
                                    context.read<LocalizationService>().t(
                                      'avatars.refreshTooltip',
                                    ),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      height: 1.2,
                                      fontStyle: FontStyle.normal,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // Kein zusätzlicher Abstand unten – passt exakt in totalH
                    const SizedBox.shrink(),
                  ],
                ),
                const SizedBox(width: spacing),
                // Galerie: unten bündig (leftH) und Toolbar exakt auf Höhe der linken Navi-Leiste
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Liste unten bündig
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: SizedBox(
                          height: leftH,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: remoteFour.length.clamp(0, 4),
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: gridSpacing),
                            itemBuilder: (context, index) {
                              final url = remoteFour[index];
                              final isCrown =
                                  _profileImageUrl == url ||
                                  (_profileImageUrl == null && index == 0);
                              return SizedBox(
                                width: leftW,
                                height: leftH,
                                child: _imageThumbNetwork(url, isCrown),
                              );
                            },
                          ),
                        ),
                      ),
                      // Toolbar oben, ausgerichtet wie die linke Navi (Größe = navBtnH)
                      if (_isDeleteMode &&
                          (_selectedRemoteImages.length +
                                  _selectedLocalImages.length) >
                              0)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Row(
                            children: [
                              SizedBox(
                                width: navBtnH,
                                height: navBtnH,
                                child: ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _isDeleteMode = false;
                                      _selectedRemoteImages.clear();
                                      _selectedLocalImages.clear();
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
                                  child: const Icon(Icons.close, size: 20),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: navBtnH,
                                height: navBtnH,
                                child: ElevatedButton(
                                  onPressed: _confirmDeleteSelectedImages,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Icon(Icons.delete, size: 20),
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
          );
        },
      ),
    );
  }

  Widget _buildVideosRowLayout([double? mediaW]) {
    final List<String> remoteFour = _videoUrls.take(4).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (ctx, cons) {
          const double spacing = 16.0;
          const double minThumbWidth = 120.0;
          const double gridSpacing = 12.0;
          const double navBtnH = 40.0;
          final double minRightWidth = (2 * minThumbWidth) + gridSpacing;
          double leftW = cons.maxWidth - spacing - minRightWidth;
          if (leftW > 240) leftW = 240;
          if (leftW < 160) leftW = 160;
          // Video-Preview ebenfalls im 9:16 Portrait‑Format wie das Hero-Image
          final double leftH = leftW * (16 / 9);
          final double totalH = navBtnH + 8 + leftH;

          return SizedBox(
            height: totalH,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Video-Preview/Inline-Player links GROSS (responsive) + lokale Navigation oben
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Navigation: links Icons (Bild/Video), rechts Upload‑Icon nur im aktiven Tab (Videos)
                    SizedBox(
                      width: leftW,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: navBtnH,
                                height: navBtnH,
                                child: ElevatedButton(
                                  onPressed: () {
                                    if (_mediaTab != 'images') {
                                      setState(() => _mediaTab = 'images');
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _mediaTab == 'images'
                                        ? AppColors.accentGreenDark
                                        : Colors.transparent,
                                    foregroundColor: Colors.white,
                                    shadowColor: Colors.transparent,
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: BorderSide(
                                        color: _mediaTab == 'images'
                                            ? AppColors.accentGreenDark
                                            : Colors.white24,
                                      ),
                                    ),
                                  ),
                                  child: const Icon(Icons.image, size: 20),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: navBtnH,
                                height: navBtnH,
                                child: ElevatedButton(
                                  onPressed: () {
                                    if (_mediaTab != 'videos') {
                                      setState(() => _mediaTab = 'videos');
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _mediaTab == 'videos'
                                        ? AppColors.accentGreenDark
                                        : Colors.transparent,
                                    foregroundColor: Colors.white,
                                    shadowColor: Colors.transparent,
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: BorderSide(
                                        color: _mediaTab == 'videos'
                                            ? AppColors.accentGreenDark
                                            : Colors.white24,
                                      ),
                                    ),
                                  ),
                                  child: const Icon(Icons.videocam, size: 20),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(
                            width: navBtnH,
                            height: navBtnH,
                            child: (_mediaTab == 'videos')
                                ? ElevatedButton(
                                    onPressed: _onAddVideos,
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
                                      child: const Center(
                                        child: Icon(
                                          Icons.file_upload,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: leftW,
                      height: leftH,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.black.withValues(alpha: 0.05),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Stack(
                          clipBehavior: Clip.hardEdge,
                          children: [
                            if (_inlineVideoController != null)
                              Positioned.fill(
                                child: VideoPlayerWidget(
                                  controller: _inlineVideoController!,
                                ),
                              ),
                            if (_inlineVideoController == null)
                              Positioned.fill(
                                child: Builder(
                                  builder: (context) {
                                    final crown = _getCrownVideoUrl();
                                    return GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () {
                                        if ((crown ?? '').isNotEmpty) {
                                          _playNetworkInline(crown!);
                                        }
                                      },
                                      child: (crown == null)
                                          ? Container(
                                              color: Colors.black26,
                                              child: const Icon(
                                                Icons.play_arrow,
                                                color: Colors.white54,
                                                size: 48,
                                              ),
                                            )
                                          : AspectRatio(
                                              aspectRatio: 9 / 16,
                                              child: FutureBuilder<Uint8List?>(
                                                future: _thumbnailForRemote(
                                                  crown,
                                                ),
                                                builder: (context, snapshot) {
                                                  if (snapshot.hasData &&
                                                      snapshot.data != null) {
                                                    return Image.memory(
                                                      snapshot.data!,
                                                      fit: BoxFit.cover,
                                                    );
                                                  }
                                                  return Container(
                                                    color: Colors.black26,
                                                  );
                                                },
                                              ),
                                            ),
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: spacing),
                // Galerie (max. 4) – unten bündig, Toolbar oben ausgerichtet wie links
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: SizedBox(
                          height: leftH,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: remoteFour.length.clamp(0, 4),
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: gridSpacing),
                            itemBuilder: (context, index) {
                              final url = remoteFour[index];
                              return SizedBox(
                                width: leftW,
                                height: leftH,
                                child: _videoTile(url, leftW, leftH),
                              );
                            },
                          ),
                        ),
                      ),
                      if (_isDeleteMode &&
                          (_selectedRemoteVideos.length +
                                  _selectedLocalVideos.length) >
                              0)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Row(
                            children: [
                              SizedBox(
                                width: navBtnH,
                                height: navBtnH,
                                child: ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _isDeleteMode = false;
                                      _selectedRemoteVideos.clear();
                                      _selectedLocalVideos.clear();
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
                                  child: const Icon(Icons.close, size: 20),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: navBtnH,
                                height: navBtnH,
                                child: ElevatedButton(
                                  onPressed: _confirmDeleteSelectedImages,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Icon(Icons.delete, size: 20),
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
          );
        },
      ),
    );
  }

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
        TextField(
          controller: _textFilterController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            isDense: true,
            hintText: context.read<LocalizationService>().t(
              'avatars.details.textFileFilterHint',
            ),
            hintStyle: const TextStyle(color: Colors.white54),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.2),
              ),
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
                          child: Text(
                            context.read<LocalizationService>().t(
                              'avatars.details.cancel',
                            ),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(
                            context.read<LocalizationService>().t(
                              'avatars.details.delete',
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await FirebaseStorageService.deleteFile(url);
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
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _onCloneVoice,
              icon: const Icon(Icons.auto_fix_high),
              label: Text(
                _isSaving
                    ? context.read<LocalizationService>().t(
                        'avatars.details.cloningInProgress',
                      )
                    : context.read<LocalizationService>().t(
                        'avatars.details.cloneVoiceButton',
                      ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isSaving
                    ? Colors.grey
                    : _hasNoClonedVoice
                    ? const Color(0xFF9C27B0) // Magenta
                    : AppColors.accentGreenDark,
                foregroundColor: Colors.white,
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
        Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                context.read<LocalizationService>().t(
                  'avatars.details.dialect',
                ),
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _voiceDialect,
                dropdownColor: Colors.black,
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
                iconEnabledColor: Colors.white70,
              ),
            ),
          ],
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

  Future<void> _testVoicePlayback() async {
    try {
      final base = dotenv.env['MEMORY_API_BASE_URL'];
      if (base == null || base.isEmpty) {
        _showSystemSnack(
          context.read<LocalizationService>().t(
            'avatars.details.backendUrlMissing',
          ),
        );
        return;
      }
      String? voiceId;
      try {
        voiceId = (_avatarData?.training?['voice']?['elevenVoiceId'] as String?)
            ?.trim();
      } catch (_) {}
      if (voiceId == null || voiceId.isEmpty) {
        _showSystemSnack(
          context.read<LocalizationService>().t(
            'avatars.details.noClonedVoice',
          ),
        );
        return;
      }

      final uri = Uri.parse('$base/avatar/tts');
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
        'voice_id': voiceId,
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
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final b64 = data['audio_b64'] as String?;
        if (b64 == null || b64.isEmpty) {
          _showSystemSnack(
            context.read<LocalizationService>().t(
              'avatars.details.noAudioReceived',
            ),
          );
          return;
        }
        final bytes = base64Decode(b64);
        final dir = await getTemporaryDirectory();
        final file = File(
          '${dir.path}/voice_test_${DateTime.now().millisecondsSinceEpoch}.mp3',
        );
        await file.writeAsBytes(bytes, flush: true);
        await _voiceTestPlayer.setFilePath(file.path);
        await _voiceTestPlayer.play();
      } else {
        final detail = (res.body.isNotEmpty) ? ' ${res.body}' : '';
        _showSystemSnack(
          context.read<LocalizationService>().t(
            'avatars.details.ttsFailed',
            params: {'code': res.statusCode.toString(), 'detail': detail},
          ),
        );
      }
    } catch (e) {
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
      if (ok) {
        if (!mounted) return;
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
              // training.voice.elevenVoiceId speichern
              final existingVoice = (_avatarData!.training != null)
                  ? Map<String, dynamic>.from(
                      _avatarData!.training!['voice'] ?? {},
                    )
                  : <String, dynamic>{};
              existingVoice['elevenVoiceId'] = voiceId;
              existingVoice['cloneVoiceId'] = voiceId;
              existingVoice['activeUrl'] = _activeAudioUrl;
              existingVoice['candidates'] = _avatarData!.audioUrls;

              final updated = _avatarData!.copyWith(
                training: {
                  ...(_avatarData!.training ?? {}),
                  'voice': existingVoice,
                },
                updatedAt: DateTime.now(),
              );
              final ok = await _avatarService.updateAvatar(updated);
              if (ok) {
                _applyAvatar(updated);
                _showSystemSnack(
                  context.read<LocalizationService>().t(
                    'avatars.details.voiceClonedSaved',
                  ),
                );
                if (mounted) setState(() => _isDirty = false);
              } else {
                _showSystemSnack(
                  context.read<LocalizationService>().t(
                    'avatars.details.saveVoiceIdFailed',
                  ),
                );
              }
            } else {
              _showSystemSnack(
                context.read<LocalizationService>().t(
                  'avatars.details.elevenNoVoiceId',
                ),
              );
            }
          } else {
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
            child: Text(
              context.read<LocalizationService>().t('avatars.details.cancel'),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              context.read<LocalizationService>().t('avatars.details.delete'),
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          context.read<LocalizationService>().t(
            'avatars.details.confirmDeleteFileTitle',
          ),
        ),
        content: Text(
          context.read<LocalizationService>().t(
            'avatars.details.confirmDeleteFileContent',
            params: {'name': _fileNameFromUrl(url)},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              context.read<LocalizationService>().t('avatars.details.cancel'),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              context.read<LocalizationService>().t('avatars.details.delete'),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      // Fortschritts-Notifier entfernt (nicht genutzt)
      await _showBlockingProgress<void>(
        title: context.read<LocalizationService>().t(
          'avatars.details.deletingTitle',
        ),
        message: _fileNameFromUrl(url),
        progress: null, // kein Prozent für Delete
        task: () async {
          final deleted = await FirebaseStorageService.deleteFile(url);
          if (!deleted) {
            _showSystemSnack(
              context.read<LocalizationService>().t(
                'avatars.details.deleteFailed',
              ),
            );
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
          if (mounted) setState(() {});
          final ok = await _persistTextFileUrls();
          if (!ok) {
            _showSystemSnack(
              context.read<LocalizationService>().t(
                'avatars.details.firestoreUpdateFailed',
              ),
            );
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

  Widget _imageThumbNetwork(String url, bool isCrown) {
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
            _profileImageUrl = url;
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
          if (isCrown)
            const Positioned(
              top: 4,
              left: 4,
              child: Text('⭐', style: TextStyle(fontSize: 16)),
            ),
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
          Positioned(
            left: 6,
            bottom: 6,
            child: InkWell(
              onTap: () => _reopenCrop(url),
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
        ],
      ),
    );
  }

  // _imageThumbFile wurde im neuen Layout nicht mehr benötigt
  String? _getCrownVideoUrl() {
    try {
      final tr = Map<String, dynamic>.from(_avatarData?.training ?? {});
      final v = (tr['crownVideoUrl'] as String?)?.trim();
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}
    if (_videoUrls.isNotEmpty) return _videoUrls.first;
    return null;
  }

  Future<void> _setCrownVideo(String url) async {
    if (_avatarData == null) return;
    try {
      final tr = Map<String, dynamic>.from(_avatarData!.training ?? {});
      tr['crownVideoUrl'] = url;
      final updated = _avatarData!.copyWith(
        training: tr,
        updatedAt: DateTime.now(),
      );
      final ok = await _avatarService.updateAvatar(updated);
      if (ok) {
        _applyAvatar(updated);
        await _initInlineFromCrown();
        _showSystemSnack(
          context.read<LocalizationService>().t('avatars.details.heroVideoSet'),
        );
      }
    } catch (e) {
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

  Future<void> _initInlineFromCrown() async {
    final crown = _getCrownVideoUrl();
    if (crown == null || crown.isEmpty) {
      await _clearInlinePlayer();
      return;
    }
    // Falls URL bereits aktiv, nichts tun
    if (_currentInlineUrl == crown && _inlineVideoController != null) {
      return;
    }
    // Frische Download-URL sichern (kann ablaufen)
    final fresh = await _refreshDownloadUrl(crown) ?? crown;
    try {
      await _clearInlinePlayer();
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(fresh));
      await ctrl.initialize();
      await ctrl.setLooping(false); // kein Looping in Großansicht
      // nicht auto-play; zeigt erstes Frame
      _inlineVideoController = ctrl;
      _currentInlineUrl = crown;
      if (mounted) setState(() {});
    } catch (_) {
      // Bei Fehler: Controller freigeben und auf Thumbnail-Fallback lassen
      await _clearInlinePlayer();
    }
  }

  // _deleteRemoteVideo ungenutzt entfernt

  Widget _videoTile(String url, double w, double h) {
    final crownUrl = _getCrownVideoUrl();
    final isCrown = crownUrl != null && url == crownUrl;
    return Stack(
      children: [
        Positioned.fill(child: _imageThumbNetwork(url, isCrown)),
        // Hero-Video-Overlay (star) – 30px Bereich oben links, separate Touch-Zone
        Positioned(
          top: 4,
          left: 6,
          child: SizedBox(
            height: 30,
            width: 30,
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                '⭐',
                style: TextStyle(
                  fontSize: 14,
                  color: isCrown ? const Color(0xFFFFD700) : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _videoThumbNetwork(String url) {
    final selected = _selectedRemoteVideos.contains(url);
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List?>(
              future: _thumbnailForRemote(url),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  return Image.memory(snapshot.data!, fit: BoxFit.cover);
                }
                return Container(color: Colors.black26);
              },
            ),
            // Mini-Play-Icon entfernt – Galerie klickt nur Hero-Video/Trash
            // Tap in Galerie: setzt Hero-Video (wie verlangt). Delete funktioniert weiter über Icon.
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(onTap: () => _setCrownVideo(url)),
              ),
            ),
            Positioned(
              right: 6,
              bottom: 6,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _isDeleteMode = true;
                    if (selected) {
                      _selectedRemoteVideos.remove(url);
                    } else {
                      _selectedRemoteVideos.add(url);
                    }
                  });
                },
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
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

  // _videoThumbLocal ungenutzt entfernt

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
      if (mounted) setState(() => _inlineVideoController = controller);
    } catch (e) {
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
      setState(() => _inlineVideoController = controller);
    } catch (e) {
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
        _showSystemSnack(
          context.read<LocalizationService>().t(
            'avatars.details.noAudioSample',
          ),
        );
        return;
      }
      audioFile = await _downloadToTemp(audioUrl, suffix: '.mp3');
      if (audioFile == null) {
        _showSystemSnack(
          context.read<LocalizationService>().t(
            'avatars.details.audioLoadFailed',
          ),
        );
        return;
      }

      await _showBlockingProgress<void>(
        title: context.read<LocalizationService>().t(
          'avatars.details.generatingAvatarTitle',
        ),
        message: context.read<LocalizationService>().t(
          'avatars.details.processingImageAudio',
        ),
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
            final uid = FirebaseAuth.instance.currentUser!.uid;
            final path =
                'avatars/$uid/${_avatarData!.id}/videos/${DateTime.now().millisecondsSinceEpoch}_gen.mp4';
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
            _showSystemSnack(
              context.read<LocalizationService>().t(
                'avatars.details.avatarVideoCreated',
              ),
            );
          } else {
            final body = await streamed.stream.bytesToString();
            _showSystemSnack(
              'Generierung fehlgeschlagen: ${streamed.statusCode} ${body.isNotEmpty ? body : ''}',
            );
          }
        },
      );
    } catch (e) {
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
      print('🎬 Thumb controller error: $e');
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
      print('🎬 Local thumb controller error: $e');
      return null;
    }
  }

  Future<Uint8List?> _thumbnailForRemote(String url) async {
    try {
      if (_videoThumbCache.containsKey(url)) return _videoThumbCache[url];
      var effectiveUrl = url;
      print('🎬 Thumbnail für: $effectiveUrl');
      var res = await http.get(Uri.parse(effectiveUrl));
      print('🎬 Response: ${res.statusCode}');
      if (res.statusCode != 200) {
        final fresh = await _refreshDownloadUrl(url);
        if (fresh != null) {
          effectiveUrl = fresh;
          res = await http.get(Uri.parse(effectiveUrl));
          print('🎬 Fresh Response: ${res.statusCode}');
          if (res.statusCode != 200) return null;
        } else {
          print('🎬 Refresh failed');
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
      print('🎬 Thumbnail data: ${data?.length ?? 0} bytes');
      if (data != null) _videoThumbCache[url] = data;
      try {
        // optional: Tempdatei löschen
        await tmp.delete();
      } catch (_) {}
      return data;
    } catch (e) {
      print('🎬 Thumbnail error: $e');
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
                          result = cropped;
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

  Future<void> _onAddImages() async {
    ImageSource? source;
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      source = ImageSource.gallery; // Kamera nicht unterstützen auf Desktop
    } else {
      source = await _chooseSource(
        context.read<LocalizationService>().t(
          'avatars.details.chooseImageSourceTitle',
        ),
      );
      if (source == null) return;
    }
    if (source == ImageSource.gallery) {
      final files = await _picker.pickMultiImage(
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
      if (files.isNotEmpty && _avatarData != null) {
        setState(() => _isDirty = true);
        final String uid = FirebaseAuth.instance.currentUser!.uid;
        final String avatarId = _avatarData!.id;
        for (int i = 0; i < files.length; i++) {
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
          // Endung passend zur Datei wählen (png bei Cropping, sonst jpg)
          String ext = p.extension(f.path).toLowerCase();
          if (ext.isEmpty ||
              (ext != '.png' && ext != '.jpg' && ext != '.jpeg')) {
            ext = '.jpg';
          }
          final String path =
              'avatars/$uid/$avatarId/images/${DateTime.now().millisecondsSinceEpoch}_$i$ext';
          final url = await FirebaseStorageService.uploadImage(
            f,
            customPath: path,
          );
          if (url != null) {
            if (!mounted) return;
            setState(() {
              _imageUrls.insert(0, url);
              if (_profileImageUrl == null || _profileImageUrl!.isEmpty) {
                _profileImageUrl = url;
              }
              _profileLocalPath = null; // nach Upload auf Remote wechseln
            });
            // Sofort persistieren (Firestore aktualisieren)
            await _persistTextFileUrls();
          }
        }
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
        final String uid = FirebaseAuth.instance.currentUser!.uid;
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
            'avatars/$uid/$avatarId/images/${DateTime.now().millisecondsSinceEpoch}_cam$ext';
        final url = await FirebaseStorageService.uploadImage(
          f,
          customPath: path,
        );
        if (url != null) {
          if (!mounted) return;
          setState(() {
            _imageUrls.insert(0, url);
            if (_profileImageUrl == null || _profileImageUrl!.isEmpty) {
              _profileImageUrl = url;
            }
            _profileLocalPath = null;
          });
          // Sofort persistieren (Firestore aktualisieren)
          await _persistTextFileUrls();
        }
      }
    }
  }

  Future<void> _onAddVideos() async {
    ImageSource? source;
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      source = ImageSource.gallery;
    } else {
      source = await _chooseSource('Videoquelle wählen');
      if (source == null) return;
    }
    if (source == ImageSource.gallery) {
      final x = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
      if (x != null && _avatarData != null) {
        setState(() => _isDirty = true);
        final String uid = FirebaseAuth.instance.currentUser!.uid;
        final String avatarId = _avatarData!.id;
        final File f = File(x.path);
        final String path =
            'avatars/$uid/$avatarId/videos/${DateTime.now().millisecondsSinceEpoch}_gal.mp4';
        final url = await FirebaseStorageService.uploadVideo(
          f,
          customPath: path,
        );
        if (url != null) {
          if (!mounted) return;
          setState(() {
            _videoUrls.add(url);
          });
          // Sofort persistieren (Firestore aktualisieren)
          await _persistTextFileUrls();
        }
      }
    } else {
      final x = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 5),
      );
      if (x != null && _avatarData != null) {
        setState(() => _isDirty = true);
        final String uid = FirebaseAuth.instance.currentUser!.uid;
        final String avatarId = _avatarData!.id;
        final File f = File(x.path);
        final String path =
            'avatars/$uid/$avatarId/videos/${DateTime.now().millisecondsSinceEpoch}_cam.mp4';
        final url = await FirebaseStorageService.uploadVideo(
          f,
          customPath: path,
        );
        if (url != null) {
          if (!mounted) return;
          setState(() {
            _videoUrls.add(url);
          });
          // Sofort persistieren (Firestore aktualisieren)
          await _persistTextFileUrls();
        }
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'wav', 'aac'],
      allowMultiple: true,
    );
    if (result != null && _avatarData != null) {
      final String uid = FirebaseAuth.instance.currentUser!.uid;
      final String avatarId = _avatarData!.id;
      final List<String> uploaded = [];

      final progress = ValueNotifier<double>(0.0);
      await _showBlockingProgress<void>(
        title: context.read<LocalizationService>().t(
          'avatars.details.uploadAudioTitle',
        ),
        message: result.files.length == 1
            ? context.read<LocalizationService>().t(
                'avatars.details.fileSavingMessage',
                params: {'name': result.files.first.name},
              )
            : context.read<LocalizationService>().t(
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
                'avatars/$uid/$avatarId/audio/${DateTime.now().millisecondsSinceEpoch}_$i$base';
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
            if (url != null) uploaded.add(url);
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

      if (uploaded.isNotEmpty) {
        _showSystemSnack(
          uploaded.length == 1
              ? context.read<LocalizationService>().t(
                  'avatars.details.audioUploadedSingle',
                )
              : context.read<LocalizationService>().t(
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
        // Vorname (Pflichtfeld)
        _buildTextField(
          controller: _firstNameController,
          label: context.read<LocalizationService>().t(
            'avatars.details.firstNameLabel',
          ),
          hint: context.read<LocalizationService>().t(
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
        ),

        const SizedBox(height: 16),

        // Spitzname (optional)
        _buildTextField(
          controller: _nicknameController,
          label: context.read<LocalizationService>().t(
            'avatars.details.nicknameLabel',
          ),
          hint: context.read<LocalizationService>().t(
            'avatars.details.nicknameHint',
          ),
        ),

        const SizedBox(height: 16),

        // Nachname (optional)
        _buildTextField(
          controller: _lastNameController,
          label: context.read<LocalizationService>().t(
            'avatars.details.lastNameLabel',
          ),
          hint: context.read<LocalizationService>().t(
            'avatars.details.lastNameHint',
          ),
        ),

        const SizedBox(height: 16),

        Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.white24,
            listTileTheme: const ListTileThemeData(
              iconColor: AppColors.accentGreenDark,
            ),
          ),
          child: ExpansionTile(
            initiallyExpanded: false,
            tilePadding: EdgeInsets.zero,
            collapsedIconColor: AppColors.accentGreenDark,
            iconColor: AppColors.accentGreenDark,
            collapsedBackgroundColor: Colors.white.withValues(alpha: 0.02),
            backgroundColor: Colors.white.withValues(alpha: 0.04),
            title: Text(
              context.read<LocalizationService>().t(
                'avatars.details.regionTitle',
              ),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.accentGreenDark,
              ),
            ),
            childrenPadding: const EdgeInsets.symmetric(
              horizontal: 0,
              vertical: 8,
            ),
            children: _regionEditing
                ? [
                    TextField(
                      controller: _regionInputController,
                      decoration: InputDecoration(
                        labelText: context.read<LocalizationService>().t(
                          'regionSearchLabel',
                        ),
                        hintText: context.read<LocalizationService>().t(
                          'regionSearchHint',
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.accentGreenDark,
                            width: 2,
                          ),
                        ),
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
                          foregroundColor: AppColors.accentGreenDark,
                        ),
                        child: Text(
                          context.read<LocalizationService>().t(
                            'regionApplyLink',
                          ),
                          style: TextStyle(
                            color: _regionCanApply
                                ? AppColors.accentGreenDark
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
                    const SizedBox(height: 16),
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
                      child: Text(
                        _buildRegionSummary(),
                        style: TextStyle(
                          color:
                              (_cityController.text.trim().isEmpty &&
                                  _postalCodeController.text.trim().isEmpty &&
                                  _countryController.text.trim().isEmpty)
                              ? Colors.white24
                              : Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
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
                              _buildRegionSummary(),
                              style: const TextStyle(
                                color: Colors.white,
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
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
          ),
        ),

        const SizedBox(height: 16),

        // Geburtsdatum (optional)
        _buildDateField(
          controller: _birthDateController,
          label: context.read<LocalizationService>().t(
            'avatars.details.birthDateLabel',
          ),
          hint: context.read<LocalizationService>().t(
            'avatars.details.birthDateHint',
          ),
          onTap: () => _selectBirthDate(),
        ),

        const SizedBox(height: 16),

        // Sterbedatum (optional)
        _buildDateField(
          controller: _deathDateController,
          label: context.read<LocalizationService>().t(
            'avatars.details.deathDateLabel',
          ),
          hint: context.read<LocalizationService>().t(
            'avatars.details.deathDateHint',
          ),
          onTap: () => _selectDeathDate(),
        ),

        const SizedBox(height: 16),

        // Berechnetes Alter anzeigen
        if (_calculatedAge != null) _buildAgeDisplay(),
      ],
    );
  }

  Widget _buildPersonDataTile() {
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.white24,
        listTileTheme: const ListTileThemeData(iconColor: Colors.white70),
      ),
      child: ExpansionTile(
        initiallyExpanded: false,
        collapsedBackgroundColor: Colors.white.withValues(alpha: 0.04),
        backgroundColor: Colors.white.withValues(alpha: 0.06),
        title: Text(
          context.read<LocalizationService>().t(
            'avatars.details.personDataTitle',
          ),
          style: const TextStyle(color: Colors.white),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
            child: _buildInputFields(),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.accentGreenDark,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.accentGreenDark,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    controller.text.isEmpty ? hint : controller.text,
                    style: TextStyle(
                      color: controller.text.isEmpty
                          ? Colors.white70
                          : Colors.white,
                    ),
                  ),
                ),
                const Icon(Icons.calendar_today, color: Colors.white70),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAgeDisplay() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x80FFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.accentGreenDark.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.cake, color: AppColors.accentGreenDark),
          const SizedBox(width: 12),
          Text(
            context.read<LocalizationService>().t(
              'avatars.details.calculatedAge',
              params: {'age': _calculatedAge?.toString() ?? ''},
            ),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.accentGreenDark,
            ),
          ),
        ],
      ),
    );
  }

  // Speichern-Button entfernt – Save via Diskette in der AppBar

  Future<void> _selectBirthDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 25)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _birthDate = picked;
        _birthDateController.text = _formatDate(picked);
        _calculateAge();
      });
    }
  }

  Future<void> _selectDeathDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime.now(),
      firstDate: _birthDate ?? DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _deathDate = picked;
        _deathDateController.text = _formatDate(picked);
        _calculateAge();
      });
    }
  }

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
            title: context.read<LocalizationService>().t(
              'avatars.details.uploadImagesTitle',
            ),
            message: context.read<LocalizationService>().t(
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
                      'avatars/${FirebaseAuth.instance.currentUser!.uid}/$avatarId/images/${DateTime.now().millisecondsSinceEpoch}_$i.jpg',
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
            title: context.read<LocalizationService>().t(
              'avatars.details.uploadVideosTitle',
            ),
            message: context.read<LocalizationService>().t(
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
                      'avatars/${FirebaseAuth.instance.currentUser!.uid}/$avatarId/videos/${DateTime.now().millisecondsSinceEpoch}_$i.mp4',
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
        final String uid = FirebaseAuth.instance.currentUser!.uid;
        final String profilePath = 'avatars/$uid/$avatarId/texts/profile.txt';
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
              'avatars/$uid/$avatarId/texts/$freeTextLocalFileName';
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
            title: context.read<LocalizationService>().t(
              'avatars.details.uploadTextsTitle',
            ),
            message: context.read<LocalizationService>().t(
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
                final storagePath =
                    'avatars/${FirebaseAuth.instance.currentUser!.uid}/$avatarId/texts/$safeName';
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
              'avatars/${FirebaseAuth.instance.currentUser!.uid}/$avatarId/audio/${DateTime.now().millisecondsSinceEpoch}_$i$base';
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
        );

        bool ok = false;
        await _showBlockingProgress<void>(
          title: context.read<LocalizationService>().t(
            'avatars.details.savingTitle',
          ),
          message: context.read<LocalizationService>().t(
            'avatars.details.savingData',
          ),
          task: () async {
            ok = await _avatarService.updateAvatar(updated);
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
            title: context.read<LocalizationService>().t(
              'avatars.details.savingTitle',
            ),
            message: context.read<LocalizationService>().t(
              'avatars.details.textsTransferMessage',
            ),
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

  String _memoryApiBaseUrl() {
    return EnvService.memoryApiBaseUrl();
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
    final base = _memoryApiBaseUrl();
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
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        // Fallback: Debug-Upsert erzwingen, damit Namespace/Index sicher entstehen
        await _fallbackDebugUpsert(
          userId: userId,
          avatarId: avatarId,
          note: 'fallback:${fileName ?? 'text'}',
        );
        if (mounted) {
          _showSystemSnack(
            'Memory insert fehlgeschlagen (${res.statusCode}) – Fallback ausgeführt',
          );
        }
      }
    } catch (_) {
      // Netzwerkfehler → Fallback
      await _fallbackDebugUpsert(
        userId: userId,
        avatarId: avatarId,
        note: 'fallback:${fileName ?? 'text'}',
      );
      if (mounted) {
        _showSystemSnack(
          context.read<LocalizationService>().t(
            'avatars.details.memoryInsertFallback',
          ),
        );
      }
    }
  }

  Future<void> _fallbackDebugUpsert({
    required String userId,
    required String avatarId,
    String? note,
  }) async {
    final base = _memoryApiBaseUrl();
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
    final base = _memoryApiBaseUrl();
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
            child: Text(
              context.read<LocalizationService>().t('avatars.details.cancel'),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              context.read<LocalizationService>().t('avatars.details.delete'),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    // Remote löschen (Bilder)
    for (final url in _selectedRemoteImages) {
      await FirebaseStorageService.deleteFile(url);
      _imageUrls.remove(url);
      if (_profileImageUrl == url) {
        _profileImageUrl = _imageUrls.isNotEmpty ? _imageUrls.first : null;
      }
    }
    // Remote löschen (Videos)
    for (final url in _selectedRemoteVideos) {
      await FirebaseStorageService.deleteFile(url);
      _videoUrls.remove(url);
    }
    // Hero-Video sicherstellen: wenn Hero-Video gelöscht oder fehlt, nächstes setzen
    try {
      final currentCrown = _getCrownVideoUrl();
      final crownDeleted =
          currentCrown != null && _selectedRemoteVideos.contains(currentCrown);
      final crownMissing =
          currentCrown != null && !_videoUrls.contains(currentCrown);
      if (crownDeleted || crownMissing || currentCrown == null) {
        if (_videoUrls.isNotEmpty) {
          await _setCrownVideo(_videoUrls.first);
        } else {
          // Keine Videos mehr vorhanden: crownVideoUrl aus training entfernen
          if (_avatarData != null) {
            final tr = Map<String, dynamic>.from(_avatarData!.training ?? {});
            if (tr.containsKey('crownVideoUrl')) {
              tr.remove('crownVideoUrl');
              final updated = _avatarData!.copyWith(
                training: tr,
                updatedAt: DateTime.now(),
              );
              final ok = await _avatarService.updateAvatar(updated);
              if (ok) _applyAvatar(updated);
            }
          }
        }
      }
    } catch (_) {}
    // Local entfernen (Bilder)
    _newImageFiles.removeWhere((f) => _selectedLocalImages.contains(f.path));
    // Local entfernen (Videos)
    _newVideoFiles.removeWhere((f) => _selectedLocalVideos.contains(f.path));
    _selectedRemoteImages.clear();
    _selectedLocalImages.clear();
    _selectedRemoteVideos.clear();
    _selectedLocalVideos.clear();
    // Persistiere Änderungen sofort (Storage + Firestore)
    // Spezialsituation: Hero-Image wurde gelöscht und es gibt KEINE weiteren Bilder → avatarImageUrl muss auf null
    if (_profileImageUrl == null && _imageUrls.isEmpty) {
      // Erzwinge Clear des Hero-Image-Feldes in Firestore
      final updated = _avatarData!.copyWith(
        imageUrls: [],
        videoUrls: [..._videoUrls],
        textFileUrls: [..._textFileUrls],
        avatarImageUrl: null,
        clearAvatarImageUrl: true,
        updatedAt: DateTime.now(),
      );
      await _avatarService.updateAvatar(updated);
      _applyAvatar(updated);
    } else {
      await _persistTextFileUrls();
    }
    _isDeleteMode = false;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final backgroundImage = _profileImageUrl ?? _avatarData?.avatarImageUrl;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.watch<LocalizationService>().t('avatars.details.appbarTitle'),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (_isDirty)
            IconButton(
              tooltip: context.read<LocalizationService>().t(
                'avatars.details.saveTooltip',
              ),
              onPressed: _isSaving ? null : _saveAvatarDetails,
              icon: Icon(
                Icons.save_outlined,
                color: _isSaving ? Colors.grey : Colors.white,
                size: 28,
              ),
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: backgroundImage != null
                ? NetworkImage(backgroundImage)
                : const AssetImage('assets/sunriza_complete/images/sunset1.jpg')
                      as ImageProvider,
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.7),
              BlendMode.darken,
            ),
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Rundes Avatar-Bild entfernt (vollflächiger Hintergrund aktiv)
                const SizedBox(height: 12),
                _buildMediaSection(),

                // Eingabefelder (aufklappbar)
                _buildPersonDataTile(),

                const SizedBox(height: 32),

                // Speichern-Button entfernt – Diskette in AppBar
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
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
    super.dispose();
  }

  Future<void> _reopenCrop(String url, [String? tempPath]) async {
    try {
      File? source;
      if (tempPath != null && tempPath.isNotEmpty) {
        final f = File(tempPath);
        if (await f.exists()) source = f;
      }
      source ??= await _downloadToTemp(url, suffix: '.png');
      if (source == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bild konnte nicht geladen werden.')),
        );
        return;
      }
      final newCrop = await _cropToPortrait916(source);
      if (newCrop == null) return;
      final bytes = await newCrop.readAsBytes();
      final dir = await getTemporaryDirectory();
      final cached = await File(
        '${dir.path}/reCrop_${DateTime.now().millisecondsSinceEpoch}.png',
      ).create(recursive: true);
      await cached.writeAsBytes(bytes, flush: true);
      if (mounted) setState(() => _profileLocalPath = cached.path);

      final originalPath = FirebaseStorageService.pathFromUrl(url);
      if (originalPath.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Speicherpfad konnte nicht ermittelt werden.'),
          ),
        );
        return;
      }
      final baseDir = p.dirname(originalPath);
      final ext = p.extension(originalPath).isNotEmpty
          ? p.extension(originalPath)
          : '.jpg';
      final newPath =
          '$baseDir/recrop_${DateTime.now().millisecondsSinceEpoch}$ext';

      final upload = await FirebaseStorageService.uploadImage(
        cached,
        customPath: newPath,
      );
      if (upload != null && mounted) {
        String newUrl;
        try {
          newUrl = await FirebaseStorage.instance
              .ref()
              .child(newPath)
              .getDownloadURL();
        } catch (_) {
          newUrl = upload;
        }

        PaintingBinding.instance.imageCache
          ..evict(NetworkImage(url))
          ..evict(NetworkImage(newUrl));

        setState(() {
          final index = _imageUrls.indexOf(url);
          if (index != -1) {
            _imageUrls[index] = newUrl;
          }
          if (_profileImageUrl == url) _profileImageUrl = newUrl;
          if (_profileLocalPath == cached.path) _profileLocalPath = null;
        });

        await _persistTextFileUrls();

        try {
          await FirebaseStorageService.deleteFile(url);
        } catch (_) {}
        try {
          await cached.delete();
        } catch (_) {}
      }
    } catch (e) {
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

  Widget _buildCountryDropdown() {
    final loc = context.read<LocalizationService>();
    final currentValue = _countryController.text.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value:
              currentValue.isNotEmpty && _countryOptions.contains(currentValue)
              ? currentValue
              : null,
          isExpanded: true,
          dropdownColor: Colors.black87,
          hint: Text(
            loc.t('avatars.details.countryDropdownHint'),
            style: const TextStyle(color: Colors.white70),
          ),
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
        ),
      ),
    );
  }

  Future<void> _confirmRegionSelection() async {
    final loc = context.read<LocalizationService>();
    final raw = _regionInputController.text.trim();
    if (raw.isEmpty) return;

    final result = await _resolveRegion(raw);
    final city = result['city'] ?? '';
    final postal = result['postal'] ?? '';
    final country = result['country'] ?? '';
    final hasResult = city.isNotEmpty || postal.isNotEmpty;

    final summaryParts = [
      if (postal.isNotEmpty) postal,
      if (city.isNotEmpty) city,
      if (country.isNotEmpty) country,
    ];
    final summary = summaryParts.join(', ');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('avatars.details.regionConfirmTitle')),
        content: Text(
          hasResult
              ? loc.t(
                  'avatars.details.regionConfirmMessage',
                  params: {'summary': summary.isEmpty ? '-' : summary},
                )
              : loc.t('avatars.details.regionNotFound'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.t('avatars.details.cancel')),
          ),
          if (hasResult)
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentGreenDark,
                foregroundColor: Colors.white,
              ),
              child: Text(loc.t('avatars.details.confirmApply')),
            ),
        ],
      ),
    );

    if (confirmed == true && hasResult) {
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
  }

  Future<Map<String, String>> _resolveRegion(String rawInput) async {
    final raw = rawInput.trim();
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

    final postalCityRegex = RegExp(r'^(\d{3,10})\s+(.+)$');
    final postalOnlyRegex = RegExp(r'^(\d{3,10})$');

    if (postalCityRegex.hasMatch(raw)) {
      final match = postalCityRegex.firstMatch(raw);
      postal = match?.group(1) ?? '';
      city = match?.group(2) ?? '';
    } else if (postalOnlyRegex.hasMatch(raw)) {
      postal = raw;
    } else {
      city = raw;
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

    return {
      'city': city.trim(),
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
}

// _CropFramePainter ungenutzt entfernt
