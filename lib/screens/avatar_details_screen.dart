import 'package:flutter/material.dart';
import 'dart:io';
import '../theme/app_theme.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/avatar_data.dart';
import '../services/firebase_storage_service.dart';
import '../services/avatar_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'avatar_editor_screen.dart';
import 'package:video_player/video_player.dart';
import '../widgets/video_player_widget.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'dart:typed_data';
import '../services/elevenlabs_service.dart';

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
  final _birthDateController = TextEditingController();
  final _deathDateController = TextEditingController();

  DateTime? _birthDate;
  DateTime? _deathDate;
  int? _calculatedAge;

  AvatarData? _avatarData;
  final List<String> _imageUrls = [];
  final List<String> _videoUrls = [];
  final List<String> _textFileUrls = [];
  final TextEditingController _textAreaController = TextEditingController();
  final TextEditingController _greetingController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final AvatarService _avatarService = AvatarService();
  final List<File> _newImageFiles = [];
  final List<File> _newVideoFiles = [];
  final List<File> _newTextFiles = [];
  final List<File> _newAudioFiles = [];
  String? _activeAudioUrl; // ausgewählte Stimmprobe
  String? _profileImageUrl; // Krone
  String? _profileLocalPath; // Krone (lokal, noch nicht hochgeladen)
  bool _isSaving = false;
  VideoPlayerController? _inlineVideoController; // Inline-Player für Videos
  // Inline-Vorschaubild nicht nötig, Thumbnails entstehen in den Tiles per FutureBuilder
  final Map<String, Uint8List> _videoThumbCache = {};
  final Set<String> _selectedRemoteImages = {};
  final Set<String> _selectedLocalImages = {};
  final Set<String> _selectedRemoteVideos = {};
  final Set<String> _selectedLocalVideos = {};
  bool _isDeleteMode = false;
  bool _isDirty = false;
  // Medien-Tab: 'images' oder 'videos'
  String _mediaTab = 'images';
  // ElevenLabs Voice-Parameter (per Avatar speicherbar)
  double _voiceStability = 0.25;
  double _voiceSimilarity = 0.9;
  double _voiceTempo = 1.0; // 0.5 .. 1.5
  String _voiceDialect = 'de-DE';
  // ElevenLabs Voices
  List<Map<String, dynamic>> _elevenVoices = [];
  String? _selectedVoiceId;
  bool _voicesLoading = false;

  double _mediaWidth(BuildContext context) {
    final double available =
        MediaQuery.of(context).size.width -
        32; // 16px Seitenabstand links/rechts
    double w = (available - 16) / 2; // Abstand zwischen den Spalten
    if (w < 220) w = 220;
    if (w > 360) w = 360;
    return w;
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

    // Krone / Profilbild geändert
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
    // Empfange AvatarData von der vorherigen Seite
    _firstNameController.addListener(_updateDirty);
    _nicknameController.addListener(_updateDirty);
    _lastNameController.addListener(_updateDirty);
    _textAreaController.addListener(_updateDirty);
    _greetingController.addListener(_updateDirty);
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
        : 'Hallo, schön, dass Du vorbeischaust. Magst Du mir Deinen Namen verraten?';
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
            'Diese Bilder, Videos und Texte dienen dazu, den Avatar möglichst genau zu trainieren – keine Urlaubsgalerie.',
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
        Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_isDeleteMode)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isDeleteMode = true;
                      _selectedRemoteImages.clear();
                      _selectedLocalImages.clear();
                      _selectedRemoteVideos.clear();
                      _selectedLocalVideos.clear();
                    });
                  },
                  child: const Text(
                    'Löschen',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                )
              else ...[
                TextButton(
                  onPressed: () async {
                    await _confirmDeleteSelectedImages();
                  },
                  child: const Text(
                    'Ausgewählte endgültig löschen',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
                const SizedBox(width: 16),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isDeleteMode = false;
                      _selectedRemoteImages.clear();
                      _selectedLocalImages.clear();
                      _selectedRemoteVideos.clear();
                      _selectedLocalVideos.clear();
                    });
                  },
                  child: const Text('Abbrechen'),
                ),
              ],
            ],
          ),
        ),

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
                title: const Text(
                  'Begrüßungstext',
                  style: TextStyle(color: Colors.white),
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
                          decoration: const InputDecoration(
                            hintText: 'Begrüßungstext des Avatars',
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
                title: const Text(
                  'Texte',
                  style: TextStyle(color: Colors.white),
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
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Textdateien hochladen',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  '(.txt, .md, .rtf) – Wissen/Erinnerungen hinzufügen',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w300,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Freitext (wird als .txt gespeichert)',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _textAreaController,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: 'Schreibe Gedanken/Erinnerungen…',
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
                        if (_textFileUrls.isNotEmpty ||
                            _newTextFiles.isNotEmpty)
                          _buildTextFilesList(),
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
                title: const Text(
                  'Stimmauswahl',
                  style: TextStyle(color: Colors.white),
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
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Audio-Dateien hochladen',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  '(.mp3, .m4a, .wav, .aac, .ogg) – Stimme/Referenzen',
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

  Widget _buildVoiceSelect() {
    if (_voicesLoading) {
      return const LinearProgressIndicator(minHeight: 3);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Stimme wählen (ElevenLabs)',
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
              hint: const Text(
                'Stimme wählen',
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
                    child: const Text(
                      'MEIN VOICE KLON',
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
                        (v['name'] ?? 'Voice') as String,
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
            child: const Text('Probehören'),
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
  }) async {
    if (!mounted) return null;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Row(
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
          // Rechts mindestens 2 Thumbs: 2 * min + Zwischenabstand
          final double minRightWidth = (2 * minThumbWidth) + gridSpacing;
          double leftW = cons.maxWidth - spacing - minRightWidth;
          // Begrenze links sinnvoll
          if (leftW > 240) leftW = 240;
          if (leftW < 160) leftW = 160;
          final double leftH = leftW * 1.5; // etwa 2:3 Verhältnis

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Krone links GROSS (responsive)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Lokale Navigation direkt über dem großen Bild (hälftig, 16px Abstand)
                  SizedBox(
                    width: leftW,
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () =>
                                setState(() => _mediaTab = 'images'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _mediaTab == 'images'
                                  ? AppColors.accentGreenDark
                                  : Colors.transparent,
                              foregroundColor: _mediaTab == 'images'
                                  ? Colors.white
                                  : Colors.white70,
                              side: BorderSide(
                                color: _mediaTab == 'images'
                                    ? AppColors.accentGreenDark
                                    : Colors.white24,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Bilder'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () =>
                                setState(() => _mediaTab = 'videos'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _mediaTab == 'videos'
                                  ? AppColors.accentGreenDark
                                  : Colors.transparent,
                              foregroundColor: _mediaTab == 'videos'
                                  ? Colors.white
                                  : Colors.white70,
                              side: BorderSide(
                                color: _mediaTab == 'videos'
                                    ? AppColors.accentGreenDark
                                    : Colors.white24,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Videos'),
                          ),
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
                          Positioned(
                            left: 12,
                            right: 12,
                            bottom: 12,
                            child: ElevatedButton(
                              onPressed: () async {
                                if (_avatarData == null) return;
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Avatar generieren?'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: const [
                                        Text(
                                          'Wir generieren automatisch einen lebensechten Avatar aus deinem Bild. Der Avatar spricht mit der ausgewählten Stimme oder Deiner eigenen.',
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          'WICHTIG: Dieser Vorgang kostet pro Vorgang 50 credits! Bitte überlege Dir also genau, welches Bild Du nutzen möchtest.',
                                          style: TextStyle(
                                            color: AppColors.accentGreenDark,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Abbrechen'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Generieren'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok != true) return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => AvatarEditorScreen(
                                      avatarId: _avatarData!.id,
                                      avatarName: _avatarData!.firstName,
                                      avatarImageUrl:
                                          _profileImageUrl ??
                                          _avatarData!.avatarImageUrl ??
                                          (_imageUrls.isNotEmpty
                                              ? _imageUrls.first
                                              : null),
                                    ),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.zero,
                                minimumSize: const Size.fromHeight(0),
                                elevation: 0,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text(
                                'Avatar generieren',
                                style: TextStyle(fontSize: 13, height: 1.2),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Button ist jetzt im Bild platziert
                  const SizedBox.shrink(),
                ],
              ),
              const SizedBox(width: spacing),
              // Galerie (max. 4) + Hinweistext darunter + Upload-Button (lila)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Upload zuerst, Galerie darunter
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _onAddImages,
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
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(color: Colors.white),
                            children: [
                              TextSpan(
                                text: 'Bild-Upload  ',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              TextSpan(
                                text: 'Avatarbild auswählen',
                                style: TextStyle(
                                  fontWeight: FontWeight.w400,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (ctx, cons) {
                        final double targetItemWidth = (cons.maxWidth / 3)
                            .clamp(minThumbWidth, 200.0);
                        final int cols = (cons.maxWidth / targetItemWidth)
                            .floor()
                            .clamp(2, 3); // mindestens 2 Spalten
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                mainAxisSpacing: gridSpacing,
                                crossAxisSpacing: gridSpacing,
                                childAspectRatio: 1,
                              ),
                          itemCount: remoteFour.length.clamp(0, 4),
                          itemBuilder: (context, index) {
                            final url = remoteFour[index];
                            final isCrown =
                                _profileImageUrl == url ||
                                (_profileImageUrl == null && index == 0);
                            return _imageThumbNetwork(url, isCrown);
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
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
          final double minRightWidth = (2 * minThumbWidth) + gridSpacing;
          double leftW = cons.maxWidth - spacing - minRightWidth;
          if (leftW > 240) leftW = 240;
          if (leftW < 160) leftW = 160;
          final double leftH = leftW * 1.5;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Video-Preview/Inline-Player links GROSS (responsive) + lokale Navigation oben
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: leftW,
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              if (_mediaTab != 'images') {
                                setState(() => _mediaTab = 'images');
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _mediaTab == 'images'
                                  ? AppColors.accentGreenDark
                                  : Colors.white24,
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: _mediaTab == 'images'
                                    ? AppColors.accentGreenDark
                                    : Colors.white24,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Bilder'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              if (_mediaTab != 'videos') {
                                setState(() => _mediaTab = 'videos');
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _mediaTab == 'videos'
                                  ? AppColors.accentGreenDark
                                  : Colors.white24,
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: _mediaTab == 'videos'
                                    ? AppColors.accentGreenDark
                                    : Colors.white24,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              'Videos',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: leftW,
                    height: leftH,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _inlineVideoController != null
                          ? AspectRatio(
                              aspectRatio: 9 / 16,
                              child: VideoPlayerWidget(
                                controller: _inlineVideoController!,
                              ),
                            )
                          : Container(
                              color: Colors.black26,
                              child: const Icon(
                                Icons.play_arrow,
                                color: Colors.white54,
                                size: 48,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: spacing),
              // Galerie (max. 4) – Upload-Button über den Thumbs
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _onAddVideos,
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
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(color: Colors.white),
                            children: [
                              TextSpan(
                                text: 'Video-Upload',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              TextSpan(
                                text: ' Trainingsvideos',
                                style: TextStyle(
                                  fontWeight: FontWeight.w400,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (ctx, cons) {
                        final double targetItemWidth = (cons.maxWidth / 3)
                            .clamp(minThumbWidth, 200.0);
                        final int cols = (cons.maxWidth / targetItemWidth)
                            .floor()
                            .clamp(2, 3);
                        final totalCount =
                            (remoteFour.length +
                            (4 - remoteFour.length)
                                .clamp(0, 4)
                                .clamp(0, _newVideoFiles.length));
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                mainAxisSpacing: gridSpacing,
                                crossAxisSpacing: gridSpacing,
                                childAspectRatio: 1,
                              ),
                          itemCount: totalCount,
                          itemBuilder: (context, index) {
                            if (index < remoteFour.length) {
                              return _videoThumbNetwork(remoteFour[index]);
                            }
                            final localIndex = index - remoteFour.length;
                            return _videoThumbLocal(_newVideoFiles[localIndex]);
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTextFilesList() {
    // Kombiniere Remote- und lokale Textdateien
    final List<Widget> tiles = [];

    // Remote URLs aus Firestore
    for (final url in _textFileUrls) {
      tiles.add(
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.description, color: Colors.white70),
          title: Text(
            _fileNameFromUrl(url),
            style: const TextStyle(color: Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Öffnen',
                icon: const Icon(Icons.open_in_new, color: Colors.white70),
                onPressed: () => _openUrl(url),
              ),
              IconButton(
                tooltip: 'Löschen',
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () => _confirmDeleteRemoteText(url),
              ),
            ],
          ),
        ),
      );
    }

    // Lokale (neu hinzugefügte) Textdateien – noch nicht hochgeladen
    for (final f in _newTextFiles) {
      tiles.add(
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(
            Icons.description_outlined,
            color: Colors.white54,
          ),
          title: Text(
            pathFromLocalFile(f.path),
            style: const TextStyle(color: Colors.white70),
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Anzeigen',
                icon: const Icon(
                  Icons.visibility_outlined,
                  color: Colors.white70,
                ),
                onPressed: () => _openLocalFile(f),
              ),
              IconButton(
                tooltip: 'Entfernen',
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => _confirmDeleteLocalText(f),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Textdateien',
          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        ...tiles,
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
                tooltip: 'Als Stimme wählen',
                icon: Icon(
                  _activeAudioUrl == url ? Icons.star : Icons.star_border,
                  color: _activeAudioUrl == url ? Colors.amber : Colors.white70,
                ),
                onPressed: () {
                  setState(() {
                    _activeAudioUrl = url;
                    _updateDirty();
                  });
                },
              ),
              IconButton(
                tooltip: 'Abspielen',
                icon: const Icon(Icons.play_arrow, color: Colors.white70),
                onPressed: () => _openUrl(url),
              ),
              IconButton(
                tooltip: 'Löschen',
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Audio löschen?'),
                      content: Text(
                        '${_fileNameFromUrl(url)} endgültig löschen?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Abbrechen'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Löschen'),
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
            '${pathFromLocalFile(f.path)} (neu)',
            style: const TextStyle(color: Colors.white70),
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            tooltip: 'Entfernen',
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
        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _onCloneVoice,
            icon: const Icon(Icons.auto_fix_high),
            label: Text(_isSaving ? 'Wird geklont...' : 'Stimme klonen'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isSaving
                  ? Colors.grey
                  : AppColors.accentGreenDark,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceParams() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Stimmeinstellungen',
          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(
              width: 90,
              child: Text('Stability', style: TextStyle(color: Colors.white70)),
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
            const SizedBox(
              width: 90,
              child: Text(
                'Similarity',
                style: TextStyle(color: Colors.white70),
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
            const SizedBox(
              width: 90,
              child: Text('Tempo', style: TextStyle(color: Colors.white70)),
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
            const SizedBox(
              width: 90,
              child: Text('Dialekt', style: TextStyle(color: Colors.white70)),
            ),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _voiceDialect,
                dropdownColor: Colors.black,
                items: const [
                  DropdownMenuItem(
                    value: 'de-DE',
                    child: Text(
                      'Deutsch (DE)',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'de-AT',
                    child: Text(
                      'Deutsch (AT)',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'de-CH',
                    child: Text(
                      'Deutsch (CH)',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'en-US',
                    child: Text(
                      'Englisch (US)',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'en-GB',
                    child: Text(
                      'Englisch (UK)',
                      style: TextStyle(color: Colors.white),
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
    );
    final ok = await _avatarService.updateAvatar(updated);
    if (ok && mounted) {
      _applyAvatar(updated);
      _showSystemSnack('Stimmeinstellungen gespeichert');
    }
  }

  Future<void> _onCloneVoice() async {
    if (_avatarData == null) return;
    if (_isSaving) {
      _showSystemSnack('Stimme wird bereits geklont...');
      return;
    }

    // SOFORT setState um Button zu disabled
    setState(() => _isSaving = true);

    if (_newAudioFiles.isNotEmpty) {
      setState(() => _isSaving = false);
      _showSystemSnack('Bitte zuerst speichern, dann klonen.');
      return;
    }
    final audios = List<String>.from(_avatarData!.audioUrls);
    if (audios.isEmpty) {
      setState(() => _isSaving = false);
      _showSystemSnack('Keine Audio-Stimmprobe vorhanden.');
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
      _showSystemSnack('Bitte markiere eine Audio-Datei mit dem Stern.');
      return;
    }
    try {
      await _showBlockingProgress(
        title: 'Stimme wird geklont…',
        message: 'Das dauert einen Moment. Bitte gedulde dich.',
        task: () async {
          final uid = FirebaseAuth.instance.currentUser!.uid;
          final base = dotenv.env['MEMORY_API_BASE_URL'];
          if (base == null || base.isEmpty) {
            _showSystemSnack('Backend-URL fehlt (.env MEMORY_API_BASE_URL)');
            return;
          }
          final uri = Uri.parse('$base/avatar/voice/create');
          final Map<String, dynamic> payload = {
            'user_id': uid,
            'avatar_id': _avatarData!.id,
            'audio_urls': selected,
            'name': _avatarData!.displayName,
          };
          // Dialekt/Tempo mitsenden, wenn vorhanden
          try {
            final v = _avatarData?.training?['voice'] as Map<String, dynamic>?;
            final tempo = (v?['tempo'] as num?)?.toDouble();
            final dialect = v?['dialect'] as String?;
            if (tempo != null) payload['tempo'] = tempo;
            if (dialect != null && dialect.isNotEmpty)
              payload['dialect'] = dialect;
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

          final res = await http.post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          );
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
                _showSystemSnack('Stimme geklont. Voice-ID gespeichert.');
                if (mounted) setState(() => _isDirty = false);
              } else {
                _showSystemSnack('Speichern der Voice-ID fehlgeschlagen.');
              }
            } else {
              _showSystemSnack('ElevenLabs: keine voice_id erhalten.');
            }
          } else {
            final detail = (res.body.isNotEmpty) ? ' ${res.body}' : '';
            _showSystemSnack('Klonen fehlgeschlagen: ${res.statusCode}$detail');
          }
        },
      );
    } catch (e) {
      _showSystemSnack('Klon-Fehler: $e');
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
        title: const Text('Datei entfernen?'),
        content: Text('${pathFromLocalFile(f.path)} wirklich entfernen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
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
        title: const Text('Datei löschen?'),
        content: Text('${_fileNameFromUrl(url)} endgültig löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await FirebaseStorageService.deleteFile(url);
        // Pinecone: zugehörige Chunks löschen (OR: file_url / file_path / file_name)
        try {
          final uid = FirebaseAuth.instance.currentUser!.uid;
          final avatarId = _avatarData!.id;
          await _triggerMemoryDelete(
            userId: uid,
            avatarId: avatarId,
            fileUrl: url,
            fileName: _fileNameFromUrl(url),
            filePath: _storagePathFromUrl(url),
          );
        } catch (_) {}
        _textFileUrls.remove(url);
        await _persistTextFileUrls();
        if (mounted) setState(() {});
      } catch (_) {}
    }
  }

  Future<void> _persistTextFileUrls() async {
    if (_avatarData == null) return;
    final allImages = [..._imageUrls];
    final allVideos = [..._videoUrls];
    final allTexts = [..._textFileUrls];

    final totalDocuments =
        allImages.length +
        allVideos.length +
        allTexts.length +
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
      training: training,
      updatedAt: DateTime.now(),
    );
    await _avatarService.updateAvatar(updated);
    _applyAvatar(updated);
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
    // Verwende die ersten ~6 Wörter als Schwerpunkt
    final words = text
        .replaceAll(RegExp(r"[\n\r\t_]+"), ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(6)
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
    return AspectRatio(
      aspectRatio: 1,
      child: GestureDetector(
        onTap: () => setState(() {
          if (_isDeleteMode) {
            if (selected) {
              _selectedRemoteImages.remove(url);
            } else {
              _selectedRemoteImages.add(url);
            }
          } else {
            _profileImageUrl = url;
            _updateDirty();
          }
        }),
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
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(url, fit: BoxFit.cover),
            ),
            if (isCrown)
              const Positioned(
                top: 4,
                left: 4,
                child: Icon(Icons.emoji_events, color: Colors.amber, size: 18),
              ),
            // keine Häkchen im Normalmodus
            if (_isDeleteMode)
              Positioned(
                top: 4,
                right: 4,
                child: Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected ? Colors.redAccent : Colors.white70,
                  size: 18,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // _imageThumbFile wurde im neuen Layout nicht mehr benötigt

  Widget _videoThumbNetwork(String url) {
    final selected = _selectedRemoteVideos.contains(url);
    return AspectRatio(
      aspectRatio: 1,
      child: GestureDetector(
        onTap: () {
          if (_isDeleteMode) {
            setState(() {
              if (selected) {
                _selectedRemoteVideos.remove(url);
              } else {
                _selectedRemoteVideos.add(url);
              }
            });
          } else {
            _playNetworkInline(url);
          }
        },
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
              if (_isDeleteMode)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected ? Colors.redAccent : Colors.white70,
                    size: 18,
                  ),
                ),
              if (!_isDeleteMode)
                const Align(
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.play_circle_fill,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _videoThumbLocal(File file) {
    final key = file.path;
    final selected = _selectedLocalVideos.contains(key);
    return AspectRatio(
      aspectRatio: 1,
      child: GestureDetector(
        onTap: () {
          if (_isDeleteMode) {
            setState(() {
              if (selected) {
                _selectedLocalVideos.remove(key);
              } else {
                _selectedLocalVideos.add(key);
              }
            });
          } else {
            _playLocalInline(file);
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            fit: StackFit.expand,
            children: [
              FutureBuilder<Uint8List?>(
                future: _thumbnailForLocal(file.path),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data != null) {
                    return Image.memory(snapshot.data!, fit: BoxFit.cover);
                  }
                  return Container(color: Colors.black26);
                },
              ),
              if (_isDeleteMode)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected ? Colors.redAccent : Colors.white70,
                    size: 18,
                  ),
                ),
              if (!_isDeleteMode)
                const Align(
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.play_circle_fill,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _playNetworkInline(String url) async {
    try {
      // Vorherigen Controller freigeben
      await _inlineVideoController?.dispose();
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      setState(() => _inlineVideoController = controller);
    } catch (e) {
      // Versuch: Download-URL auffrischen (z.B. abgelaufener Token)
      try {
        final fresh = await _refreshDownloadUrl(url);
        if (fresh != null) {
          final controller = VideoPlayerController.networkUrl(Uri.parse(fresh));
          await controller.initialize();
          setState(() => _inlineVideoController = controller);
          // gespeicherte URL ersetzen und persistieren
          final idx = _videoUrls.indexOf(url);
          if (idx >= 0) {
            _videoUrls[idx] = fresh;
            await _persistTextFileUrls();
          }
          return;
        }
      } catch (_) {}
      _showSystemSnack('Video kann nicht geladen werden');
    }
  }

  // Lokales Video im großen Player abspielen
  Future<void> _playLocalInline(File file) async {
    try {
      await _inlineVideoController?.dispose();
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      setState(() => _inlineVideoController = controller);
    } catch (e) {
      _showSystemSnack('Lokales Video kann nicht geladen werden');
    }
  }

  Future<Uint8List?> _thumbnailForRemote(String url) async {
    try {
      if (_videoThumbCache.containsKey(url)) return _videoThumbCache[url];
      var effectiveUrl = url;
      var res = await http.get(Uri.parse(effectiveUrl));
      if (res.statusCode != 200) {
        final fresh = await _refreshDownloadUrl(url);
        if (fresh != null) {
          effectiveUrl = fresh;
          res = await http.get(Uri.parse(effectiveUrl));
          if (res.statusCode != 200) return null;
          // Cache frische URL direkt ablegen, damit Thumbs stabil sind
          final idx = _videoUrls.indexOf(url);
          if (idx >= 0) _videoUrls[idx] = fresh;
          // kein persist hier, damit UI flott bleibt; persist passiert beim Speichern
        } else {
          return null;
        }
      }
      final tmp = await File(
        '${Directory.systemTemp.path}/thumb_${DateTime.now().microsecondsSinceEpoch}.mp4',
      ).create();
      await tmp.writeAsBytes(res.bodyBytes);
      final data = await VideoThumbnail.thumbnailData(
        video: tmp.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 360,
        quality: 60,
      );
      if (data != null) _videoThumbCache[url] = data;
      try {
        // optional: Tempdatei löschen
        await tmp.delete();
      } catch (_) {}
      return data;
    } catch (_) {
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

  Future<Uint8List?> _thumbnailForLocal(String path) async {
    try {
      if (_videoThumbCache.containsKey(path)) return _videoThumbCache[path]!;
      final data = await VideoThumbnail.thumbnailData(
        video: path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 360,
        quality: 60,
      );
      if (data != null) _videoThumbCache[path] = data;
      return data;
    } catch (_) {
      return null;
    }
  }

  // _bigMediaButton entfällt im neuen Layout

  Future<void> _onAddImages() async {
    ImageSource? source;
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      source = ImageSource.gallery; // Kamera nicht unterstützen auf Desktop
    } else {
      source = await _chooseSource('Bildquelle wählen');
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
          final File f = File(files[i].path);
          final String path =
              'avatars/$uid/$avatarId/images/${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
          final url = await FirebaseStorageService.uploadImage(
            f,
            customPath: path,
          );
          if (url != null) {
            if (!mounted) return;
            setState(() {
              _imageUrls.add(url);
              _profileImageUrl ??= _imageUrls.first;
            });
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
        final File f = File(x.path);
        final String path =
            'avatars/$uid/$avatarId/images/${DateTime.now().millisecondsSinceEpoch}_cam.jpg';
        final url = await FirebaseStorageService.uploadImage(
          f,
          customPath: path,
        );
        if (url != null) {
          if (!mounted) return;
          setState(() {
            _imageUrls.add(url);
            _profileImageUrl ??= _imageUrls.first;
          });
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
    if (result != null) {
      setState(() {
        for (final f in result.files) {
          if (f.path != null) _newAudioFiles.add(File(f.path!));
        }
        _updateDirty();
      });
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
              title: const Text('Galerie'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Kamera'),
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
          label: 'Vorname *',
          hint: 'Gib den Vornamen ein',
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Vorname ist erforderlich';
            }
            return null;
          },
        ),

        const SizedBox(height: 16),

        // Spitzname (optional)
        _buildTextField(
          controller: _nicknameController,
          label: 'Spitzname',
          hint: 'Gib einen Spitznamen ein (optional)',
        ),

        const SizedBox(height: 16),

        // Nachname (optional)
        _buildTextField(
          controller: _lastNameController,
          label: 'Nachname',
          hint: 'Gib den Nachnamen ein (optional)',
        ),

        const SizedBox(height: 16),

        // Geburtsdatum (optional)
        _buildDateField(
          controller: _birthDateController,
          label: 'Geburtsdatum',
          hint: 'Wähle das Geburtsdatum',
          onTap: () => _selectBirthDate(),
        ),

        const SizedBox(height: 16),

        // Sterbedatum (optional)
        _buildDateField(
          controller: _deathDateController,
          label: 'Sterbedatum',
          hint: 'Wähle das Sterbedatum (optional)',
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
        title: const Text(
          'Personendaten',
          style: TextStyle(color: Colors.white),
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
            'Berechnetes Alter: $_calculatedAge Jahre',
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
          final filename = 'schatzy_${slug}_$ts.txt';
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

        // Upload Images einzeln
        for (int i = 0; i < _newImageFiles.length; i++) {
          final url = await FirebaseStorageService.uploadImage(
            _newImageFiles[i],
            customPath:
                'avatars/${FirebaseAuth.instance.currentUser!.uid}/$avatarId/images/${DateTime.now().millisecondsSinceEpoch}_$i.jpg',
          );
          if (url != null) allImages.add(url);
        }

        // Upload Videos einzeln
        for (int i = 0; i < _newVideoFiles.length; i++) {
          final url = await FirebaseStorageService.uploadVideo(
            _newVideoFiles[i],
            customPath:
                'avatars/${FirebaseAuth.instance.currentUser!.uid}/$avatarId/videos/${DateTime.now().millisecondsSinceEpoch}_$i.mp4',
          );
          if (url != null) allVideos.add(url);
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

        // c) sonstige neue Textdateien hochladen (sichtbar)
        for (int i = 0; i < _newTextFiles.length; i++) {
          final baseName = p.basename(_newTextFiles[i].path);
          final safeName = baseName.endsWith('.txt')
              ? baseName
              : '$baseName.txt';
          final storagePath =
              'avatars/${FirebaseAuth.instance.currentUser!.uid}/$avatarId/texts/$safeName';
          final url = await FirebaseStorageService.uploadTextFile(
            _newTextFiles[i],
            customPath: storagePath,
          );
          if (url != null) {
            allTexts.add(url);
          }
        }

        // Upload Audio Files einzeln (wird gespeichert und im Avatar geführt)
        final List<String> allAudios = [...(_avatarData?.audioUrls ?? [])];
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

        final ok = await _avatarService.updateAvatar(updated);
        if (!mounted) return;
        if (ok) {
          if (!mounted) return;
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Erfolgreich gespeichert'),
              content: const Text(
                'Deine Daten wurden erfolgreich gespeichert.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
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
          if (combinedText.trim().isNotEmpty) {
            () async {
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
                // nur loggen, UI nicht stören
                // ignore: avoid_print
                print('Memory insert failed: $e');
              }
            }();
          }
          // Immer: profile.txt als Chunks in Pinecone aktualisieren (stable file)
          () async {
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
          }();
          // Jetzt lokale Textdateien leeren (nachdem wir sie gelesen/gesendet haben)
          _newTextFiles.clear();
          _newAudioFiles.clear();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Speichern fehlgeschlagen')),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler: $e')));
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
    return dotenv.env['MEMORY_API_BASE_URL'] ?? '';
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
      if (fileUrl != null) 'file_url': fileUrl,
      if (fileName != null) 'file_name': fileName,
      if (filePath != null) 'file_path': filePath,
    };
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Memory insert HTTP ${res.statusCode}: ${res.body}');
    }
  }

  Future<void> _triggerMemoryDelete({
    required String userId,
    required String avatarId,
    String? fileUrl,
    String? fileName,
    String? filePath,
  }) async {
    final uri = Uri.parse(
      '${_memoryApiBaseUrl()}/avatar/memory/delete/by-file',
    );
    final Map<String, dynamic> payload = {
      'user_id': userId,
      'avatar_id': avatarId,
      if (fileUrl != null) 'file_url': fileUrl,
      if (fileName != null) 'file_name': fileName,
      if (filePath != null) 'file_path': filePath,
    };
    await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
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
        title: const Text('Bilder löschen?'),
        content: Text('Möchtest du $total Bild(er) wirklich löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
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
    // Local entfernen (Bilder)
    _newImageFiles.removeWhere((f) => _selectedLocalImages.contains(f.path));
    // Local entfernen (Videos)
    _newVideoFiles.removeWhere((f) => _selectedLocalVideos.contains(f.path));
    _selectedRemoteImages.clear();
    _selectedLocalImages.clear();
    _selectedRemoteVideos.clear();
    _selectedLocalVideos.clear();
    _isDeleteMode = false;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final backgroundImage = _profileImageUrl ?? _avatarData?.avatarImageUrl;

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: () => Navigator.pop(context),
          child: const Text('Datenwelt schließen'),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (_isDirty)
            IconButton(
              tooltip: 'Speichern',
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
        decoration: backgroundImage != null
            ? BoxDecoration(
                image: DecorationImage(
                  image: NetworkImage(backgroundImage),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    Colors.black.withValues(alpha: 0.7),
                    BlendMode.darken,
                  ),
                ),
              )
            : null,
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

                const SizedBox(height: 24),

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
    _birthDateController.dispose();
    _deathDateController.dispose();
    _inlineVideoController?.dispose();
    super.dispose();
  }
}
