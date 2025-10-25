import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import '../models/avatar_data.dart';
import '../services/env_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http_parser/http_parser.dart';
import 'package:provider/provider.dart';
import '../services/localization_service.dart';
import '../services/livekit_service.dart';
import '../services/lipsync/lipsync_strategy.dart';
import '../services/lipsync/lipsync_factory.dart';
import '../config.dart';
import '../theme/app_theme.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:video_player/video_player.dart';
import '../services/playlist_service.dart';
import '../services/media_service.dart';
import '../services/shared_moments_service.dart';
import '../services/moments_service.dart';
import '../services/media_purchase_service.dart';
import '../models/media_models.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/liveportrait_canvas.dart';
import '../widgets/chat_bubbles/user_message_bubble.dart';
import '../widgets/chat_bubbles/avatar_message_bubble.dart';
import '../widgets/hero_chat_fab_button.dart';
import '../widgets/media/timeline_media_slider.dart';
import '../widgets/media/timeline_media_overlay.dart';
import 'hero_chat_screen.dart';

// GLOBAL Guard: verhindert mehrfache /publisher/start Calls über Widget-Lifecycle hinweg!
final Map<String, DateTime> _globalActiveMuseTalkRooms = {};

class AvatarChatScreen extends StatefulWidget {
  final String? avatarId; // Optional: Für Overlay-Chat
  final VoidCallback? onClose; // Optional: Für Overlay-Chat

  const AvatarChatScreen({super.key, this.avatarId, this.onClose});

  @override
  State<AvatarChatScreen> createState() => _AvatarChatScreenState();
}

class _AvatarChatScreenState extends State<AvatarChatScreen>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _messageController = TextEditingController();
  bool _inputFocused = false;
  bool _firstValidSend = false; // vermeidet Kosten vor erstem echten Senden
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final Map<String, Timer> _deleteTimers = {}; // Hero Chat Lösch-Timer
  DocumentSnapshot? _lastMessageDoc; // Für Infinite Scroll Pagination
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  Timer? _publisherIdleTimer; // Stoppt MuseTalk bei Inaktivität (Kostenbremse)
  bool _isRecording = false;
  bool _isTyping = false;
  double _chatHeight = 200.0; // Resizable Chat-Höhe
  bool _chatHandleHovered = false;
  bool _isStreamingSpeaking = false; // steuert LivePortrait Canvas
  bool _isFileSpeaking = false; // steuert Datei‑Replay
  // ignore: unused_field
  final bool _isMuted =
      false; // UI Mute (wirkt auf TTS-Player; LiveKit bleibt unverändert)
  bool _isStoppingPlayback = false;
  bool _historyLoaded = false; // History vorhanden, aber initial nicht eingeblendet
  // Multi-Delete-Modus (WhatsApp-Style)
  bool _isMultiDeleteMode = false;
  final Set<String> _selectedMessageIds = {};
  
  // Timeline Integration (Playlist-basiert)
  AvatarMedia? _activeTimelineItem;
  Timer? _timelineTimer;
  bool _timelineSliderVisible = false;
  List<AvatarMedia> _timelineItems = []; // Media Assets
  List<Map<String, dynamic>> _timelineItemsMetadata = []; // Playlist Metadata (minutes, delaySec, startSec)
  int _timelineCurrentIndex = 0; // Aktueller Index
  final Stopwatch _chatStopwatch = Stopwatch(); // Chat-Zeit (00:00 bei Start)
  bool _timelineLoop = false; // Loop am Ende?
  
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _playerPositionSub;
  StreamSubscription<VisemeEvent>? _visemeSub;
  final GlobalKey<LivePortraitCanvasState> _lpKey =
      GlobalKey<LivePortraitCanvasState>();
  StreamSubscription<PcmChunkEvent>? _pcmSub;

  // Live Avatar Animation (Sequential Chunked Loading für schnellen Start!)
  VideoPlayerController? _idleController; // Full 10s Loop (lädt im Hintergrund)
  VideoPlayerController?
  _chunk1Controller; // 2s (lädt zuerst, sofortiger Start!)
  VideoPlayerController? _chunk2Controller; // 4s (preload während Chunk1)
  VideoPlayerController? _chunk3Controller; // 4s (preload während Chunk2)
  int _currentChunk = 0; // 0=none, 1=chunk1, 2=chunk2, 3=chunk3, 4=idle.mp4
  bool _liveAvatarEnabled = false;
  bool _hasIdleDynamics = false;
  String? _idleVideoUrl;
  String? _chunk1Url;
  String? _chunk2Url;
  String? _chunk3Url;
  String? _cachedHeroChunkUrl; // Cache für sync Zugriff in build()

  // Rate-Limiting für TTS-Requests
  DateTime? _lastTtsRequestTime;
  static const int _minTtsDelayMs =
      800; // Mindestens 800ms zwischen TTS-Requests

  String? _partnerName;
  String? _pendingFullName;
  String? _pendingLooseName;
  bool _awaitingNameConfirm = false;
  final bool _pendingIsKnownPartner = false;
  bool _isKnownPartner = false;
  String? _partnerPetName;
  String? _partnerRole;

  AvatarData? _avatarData;
  String? _cachedVoiceId; // Cache für schnellen Zugriff!
  final AudioPlayer _player = AudioPlayer();
  late LipsyncStrategy _lipsync;
  String? _lastRecordingPath;
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _ampSub;
  DateTime? _segmentStartAt;
  // ENTFERNT: Widget-lokale Guards (ersetzt durch globale Map!)
  // String? _activeMuseTalkRoom;
  // DateTime? _museTalkSessionStartedAt;
  String?
  _persistentRoomName; // Room-Name bleibt während gesamter Chat-Session gleich!
  int _silenceMs = 0;
  bool _sttBusy = false;
  bool _segmentClosing = false;
  // Kosten: MuseTalk nicht mehr vorab starten – erst beim ersten Sprechen
  static const bool _kPrestartMuseTalk = false;

  // Hinweis-Banner (GMBC) oberhalb der Input-Leiste
  String? _bannerText; // z.B. "Bitte Text prüfen und Senden tippen."
  Timer? _bannerTimer;

  // Image Timeline für automatischen Bildwechsel
  String? _currentBackgroundImage;
  Timer? _imageTimer;
  int _currentImageIndex = 0;
  List<String> _imageUrls = [];
  List<String> _activeImageUrls = []; // Nur aktive Bilder
  Map<String, int> _imageDurations = {}; // URL -> Sekunden
  Map<String, bool> _imageActive = {}; // URL -> aktiv
  bool _isImageLoopMode = true;
  bool _isTimelineEnabled = true;

  // Timeline-Daten aus Firebase laden und Timer starten
  Future<void> _loadAndStartImageTimeline(String avatarId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('avatars')
          .doc(avatarId)
          .get()
          .timeout(const Duration(seconds: 5));
      if (!doc.exists || doc.data() == null) return;

      final data = doc.data()!;

      // ImageUrls laden
      final images = data['imageUrls'] as List<dynamic>?;
      if (images != null && images.isNotEmpty) {
        _imageUrls = images.cast<String>();
      }

      // Timeline-Daten laden
      final timeline = data['imageTimeline'] as Map<String, dynamic>?;
      if (timeline != null) {
        final durationsMap = timeline['durations'] as Map<String, dynamic>?;
        if (durationsMap != null) {
          _imageDurations = durationsMap.map((k, v) {
            final duration = (v as int?) ?? 60;
            // WICHTIG: Mindestens 60 Sekunden (1 Minute)
            return MapEntry(k, duration < 60 ? 60 : duration);
          });
        }
        final loopMode = timeline['loopMode'];
        if (loopMode is bool) {
          _isImageLoopMode = loopMode;
        }
        final enabled = timeline['enabled'];
        if (enabled is bool) {
          _isTimelineEnabled = enabled;
        }
        final activeMap = timeline['active'] as Map<String, dynamic>?;
        if (activeMap != null) {
          _imageActive = activeMap.map(
            (k, v) => MapEntry(k, v as bool? ?? true),
          );
        }
      }

      // Filtere nur aktive Bilder
      // Hero-Image (Position 0) ist IMMER aktiv
      _activeImageUrls = _imageUrls
          .asMap()
          .entries
          .where((entry) {
            final index = entry.key;
            final url = entry.value;
            final isHero = index == 0; // Hero-Image ist IMMER Position 0
            final isActive =
                isHero || (_imageActive[url] ?? true); // Hero IMMER aktiv
            return isActive; // Alle aktiven Bilder anzeigen
          })
          .map((entry) => entry.value)
          .toList();

      // Starte mit erstem AKTIVEN Bild (Hero-Image) - nur wenn Timeline aktiviert
      if (_isTimelineEnabled && _activeImageUrls.isNotEmpty) {
        _currentImageIndex = 0;
        _currentBackgroundImage = _activeImageUrls[0];
        // Lade erstes Bild vor, um Flackern zu vermeiden
        if (_activeImageUrls.isNotEmpty && mounted) {
          precacheImage(NetworkImage(_activeImageUrls[0]), context);
        }
        _startImageTimer();
      } else if (_imageUrls.isNotEmpty) {
        // Timeline deaktiviert: Zeige nur Hero-Image (statisch)
        _currentBackgroundImage = _imageUrls[0];
        // Lade Hero-Image vor
        if (mounted) {
          precacheImage(NetworkImage(_imageUrls[0]), context);
        }
      }

      debugPrint(
        '✅ Image Timeline geladen: ${_activeImageUrls.length}/${_imageUrls.length} aktive Bilder, Loop: $_isImageLoopMode, Enabled: $_isTimelineEnabled',
      );
      if (_activeImageUrls.isNotEmpty) {
        final firstUrl = _activeImageUrls[0];
        final firstDuration = _imageDurations[firstUrl] ?? 60;
        debugPrint('⏱️ Erste Bild-Duration: $firstDuration Sekunden');
      }
    } catch (e) {
      debugPrint('❌ Fehler beim Laden der Image Timeline: $e');
    }
  }

  // Timer für Bildwechsel starten (nur aktive Bilder)
  void _startImageTimer() {
    _imageTimer?.cancel();
    if (_activeImageUrls.isEmpty || !_isTimelineEnabled) return;

    // Duration für aktuelles AKTIVES Bild
    final currentUrl = _activeImageUrls[_currentImageIndex];
    final duration = Duration(seconds: _imageDurations[currentUrl] ?? 60);

    // VORLADEN: Nächstes Bild bereits jetzt in den Cache laden
    final nextIndex = (_currentImageIndex + 1) % _activeImageUrls.length;
    if (nextIndex < _activeImageUrls.length) {
      final nextUrl = _activeImageUrls[nextIndex];
      precacheImage(NetworkImage(nextUrl), context);
    }

    _imageTimer = Timer(duration, () {
      if (!mounted) return;

      // Berechne nächstes Bild VORHER
      int nextImageIndex = _currentImageIndex + 1;

      // Loop oder Ende?
      if (nextImageIndex >= _activeImageUrls.length) {
        if (_isImageLoopMode) {
          nextImageIndex = 0; // Zurück zum Anfang
        } else {
          // Ende: Bleibt beim letzten
          _imageTimer?.cancel();
          return;
        }
      }

      // Setze neues Bild (ist bereits gecached → kein Flackern)
      setState(() {
        _currentImageIndex = nextImageIndex;
        _currentBackgroundImage = _activeImageUrls[_currentImageIndex];
      });

      // Nächsten Timer starten
      _startImageTimer();
    });
  }

  // Timer stoppen
  // ignore: unused_element
  void _stopImageTimer() {
    _imageTimer?.cancel();
    _imageTimer = null;
  }

  static const int _silenceThresholdDb = -40;
  static const int _silenceHoldMs = 800;
  static const int _minSegmentMs = 1200;
  static const bool kAutoSend = false;

  // Hinweis: Für Tests nicht genutzt; Tages-Limit wird später reaktiviert
  // bool _greetedOnce = false;

  // Playlist/Teaser
  final PlaylistService _playlistSvc = PlaylistService();
  final MediaService _mediaSvc = MediaService();
  final SharedMomentsService _momentsSvc = SharedMomentsService();
  Timer? _teaserTimer;
  AvatarMedia? _pendingTeaserMedia;
  OverlayEntry? _teaserEntry;

  Future<void> _maybeJoinLiveKit() async {
    try {
      // GUARD: Wenn bereits connected, skip!
      if (LiveKitService().isConnected && LiveKitService().roomName != null) {
        debugPrint(
          '⏭️ LiveKit bereits connected (room: ${LiveKitService().roomName})',
        );
        return;
      }

      if ((dotenv.env['LIVEKIT_ENABLED'] ?? '').trim() != '1') {
        debugPrint('⚠️ LiveKit DISABLED (LIVEKIT_ENABLED != 1)');
        return;
      }
      final base = EnvService.memoryApiBaseUrl();
      final tokenUrlEnv = (dotenv.env['LIVEKIT_TOKEN_URL'] ?? '').trim();
      debugPrint('🔑 LiveKit Token URL: $tokenUrlEnv');
      Uri? tokenUri;

      if (tokenUrlEnv.isNotEmpty) {
        // Explizit gesetzter Token‑Endpoint (Orchestrator o.ä.)
        tokenUri = Uri.parse(tokenUrlEnv);
      } else if (base.isEmpty) {
        // Fallback: Direkt aus .env joinen, wenn ein Test‑Token hinterlegt ist
        final testToken = (dotenv.env['LIVEKIT_TEST_TOKEN'] ?? '').trim();
        final url = (dotenv.env['LIVEKIT_URL'] ?? '').trim();
        if (testToken.isNotEmpty && url.isNotEmpty) {
          await LiveKitService().join(
            room: (dotenv.env['LIVEKIT_TEST_ROOM'] ?? 'sunriza').trim(),
            token: testToken,
            urlOverride: url,
          );
        }
        return;
      } else {
        tokenUri = Uri.parse('$base/livekit/token');
      }
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || _avatarData == null) return;

      // Raum vorab bestimmen (für GET-Fallback nutzbar)
      String roomCandidate =
          LiveKitService().roomName ?? _persistentRoomName ?? '';
      if (roomCandidate.isEmpty) {
        final uid = user.uid;
        final short = uid.length >= 8 ? uid.substring(0, 8) : uid;
        roomCandidate = 'mt-$short-${DateTime.now().millisecondsSinceEpoch}';
        _persistentRoomName = roomCandidate;
        debugPrint('🆕 Pre-generated room candidate: $roomCandidate');
      }
      // Avatar-Info optional senden (fire-and-forget, mit kurzem Timeout)
      unawaited(() async {
        try {
          final infoRes = await http
              .post(
                Uri.parse('$base/avatar/info'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'user_id': user.uid,
                  'avatar_id': _avatarData!.id,
                }),
              )
              .timeout(const Duration(seconds: 3));
          if (infoRes.statusCode >= 200 && infoRes.statusCode < 300) {
            final info = jsonDecode(infoRes.body) as Map<String, dynamic>;
            final imgUrl = (info['avatar_image_url'] as String?)?.trim();
            if (imgUrl != null && imgUrl.isNotEmpty) {
              // optional nutzbar
            }
          }
        } catch (_) {}
      }());
      final uri = tokenUri;
      debugPrint('🌐 Requesting LiveKit token from: $uri');
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': user.uid,
              'avatar_id': _avatarData!.id,
              'name': user.displayName,
              'avatar_image_url': _avatarData?.avatarImageUrl,
            }),
          )
          .timeout(const Duration(seconds: 6));
      debugPrint('📥 Token response: ${res.statusCode}');
      Map<String, dynamic>? data;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        data = jsonDecode(res.body) as Map<String, dynamic>;
      } else {
        debugPrint('⚠️ Token POST failed (${res.statusCode}) – trying GET...');
        try {
          final getUri = Uri.parse(
            tokenUri.toString(),
          ).replace(queryParameters: {'room': roomCandidate});
          final getRes = await http
              .get(getUri)
              .timeout(const Duration(seconds: 6));
          debugPrint('📥 Token GET response: ${getRes.statusCode}');
          if (getRes.statusCode >= 200 && getRes.statusCode < 300) {
            data = jsonDecode(getRes.body) as Map<String, dynamic>;
          }
        } catch (e) {
          debugPrint('⚠️ Token GET exception: $e');
        }

        if (data == null) {
          // Letzter Fallback: .env Test‑Join
          final testToken = (dotenv.env['LIVEKIT_TEST_TOKEN'] ?? '').trim();
          final url = (dotenv.env['LIVEKIT_URL'] ?? '').trim();
          final fallbackRoom = (dotenv.env['LIVEKIT_TEST_ROOM'] ?? 'sunriza')
              .trim();
          if (testToken.isNotEmpty && url.isNotEmpty) {
            debugPrint('⚠️ Falling back to TEST env token');
            await LiveKitService().join(
              room: fallbackRoom,
              token: testToken,
              urlOverride: url,
            );
          }
          return;
        }
      }

      final token = (data['token'] as String?)?.trim();
      String? room = (data['room'] as String?)?.trim();
      final lkUrl = (data['url'] as String?)?.trim();
      // Dynamischer Raum, falls Backend keinen liefert ODER statischen Default liefert
      const knownStaticRooms = {'sunriza26', 'sunriza'};
      if (room == null || room.isEmpty || knownStaticRooms.contains(room)) {
        // WICHTIG: Room nur 1× generieren (persistent über Chat-Sessions hinweg!)
        // 1. Prüfe ob LiveKit schon einen Room hat (vom vorherigen Chat)
        final existingRoom = LiveKitService().roomName;
        if (existingRoom != null &&
            existingRoom.isNotEmpty &&
            existingRoom.startsWith('mt-')) {
          room = existingRoom;
          _persistentRoomName = existingRoom;
          debugPrint(
            '♻️ Wiederverwendeter Room: $room (LiveKit noch connected!)',
          );
        } else if (_persistentRoomName == null ||
            _persistentRoomName!.isEmpty) {
          // 2. Ansonsten: vorab generierten Room verwenden
          _persistentRoomName = roomCandidate;
          room = _persistentRoomName!;
          debugPrint('🆕 Using pre-generated room: $_persistentRoomName');
        } else {
          // 3. Fallback: persistentRoomName aus dieser Widget-Instanz
          room = _persistentRoomName!;
        }
      }
      if (token == null || token.isEmpty) {
        // Versuch: GET-Fallback wenn POST ok, aber ohne Token
        try {
          final getUri = Uri.parse(
            tokenUri.toString(),
          ).replace(queryParameters: {'room': room ?? roomCandidate});
          final getRes = await http
              .get(getUri)
              .timeout(const Duration(seconds: 6));
          if (getRes.statusCode >= 200 && getRes.statusCode < 300) {
            final d2 = jsonDecode(getRes.body) as Map<String, dynamic>;
            final t2 = (d2['token'] as String?)?.trim();
            final u2 = (d2['url'] as String?)?.trim();
            final r2 = (d2['room'] as String?)?.trim();
            if (t2 != null && t2.isNotEmpty && u2 != null && u2.isNotEmpty) {
              await LiveKitService().join(
                room: r2 ?? room ?? roomCandidate,
                token: t2,
                urlOverride: u2,
              );
              return;
            }
          }
        } catch (_) {}

        // Fallback: .env Test‑Join
        final testToken = (dotenv.env['LIVEKIT_TEST_TOKEN'] ?? '').trim();
        final url = (dotenv.env['LIVEKIT_URL'] ?? '').trim();
        final fallbackRoom = (dotenv.env['LIVEKIT_TEST_ROOM'] ?? 'sunriza')
            .trim();
        if (testToken.isNotEmpty && url.isNotEmpty) {
          debugPrint('⚠️ Token missing – fallback to TEST env');
          await LiveKitService().join(
            room: fallbackRoom,
            token: testToken,
            urlOverride: url,
          );
        }
        return;
      }
      // Token für möglichen Reconnect hinterlegen (nur im Flutter-Prozess)
      try {
        // Achtung: .env ist nur für Boot-Config; hier nur in-memory speichern wäre sauberer.
        // Wir verwenden dotenv hier nicht zum Schreiben; daher nur Service-intern.
        // Falls gewünscht, könnte man einen kleinen TokenCache-Service ergänzen.
      } catch (_) {}
      // Mapping wie im PDF: NEXT_PUBLIC_LIVEKIT_URL == LIVEKIT_URL → vom Backend geliefert
      debugPrint('✅ Joining LiveKit: room=$room, url=$lkUrl');
      try {
        await Future.any([
          LiveKitService().join(room: room, token: token, urlOverride: lkUrl),
          Future.delayed(
            const Duration(seconds: 8),
            () => throw TimeoutException('LiveKit join timeout (8s)'),
          ),
        ]);
        debugPrint('✅ LiveKit connected successfully!');
      } catch (joinError) {
        debugPrint('❌ LiveKit join failed (attempt 1/2): $joinError');
        // Retry nach 2s (Network glitch, etc.)
        await Future.delayed(const Duration(seconds: 2));
        try {
          debugPrint('🔄 Retrying LiveKit join...');
          await Future.any([
            LiveKitService().join(room: room, token: token, urlOverride: lkUrl),
            Future.delayed(
              const Duration(seconds: 8),
              () => throw TimeoutException('LiveKit join retry timeout (8s)'),
            ),
          ]);
          debugPrint('✅ LiveKit connected on retry!');
        } catch (retryError) {
          debugPrint('❌ LiveKit join failed permanently: $retryError');
          // User kann trotzdem chatten (ohne Video/Audio)
        }
      }
    } catch (e) {
      debugPrint('❌ LiveKit setup failed: $e');
    }
  }

  Future<void> _startLiveKitPublisher(
    String room,
    String avatarId,
    String voiceId,
  ) async {
    // GLOBAL GUARD: Verhindere doppelte /session/start Calls über Widget-Lifecycle hinweg!
    final now = DateTime.now();
    final lastStarted = _globalActiveMuseTalkRooms[room];

    if (lastStarted != null) {
      final age = now.difference(lastStarted);
      if (age.inSeconds < 3) {
        // Session gerade gestartet (< 3s) → SKIP Doppelstart!
        debugPrint(
          '⏭️ MuseTalk session gerade gestartet für room=$room (age: ${age.inSeconds}s) - SKIP!',
        );
        return;
      } else {
        // Session älter als 3s → Kann neu starten
        debugPrint(
          '🔄 MuseTalk Guard abgelaufen (${age.inSeconds}s) - Neustart erlaubt',
        );
        _globalActiveMuseTalkRooms.remove(room);
      }
    }

    // WICHTIG: Guard SOFORT setzen (synchron), BEVOR await kommt!
    _globalActiveMuseTalkRooms[room] = now;
    debugPrint('🔒 GLOBAL MuseTalk Guard gesetzt für room=$room');

    try {
      // Get idle video URL + frames.zip URL + latents URL from Firestore
      String? idleVideoUrl;
      String? framesZipUrl;
      String? latentsUrl;
      if (_avatarData != null) {
        final doc = await FirebaseFirestore.instance
            .collection('avatars')
            .doc(_avatarData!.id)
            .get()
            .timeout(const Duration(seconds: 5));

        if (doc.exists) {
          final data = doc.data();
          final dynamics = data?['dynamics'] as Map<String, dynamic>?;
          final basicDynamics = dynamics?['basic'] as Map<String, dynamic>?;
          idleVideoUrl = basicDynamics?['idleVideoUrl'] as String?;
          framesZipUrl = basicDynamics?['framesZipUrl'] as String?;
          latentsUrl = basicDynamics?['latentsUrl'] as String?;
        }
      }

      // Ohne idle.mp4 KEIN Lipsync/MuseTalk
      if (idleVideoUrl == null || idleVideoUrl.isEmpty) {
        debugPrint('🛑 Kein idle.mp4 – Lipsync/MuseTalk deaktiviert');
        return;
      }

      final orchUrl = AppConfig.orchestratorUrl
          .replaceFirst('wss://', 'https://')
          .replaceFirst('ws://', 'http://');
      final url = orchUrl.endsWith('/')
          ? '${orchUrl}publisher/start'
          : '$orchUrl/publisher/start';
      debugPrint('🎬 Starting MuseTalk publisher: $url');
      debugPrint('📹 Idle video: $idleVideoUrl');
      if (framesZipUrl != null && framesZipUrl.isNotEmpty) {
        debugPrint('🖼️ Frames zip: $framesZipUrl');
      }

      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'room': room,
          'avatar_id': avatarId,
          'idle_video_url': idleVideoUrl,
        }),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        debugPrint('✅ MuseTalk publisher started');
      } else {
        debugPrint('⚠️ Publisher start failed: ${res.statusCode}');
      }

      // Direkt MuseTalk Session im gleichen Room starten (Service-API)
      try {
        final mtUrl = AppConfig.museTalkHttpUrl.endsWith('/')
            ? '${AppConfig.museTalkHttpUrl}session/start'
            : '${AppConfig.museTalkHttpUrl}/session/start';
        final payload = <String, dynamic>{
          'room': room,
          'connect_livekit': true,
        };
        // Nur idle.mp4 erlauben
        payload['idle_video_url'] = idleVideoUrl;
        await http.post(
          Uri.parse(mtUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 10));
        debugPrint('✅ MuseTalk session started (room=$room)');
      } catch (e) {
        debugPrint('⚠️ MuseTalk session start failed: $e');
        // Bei Fehler: Guard zurücksetzen, damit Retry möglich ist
        _globalActiveMuseTalkRooms.remove(room);
      }
    } catch (e) {
      debugPrint('❌ Publisher start error: $e');
      // Bei Fehler: Guard zurücksetzen, damit Retry möglich ist
      _globalActiveMuseTalkRooms.remove(room);
    }
  }

  Future<void> _ensureMuseTalkStarted() async {
    final roomName = LiveKitService().roomName;
    if (roomName == null || roomName.isEmpty) return;
    if (_avatarData?.id == null || _cachedVoiceId == null) return;
    // Lipsync global deaktiviert? → sofort abbrechen (Audio‑only Modus)
    final lipsyncEnabled =
        (_avatarData?.training?['lipsyncEnabled'] as bool?) ?? true;
    if (!lipsyncEnabled) return;
    if (_globalActiveMuseTalkRooms.containsKey(roomName)) return;
    debugPrint('🎬 Lazy-start MuseTalk publisher for room=$roomName');
    unawaited(
      _startLiveKitPublisher(roomName, _avatarData!.id, _cachedVoiceId!),
    );
  }

  Future<void> _stopLiveKitPublisher(
    String room, {
    bool stopSession = true,
  }) async {
    try {
      final orchUrl = AppConfig.orchestratorUrl
          .replaceFirst('wss://', 'https://')
          .replaceFirst('ws://', 'http://');
      final url = orchUrl.endsWith('/')
          ? '${orchUrl}publisher/stop'
          : '$orchUrl/publisher/stop';
      debugPrint('🛑 Stopping LiveKit publisher: $url');

      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'room': room}),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        debugPrint('✅ LiveKit publisher stopped');
      }

      // Optional: MuseTalk Session stoppen (teurer Kaltstart vermeiden → nur bei explizitem Verlassen)
      if (stopSession) {
        try {
          final mtUrl = AppConfig.museTalkHttpUrl.endsWith('/')
              ? '${AppConfig.museTalkHttpUrl}session/stop'
              : '${AppConfig.museTalkHttpUrl}/session/stop';
          await http.post(
            Uri.parse(mtUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'room': room}),
          ).timeout(const Duration(seconds: 5));
          _globalActiveMuseTalkRooms.remove(room); // Reset GLOBAL Guard!
          debugPrint('✅ MuseTalk session stopped (room=$room)');
        } catch (e) {
          debugPrint('⚠️ MuseTalk session stop failed: $e');
        }
      }
    } catch (e) {
      debugPrint('❌ Publisher stop error: $e');
    }
  }

  // Cache-Buster für Storage-URLs, um harte Caches (Safari/CDN) zu umgehen
  String _addCacheBuster(String? url) {
    if (url == null || url.isEmpty) return url ?? '';
    final hasQuery = url.contains('?');
    final sep = hasQuery ? '&' : '?';
    return '$url${sep}v=${DateTime.now().millisecondsSinceEpoch}';
  }

  StreamSubscription<DocumentSnapshot>? _avatarSub;

  void _startAvatarListener(String avatarId) {
    _avatarSub?.cancel();

    // GLOBAL Collection (hat dynamics!)
    _avatarSub = FirebaseFirestore.instance
        .collection('avatars')
        .doc(avatarId)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists && mounted) {
            setState(() {
              _avatarData = AvatarData.fromMap(snapshot.data()!);
            });
            // WICHTIG: Timeline NEU LADEN bei Änderungen (Bilder gelöscht/verschoben/etc.)
            _loadAndStartImageTimeline(avatarId);
          }
        });
    // Starte Image Timeline (initial)
    _loadAndStartImageTimeline(avatarId);
  }

  @override
  void initState() {
    super.initState();

    // Initialize Lipsync Strategy (Streaming bevorzugt; fallback per Flag)
    final useOrch = EnvService.orchestratorEnabled();
    final mode = useOrch ? AppConfig.lipsyncMode : LipsyncMode.fileBased;
    _lipsync = LipsyncFactory.create(
      mode: mode,
      backendUrl: AppConfig.backendUrl,
      orchestratorUrl: AppConfig.orchestratorUrl,
    );

    // Einmaliger Warmup-Ping vor erster Eingabe (kein permanentes Warmhalten)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _lipsync.warmUp();
      } catch (e) {
        debugPrint('⚠️ Lipsync warmUp error: $e');
      }
    });

    // Callback für Streaming Playback Status
    _lipsync.onPlaybackStateChanged = (isPlaying) async {
      if (!mounted) return;
      if (_isStreamingSpeaking != isPlaying) {
        debugPrint('🎙️ _isStreamingSpeaking: $isPlaying');
        setState(() => _isStreamingSpeaking = isPlaying);

        // WICHTIG: MuseTalk Session wird NUR EINMAL beim Chat-Eintritt gestartet (_initLiveAvatar)!
        // NICHT bei jedem Audio-Playback starten - das würde zu vielen Container-Starts führen!
        // Der Guard verhindert bereits doppelte Starts, aber wir vermeiden hier unnötige Calls.

        // Kostenbremse: MuseTalk-Publisher automatisch stoppen, wenn
        // 20s keine Ausgabe mehr (WhatsApp-ähnliches Verhalten: Session endet leise).
        final roomName = LiveKitService().roomName;
        if (isPlaying) {
          // Bei Aktivität: geplanten Stop abbrechen
          _publisherIdleTimer?.cancel();
          _publisherIdleTimer = null;
        } else if (roomName != null && roomName.isNotEmpty) {
          _publisherIdleTimer?.cancel();
          _publisherIdleTimer = Timer(const Duration(seconds: 1), () async {
            try {
              if (!mounted) return;
              debugPrint('⏹️ Auto-stop publisher+session (idle 1s) → Modal.com Kosten sparen');
              await _stopLiveKitPublisher(roomName, stopSession: true);
            } catch (_) {}
          });
        }
      }
    };

    // Hör auf Audio-Player-Status, um Sprech-Indikator zu steuern
    _playerStateSub = _player.playerStateStream.listen((state) {
      final speaking =
          state.playing &&
          state.processingState != ProcessingState.completed &&
          state.processingState != ProcessingState.idle;
      if (mounted && _isFileSpeaking != speaking) {
        debugPrint('🔊 _isFileSpeaking: $speaking');
        setState(() => _isFileSpeaking = speaking);
      }
    });

    // Viseme-Stream → LivePortrait (sofort verdrahten)
    if (_lipsync.visemeStream != null) {
      debugPrint('✅ Viseme Stream verfügbar (für LivePortrait)');
      _visemeSub = _lipsync.visemeStream!.listen(
        (ev) {
          // Während Sprechen Canvas sichtbar halten
          if (mounted && !_isStreamingSpeaking) {
            setState(() => _isStreamingSpeaking = true);
          }
          debugPrint('👄 Viseme: ${ev.viseme} @ ${ev.ptsMs}ms');
          // Viseme an LivePortrait-Canvas weiterleiten (falls vorhanden)
          _lpKey.currentState?.sendViseme(ev.viseme, ev.ptsMs, ev.durationMs);
        },
        onError: (e) {
          debugPrint('⚠️ Viseme stream error: $e');
        },
      );
    }

    // PCM-Stream → LivePortrait (Audio-Treiber)
    if (_lipsync.pcmStream != null) {
      _pcmSub = _lipsync.pcmStream!.listen(
        (chunk) {
          final bytes = Uint8List.fromList(chunk.bytes);
          _lpKey.currentState?.sendAudioChunk(bytes, chunk.ptsMs);
        },
        onError: (e) {
          debugPrint('⚠️ PCM stream error: $e');
        },
      );
    }
    // Scroll Listener für Infinite Scroll (oben = ältere Messages)
    _scrollController.addListener(_onScroll);
    
    // Empfange AvatarData SOFORT (synchron) von der vorherigen Seite
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final args = ModalRoute.of(context)?.settings.arguments;

      // SOFORT setzen, wenn als Argument übergeben (KEIN await!)
      if (args is AvatarData && _avatarData == null) {
        // WICHTIG: Neu laden aus globaler Collection (für dynamics!)
        final doc = await FirebaseFirestore.instance
            .collection('avatars')
            .doc(args.id)
            .get()
            .timeout(const Duration(seconds: 5));
        if (doc.exists && mounted) {
          setState(() {
            _avatarData = AvatarData.fromMap(doc.data()!);
          });
        }
        // Starte Firestore-Listener für Live-Updates
        _startAvatarListener(args.id);
      }

      // Priorisiere widget.avatarId (Overlay-Chat) - nur wenn noch nicht gesetzt
      if (widget.avatarId != null && _avatarData == null) {
        final doc = await FirebaseFirestore.instance
            .collection('avatars')
            .doc(widget.avatarId)
            .get()
            .timeout(const Duration(seconds: 5));
        if (doc.exists && mounted) {
          setState(() {
            _avatarData = AvatarData.fromMap(doc.data()!);
          });
          // Starte Firestore-Listener für Live-Updates
          _startAvatarListener(widget.avatarId!);
        }
      }

      // Weiter mit Loading + Greeting
      if (_avatarData != null) {
        // VoiceId robust ermitteln (alle möglichen Felder)
        _cachedVoiceId =
            (_avatarData?.training?['voice']?['elevenVoiceId'] as String?) ??
            (_avatarData?.training?['voice']?['cloneVoiceId'] as String?) ??
            (_avatarData?.training?['elevenVoiceId'] as String?) ??
            (_avatarData?.training?['cloneVoiceId'] as String?);
        debugPrint(
          '✅ VoiceId from _avatarData: ${_cachedVoiceId?.substring(0, 8) ?? "NULL"}...',
        );

        // Falls noch NULL: sofort aus User-Firestore nachladen
        if (_cachedVoiceId == null || _cachedVoiceId!.isEmpty) {
          _cachedVoiceId = await _reloadVoiceIdFromFirestore();
          debugPrint(
            '🔁 VoiceId reloaded: ${_cachedVoiceId?.substring(0, 8) ?? "NULL"}...',
          );
        }

        // Precache Hero-Image für nahtlosen Übergang
        final heroUrl = _avatarData?.avatarImageUrl;
        if (heroUrl != null && heroUrl.isNotEmpty && mounted) {
          precacheImage(NetworkImage(heroUrl), context);
        }

        await _loadPartnerName();
        // Lipsync warm-up: WS vor der Begrüßung initialisieren (verhindert Stille bei 1. Audio)
        try {
          await _lipsync.warmUp();
        } catch (_) {}
        final manual = (dotenv.env['LIVEKIT_MANUAL_START'] ?? '').trim() == '1';

        // Auto‑Greeting aktiv (kostengünstig)
        final greet = (_avatarData?.greetingText?.trim().isNotEmpty == true)
            ? _avatarData!.greetingText!
            : ((_partnerName ?? '').isNotEmpty
                  ? _friendlyGreet(_partnerName ?? '')
                  : 'Hallo, schön, dass Du vorbeischaust. Magst Du mir Deinen Namen verraten?');

        // Chat History laden (OHNE sie anzuzeigen)
        _loadInitialMessages();

        // Timeline initialisieren (Audio Cover Slider)
        _initTimeline();

        // Video laden; danach Greeting abspielen
        _initLiveAvatar(_avatarData!.id).then((_) async {
          if (!mounted) return; // Screen disposed? → STOP
          
          final lipsyncEnabled =
              (_avatarData?.training?['lipsyncEnabled'] as bool?) ?? true;
          if (!manual && _hasIdleDynamics && lipsyncEnabled) {
            await _maybeJoinLiveKit();
          }
          
          if (!mounted) return; // Screen disposed? → STOP
          
          // WICHTIG: Prüfe nochmal ob _avatarData noch gesetzt ist!
          if (_avatarData == null) {
            debugPrint('❌ FEHLER: _avatarData ist null beim Greeting!');
            return;
          }
          
          debugPrint('🎙️ Auto‑Greeting START (_avatarData.id=${_avatarData!.id})');
          await _botSay(greet); // AWAIT damit Message garantiert gespeichert wird!
          debugPrint('🎙️ Auto‑Greeting DONE');
        });
      }
    });
  }

  Future<void> _initLiveAvatar(String avatarId) async {
    try {
      if (_avatarData == null) {
        debugPrint('⚠️ _avatarData noch nicht geladen');
        return;
      }
      // respektiere Toggles
      final dynamicsEnabled =
          (_avatarData?.training?['dynamicsEnabled'] as bool?) ?? true;

      // DIREKT aus _avatarData.dynamics lesen - KEINE Firestore Query! 🚀
      final dynamics = _avatarData!.dynamics;
      final basicDynamics = dynamics?['basic'] as Map<String, dynamic>?;

      if (!dynamicsEnabled ||
          basicDynamics == null ||
          basicDynamics['status'] != 'ready') {
        debugPrint(
          '⚠️ Dynamics-Video: deaktiviert oder kein "basic" Dynamics für $avatarId\n'
          '→ Fallback: Nur Hero-Image wird angezeigt',
        );
        if (!mounted) return;
        setState(() {
          _liveAvatarEnabled = false;
          _hasIdleDynamics = false;
        });
        return;
      }

      // Video läuft bereits? → SKIP Reload!
      if (_liveAvatarEnabled && _idleController != null) {
        debugPrint('✅ Video bereits aktiv - skip reload!');
        return;
      }

      // URLs DIREKT aus _avatarData (INSTANT - 0ms!)
      debugPrint('⚡ Lade Videos INSTANT aus _avatarData.dynamics (0ms)!');
      final idleUrl = _addCacheBuster(basicDynamics['idleVideoUrl'] as String?);
      final chunk1Url = _addCacheBuster(
        basicDynamics['idleChunk1Url'] as String?,
      );
      final chunk2Url = _addCacheBuster(
        basicDynamics['idleChunk2Url'] as String?,
      );
      final chunk3Url = _addCacheBuster(
        basicDynamics['idleChunk3Url'] as String?,
      );

      // Cache für sync Zugriff in build()
      _cachedHeroChunkUrl = _addCacheBuster(
        basicDynamics['heroImageChunkUrl'] as String?,
      );

      // idle.mp4 existiert!
      if (!mounted) return;
      setState(() => _hasIdleDynamics = true);

      if (idleUrl.isEmpty) {
        debugPrint(
          '⚠️ Dynamics-Video: Keine idleVideoUrl\n'
          '→ Fallback: Nur Hero-Image wird angezeigt',
        );
        if (!mounted) return;
        setState(() {
          _liveAvatarEnabled = false;
          _hasIdleDynamics = false;
        });
        return;
      }

      // Nur neu laden, wenn sich die URL geändert hat – vermeidet Black‑Flash
      if (_idleVideoUrl == idleUrl && _idleController != null) {
        if (!mounted) return;
        setState(() => _liveAvatarEnabled = true);
        return;
      }

      // CHUNKED LOADING: Sofortiger Start mit Chunk1 (2s), dann Chunk2, Chunk3, dann idle.mp4 Loop!
      final hasChunks =
          chunk1Url.isNotEmpty && chunk2Url.isNotEmpty && chunk3Url.isNotEmpty;

      if (hasChunks) {
        debugPrint(
          '⚡ Sequential Chunked Loading: Chunk1 → Chunk2 → Chunk3 → idle.mp4',
        );

        // 1. Chunk1 SOFORT starten (ohne await - lädt während Playback!)
        final chunk1Ctrl = VideoPlayerController.networkUrl(
          Uri.parse(chunk1Url),
        );

        // Initialize + Play ASYNC (non-blocking!)
        chunk1Ctrl.initialize().then((_) {
          if (!mounted) return;
          chunk1Ctrl.play();
          debugPrint('✅ Chunk1 initialized + playing!');
        });

        _chunk1Controller?.dispose();
        _chunk1Controller = chunk1Ctrl;
        _chunk1Url = chunk1Url;
        _currentChunk = 1;

        // SOFORT sichtbar machen (Video lädt im Hintergrund)
        if (!mounted) return;
        setState(() => _liveAvatarEnabled = true);
        debugPrint(
          '⚡ Chunk1 startet (lädt parallel)! Preload Chunk2+3+idle.mp4...',
        );

        // 2. PARALLEL im Hintergrund: Chunk2, Chunk3, idle.mp4 laden –
        //    aber erst nach LiveKit-Join starten (oder Fallback nach 2s),
        //    damit Netzwerk/Thread nicht den Join verzögern.
        if (LiveKitService().connected.value) {
          unawaited(_preloadChunks(chunk2Url, chunk3Url, idleUrl));
        } else {
          void Function()? onLkJoin;
          onLkJoin = () {
            if (LiveKitService().connected.value) {
              LiveKitService().connected.removeListener(onLkJoin!);
              unawaited(_preloadChunks(chunk2Url, chunk3Url, idleUrl));
            }
          };
          LiveKitService().connected.addListener(onLkJoin);
          // Fallback: spätestens nach 2s trotzdem starten
          Future.delayed(const Duration(seconds: 2), () {
            try {
              LiveKitService().connected.removeListener(onLkJoin!);
            } catch (_) {}
            unawaited(_preloadChunks(chunk2Url, chunk3Url, idleUrl));
          });
        }

        // 3. Sequential Playback: Chunk1 → Chunk2 → Chunk3 → idle.mp4
        // WICHTIG: Listener muss sich nach erstem Trigger selbst entfernen!
        void Function()? chunk1Listener;
        chunk1Listener = () {
          if (!mounted) return;
          final pos = chunk1Ctrl.value.position;
          final dur = chunk1Ctrl.value.duration;

          // Trigger kurz VOR Ende (100ms Buffer)
          if (_currentChunk == 1 &&
              pos.inMilliseconds >= (dur.inMilliseconds - 100) &&
              pos.inMilliseconds > 0) {
            debugPrint('🔄 Chunk1 fast fertig → Switch zu Chunk2');
            chunk1Ctrl.removeListener(chunk1Listener!);
            _playChunk2();
          }
        };
        chunk1Ctrl.addListener(chunk1Listener);
      } else {
        // FALLBACK: Keine Chunks → Direkt idle.mp4 laden (alte Logik)
        debugPrint('⚠️ Keine Chunks vorhanden → Lade idle.mp4 direkt');
        final newCtrl = VideoPlayerController.networkUrl(Uri.parse(idleUrl));
        await newCtrl.initialize();
        await newCtrl.seekTo(Duration.zero);
        newCtrl.setLooping(true);
        newCtrl.play();

        final old = _idleController;
        _idleController = newCtrl;
        _idleVideoUrl = idleUrl;
        _currentChunk = 4; // WICHTIG: Für build() switch statement!
        old?.dispose();

        if (!mounted) return;
        setState(() => _liveAvatarEnabled = true);
        debugPrint('✅ Idle-Video initialisiert (swap): $idleUrl');
      }

      // Optionales Prestarten deaktiviert (Kostenbremse)
      if (_kPrestartMuseTalk) {
        final roomName = LiveKitService().roomName;
        if (roomName != null &&
            roomName.isNotEmpty &&
            _avatarData?.id != null &&
            _cachedVoiceId != null &&
            !_globalActiveMuseTalkRooms.containsKey(roomName)) {
          debugPrint('🎬 Preparing MuseTalk session (once) for room=$roomName');
          unawaited(
            _startLiveKitPublisher(roomName, _avatarData!.id, _cachedVoiceId!),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Idle-Video Init Fehler: $e');
      if (!mounted) return;
      setState(() {
        _liveAvatarEnabled = false;
        _hasIdleDynamics = false;
      });
    }
  }

  // Fallback lokal entfernt
  // Live Speak entfernt

  @override
  Widget build(BuildContext context) {
    super.build(context); // wichtig für AutomaticKeepAliveClientMixin

    // Hero Image = IMMER Background Layer
    // WENN idle.mp4 existiert → nutze heroImageChunkUrl (erster Frame, nahtloser Übergang!)
    // SONST → nutze avatarImageUrl (echtes Hero Image)
    String? backgroundImage =
        _currentBackgroundImage ?? _avatarData?.avatarImageUrl;

    // Wenn Chunks existieren: Nutze heroImageChunkUrl als Background
    if (_hasIdleDynamics &&
        _cachedHeroChunkUrl != null &&
        _cachedHeroChunkUrl!.isNotEmpty) {
      backgroundImage = _cachedHeroChunkUrl;
    }

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        // Nur über AppBar-Back zulassen
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          toolbarHeight: 56,
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              // IMMER zu Explorer (Avatar-List)
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/avatar-list',
                (route) => false,
              );
            },
          ),
          title: Transform.translate(
            offset: const Offset(0, 3),
            child: Text(
              (() {
                final parts = <String>[];
                if (_avatarData?.firstNamePublic == true) {
                  parts.add(_avatarData!.firstName);
                }
                if (_avatarData?.nicknamePublic == true &&
                    _avatarData?.nickname != null) {
                  parts.add('"${_avatarData!.nickname}"');
                }
                if (_avatarData?.lastNamePublic == true &&
                    _avatarData?.lastName != null) {
                  parts.add(_avatarData!.lastName!);
                }
                return parts.isEmpty ? '' : parts.join(' ');
              })(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w300,
                height: 1.0,
                shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Chat neu laden',
              icon: const Icon(Icons.refresh, color: Colors.white, size: 24),
              onPressed: () {
                if (_avatarData == null) return;
                // Chat-Screen neu starten
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AvatarChatScreen(
                      avatarId: _avatarData!.id,
                      onClose: widget.onClose,
                    ),
                    settings: RouteSettings(arguments: _avatarData),
                  ),
                );
              },
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Hero Chat',
              icon: const Icon(Icons.bookmark, color: Colors.white, size: 24),
              onPressed: () {
                if (_avatarData == null) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HeroChatScreen(
                      avatarData: _avatarData!,
                      messages: _messages,
                      onIconChanged: _handleIconChanged,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
        resizeToAvoidBottomInset: true,
        body: SizedBox.expand(
          child: Stack(
            children: [
              // Black transparent overlay für AppBar-Bereich
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 100,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.6),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // Hero-Animation für nahtlosen Übergang vom Explorer!
              // Positioned MUSS außen sein, Hero innen!
              Positioned.fill(
                child: Hero(
                  tag: 'avatar-chat-${_avatarData?.id}',
                  child: ValueListenableBuilder<lk.VideoTrack?>(
                    valueListenable: LiveKitService().remoteVideo,
                    builder: (context, remoteVideoTrack, _) {
                      // PRIORITÄT 1: LiveKit Video-Track (MuseTalk Lipsync)
                      if (remoteVideoTrack != null) {
                        return lk.VideoTrackRenderer(
                          remoteVideoTrack,
                          fit: lk.VideoViewFit.cover,
                        );
                      }

                      // PRIORITÄT 2: Sequential Chunked Video (Chunk1 → Chunk2 → Chunk3 → idle.mp4 Loop)
                      if (_liveAvatarEnabled) {
                        VideoPlayerController? activeCtrl;

                        // Wähle den richtigen Controller basierend auf _currentChunk
                        switch (_currentChunk) {
                          case 1:
                            activeCtrl = _chunk1Controller;
                            break;
                          case 2:
                            activeCtrl = _chunk2Controller;
                            break;
                          case 3:
                            activeCtrl = _chunk3Controller;
                            break;
                          case 4:
                            activeCtrl = _idleController;
                            break;
                          default:
                            activeCtrl = null;
                        }

                        if (activeCtrl != null &&
                            activeCtrl.value.isInitialized) {
                          return FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: activeCtrl.value.size.width,
                              height: activeCtrl.value.size.height,
                              child: VideoPlayer(activeCtrl),
                            ),
                          );
                        }
                      }

                      // PRIORITÄT 3: Statisches Hero-Image
                      if (backgroundImage != null &&
                          backgroundImage.isNotEmpty) {
                        return Image.network(
                          backgroundImage,
                          fit: BoxFit.cover,
                          frameBuilder:
                              (context, child, frame, wasSynchronouslyLoaded) {
                                if (wasSynchronouslyLoaded || frame != null) {
                                  return child;
                                }
                                return Container(color: Colors.black);
                              },
                        );
                      }

                      // FALLBACK: Schwarz
                      return Container(color: Colors.black);
                    },
                  ),
                ),
              ),

              // AppBar ist nun direkt im Scaffold eingebunden (siehe oben)

              // Content unten
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Resize-Handle
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeUpDown,
                        onEnter: (_) => setState(() => _chatHandleHovered = true),
                        onExit: (_) => setState(() => _chatHandleHovered = false),
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onVerticalDragUpdate: (details) {
                            setState(() {
                              final maxHeight = MediaQuery.of(context).size.height - 200; // Bildschirmhöhe - Header/Input
                              _chatHeight = (_chatHeight - details.delta.dy).clamp(150.0, maxHeight);
                            });
                          },
                          child: Container(
                            height: 16,
                            decoration: _chatHandleHovered
                                ? const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [AppColors.magenta, AppColors.lightBlue],
                                    ),
                                  )
                                : null,
                            child: Center(
                              child: Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      
                      // Chat-Nachrichten (resizable)
                      SizedBox(height: _chatHeight, child: _buildChatMessages()),

                      // Input-Bereich
                      _buildInputArea(),

                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),

              // Aufnahme-Badge (GMBC) über Input, nur bei aktiver Aufnahme
              Positioned(
                left: 0,
                right: 0,
                bottom: 61 + 28,
                child: IgnorePointer(
                  ignoring: true,
                  child: AnimatedOpacity(
                    opacity: _isRecording ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.magenta, AppColors.lightBlue],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.mic, size: 14, color: Colors.white),
                            SizedBox(width: 6),
                            Text(
                              'Aufnahme läuft…',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Dynamischer Hinweis-Badge (z.B. Bitte Text prüfen...)
              Positioned(
                left: 0,
                right: 0,
                bottom: 61 + 28,
                child: IgnorePointer(
                  ignoring: true,
                  child: AnimatedOpacity(
                    opacity: (_bannerText != null && _bannerText!.isNotEmpty)
                        ? 1.0
                        : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.magenta, AppColors.lightBlue],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _bannerText ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _scheduleTeaser() async {
    try {
      if (_avatarData == null) return;
      final avatarId = _avatarData!.id;
      final playlists = await _playlistSvc.list(avatarId);
      if (playlists.isEmpty) return;
      final now = DateTime.now();
      final active = playlists
          .where((p) => _playlistSvc.isActiveNow(p, now))
          .toList();
      if (active.isEmpty) return;
      // Entscheidungen laden, bereits entschiedene Medien überspringen
      final decided = await _momentsSvc.latestDecisions(avatarId);
      final allMedia = await _mediaSvc.list(avatarId);
      final mediaMap = {for (final x in allMedia) x.id: x};

      // Finde erstes anzeigbares Item über alle Playlists
      AvatarMedia? nextMedia;
      int delaySec = 0;
      for (final p in active) {
        final items = await _playlistSvc.listItems(avatarId, p.id);
        for (final it in items) {
          if (decided.containsKey(it.mediaId)) continue; // bereits entschieden
          final cand = mediaMap[it.mediaId];
          if (cand != null) {
            nextMedia = cand;
            delaySec = p.showAfterSec;
            break;
          }
        }
        if (nextMedia != null) break;
      }
      if (nextMedia == null) return;
      _teaserTimer?.cancel();
      _teaserTimer = Timer(Duration(seconds: delaySec.clamp(0, 86400)), () {
        _pendingTeaserMedia = nextMedia;
        _showTeaserOverlay();
      });
    } catch (_) {}
  }

  void _showTeaserOverlay() {
    if (!mounted || _pendingTeaserMedia == null) return;
    _teaserEntry?.remove();
    _teaserEntry = OverlayEntry(
      builder: (ctx) {
        return Positioned(
          right: 16,
          bottom: 90,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                _teaserEntry?.remove();
                _teaserEntry = null;
                _openMediaDecisionDialog(_pendingTeaserMedia!);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xCC000000),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.image, color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      context.read<LocalizationService>().t(
                        'chat.teaser.newMoment',
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_teaserEntry!);
  }

  Future<void> _openMediaDecisionDialog(AvatarMedia media) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return _MediaDecisionDialog(
          avatarId: _avatarData!.id,
          media: media,
          onDecision: (d) async {
            await _momentsSvc.store(_avatarData!.id, media.id, d);
            // Nächsten Teaser planen
            _pendingTeaserMedia = null;
            _teaserEntry?.remove();
            _teaserEntry = null;
            _teaserTimer?.cancel();
            // kleine Pause, dann neu planen
            Future.delayed(const Duration(milliseconds: 300), _scheduleTeaser);
          },
        );
      },
    );
  }

  // ignore: unused_element
  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Row(
        children: [
          // Zurück-Pfeil IMMER anzeigen (zu Explorer)
          IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                // IMMER zu Explorer (Avatar-List)
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/avatar-list',
                  (route) => false,
                );
              },
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Nur isPublic Namen anzeigen
                final nameParts = <String>[];
                if (_avatarData?.firstNamePublic == true) {
                  nameParts.add(_avatarData!.firstName);
                }
                if (_avatarData?.nicknamePublic == true &&
                    _avatarData?.nickname != null) {
                  nameParts.add('"${_avatarData!.nickname}"');
                }
                if (_avatarData?.lastNamePublic == true &&
                    _avatarData?.lastName != null) {
                  nameParts.add(_avatarData!.lastName!);
                }

                final displayText = nameParts.isEmpty
                    ? ''
                    : nameParts.join(' ');

                return Transform.translate(
                  offset: const Offset(0, 3),
                  child: Text(
                    displayText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w300,
                      height: 1.0,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
          // Hero Chat FAB Button
          HeroChatFabButton(
            highlightCount: _messages.where((m) => m.isHighlighted).length,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HeroChatScreen(
                    avatarData: _avatarData!,
                    messages: _messages,
                    onIconChanged: _handleIconChanged,
                  ),
                ),
              );
            },
          ),

          // Timeline Media Slider (links am Bildrand, alle Media-Typen)
          if (_timelineSliderVisible && _activeTimelineItem != null)
            TimelineMediaSlider(
              media: _activeTimelineItem!,
              slidingDuration: const Duration(minutes: 2),
              isBlurred: !_isTimelineItemPurchased(), // Blur wenn nicht gekauft
              onTap: _onTimelineItemTap,
            ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildAvatarImage() {
    return Container(
      width: double.infinity,
      decoration: null,
      child: Stack(
        children: [
          // LiveKit Remote-Video (Feature‑Flag)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: AnimatedBuilder(
                animation: LiveKitService().remoteVideo,
                builder: (context, _) {
                  final enabled =
                      (dotenv.env['LIVEKIT_ENABLED'] ?? '').trim() == '1';
                  final track = LiveKitService().remoteVideo.value;
                  if (!enabled || track == null) return const SizedBox.shrink();
                  return lk.VideoTrackRenderer(
                    track,
                    fit: lk.VideoViewFit.cover,
                  );
                },
              ),
            ),
          ),

          // Kein Default-Avatar mehr - nur schwarzer Hintergrund!

          // Typing-Indikator
          if (_isTyping)
            Positioned(
              bottom: 50,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: true,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Avatar denkt nach',
                          style: TextStyle(color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Zusätzliche Ebene nicht nötig – ein Overlay reicht
          // Status-Badge (Verbinde/Verbunden/Getrennt)
          Positioned(
            top: 12,
            right: 12,
            child: IgnorePointer(
              ignoring: true,
              child: AnimatedBuilder(
                animation: LiveKitService().connectionStatus,
                builder: (context, _) {
                  final s = LiveKitService().connectionStatus.value;
                  // Immer den LiveKit-Status anzeigen (auch bei 'idle')
                  Color bg = Colors.black.withValues(alpha: 0.6);
                  String label = 'LK: $s';
                  if (s == 'connected') {
                    bg = Colors.green.withValues(alpha: 0.7);
                  }
                  if (s == 'reconnecting') {
                    bg = Colors.orange.withValues(alpha: 0.7);
                  }
                  if (s == 'disconnected') {
                    bg = Colors.red.withValues(alpha: 0.7);
                  }
                  if (s == 'ended') bg = Colors.grey.withValues(alpha: 0.7);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  );
                },
              ),
            ),
          ),
          // Start-Button (manueller Start) – nur wenn LiveKit aktiviert und Flag gesetzt
          Positioned.fill(
            child: IgnorePointer(
              ignoring: false,
              child: AnimatedBuilder(
                animation: LiveKitService().connected,
                builder: (context, _) {
                  final manual =
                      (dotenv.env['LIVEKIT_MANUAL_START'] ?? '').trim() == '1';
                  final enabled =
                      (dotenv.env['LIVEKIT_ENABLED'] ?? '').trim() == '1';
                  final isConn = LiveKitService().connected.value;
                  if (!enabled || !manual || isConn) {
                    return const SizedBox.shrink();
                  }
                  return Center(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await _maybeJoinLiveKit();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Gespräch starten'),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatMessages() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0x20000000),
        // borderRadius: BorderRadius.only(
        //   topLeft: Radius.circular(20),
        //   topRight: Radius.circular(20),
        // ),
      ),
      child: Column(
        children: [
          // "Ältere Nachrichten anzeigen" Link
          if (_historyLoaded && _hasMoreMessages)
            GestureDetector(
              onTap: _isLoadingMore ? null : _loadMoreMessages,
              child: Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: Center(
                  child: Text(
                    _isLoadingMore ? 'Lade ältere Nachrichten…' : 'Ältere Nachrichten anzeigen',
                    style: const TextStyle(
                  color: Colors.white70,
                      fontSize: 12,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ),
          // Nachrichten-Liste
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : _buildDatedMessageList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDatedMessageList() {
    final items = <Widget>[];
    DateTime? lastDate;
    for (final m in _messages) {
      final day = DateTime(m.timestamp.year, m.timestamp.month, m.timestamp.day);
      if (lastDate == null || day.isAfter(lastDate)) {
        items.add(_buildDateSeparator(day));
        lastDate = day;
      }
      items.add(_buildMessageBubble(m));
    }
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: items,
    );
  }

  Widget _buildDateSeparator(DateTime day) {
    final label = _formatDay(day);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDay(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return 'Heute';
    if (day == yesterday) return 'Gestern';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  Widget _buildEmptyState() {
    // Kein Platzhalter – der Avatar begrüßt automatisch
    return const SizedBox.shrink();
  }

  Widget _buildMessageBubble(ChatMessage message) {
    return message.isUser
        ? UserMessageBubble(
            message: message,
            onIconChanged: _handleIconChanged,
            onDelete: _deleteMessage,
            isMultiDeleteMode: _isMultiDeleteMode,
            isSelected: _selectedMessageIds.contains(message.messageId),
            onSelectionToggle: _toggleMessageSelection,
            onMultiDeleteStart: _startMultiDeleteMode,
          )
        : AvatarMessageBubble(
            message: message,
            onIconChanged: _handleIconChanged,
            onDelete: _deleteMessage,
            avatarImageUrl: _avatarData?.avatarImageUrl,
            isMultiDeleteMode: _isMultiDeleteMode,
            isSelected: _selectedMessageIds.contains(message.messageId),
            onSelectionToggle: _toggleMessageSelection,
            onMultiDeleteStart: _startMultiDeleteMode,
          );
  }

  void _handleIconChanged(ChatMessage message, String? icon) {
    debugPrint('🎯 _handleIconChanged CALLED: messageId=${message.messageId}, text="${message.text.substring(0, message.text.length > 20 ? 20 : message.text.length)}", icon=$icon');
    
    // WICHTIG: Finde Message in lokaler Liste über messageId
    final localMessage = _messages.firstWhere(
      (m) => m.messageId == message.messageId,
      orElse: () {
        debugPrint('⚠️ Message nicht in _messages gefunden! Verwende Original.');
        return message;
      },
    );
    
    debugPrint('🎯 localMessage.messageId=${localMessage.messageId}');
    
    setState(() {
      if (icon != null) {
        // Icon setzen (neu markiert)
        localMessage.highlightIcon = icon;
        debugPrint('🎯 State updated: Icon = $icon');
      } else {
        // Icon entfernen (aus Hero-Screen gelöscht)
        localMessage.highlightIcon = null;
        debugPrint('🎯 State updated: Icon entfernt');
      }
    });
    
    // Firebase: Update highlightIcon Feld direkt in avatarUserChats/messages
    debugPrint('🎯 Calling _updateMessageIcon with AWAIT...');
    _updateMessageIcon(localMessage.messageId, icon); // Fire-and-forget OK (nicht blockieren)
    debugPrint('🎯 _updateMessageIcon triggered (async)');
  }

  // Multi-Delete-Modus (WhatsApp-Style)
  void _startMultiDeleteMode() {
    setState(() {
      _isMultiDeleteMode = true;
      _selectedMessageIds.clear();
    });
  }

  void _toggleMessageSelection(String messageId) {
    setState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
      } else {
        _selectedMessageIds.add(messageId);
      }
    });
  }

  void _cancelMultiDelete() {
    setState(() {
      _isMultiDeleteMode = false;
      _selectedMessageIds.clear();
    });
  }

  Future<void> _confirmMultiDelete() async {
    if (_selectedMessageIds.isEmpty) {
      _cancelMultiDelete();
      return;
    }

    // Confirm Dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nachrichten löschen?'),
        content: Text(
          '${_selectedMessageIds.length} ${_selectedMessageIds.length == 1 ? "Nachricht" : "Nachrichten"} werden dauerhaft gelöscht.',
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

    // Delete all selected messages
    final idsToDelete = List<String>.from(_selectedMessageIds);
    for (final messageId in idsToDelete) {
      final msg = _messages.firstWhere((m) => m.messageId == messageId, orElse: () => ChatMessage(
        messageId: messageId,
        text: '',
        isUser: false,
        timestamp: DateTime.now(),
      ));
      await _deleteMessageById(msg);
    }

    _cancelMultiDelete();

    // Status neu prüfen nach Multi-Delete
    if (_messages.isEmpty) {
      setState(() {
        _historyLoaded = false;
        _hasMoreMessages = true; // Reset
      });
      _loadInitialMessages(); // Neu prüfen ob Messages in Firebase
    }  }

  Future<void> _deleteMessageById(ChatMessage message) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _avatarData == null) return;

    try {
      // 1) Lokal entfernen (sofort)
      setState(() {
        _messages.removeWhere((m) => m.messageId == message.messageId);
      });

      // 2) Firestore löschen (richtiger Pfad!)
      final chatId = '${uid}_${_avatarData!.id}';
      await FirebaseFirestore.instance
          .collection('avatarUserChats')
          .doc(chatId)
          .collection('messages')
          .doc(message.messageId)
          .delete()
          .timeout(const Duration(seconds: 5));
      
      debugPrint('✅ Multi-Delete: Message gelöscht: ${message.messageId}');
    } catch (e) {
      debugPrint('❌ Multi-Delete Error: $e');
    }
  }


  // Update highlightIcon direkt in avatarUserChats/messages
  Future<void> _updateMessageIcon(String messageId, String? icon) async {
    debugPrint('🔧 _updateMessageIcon CALLED: messageId=$messageId, icon=$icon');
    
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      debugPrint('❌ _updateMessageIcon: uid is null!');
      return;
    }
    if (_avatarData == null) {
      debugPrint('❌ _updateMessageIcon: _avatarData is null!');
      return;
    }

    try {
      final chatId = '${uid}_${_avatarData!.id}';
      debugPrint('🔧 chatId=$chatId');
      debugPrint('🔧 Firebase path: avatarUserChats/$chatId/messages/$messageId');
      
      if (icon != null) {
        debugPrint('🔧 Setze Icon: $icon');
        // Icon setzen (set mit merge: true statt update!)
        await FirebaseFirestore.instance
            .collection('avatarUserChats')
            .doc(chatId)
            .collection('messages')
            .doc(messageId)
            .set({'highlightIcon': icon}, SetOptions(merge: true))
            .timeout(const Duration(seconds: 5));
        debugPrint('✅ Icon ERFOLGREICH gesetzt: $messageId → $icon');
      } else {
        debugPrint('🔧 Entferne Icon');
        // Icon entfernen
        await FirebaseFirestore.instance
            .collection('avatarUserChats')
            .doc(chatId)
            .collection('messages')
            .doc(messageId)
            .set({'highlightIcon': FieldValue.delete()}, SetOptions(merge: true))
            .timeout(const Duration(seconds: 5));
        debugPrint('✅ Icon ERFOLGREICH entfernt: $messageId');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Icon Update fehlgeschlagen: $e');
      debugPrint('❌ StackTrace: $stackTrace');
    }
  }

  // Message löschen (aus View + Firebase)
  void _deleteMessage(ChatMessage message) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _avatarData == null) return;

    try {
      // 1) Lokal entfernen (sofort)
      setState(() {
        _messages.remove(message);
      });

      // 2) Firebase löschen
      final chatId = '${uid}_${_avatarData!.id}';
      await FirebaseFirestore.instance
          .collection('avatarUserChats')
          .doc(chatId)
          .collection('messages')
          .doc(message.messageId)
          .delete();
      
      debugPrint('✅ Message gelöscht: ${message.messageId}');
    } catch (e) {
      debugPrint('❌ Message löschen fehlgeschlagen: $e');
    }
  }



  Widget _buildMultiDeleteBar() {
    final isEmpty = _selectedMessageIds.isEmpty;
    return Container(
      height: 48,
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Selection count
          Expanded(
            child: Text(
              '${_selectedMessageIds.length} ${_selectedMessageIds.length == 1 ? "Nachricht" : "Nachrichten"} ausgewählt',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Abbrechen Button
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _cancelMultiDelete,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                ),
                child: const Text(
                  'Abbrechen',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Löschen Button (WHITE BG + GMBC TEXT)
          Opacity(
            opacity: isEmpty ? 0.4 : 1.0,
            child: MouseRegion(
              cursor: isEmpty ? SystemMouseCursors.basic : SystemMouseCursors.click,
              child: GestureDetector(
                onTap: isEmpty ? null : _confirmMultiDelete,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                  ),
                  child: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [
                        Color(0xFFFF2EC8), // Magenta
                        Color(0xFF8AB4F8), // LightBlue
                      ],
                    ).createShader(bounds),
                    child: const Text(
                      'Löschen',
                      style: TextStyle(
                        color: Colors.white, // Wird durch ShaderMask ersetzt
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildInputArea() {
    return SafeArea(
      top: false,
      bottom: true,
      child: Stack(
        children: [
          // Input Field Container
          Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          // gesamte Leiste leicht weiß, ohne Farbstich
          color: Colors.white.withValues(alpha: 0.3),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<TextEditingValue>(
          valueListenable: _messageController,
          builder: (context, value, _) {
            final hasText = value.text.trim().isNotEmpty;
            return Row(
              children: [
                // Plus-Button (Anhänge)
                GestureDetector(
                  onTap: () {},
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.add,
                        color: Colors.black54,
                        size: 22,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Text-Eingabe (ohne Rahmenlinien)
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 36),
                    child: AnimatedContainer(
                      decoration: BoxDecoration(
                        // Weiß-transparenter Feld-Background
                        color: _inputFocused
                            ? Colors.white.withValues(alpha: 0.4)
                            : Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white54), // light grey
                      ),
                      clipBehavior: Clip.hardEdge,
                      duration: const Duration(milliseconds: 120),
                      child: const _ChatInputField(),
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                // Rechts: Mic UND Send nebeneinander
                Row(
                  children: [
                    GestureDetector(
                      onTap: _toggleRecording,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: _isRecording
                              ? ShaderMask(
                                  shaderCallback: (bounds) =>
                                      const LinearGradient(
                                        colors: [
                                          AppColors.magenta,
                                          AppColors.lightBlue,
                                        ],
                                      ).createShader(bounds),
                                  blendMode: BlendMode.srcIn,
                                  child: const Icon(
                                    Icons.stop,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                )
                              : const Icon(
                                  Icons.mic,
                                  color: Colors.black54,
                                  size: 22,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () {
                        _sendMessage();
                        _messageController.clear();
                        setState(() {}); // Box schrumpft
                      },
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: hasText
                              ? ShaderMask(
                                  shaderCallback: (bounds) =>
                                      const LinearGradient(
                                        colors: [
                                          AppColors.magenta,
                                          AppColors.lightBlue,
                                        ],
                                      ).createShader(bounds),
                                  blendMode: BlendMode.srcIn,
                                  child: const Icon(
                                    Icons.send,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                )
                              : const Icon(
                                  Icons.send,
                                  color: Colors.black45,
                                  size: 20,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
            ),
            const SizedBox(height: 6),
            _buildMtRoomFooter(),
          ],
        ),
      ),
          // Multi-Delete-Bar Overlay
          if (_isMultiDeleteMode)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _buildMultiDeleteBar(),
            ),
        ],
      ),
    );
  }

  Widget _buildMtRoomFooter() {
    final room = LiveKitService().roomName;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Tooltip(
          message: room == null || room.isEmpty ? 'Room: -' : 'Room: $room',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF7E57C2), // GMBC
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'mt-room',
              style: TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: LiveKitService().connected,
          builder: (context, connected, _) {
            if (!connected) return const SizedBox.shrink();
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green, // verbunden = grün
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'LKC',
                style: TextStyle(color: Colors.white, fontSize: 11),
              ),
            );
          },
        ),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildStopButton() {
    return Padding(
      padding: const EdgeInsets.only(right: 16, bottom: 12),
      child: ElevatedButton.icon(
        onPressed: _isStoppingPlayback ? null : _stopPlayback,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red.shade600,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        ),
        icon: _isStoppingPlayback
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.stop),
        label: const Text('Stop'),
      ),
    );
  }

  void _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      // Berechtigungen und Start
      bool has = await _recorder.hasPermission();
      if (!has) {
        try {
          final status = await Permission.microphone.request();
          has = status.isGranted;
        } catch (_) {
          has = false;
        }
      }
      if (!has) {
        _showSystemSnack(
          'Bitte Mikrofon zulassen (Systemeinstellungen > Datenschutz > Mikrofon)',
        );
        return;
      }
      _silenceMs = 0;
      await _startNewSegment();
      if (mounted) setState(() => _isRecording = true);
    } catch (e) {
      _showSystemSnack('Aufnahme-Start fehlgeschlagen: $e');
    }
  }

  Future<void> _startNewSegment() async {
    // Temporären Pfad für Aufnahme generieren
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '${dir.path}/segment_$timestamp.wav';

    await _recorder.start(
      RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000),
      path: path,
    );
    _segmentStartAt = DateTime.now();
    _ampSub?.cancel();
    try {
      _ampSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 200))
          .listen(_onAmplitude);
    } catch (_) {
      // Plattform unterstützt Amplituden-Stream evtl. nicht → VAD deaktivieren
      _ampSub = null;
    }
  }

  void _onAmplitude(Amplitude amp) async {
    if (!kAutoSend) return; // Auto-Senden derzeit deaktiviert
    if (!_isRecording) return;
    final now = DateTime.now();
    final startedMs = _segmentStartAt == null
        ? 0
        : now.difference(_segmentStartAt!).inMilliseconds;
    final double levelDb = amp.current; // meist negativ (dBFS)
    final bool isSilent = levelDb <= _silenceThresholdDb;
    _silenceMs = isSilent ? (_silenceMs + 200) : 0;

    if (_silenceMs >= _silenceHoldMs && startedMs >= _minSegmentMs) {
      // Segment beenden und senden, danach neues Segment starten
      if (_segmentClosing || _sttBusy) return;
      _segmentClosing = true;
      try {
        _ampSub?.cancel();
        final segPath = await _recorder.stop();
        if (segPath != null && segPath.isNotEmpty) {
          final txt = await _transcribeWithWhisper(
            File(_normalizeFilePath(segPath)),
          );
          if (txt != null && txt.trim().isNotEmpty) {
            _messageController.text = txt.trim();
            await _sendMessage();
          }
        }
      } catch (_) {}
      _segmentClosing = false;
      if (_isRecording && !_sttBusy) {
        _silenceMs = 0;
        await _startNewSegment();
      }
    }
  }

  Future<void> _stopRecording() async {
    try {
      _ampSub?.cancel();
      final path = await _recorder.stop();
      setState(() => _isRecording = false);
      final filePath = path ?? _lastRecordingPath;
      if (filePath == null || filePath.isEmpty) {
        _showSystemSnack('Keine Audiodatei aufgenommen');
        return;
      }
      final norm = _normalizeFilePath(filePath);
      File f = File(norm);
      int tries = 0;
      while (!(await f.exists()) && tries < 3) {
        await Future.delayed(const Duration(milliseconds: 120));
        tries++;
      }
      if (!(await f.exists())) {
        _showSystemSnack('STT Fehler: Datei nicht vorhanden');
        return;
      }
      final meta = await f.stat();
      if (meta.size < 4000) {
        _showSystemSnack(
          'Hinweis: Aufnahme evtl. leise – wird trotzdem gesendet',
        );
      }
      final txt = await _transcribeWithWhisper(f);
      if (txt != null && txt.trim().isNotEmpty) {
        // Zeige Text im Input zur Korrektur; Senden erst per Button
        _messageController.text = txt.trim();
        _showSystemSnack('Bitte Text prüfen und Senden tippen.');
      }
      _segmentStartAt = null;
      _silenceMs = 0;
    } catch (e) {
      _showSystemSnack('Aufnahme-Stopp fehlgeschlagen: $e');
    }
  }

  Future<String?> _transcribeWithWhisper(File audioFile) async {
    try {
      final key = dotenv.env['OPENAI_API_KEY']?.trim();
      if (key == null || key.isEmpty) {
        _showSystemSnack('OPENAI_API_KEY fehlt (.env)');
        return null;
      }
      _sttBusy = true;
      final uri = Uri.parse('https://api.openai.com/v1/audio/transcriptions');
      final req = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $key'
        ..fields['model'] = 'whisper-1'
        ..files.add(
          await http.MultipartFile.fromPath(
            'file',
            audioFile.path,
            contentType: MediaType('audio', 'wav'),
          ),
        );
      final resp = await req.send().timeout(const Duration(seconds: 30));
      final body = await resp.stream.bytesToString();
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        return (data['text'] as String?)?.trim();
      } else {
        _showSystemSnack('Whisper-Fehler: ${resp.statusCode}');
        return null;
      }
    } catch (e) {
      _showSystemSnack('STT Fehler: $e');
      return null;
    } finally {
      _sttBusy = false;
    }
  }

  String _normalizeFilePath(String p) {
    try {
      final u = Uri.parse(p);
      if (u.scheme == 'file') return u.toFilePath();
    } catch (_) {}
    return p.startsWith('file://') ? p.replaceFirst('file://', '') : p;
  }

  Future<void> _sendMessage() async {
    final raw = _messageController.text;
    // Verhindere Kosten: Nur senden, wenn echter Inhalt vorhanden ist
    final text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isNotEmpty) {
      // Lazy-start MuseTalk beim ersten Sprechen (Kostenbremse)
      if (!_firstValidSend) {
        _firstValidSend = true;
        unawaited(_ensureMuseTalkStarted());
      }
      // Aktuellen Stream sauber beenden, nur bei explizitem Senden
      try {
        await _lipsync.stop();
      } catch (_) {}

      // text ist bereits getrimmt/normalisiert
      // Direkte Beantwortung: "Weißt du, wer ich bin?"
      final whoAmI = RegExp(
        r'(wei[ßs]t\s+du\s+wer\s+ich\s+bin\??|wer\s+bin\s+ich\??|kennst\s+du\s+mich\??)',
        caseSensitive: false,
      );
      if (whoAmI.hasMatch(text) &&
          (_partnerName != null && _partnerName!.isNotEmpty)) {
        final first = _shortFirstName(_partnerName ?? '');
        final suffix = _affectionateSuffix();
        await _botSay('Klar – du bist $first${suffix.replaceFirst(',', '')}');
        await _addMessage(text, true);
        _messageController.clear();
        return;
      }
      await _addMessage(text, true, skipPersist: false); // Backend speichert User + Avatar Message!
      _messageController.clear();
      // Falls wir gerade auf Bestätigung warten
      if (_awaitingNameConfirm) {
        final useFull = _isAffirmative(text);
        final nameToSave = useFull
            ? (_pendingFullName ?? _pendingLooseName)
            : _pendingLooseName;
        if (nameToSave != null && nameToSave.isNotEmpty) {
          _isKnownPartner = _pendingIsKnownPartner;
          _savePartnerName(nameToSave);
          await _botSay(_friendlyGreet(_shortFirstName(nameToSave)));
          _pendingFullName = null;
          _pendingLooseName = null;
          _awaitingNameConfirm = false;
          return;
        }
      }

      // Korrektur: Wenn bereits ein Name existiert, aber der User sich jetzt explizit (oder per Einwort) anders nennt → überschreiben
      if ((_partnerName != null && _partnerName!.isNotEmpty)) {
        final exp = _extractNameExplicit(text);
        String? single;
        final onlyWord = RegExp(r'^[A-Za-zÄÖÜäöüß\-]{2,24}$');
        if (exp == null && onlyWord.hasMatch(text)) {
          single = _capitalize(
            text.replaceAll(RegExp(r'[^A-Za-zÄÖÜäöüß\-]'), ''),
          );
        }
        final candidate = exp ?? single;
        if (candidate != null &&
            candidate.isNotEmpty &&
            candidate.toLowerCase() != (_partnerName ?? '').toLowerCase()) {
          _isKnownPartner = true;
          _savePartnerName(candidate);
          final first = _shortFirstName(candidate);
          final tail = (_partnerPetName != null && _partnerPetName!.isNotEmpty)
              ? ', mein ${_partnerPetName ?? ''}!'
              : '!';
          await _botSay('Alles klar – du bist $first$tail');
          return;
        }
      }

      // ALLES direkt zu Backend → Pinecone/OpenAI entscheidet
      if (text.isNotEmpty) {
        _chatWithBackend(text);
      }
    }
  }

  Future<void> _botSay(String text) async {
    // Screen disposed? → SOFORT ABBRECHEN
    if (!mounted) {
      debugPrint('⚠️ _botSay aborted: Screen disposed');
      return;
    }
    
    // Rate-Limiting: Prüfe letzte TTS-Anfrage
    final now = DateTime.now();
    if (_lastTtsRequestTime != null) {
      final diff = now.difference(_lastTtsRequestTime!).inMilliseconds;
      if (diff < _minTtsDelayMs) {
        debugPrint('⏳ TTS Rate-Limit: Warte ${_minTtsDelayMs - diff}ms');
        await Future.delayed(Duration(milliseconds: _minTtsDelayMs - diff));
      }
    }
    _lastTtsRequestTime = DateTime.now();

    // Nochmal prüfen nach delay
    if (!mounted) {
      debugPrint('⚠️ _botSay aborted after delay: Screen disposed');
      return;
    }

    // PRIORITÄT: Streaming (schnell!)
    if (_lipsync.visemeStream != null &&
        _cachedVoiceId != null &&
        _cachedVoiceId!.isNotEmpty) {
      await _addMessage(text, false);
      debugPrint('🚀 _botSay: Using STREAMING (cached voiceId)');
      try {
        await _lipsync.speak(text, _cachedVoiceId!);
      } catch (e) {
        debugPrint('⚠️ Lipsync speak error: $e');
      }
      return; // ← KEIN Backend-MP3!
    }

    debugPrint(
      '⚠️ Fallback: Kein Streaming (voiceId: $_cachedVoiceId, stream: ${_lipsync.visemeStream != null})',
    );

    String? path;
    try {
      String? voiceId = (_avatarData?.training != null)
          ? (_avatarData?.training?['voice'] != null
                ? (_avatarData?.training?['voice']?['elevenVoiceId'] as String?)
                : null)
          : null;
      if (voiceId == null || voiceId.isEmpty) {
        voiceId = await _reloadVoiceIdFromFirestore();
      }
      final base = EnvService.memoryApiBaseUrl();
      if (base.isEmpty) {
        await _addMessage(text, false);
        return;
      }
      final uri = Uri.parse('$base/avatar/tts');
      final payload = <String, dynamic>{'text': text};
      if (voiceId != null) payload['voice_id'] = voiceId;
      final double? stability = (_avatarData?.training != null)
          ? (_avatarData?.training?['voice'] != null
                ? (_avatarData?.training?['voice']?['stability'] as num?)
                      ?.toDouble()
                : null)
          : null;
      final double? similarity = (_avatarData?.training != null)
          ? (_avatarData?.training?['voice'] != null
                ? (_avatarData?.training?['voice']?['similarity'] as num?)
                      ?.toDouble()
                : null)
          : null;
      final double? tempo = (_avatarData?.training != null)
          ? (_avatarData?.training?['voice'] != null
                ? (_avatarData?.training?['voice']?['tempo'] as num?)
                      ?.toDouble()
                : null)
          : null;
      final String? dialect = (_avatarData?.training != null)
          ? (_avatarData?.training?['voice']?['dialect'] as String?)
          : null;
      if (stability != null) payload['stability'] = stability;
      if (similarity != null) payload['similarity'] = similarity;
      if (tempo != null) payload['speed'] = tempo;
      if (dialect != null && dialect.isNotEmpty) payload['dialect'] = dialect;
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final Map<String, dynamic> j =
            jsonDecode(res.body) as Map<String, dynamic>;
        final String? b64 = j['audio_b64'] as String?;
        if (b64 != null && b64.isNotEmpty) {
          final bytes = base64Decode(b64);
          final dir = await getTemporaryDirectory();
          final file = File(
            '${dir.path}/bot_local_tts_${DateTime.now().millisecondsSinceEpoch}.mp3',
          );
          await file.writeAsBytes(bytes, flush: true);
          path = file.path;
        } else {
          debugPrint('TTS-Fehler: leere Antwort');
        }
      } else {
        debugPrint(
          'TTS-HTTP: ${res.statusCode} ${res.body.substring(0, res.body.length > 120 ? 120 : res.body.length)}',
        );
      }
    } catch (e) {
      debugPrint('TTS-Fehler: $e');
    }
    await _addMessage(text, false, audioPath: path);
    if (path != null) {
      await _playAudioAtPath(path);
    }
  }

  Future<String?> _ensureTtsForText(String text) async {
    // Rate-Limiting: Prüfe letzte TTS-Anfrage
    final now = DateTime.now();
    if (_lastTtsRequestTime != null) {
      final diff = now.difference(_lastTtsRequestTime!).inMilliseconds;
      if (diff < _minTtsDelayMs) {
        debugPrint('⏳ TTS Rate-Limit: Warte ${_minTtsDelayMs - diff}ms');
        await Future.delayed(Duration(milliseconds: _minTtsDelayMs - diff));
      }
    }
    _lastTtsRequestTime = DateTime.now();

    try {
      final base2 = EnvService.memoryApiBaseUrl();
      if (base2.isEmpty) {
        _showSystemSnack('Backend-URL fehlt (.env MEMORY_API_BASE_URL)');
        return null;
      }
      final uri = Uri.parse('$base2/avatar/tts');
      String? voiceId = (_avatarData?.training != null)
          ? (_avatarData?.training?['voice'] != null
                ? (_avatarData?.training?['voice']?['elevenVoiceId'] as String?)
                : null)
          : null;
      if (voiceId == null || voiceId.isEmpty) {
        voiceId = await _reloadVoiceIdFromFirestore();
      }
      final payload = <String, dynamic>{'text': text};
      // Immer die geklonte Stimme verwenden
      if (voiceId != null) {
        payload['voice_id'] = voiceId;
      } else {
        _showSystemSnack('Keine geklonte Stimme verfügbar');
        return null;
      }
      final double? stability = (_avatarData?.training != null)
          ? (_avatarData?.training?['voice'] != null
                ? (_avatarData?.training?['voice']?['stability'] as num?)
                      ?.toDouble()
                : null)
          : null;
      final double? similarity = (_avatarData?.training != null)
          ? (_avatarData?.training?['voice'] != null
                ? (_avatarData?.training?['voice']?['similarity'] as num?)
                      ?.toDouble()
                : null)
          : null;
      if (stability != null) payload['stability'] = stability;
      if (similarity != null) payload['similarity'] = similarity;
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final Map<String, dynamic> j =
            jsonDecode(res.body) as Map<String, dynamic>;
        final String? b64 = j['audio_b64'] as String?;
        if (b64 != null && b64.isNotEmpty) {
          final bytes = base64Decode(b64);
          final dir = await getTemporaryDirectory();
          final file = File(
            '${dir.path}/tts_on_demand_${DateTime.now().millisecondsSinceEpoch}.mp3',
          );
          await file.writeAsBytes(bytes, flush: true);
          return file.path;
        }
      } else {
        _showSystemSnack(
          'TTS-HTTP: ${res.statusCode} ${res.body.substring(0, res.body.length > 120 ? 120 : res.body.length)}',
        );
      }
    } catch (e) {
      _showSystemSnack('TTS-Fehler: $e');
    }
    return null;
  }

  Future<String?> _reloadVoiceIdFromFirestore() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || _avatarData == null) return null;
      final fs = FirebaseFirestore.instance;
      final doc = await fs
          .collection('users')
          .doc(uid)
          .collection('avatars')
          .doc(_avatarData?.id ?? '')
          .get()
          .timeout(const Duration(seconds: 5));
      final data = doc.data();
      if (data == null) return null;
      final training = data['training'] as Map<String, dynamic>?;
      final voice = training != null
          ? training['voice'] as Map<String, dynamic>?
          : null;
      final String? vid = voice != null
          ? voice['elevenVoiceId'] as String?
          : null;
      if (vid != null && vid.isNotEmpty) {
        // lokal aktualisieren
        setState(() {
          final currentTraining = Map<String, dynamic>.from(
            _avatarData?.training ?? {},
          );
          final currentVoice = Map<String, dynamic>.from(
            (currentTraining['voice'] ?? {}) as Map,
          );
          currentVoice['elevenVoiceId'] = vid;
          currentTraining['voice'] = currentVoice;
          _avatarData = _avatarData?.copyWith(training: currentTraining);
        });
      }
      return vid;
    } catch (_) {
      return null;
    }
  }

  Future<void> _addMessage(String text, bool isUser, {String? audioPath, bool skipPersist = false}) async {
    debugPrint('💬 _addMessage: isUser=$isUser, skipPersist=$skipPersist, text="${text.substring(0, text.length > 30 ? 30 : text.length)}..."');
    if (!mounted) return;
    
    // Generate messageId
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final messageId = 'msg-$timestamp-${uid?.substring(0, 6) ?? 'anon'}';
    
    // IMMER hinzufügen (kein Dedupe!)
    setState(() {
      _messages.add(
        ChatMessage(
          messageId: messageId,
          text: text,
          isUser: isUser,
          audioPath: audioPath,
        ),
      );
    });
    _scrollToBottom();
    
    // WICHTIG: await damit Message in Firebase ist bevor Icon gesetzt werden kann
    await _persistMessage(messageId: messageId, text: text, isUser: isUser, skipPersist: skipPersist);
  }

  Future<void> _chatWithBackend(String userText) async {
    debugPrint('🔥 _chatWithBackend CALLED with: "$userText"');
    if (_avatarData == null) return;
    setState(() => _isTyping = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSystemSnack('Nicht angemeldet');
        return;
      }
      final uid = user.uid;
      final baseChat = EnvService.memoryApiBaseUrl();
      if (baseChat.isEmpty) {
        _showSystemSnack('Backend-URL fehlt (.env MEMORY_API_BASE_URL)');
        return;
      }
      final uri = Uri.parse('$baseChat/avatar/chat');

      // Stimme robust ermitteln
      String? voiceId = (_avatarData?.training != null)
          ? (_avatarData?.training?['voice'] != null
                ? (_avatarData?.training?['voice']?['elevenVoiceId'])
                : null)
          : null;
      if (voiceId == null || (voiceId.isEmpty)) {
        voiceId = await _reloadVoiceIdFromFirestore();
      }
      Future<Map<String, dynamic>?> primary() async {
        // Nutzer-Zielsprache aus Firestore/Provider (optional)
        String? lang;
        try {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get()
              .timeout(const Duration(seconds: 3));
          lang = (doc.data()?['language'] as String?)?.trim();
        } catch (_) {}
        final res = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'user_id': uid,
                'avatar_id': _avatarData?.id ?? '',
                'message': userText,
                'top_k': 2,
                'voice_id': (voiceId is String && voiceId.isNotEmpty)
                    ? voiceId
                    : null,
                'avatar_name': _avatarData?.displayName,
                'target_language': lang,
              }),
            )
            .timeout(const Duration(seconds: 15));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          return jsonDecode(res.body) as Map<String, dynamic>;
        }
        return null;
      }

      final res = await primary().timeout(const Duration(seconds: 20));

      final answer = (res?['answer'] as String?)?.trim();
      if (answer == null || answer.isEmpty) {
        _showSystemSnack('Chat nicht verfügbar (keine Antwort)');
      } else {
        await _addMessage(answer, false, skipPersist: false); // Backend hat schon gespeichert!

        // DEBUG: Check Streaming Conditions
        debugPrint(
          '💬 Chat Response: stream=${_lipsync.visemeStream != null}, voiceId=${_cachedVoiceId != null ? _cachedVoiceId!.substring(0, 8) : "NULL"}',
        );

        // PRIORITÄT: Streaming (schnell, < 500ms)
        if (_lipsync.visemeStream != null &&
            _cachedVoiceId != null &&
            _cachedVoiceId!.isNotEmpty) {
          debugPrint('🚀 Chat: Using STREAMING audio');
          try {
            unawaited(_lipsync.speak(answer, _cachedVoiceId!));
          } catch (e) {
            debugPrint('⚠️ Lipsync speak error: $e');
          }
          // KEIN return! finally muss ausgeführt werden!
        } else {
          // FALLBACK: Backend-MP3 (langsam, ~3 Sekunden)
          debugPrint('⚠️ Chat: Fallback to Backend MP3');
          final tts = res?['tts_audio_b64'] as String?;
          if (tts != null && tts.isNotEmpty) {
            try {
              await _stopPlayback();
              final bytes = base64Decode(tts);
              final dir = await getTemporaryDirectory();
              final file = File(
                '${dir.path}/avatar_tts_${DateTime.now().millisecondsSinceEpoch}.mp3',
              );
              await file.writeAsBytes(bytes, flush: true);
              _lastRecordingPath = file.path;
              unawaited(_playAudioAtPath(file.path));
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      _showSystemSnack('Chat fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _isTyping = false);
    }
  }

  // Future<void> _recordVoice() async {}

  // Future<void> _stopAndSave() async {}

  // _playLastRecording entfernt – direkte Wiedergabe über _playAudioAtPath

  Future<void> _playAudioAtPath(String path) async {
    try {
      await _player.stop();
      await _player.setFilePath(path);
      // Kein Looping, einmalige Wiedergabe
      await _player.setLoopMode(LoopMode.off);
      await _player.play();
    } catch (e) {
      _showSystemSnack('Wiedergabefehler: $e');
    }
  }

  Future<void> _stopPlayback() async {
    if (!_player.playing && !_isStoppingPlayback) return;
    setState(() => _isStoppingPlayback = true);
    try {
      await _player.stop();
    } catch (e) {
      _showSystemSnack('Stop-Fehler: $e');
    } finally {
      if (mounted) setState(() => _isStoppingPlayback = false);
    }
  }


  Future<void> _persistMessage({
    required String messageId,
    required String text,
    required bool isUser,
    bool skipPersist = false, // Wenn true: Backend hat schon gespeichert
  }) async {
    if (skipPersist) {
      debugPrint('⏭️ Skip persist: Backend hat diese Message schon gespeichert');
      return;
    }
    
    try {
      if (_avatarData == null) {
        debugPrint('⚠️ Cannot persist: _avatarData is null');
        return;
      }
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        debugPrint('⚠️ Cannot persist: user not logged in');
        return;
      }
      final fs = FirebaseFirestore.instance;
      final chatId = '${uid}_${_avatarData!.id}';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      debugPrint('💾 Speichere ${isUser ? "USER" : "AVATAR"} Message: avatarUserChats/$chatId/messages/$messageId');
      
      // Backend-kompatibles Format + highlightIcon
      await fs
          .collection('avatarUserChats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .set({
            'message_id': messageId,
            'sender': isUser ? 'user' : 'avatar',
            'content': text,
            'timestamp': timestamp,
            'avatar_id': _avatarData!.id,
            'user_id': uid,
            'isUser': isUser,
            // highlightIcon wird später via set(merge: true) gesetzt
          });
      
      debugPrint('✅ ${isUser ? "USER" : "AVATAR"} Message gespeichert: "${text.substring(0, text.length > 30 ? 30 : text.length)}..."');
    } catch (e) {
      debugPrint('❌ _persistMessage Fehler: $e');
    }
  }

  // Scroll Listener für Infinite Scroll (DEAKTIVIERT - nur noch per Button "Ältere Nachrichten")
  void _onScroll() {
    return; // Auto-Load deaktiviert
  }

  // Initial Messages prüfen (nur Count, keine Daten laden)
  Future<void> _loadInitialMessages() async {
      if (_historyLoaded) return; // Nur einmal prüfen
      if (_avatarData == null) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

    final chatId = '${uid}_${_avatarData!.id}';
    debugPrint('📥 Prüfe Messages für chatId: $chatId');

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('avatarUserChats')
          .doc(chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(1) // NUR PRÜFEN ob Messages existieren (KEIN LADEN!)
          .get()
          .timeout(const Duration(seconds: 5));

      debugPrint('📥 Messages vorhanden: ${snapshot.docs.isNotEmpty}');

      if (!mounted) return;

      // NUR FLAG setzen für "Ältere Nachrichten" Link, KEINE Messages laden!
        setState(() {
        _hasMoreMessages = snapshot.docs.isNotEmpty; // Link zeigen wenn Messages da
        _historyLoaded = true;
      });
      
      debugPrint('✅ Link aktiv: $_hasMoreMessages');
    } catch (e) {
      debugPrint('❌ Messages prüfen fehlgeschlagen: $e');
      setState(() => _historyLoaded = true);
    }
  }

  // Messages laden (Infinite Scroll - OHNE startAfter beim 1. Mal)
  Future<void> _loadMoreMessages() async {
    if (_avatarData == null || _isLoadingMore) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

    debugPrint('📥 _loadMoreMessages: Start... (_lastMessageDoc=${_lastMessageDoc?.id ?? "null"})');
    setState(() => _isLoadingMore = true);

    try {
      final chatId = '${uid}_${_avatarData!.id}';
      
      // Query: Wenn _lastMessageDoc null → Start vom Anfang, sonst nach letztem Doc
      var query = FirebaseFirestore.instance
          .collection('avatarUserChats')
          .doc(chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true);
      
      if (_lastMessageDoc != null) {
        debugPrint('📥 Query: startAfter ${_lastMessageDoc!.id}');
        query = query.startAfterDocument(_lastMessageDoc!);
      } else {
        debugPrint('📥 Query: Start vom Anfang (1. Load)');
      }
      
      final snapshot = await query.limit(20).get().timeout(const Duration(seconds: 10));

      debugPrint('📥 Gefunden: ${snapshot.docs.length} Messages');

      if (!mounted) return;

      final messages = <ChatMessage>[];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final ts = data['timestamp'] as int?;
        final timestamp = ts != null 
            ? DateTime.fromMillisecondsSinceEpoch(ts)
            : DateTime.now();
        
        // Backend-Format: sender + content ODER altes Format: isUser + text
        final sender = data['sender'] as String?;
        final content = data['content'] as String?;
        final isUser = sender == 'user' || (data['isUser'] as bool?) == true;
        final text = content ?? data['text'] as String? ?? '';
        final messageId = doc.id; // Firestore doc ID als messageId
        final highlightIcon = data['highlightIcon'] as String?;
        
        messages.add(ChatMessage(
          messageId: messageId,
          text: text,
          isUser: isUser,
          timestamp: timestamp,
          highlightIcon: highlightIcon,
        ));
      }

      setState(() {
        _messages.insertAll(0, messages.reversed); // Älteste zuerst
        _lastMessageDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _hasMoreMessages = snapshot.docs.length == 20;
        _isLoadingMore = false;
      });
      
      debugPrint('✅ ${messages.length} Messages geladen. Total: ${_messages.length}');
    } catch (e) {
      debugPrint('❌ Messages laden fehlgeschlagen: $e');
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  // Partnername laden/speichern
  Future<void> _loadPartnerName() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || _avatarData == null) return;
      final fs = FirebaseFirestore.instance;
      final doc = await fs
          .collection('users')
          .doc(uid)
          .collection('avatars')
          .doc(_avatarData?.id ?? '')
          .get()
          .timeout(const Duration(seconds: 5));
      final data = doc.data();
      if (data != null && data['partnerName'] is String) {
        _partnerName = (data['partnerName'] as String).trim();
      }
      if (data != null && data['partnerPetName'] is String) {
        _partnerPetName = (data['partnerPetName'] as String).trim();
      }
      if (data != null && data['partnerRole'] is String) {
        final role = (data['partnerRole'] as String).toLowerCase().trim();
        _partnerRole = role;
        _isKnownPartner = role.contains('ehemann') || role.contains('partner');
      }

      // Fallback: globales Profil, falls avatar-spezifische Felder fehlen
      if ((_partnerName == null || _partnerName!.isEmpty) ||
          (_partnerPetName == null || _partnerPetName!.isEmpty) ||
          !_isKnownPartner) {
        final profile = await fs
            .collection('users')
            .doc(uid)
            .collection('profile')
            .doc('global')
            .get()
            .timeout(const Duration(seconds: 5));
        final pd = profile.data();
        if (pd != null) {
          if ((_partnerName == null || _partnerName!.isEmpty) &&
              pd['partnerName'] is String) {
            _partnerName = (pd['partnerName'] as String).trim();
          }
          if ((_partnerPetName == null || _partnerPetName!.isEmpty) &&
              pd['partnerPetName'] is String) {
            _partnerPetName = (pd['partnerPetName'] as String).trim();
          }
          if (!_isKnownPartner && pd['partnerRole'] is String) {
            final role = (pd['partnerRole'] as String).toLowerCase().trim();
            _partnerRole = role;
            _isKnownPartner =
                role.contains('ehemann') || role.contains('partner');
          }
        }
      }
      
      // Letzter Fallback: user.displayName (Anzeigename aus Firebase Auth)
      if (_partnerName == null || _partnerName!.isEmpty) {
        final displayName = FirebaseAuth.instance.currentUser?.displayName;
        if (displayName != null && displayName.trim().isNotEmpty) {
          _partnerName = displayName.trim();
        }
      }
    } catch (_) {}
  }

  Future<void> _savePartnerName(String name) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || _avatarData == null) return;
      _partnerName = name.trim();
      final fs = FirebaseFirestore.instance;
      await fs
          .collection('users')
          .doc(uid)
          .collection('avatars')
          .doc(_avatarData?.id ?? '')
          .set({
            'partnerName': _partnerName,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      await fs
          .collection('users')
          .doc(uid)
          .collection('profile')
          .doc('global')
          .set({
            'partnerName': _partnerName,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      // optional: als persönlicher Insight merken
      await _saveInsight(
        'Gesprächspartner: $_partnerName',
        source: 'profile',
        fileName: 'participant.txt',
      );
    } catch (_) {}
  }

  String? _extractNameExplicit(String input) {
    final patterns = [
      RegExp(
        r'mein\s+name\s+ist\s+([A-Za-zÄÖÜäöüß\-]{2,})',
        caseSensitive: false,
      ),
      RegExp(r'ich\s+bin\s+([A-Za-zÄÖÜäöüß\-]{2,})', caseSensitive: false),
      RegExp(r'ich\s+heisse?\s+([A-Za-zÄÖÜäöüß\-]{2,})', caseSensitive: false),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(input);
      if (m != null && m.groupCount >= 1) {
        final name = m.group(1) ?? '';
        if (name.isNotEmpty) return _capitalize(name);
      }
    }
    return null;
  }

  String? _extractNameLoose(String input) {
    final lower = input.toLowerCase();
    if (!lower.contains(' ') && input.length >= 2 && input.length <= 24) {
      final word = input.replaceAll(RegExp(r'[^A-Za-zÄÖÜäöüß\-]'), '');
      if (word.isNotEmpty) return _capitalize(word);
    }
    return null;
  }

  // z. B. "Ha ja" -> "Haja" oder "Ha-Ja" wird als Kandidat erkannt
  String? _extractNameFromSplitTypos(String input) {
    final cleaned = input.trim();
    if (!cleaned.contains(' ')) return null;
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.length == 2 &&
        parts[0].length <= 3 &&
        parts[1].length <= 3 &&
        RegExp(r'^[A-Za-zÄÖÜäöüß-]+$').hasMatch(parts[0]) &&
        RegExp(r'^[A-Za-zÄÖÜäöüß-]+$').hasMatch(parts[1])) {
      final guess = _capitalize((parts[0] + parts[1]).replaceAll('-', ''));
      if (guess.length >= 2 && guess.length <= 24) return guess;
    }
    return null;
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  bool _isAffirmative(String input) {
    final t = input.toLowerCase().trim();
    return t == 'ja' ||
        t == 'genau' ||
        t == 'richtig' ||
        t == 'yes' ||
        t == 'jap' ||
        t == 'jo' ||
        t == 'klar' ||
        t == 'okay' ||
        t == 'ok' ||
        t == 'yep' ||
        t.startsWith('ja,') ||
        t.endsWith(' ja');
  }

  String _friendlyGreet(String name) {
    final suffix = _affectionateSuffix();
    final first = _shortFirstName(name);
    final variants = [
      'Hallo $first, schön dich zu sehen$suffix',
      'Hey $first, gut dass du da bist$suffix',
      'Hi $first, ich freue mich, dich zu sprechen$suffix',
    ];
    return variants[DateTime.now().millisecondsSinceEpoch % variants.length];
  }

  String _affectionateSuffix() {
    if (_partnerPetName != null && _partnerPetName!.isNotEmpty) {
      return ', mein ${_partnerPetName ?? ''}!';
    }
    final role = (_partnerRole ?? '').toLowerCase();
    if (role.contains('ehe') || role.contains('partner')) {
      const options = [', mein Schatz!', ', mein Lieber!', ', mein Herz!'];
      return options[DateTime.now().millisecondsSinceEpoch % options.length];
    }
    if (role.contains('schwager') || role.contains('schwäger')) {
      final pick = DateTime.now().millisecondsSinceEpoch % 5; // 1 von 5
      return pick == 0 ? ', Schwagerlein!' : '!';
    }
    return '!';
  }

  String _friendlyConfirmPendingName(String fullName) {
    final first = _shortFirstName(fullName);
    final roleTail = _pendingIsKnownPartner ? ' Mein Ehemann?' : '';
    final variants = [
      'Ach wie nett – bist Du es, $first?$roleTail',
      'Hey, bist Du $first?$roleTail',
      'Klingst nach $first – bist Du\'s?$roleTail',
      'Bist Du es, $first?$roleTail',
    ];
    return variants[DateTime.now().millisecondsSinceEpoch % variants.length];
  }

  String _shortFirstName(String fullName) {
    final noSurname = fullName.split(' ').first;
    final first = noSurname.split('-').first;
    return _capitalize(first.trim());
  }

  // Heuristik: Ist der Text eine Frage?
  bool _looksLikeQuestion(String text) {
    final s = text.trim().toLowerCase();
    if (s.contains('?')) return true;
    return RegExp(r'\b(wie|was|wer|wo|warum|wann|wieviel|wieviele|bist|hast|kannst|soll|darf|möchtest|magst|nun|sonst|weiter|noch)\b',
            caseSensitive: false)
        .hasMatch(s);
  }

  // Extrahiert Kosenamen aus der Eingabe
  String? _extractPetName(String input) {
    final patterns = [
      RegExp(
        r"nenn'?\s*mich\s+([A-Za-zÄÖÜäöüß\-\s]{2,24})",
        caseSensitive: false,
      ),
      RegExp(
        r'sag\s+zu\s+mir\s+([A-Za-zÄÖÜäöüß\-\s]{2,24})',
        caseSensitive: false,
      ),
      RegExp(
        r'mein\s+(?:kosename|spitzname)\s+ist\s+([A-Za-zÄÖÜäöüß\-\s]{2,24})',
        caseSensitive: false,
      ),
      RegExp(
        r'du\s+(?:nennst|hast).*?(?:mich|mir|mein)\s+([A-Za-zÄÖÜäöüß\-\s]{2,24})',
        caseSensitive: false,
      ),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(input);
      if (m != null && m.groupCount >= 1) {
        final raw = (m.group(1) ?? '').trim();
        final cleaned = raw.replaceAll(RegExp(r'[^A-Za-zÄÖÜäöüß\-\s]'), '');
        final result = _titleCase(cleaned).trim();
        if (result.length >= 2) return result;
      }
    }
    return null;
  }

  Future<void> _savePartnerPetName(String pet) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || _avatarData == null) return;
      _partnerPetName = pet.trim();
      final fs = FirebaseFirestore.instance;
      await fs
          .collection('users')
          .doc(uid)
          .collection('avatars')
          .doc(_avatarData?.id ?? '')
          .set({
            'partnerPetName': _partnerPetName,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      await fs
          .collection('users')
          .doc(uid)
          .collection('profile')
          .doc('global')
          .set({
            'partnerPetName': _partnerPetName,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      await _saveInsight(
        'Anrede/Kosename: ${_partnerPetName ?? ''}',
        source: 'profile',
        fileName: 'petname.txt',
      );
    } catch (_) {}
  }

  // _savePartnerRole aktuell ungenutzt – Logik ist in anderen Flows abgedeckt

  String _titleCase(String s) {
    return s
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }


  Future<void> _saveInsight(
    String fullText, {
    String source = 'insight',
    String? fileName,
  }) async {
    try {
      if (_avatarData == null) return;
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final base = EnvService.memoryApiBaseUrl();
      if (base.isEmpty) return;
      final uri = Uri.parse('$base/avatar/memory/insert');
      final payload = {
        'user_id': uid,
        'avatar_id': _avatarData?.id ?? '',
        'full_text': fullText,
        'source': source,
        if (fileName != null) 'file_name': fileName,
      };
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _showSystemSnack('Memory insert fehlgeschlagen: ${res.statusCode}');
      }
    } catch (e) {
      _showSystemSnack('Memory insert Fehler: $e');
    }
  }

  // _maybeConfirmGlobalInsight aktuell ungenutzt

  void _showSystemSnack(String message) {
    if (!mounted) return;
    // Statt SnackBar: zeige GMBC-Banner über dem Inputfeld
    setState(() => _bannerText = message);
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _bannerText = null);
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // _showSettings entfernt – derzeit nicht genutzt

  // ===== SEQUENTIAL CHUNKED VIDEO PLAYBACK =====

  Future<void> _preloadChunks(
    String chunk2Url,
    String chunk3Url,
    String idleUrl,
  ) async {
    try {
      debugPrint('📦 Preloading Chunk2, Chunk3, idle.mp4 parallel...');

      // Parallel laden (non-blocking!)
      final results = await Future.wait([
        _loadChunk(chunk2Url, 2),
        _loadChunk(chunk3Url, 3),
        _loadIdleLoop(idleUrl),
      ]);

      _chunk2Controller = results[0];
      _chunk2Url = chunk2Url;
      _chunk3Controller = results[1];
      _chunk3Url = chunk3Url;
      _idleController = results[2];
      _idleVideoUrl = idleUrl;

      debugPrint(
        '✅ Preload fertig: Chunk2=${_chunk2Controller != null}, Chunk3=${_chunk3Controller != null}, idle=${_idleController != null}',
      );
    } catch (e) {
      debugPrint('⚠️ Preload Error: $e');
    }
  }

  Future<VideoPlayerController?> _loadChunk(String url, int chunkNum) async {
    try {
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
      await ctrl.initialize();
      debugPrint('✅ Chunk$chunkNum preloaded');
      return ctrl;
    } catch (e) {
      debugPrint('⚠️ Chunk$chunkNum load failed: $e');
      return null;
    }
  }

  Future<VideoPlayerController?> _loadIdleLoop(String url) async {
    try {
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
      await ctrl.initialize();
      ctrl.setLooping(true);
      debugPrint('✅ idle.mp4 (10s Loop) preloaded');
      return ctrl;
    } catch (e) {
      debugPrint('⚠️ idle.mp4 load failed: $e');
      return null;
    }
  }

  void _playChunk2() {
    if (_currentChunk != 1) return;
    if (_chunk2Controller == null || !_chunk2Controller!.value.isInitialized) {
      debugPrint('⚠️ Chunk2 noch nicht ready → Skip zu idle.mp4');
      _playIdleLoop();
      return;
    }

    debugPrint('▶️ Playing Chunk2 (4s)...');
    _currentChunk = 2;
    _chunk2Controller!.seekTo(Duration.zero);
    _chunk2Controller!.play();
    setState(() {}); // UI refresh

    void Function()? chunk2Listener;
    chunk2Listener = () {
      if (!mounted) return;
      final pos = _chunk2Controller!.value.position;
      final dur = _chunk2Controller!.value.duration;

      if (_currentChunk == 2 &&
          pos.inMilliseconds >= (dur.inMilliseconds - 100) &&
          pos.inMilliseconds > 0) {
        debugPrint('🔄 Chunk2 fast fertig → Switch zu Chunk3');
        _chunk2Controller!.removeListener(chunk2Listener!);
        _playChunk3();
      }
    };
    _chunk2Controller!.addListener(chunk2Listener);
  }

  void _playChunk3() {
    if (_currentChunk != 2) return;
    if (_chunk3Controller == null || !_chunk3Controller!.value.isInitialized) {
      debugPrint('⚠️ Chunk3 noch nicht ready → Skip zu idle.mp4');
      _playIdleLoop();
      return;
    }

    debugPrint('▶️ Playing Chunk3 (4s)...');
    _currentChunk = 3;
    _chunk3Controller!.seekTo(Duration.zero);
    _chunk3Controller!.play();
    setState(() {}); // UI refresh

    void Function()? chunk3Listener;
    chunk3Listener = () {
      if (!mounted) return;
      final pos = _chunk3Controller!.value.position;
      final dur = _chunk3Controller!.value.duration;

      if (_currentChunk == 3 &&
          pos.inMilliseconds >= (dur.inMilliseconds - 100) &&
          pos.inMilliseconds > 0) {
        debugPrint('🔄 Chunk3 fast fertig → Switch zu idle.mp4 Loop');
        _chunk3Controller!.removeListener(chunk3Listener!);
        _playIdleLoop();
      }
    };
    _chunk3Controller!.addListener(chunk3Listener);
  }

  void _playIdleLoop() {
    if (_idleController == null || !_idleController!.value.isInitialized) {
      debugPrint('⚠️ idle.mp4 noch nicht ready → Warte...');
      Future.delayed(const Duration(milliseconds: 500), _playIdleLoop);
      return;
    }

    debugPrint('▶️ Playing idle.mp4 (10s Loop)...');
    _currentChunk = 4;
    _idleController!.setLooping(true);
    _idleController!.seekTo(Duration.zero);
    _idleController!.play();
    setState(() {}); // UI refresh
  }

  @override
  void dispose() {
    // _videoService.dispose(); // entfernt – kein lokales Lipsync mehr
    _playerStateSub?.cancel();
    _playerPositionSub?.cancel();
    _visemeSub?.cancel();
    _pcmSub?.cancel();
    _avatarSub?.cancel();
    // Teaser aufräumen
    _teaserTimer?.cancel();
    _teaserEntry?.remove();
    // Image Timeline aufräumen
    _imageTimer?.cancel();
    // Audio/Player stoppen (ohne setState!)
    try {
      _player.stop();
    } catch (_) {}
    _player.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _ampSub?.cancel();
    _recorder.dispose();
    // Live Avatar aufräumen (inkl. Chunks!)
    _idleController?.dispose();
    _chunk1Controller?.dispose();
    _chunk2Controller?.dispose();
    _chunk3Controller?.dispose();
    _publisherIdleTimer?.cancel();
    // Hero Chat Timer aufräumen
    for (var timer in _deleteTimers.values) {
      timer.cancel();
    }
    _deleteTimers.clear();
    
    // Timeline Timer aufräumen
    _timelineTimer?.cancel();
    _chatStopwatch.stop();
    
    // WICHTIG: Lipsync Strategy STOP bevor dispose (stoppt Audio!)
    debugPrint('🛑 Stopping Lipsync Strategy audio...');
    _lipsync.stop().catchError((e) {
      debugPrint('⚠️ Lipsync stop error: $e');
    });
    try {
      _lipsync.dispose();
    } catch (e) {
      debugPrint('⚠️ Lipsync dispose error: $e');
    }

    // LiveKit disconnecten (spart ~1€/Monat bei 2.500 Min idle!)
    final roomName = LiveKitService().roomName;
    if (roomName != null && roomName.isNotEmpty) {
      debugPrint(
        '🔌 Disconnecting LiveKit & stopping MuseTalk (room: $roomName)',
      );
      unawaited(_stopLiveKitPublisher(roomName));
      unawaited(LiveKitService().leave());
    }

    // Audio-Playback sofort stoppen, falls noch nicht gestartet/queued
    () async {
      try {
        if (_player.playing) {
          await _player.stop();
        }
      } catch (_) {}
    }();

    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TIMELINE INTEGRATION (PLAYLIST-BASIERT)
  // ═══════════════════════════════════════════════════════════════════════

  /// Lädt Timeline Items aus AKTIVER Playlist basierend auf Zeit
  Future<void> _initTimeline() async {
    if (_avatarData == null) return;
    
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    debugPrint('📅 Initializing Timeline for avatar ${_avatarData!.id}');
    
    // Starte Chat-Timer (00:00)
    _chatStopwatch.start();
    
    // Lade Timeline Items aus aktiver Playlist
    await _loadPlaylistTimelineItems();
  }

  /// Lädt Timeline Items aus ALLEN Playlists mit Scheduler
  Future<void> _loadPlaylistTimelineItems() async {
    if (_avatarData == null) return;
    
    try {
      final now = DateTime.now();
      final weekday = now.weekday; // 1=Monday, 7=Sunday

      // 1. Hole ALLE Playlists für Avatar
      final playlistsSnapshot = await FirebaseFirestore.instance
          .collection('avatars')
          .doc(_avatarData!.id)
          .collection('playlists')
          .get();

      if (playlistsSnapshot.docs.isEmpty) {
        debugPrint('📅 No playlists found');
        return;
      }

      // 2. Sammle Timeline Items aus allen passenden Playlists
      final List<Map<String, dynamic>> allItems = [];

      for (final playlistDoc in playlistsSnapshot.docs) {
        final playlistData = playlistDoc.data();
        final playlistId = playlistDoc.id;

        // Prüfe ob Playlist aktiv ist (weeklySchedules check)
        final weeklySchedules = playlistData['weeklySchedules'] as List?;
        if (weeklySchedules == null) continue;

        bool isActiveToday = false;
        for (final schedule in weeklySchedules) {
          if (schedule is! Map) continue;
          final scheduleWeekday = schedule['weekday'] as int?;
          if (scheduleWeekday == weekday) {
            isActiveToday = true;
            break;
          }
        }

        if (!isActiveToday) continue;

        // 3. Lade timelineItems aus dieser Playlist
        final timelineItems = await FirebaseFirestore.instance
            .collection('avatars')
            .doc(_avatarData!.id)
            .collection('playlists')
            .doc(playlistId)
            .collection('timelineItems')
            .where('activity', isEqualTo: true)
            .orderBy('order')
            .get();

        for (final itemDoc in timelineItems.docs) {
          final itemData = itemDoc.data();
          itemData['id'] = itemDoc.id;
          itemData['playlistId'] = playlistId;
          allItems.add(itemData);
        }
      }

      if (allItems.isEmpty) {
        debugPrint('📅 No timeline items found');
        return;
      }

      // 4. Sortiere Items nach order
      allItems.sort((a, b) {
        final aOrder = a['order'] as int? ?? 0;
        final bOrder = b['order'] as int? ?? 0;
        return aOrder.compareTo(bOrder);
      });

      // 5. Konvertiere zu AvatarMedia und speichere
      final List<AvatarMedia> mediaItems = [];
      final List<Map<String, dynamic>> itemMetadata = [];

      for (final item in allItems) {
        final assetId = item['assetId'] as String?;
        if (assetId == null) continue;

        // Lade Media Asset
        final mediaDoc = await FirebaseFirestore.instance
            .collection('avatars')
            .doc(_avatarData!.id)
            .collection('media')
            .doc(assetId)
            .get();

        if (mediaDoc.exists) {
          final media = AvatarMedia.fromMap(mediaDoc.data()!);
          mediaItems.add(media);
          itemMetadata.add(item);
        }
      }

      if (mediaItems.isNotEmpty && mounted) {
        debugPrint('📅 Loaded ${mediaItems.length} timeline items');
        
        // Check Loop aus Playlist-Config
        bool loopEnabled = false;
        if (playlistsSnapshot.docs.isNotEmpty) {
          final firstPlaylist = playlistsSnapshot.docs.first.data();
          loopEnabled = firstPlaylist['timelineLoop'] as bool? ?? false;
        }
        
        setState(() {
          _timelineItems = mediaItems;
          _timelineItemsMetadata = itemMetadata;
          _timelineCurrentIndex = 0;
          _timelineLoop = loopEnabled;
        });
        
        // Starte Timeline mit erstem Item
        _scheduleNextTimelineItem();
      }
    } catch (e) {
      debugPrint('❌ Error loading timeline: $e');
    }
  }

  /// Plant das nächste Timeline Item basierend auf Chat-Zeit
  void _scheduleNextTimelineItem() {
    if (_timelineItems.isEmpty || _timelineItemsMetadata.isEmpty) return;
    
    // Check ob Loop oder Ende
    if (_timelineCurrentIndex >= _timelineItems.length) {
      if (_timelineLoop) {
        debugPrint('📅 Timeline Loop: Restarting from beginning');
        _timelineCurrentIndex = 0;
      } else {
        debugPrint('📅 Timeline ended (no loop)');
        return;
      }
    }

    final metadata = _timelineItemsMetadata[_timelineCurrentIndex];
    final waitMinutes = metadata['minDropdown'] as int? ?? 1;
    
    // Warte X Minuten (Chat-Zeit)
    final waitDuration = Duration(minutes: waitMinutes);
    
    debugPrint('📅 Scheduling item ${_timelineCurrentIndex + 1}/${_timelineItems.length} in ${waitMinutes}min (Chat-Zeit)');
    
    _timelineTimer = Timer(waitDuration, () {
      if (!mounted) return;
      _showCurrentTimelineItem();
    });
  }

  /// Zeigt das aktuelle Timeline Item
  void _showCurrentTimelineItem() {
    if (_timelineItems.isEmpty || _timelineItemsMetadata.isEmpty) return;
    if (_timelineCurrentIndex >= _timelineItems.length) return;

    final item = _timelineItems[_timelineCurrentIndex];
    final metadata = _timelineItemsMetadata[_timelineCurrentIndex];
    
    // Berechne Anzeigedauer
    int displayMinutes = 3; // Default: 3 Minuten
    
    if (_timelineCurrentIndex + 1 < _timelineItemsMetadata.length) {
      // Es gibt ein nächstes Item
      final nextMetadata = _timelineItemsMetadata[_timelineCurrentIndex + 1];
      final nextMinutes = nextMetadata['minDropdown'] as int? ?? 1;
      
      // Anzeigedauer = min(3, nextMinutes)
      displayMinutes = nextMinutes < 3 ? nextMinutes : 3;
    }
    // Sonst: Letztes Item = 3 Minuten

    final displayDuration = Duration(minutes: displayMinutes);
    
    debugPrint('📅 Showing item ${_timelineCurrentIndex + 1}/${_timelineItems.length}: ${item.originalFileName} (${displayMinutes}min display)');
    
    _showTimelineItemWithAnimation(item, displayDuration);
  }

  /// Zeigt Timeline Item mit Slider-Animation
  void _showTimelineItemWithAnimation(AvatarMedia media, Duration displayDuration) async {
    if (!mounted) return;
    
    // Purchase Status vorab laden
    _activeTimelineItem = media;
    await _isTimelineItemPurchasedAsync();
    
    if (!mounted) return;
    
    setState(() {
      _timelineSliderVisible = true;
    });

    // Nach displayDuration ausblenden
    _timelineTimer = Timer(displayDuration, () {
      if (!mounted) return;
      
      setState(() {
        _timelineSliderVisible = false;
        _activeTimelineItem = null;
      });

      // Nächstes Item planen
      _timelineCurrentIndex++;
      _scheduleNextTimelineItem();
    });
  }

  /// Pausiert Timeline (bei Overlay/Purchase)
  void _pauseTimeline() {
    _timelineTimer?.cancel();
    debugPrint('⏸️ Timeline paused');
  }

  /// Resume Timeline (nach Overlay/Purchase)
  void _resumeTimeline() {
    if (_activeTimelineItem != null && _timelineSliderVisible) {
      // Timeline war aktiv - zeige aktuelles Item weiter
      // Vereinfacht: Lasse Timer weiterlaufen
      debugPrint('▶️ Timeline resumed (item continues)');
    } else {
      // Timeline war in Wartezeit - plane nächstes Item neu
      _scheduleNextTimelineItem();
      debugPrint('▶️ Timeline resumed (scheduling next)');
    }
  }

  // Cache für Purchase Status
  final Map<String, bool> _purchaseStatusCache = {};

  /// Prüft ob Timeline Item bereits gekauft wurde
  Future<bool> _isTimelineItemPurchasedAsync() async {
    if (_activeTimelineItem == null) return false;
    
    final mediaId = _activeTimelineItem!.id;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    
    // Kostenlose Items sind immer "gekauft" (kein Blur)
    final price = _activeTimelineItem!.price ?? 0.0;
    if (price == 0.0) return false; // Blur zeigen für "Annehmen" Flow
    
    // Cache prüfen
    if (_purchaseStatusCache.containsKey(mediaId)) {
      return _purchaseStatusCache[mediaId]!;
    }
    
    // Firestore Check
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('purchased_media')
          .doc(mediaId)
          .get()
          .timeout(const Duration(seconds: 3));
      
      final isPurchased = doc.exists;
      _purchaseStatusCache[mediaId] = isPurchased;
      return isPurchased;
    } catch (e) {
      debugPrint('❌ Error checking purchase status: $e');
      return false; // Bei Fehler: nicht gekauft annehmen
    }
  }

  /// Synchrone Version für Build-Context (nutzt Cache)
  bool _isTimelineItemPurchased() {
    if (_activeTimelineItem == null) return false;
    
    final mediaId = _activeTimelineItem!.id;
    
    // Kostenlose Items
    final price = _activeTimelineItem!.price ?? 0.0;
    if (price == 0.0) return false;
    
    // Nutze Cache
    return _purchaseStatusCache[mediaId] ?? false;
  }

  /// Öffnet Fullsize Overlay für Timeline Item
  void _onTimelineItemTap() {
    if (_activeTimelineItem == null) return;
    
    // Timeline pausieren
    _pauseTimeline();
    
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => TimelineMediaOverlay(
        media: _activeTimelineItem!,
        isPurchased: _isTimelineItemPurchased(),
        onPurchase: () {
          // Schließe Overlay
          Navigator.pop(ctx);
          // Öffne Purchase Dialog
          _showTimelinePurchaseDialog(_activeTimelineItem!);
        },
      ),
    ).then((_) {
      // Timeline fortsetzen nach Overlay-Schließen
      _resumeTimeline();
    });
  }

  /// Zeigt Kauf/Annahme Dialog
  Future<void> _showTimelinePurchaseDialog(AvatarMedia media) async {
    // Timeline bleibt pausiert während Purchase Dialog
    final price = media.price ?? 0.0;
    final isFree = price == 0.0;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _TimelinePurchaseDialog(
        media: media,
        price: price,
        isFree: isFree,
      ),
    );
    
    // Timeline fortsetzen nach Purchase Dialog
    _resumeTimeline();
  }

  @override
  bool get wantKeepAlive => true;
}

// ═══════════════════════════════════════════════════════════════════════════
// TIMELINE PURCHASE DIALOG
// ═══════════════════════════════════════════════════════════════════════════

class _TimelinePurchaseDialog extends StatefulWidget {
  final AvatarMedia media;
  final double price;
  final bool isFree;

  const _TimelinePurchaseDialog({
    required this.media,
    required this.price,
    required this.isFree,
  });

  @override
  State<_TimelinePurchaseDialog> createState() => _TimelinePurchaseDialogState();
}

class _TimelinePurchaseDialogState extends State<_TimelinePurchaseDialog> {
  bool _isProcessing = false;
  final _momentsService = MomentsService();
  final _purchaseService = MediaPurchaseService();
  String _paymentMethod = 'credits'; // 'credits' oder 'stripe'

  @override
  void initState() {
    super.initState();
    // Auto-select: Stripe wenn >= 2€, sonst Credits
    if (!widget.isFree && widget.price >= 2.0) {
      _paymentMethod = 'stripe';
    }
  }

  Future<void> _handlePurchase() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      // Für kostenlose Items: Direkt speichern
      if (widget.isFree) {
        await _momentsService.saveMoment(
          media: widget.media,
          price: 0.0,
          paymentMethod: 'free',
        );

        // Update Purchase Status Cache
        if (context.mounted) {
          final chatState = context.findAncestorStateOfType<_AvatarChatScreenState>();
          if (chatState != null) {
            chatState._purchaseStatusCache[widget.media.id] = true;
            chatState.setState(() {}); // UI refresh
          }
        }

        if (!mounted) return;
        
        // Schließe Dialog
        Navigator.pop(context);

        // Zeige Erfolgs-Meldung
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ ${widget.media.originalFileName ?? 'Item'} wurde zu Moments hinzugefügt!',
            ),
            backgroundColor: AppColors.lightBlue,
          ),
        );
      } else {
        // Für kostenpflichtige Items: Credits oder Stripe
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) {
          throw Exception('Nicht angemeldet');
        }

        if (_paymentMethod == 'credits') {
          // Credits-basierter Kauf
          final requiredCredits = (widget.price / 0.1).round();
          
          // Prüfe ob genug Credits vorhanden
          final hasCredits = await _purchaseService.hasEnoughCredits(uid, requiredCredits);
          if (!hasCredits) {
            if (!mounted) return;
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('❌ Nicht genug Credits! Benötigt: $requiredCredits'),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }

          // Kaufe mit Credits
          final success = await _purchaseService.purchaseMediaWithCredits(
            userId: uid,
            media: widget.media,
          );

          if (!success) {
            throw Exception('Credits-Kauf fehlgeschlagen');
          }

          // Speichere in Moments
          await _momentsService.saveMoment(
            media: widget.media,
            price: widget.price,
            paymentMethod: 'credits',
          );

          // Update Purchase Status Cache
          if (context.mounted) {
            final chatState = context.findAncestorStateOfType<_AvatarChatScreenState>();
            if (chatState != null) {
              chatState._purchaseStatusCache[widget.media.id] = true;
              chatState.setState(() {}); // UI refresh
            }
          }

          if (!mounted) return;
          Navigator.pop(context);
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ ${widget.media.originalFileName ?? 'Item'} gekauft! ($requiredCredits Credits)',
              ),
              backgroundColor: AppColors.lightBlue,
            ),
          );
        } else {
          // Stripe Checkout
          final checkoutUrl = await _purchaseService.purchaseMediaWithStripe(
            userId: uid,
            media: widget.media,
          );

          if (checkoutUrl == null) {
            throw Exception('Stripe Checkout URL nicht verfügbar');
          }

          if (!mounted) return;
          Navigator.pop(context);

          // Öffne Stripe Checkout URL
          final uri = Uri.parse(checkoutUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('💳 Stripe Checkout geöffnet...'),
                backgroundColor: AppColors.magenta,
              ),
            );
          } else {
            throw Exception('Checkout URL konnte nicht geöffnet werden');
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Purchase error: $e');
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Fehler: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Widget _buildPaymentMethodTile({
    required String method,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
  }) {
    final isSelected = _paymentMethod == method;
    
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: GestureDetector(
        onTap: enabled ? () {
          setState(() => _paymentMethod = method);
        } : null,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected 
                ? AppColors.magenta.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.05),
            border: Border.all(
              color: isSelected 
                  ? AppColors.magenta
                  : Colors.white.withValues(alpha: 0.2),
              width: 2,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? AppColors.magenta : Colors.white70,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check_circle,
                  color: AppColors.magenta,
                  size: 24,
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.darkSurface,
      title: Row(
        children: [
          Expanded(
            child: Text(
              widget.isFree ? 'Kostenlos' : '${widget.price.toStringAsFixed(2)} €',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          if (_isProcessing)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Cover Image
          if (widget.media.coverImages != null && widget.media.coverImages!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                widget.media.coverImages!.first.url,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => Container(
                  height: 200,
                  color: Colors.grey.shade800,
                  child: const Icon(Icons.music_note, size: 48, color: Colors.white54),
                ),
              ),
            )
          else
            // Fallback: Thumbnail oder Icon
            Container(
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  colors: [
                    AppColors.magenta.withValues(alpha: 0.3),
                    AppColors.lightBlue.withValues(alpha: 0.3),
                  ],
                ),
              ),
              child: const Icon(Icons.music_note, size: 64, color: Colors.white54),
            ),
          const SizedBox(height: 16),
          
          // Dateiname
          Text(
            widget.media.originalFileName ?? 'Audio File',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          
          // Info Text
          const SizedBox(height: 8),
          Text(
            widget.isFree
                ? 'Diese Datei wird in Moments gespeichert.'
                : 'Nach dem Kauf wird die Datei in Moments gespeichert.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
          
          // Payment Method Selection (nur für kostenpflichtige Items)
          if (!widget.isFree) ...[
            const SizedBox(height: 20),
            const Divider(color: Colors.white24),
            const SizedBox(height: 12),
            Text(
              'Zahlungsmethode',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            
            // Credits Option
            _buildPaymentMethodTile(
              method: 'credits',
              icon: Icons.monetization_on,
              title: 'Credits',
              subtitle: '${(widget.price / 0.1).round()} Credits (1 Credit = 0,10 €)',
              enabled: widget.price < 2.0 || _paymentMethod == 'credits',
            ),
            
            const SizedBox(height: 8),
            
            // Stripe Option
            _buildPaymentMethodTile(
              method: 'stripe',
              icon: Icons.credit_card,
              title: 'Kreditkarte (Stripe)',
              subtitle: 'Mindestbetrag: 2,00 €',
              enabled: widget.price >= 2.0,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton(
          onPressed: _isProcessing ? null : _handlePurchase,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.isFree ? AppColors.lightBlue : AppColors.magenta,
          ),
          child: _isProcessing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(widget.isFree ? 'Annehmen' : 'Kaufen'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MEDIA DECISION DIALOG (EXISTING)
// ═══════════════════════════════════════════════════════════════════════════

class _MediaDecisionDialog extends StatefulWidget {
  final String avatarId;
  final AvatarMedia media;
  final Future<void> Function(String decision)? onDecision;
  const _MediaDecisionDialog({
    required this.avatarId,
    required this.media,
    this.onDecision,
  });

  @override
  State<_MediaDecisionDialog> createState() => _MediaDecisionDialogState();
}

class _MediaDecisionDialogState extends State<_MediaDecisionDialog> {
  bool _accepted = false;
  Timer? _autoHide;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _autoHide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0A0A0A),
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            AspectRatio(
              aspectRatio: 9 / 16,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (!_accepted)
                    Container(
                      color: Colors.black12,
                      child: _PixelateOverlay(url: widget.media.url),
                    ),
                  if (_accepted)
                    (widget.media.type == AvatarMediaType.video)
                        ? _VideoPlayerInline(url: widget.media.url)
                        : Image.network(widget.media.url, fit: BoxFit.cover),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _accepted
                        ? null
                        : () async {
                            setState(() => _accepted = true);
                            await widget.onDecision?.call('shown');
                            // Bilder: nach 45s schließen; Videos: schließen nach Ende (hier simple 60s Fallback)
                            if (widget.media.type == AvatarMediaType.image) {
                              _autoHide = Timer(
                                const Duration(seconds: 45),
                                () {
                                  if (mounted) Navigator.pop(context);
                                },
                              );
                            } else {
                              _autoHide = Timer(
                                const Duration(seconds: 60),
                                () {
                                  if (mounted) Navigator.pop(context);
                                },
                              );
                            }
                          },
                    icon: const Icon(Icons.visibility),
                    label: Text(
                      context.read<LocalizationService>().t('chat.media.show'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      await widget.onDecision?.call('rejected');
                      if (!mounted) return;
                      nav.pop();
                    },
                    icon: const Icon(Icons.hide_image),
                    label: Text(
                      context.read<LocalizationService>().t(
                        'chat.media.reject',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _PixelateOverlay extends StatelessWidget {
  final String url;
  const _PixelateOverlay({required this.url});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          url,
          fit: BoxFit.cover,
          color: Colors.black,
          colorBlendMode: BlendMode.srcATop,
        ),
        Center(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Verpixelt – tippe „Anzeigen" ',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ],
    );
  }
}

class _VideoPlayerInline extends StatefulWidget {
  final String url;
  const _VideoPlayerInline({required this.url});

  @override
  State<_VideoPlayerInline> createState() => _VideoPlayerInlineState();
}

class _VideoPlayerInlineState extends State<_VideoPlayerInline> {
  late final VideoPlayerController _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) setState(() => _ready = true);
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
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: AspectRatio(
        aspectRatio: _ctrl.value.aspectRatio == 0
            ? 9 / 16
            : _ctrl.value.aspectRatio,
        child: Stack(
          children: [
            Positioned.fill(child: VideoPlayer(_ctrl)),
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: VideoProgressIndicator(
                _ctrl,
                allowScrubbing: true,
                colors: VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white30,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatInputField extends StatelessWidget {
  const _ChatInputField();

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_AvatarChatScreenState>();
    final controller = state!._messageController;
    return Theme(
      data: Theme.of(context).copyWith(
        textSelectionTheme: const TextSelectionThemeData(
          selectionColor:
              Colors.transparent,
          selectionHandleColor: AppColors.magenta,
          cursorColor: AppColors.magenta,
        ),
      ),
      child: Focus(
        onFocusChange: (hasFocus) {
          state.setState(() => state._inputFocused = hasFocus);
        },
        child: TextField(
          controller: controller,
          cursorColor: AppColors.magenta,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.send,
          textAlignVertical: TextAlignVertical.center,
          // Saubere vertikale Zentrierung und feste Zeilenhöhe
          strutStyle: const StrutStyle(height: 1.2, forceStrutHeight: true),
          minLines: 1,
          maxLines: null, // wächst bei Bedarf weiter
          onSubmitted: (text) {
            if (text.trim().isNotEmpty) {
              state._sendMessage();
              controller.clear();
            }
          },
          decoration: InputDecoration(
            hintText: 'Nachricht eingeben...',
            hintStyle: TextStyle(
              color: AppColors.darkGrey.withValues(alpha: 0.7), // GMBC 0.7
              fontSize: 14,
              height: 1.0,
            ),
            filled: true,
            fillColor: Colors.transparent, // überschreibt grünes Theme-Fill
            isDense: true,
            isCollapsed: true,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            // Symmetrisch, damit Text nie unter die Border rutscht
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
          style: const TextStyle(
            color: Color(0xFF2E2E2E),
            fontSize: 14,
            height: 1.0,
          ),
          // Return sendet; Shift+Return fügt Zeile ein
        ),
      ),
    );
  }
}

class ChatMessage {
  final String messageId; // PRIMARY KEY: msg-{timestamp}-{uid6}
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final String? audioPath;
  
  // Hero Chat Highlight (direkt in Message gespeichert)
  String? highlightIcon; // 🐣🔥🍻 etc.

  ChatMessage({
    required this.messageId,
    required this.text,
    required this.isUser,
    this.audioPath,
    DateTime? timestamp,
    this.highlightIcon,
  }) : timestamp = timestamp ?? DateTime.now();
  
  // Helper: Ist diese Nachricht highlighted?
  bool get isHighlighted => highlightIcon != null;
}
