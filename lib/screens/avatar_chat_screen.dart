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
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:video_player/video_player.dart';
import '../services/playlist_service.dart';
import '../services/media_service.dart';
import '../services/shared_moments_service.dart';
import '../models/media_models.dart';
import '../widgets/liveportrait_canvas.dart';

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
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isRecording = false;
  bool _isTyping = false;
  bool _isStreamingSpeaking = false; // steuert LivePortrait Canvas
  bool _isFileSpeaking = false; // steuert Datei‑Replay
  // ignore: unused_field
  final bool _isMuted =
      false; // UI Mute (wirkt auf TTS-Player; LiveKit bleibt unverändert)
  bool _isStoppingPlayback = false;
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

  // Rate-Limiting für TTS-Requests
  DateTime? _lastTtsRequestTime;
  static const int _minTtsDelayMs =
      800; // Mindestens 800ms zwischen TTS-Requests

  String? _partnerName;
  String? _pendingFullName;
  String? _pendingLooseName;
  bool _awaitingNameConfirm = false;
  bool _pendingIsKnownPartner = false;
  bool _isKnownPartner = false;
  String? _partnerPetName;
  String? _partnerRole;
  static const int _pageSize = 30;
  DocumentSnapshot<Map<String, dynamic>>? _oldestDoc;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  AvatarData? _avatarData;
  String? _cachedVoiceId; // Cache für schnellen Zugriff!
  final AudioPlayer _player = AudioPlayer();
  late LipsyncStrategy _lipsync;
  String? _lastRecordingPath;
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _ampSub;
  DateTime? _segmentStartAt;
  String?
  _activeMuseTalkRoom; // Track aktiven MuseTalk Room (verhindert doppelte /session/start Calls!)
  DateTime? _museTalkSessionStartedAt; // Timestamp wann Session gestartet wurde
  String?
  _persistentRoomName; // Room-Name bleibt während gesamter Chat-Session gleich!
  int _silenceMs = 0;
  bool _sttBusy = false;
  bool _segmentClosing = false;

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
          .get();
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
      // Avatar-Info vor Join abrufen und an Agent/Backend übermitteln (optional nutzbar)
      try {
        final infoRes = await http.post(
          Uri.parse('$base/avatar/info'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'user_id': user.uid, 'avatar_id': _avatarData!.id}),
        );
        if (infoRes.statusCode >= 200 && infoRes.statusCode < 300) {
          final info = jsonDecode(infoRes.body) as Map<String, dynamic>;
          final imgUrl = (info['avatar_image_url'] as String?)?.trim();
          if (imgUrl != null && imgUrl.isNotEmpty) {
            // Für spätere Nutzungen verfügbar halten (wenn gewünscht)
          }
        }
      } catch (_) {}
      final uri = tokenUri;
      debugPrint('🌐 Requesting LiveKit token from: $uri');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': user.uid,
          'avatar_id': _avatarData!.id,
          'name': user.displayName,
          'avatar_image_url': _avatarData?.avatarImageUrl,
        }),
      );
      debugPrint('📥 Token response: ${res.statusCode}');
      if (res.statusCode < 200 || res.statusCode >= 300) {
        // Fallback: .env Test‑Join
        final testToken = (dotenv.env['LIVEKIT_TEST_TOKEN'] ?? '').trim();
        final url = (dotenv.env['LIVEKIT_URL'] ?? '').trim();
        final fallbackRoom = (dotenv.env['LIVEKIT_TEST_ROOM'] ?? 'sunriza')
            .trim();
        if (testToken.isNotEmpty && url.isNotEmpty) {
          debugPrint(
            '⚠️ Token endpoint failed (${res.statusCode}) – fallback to TEST env',
          );
          await LiveKitService().join(
            room: fallbackRoom,
            token: testToken,
            urlOverride: url,
          );
        }
        return;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
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
          // 2. Ansonsten: Neuen Room generieren
          final uid = user.uid;
          final short = uid.length >= 8 ? uid.substring(0, 8) : uid;
          _persistentRoomName =
              'mt-$short-${DateTime.now().millisecondsSinceEpoch}';
          room = _persistentRoomName!;
          debugPrint('🆕 Generated persistent room: $_persistentRoomName');
        } else {
          // 3. Fallback: persistentRoomName aus dieser Widget-Instanz
          room = _persistentRoomName!;
        }
      }
      if (token == null || token.isEmpty) {
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
      await LiveKitService().join(room: room, token: token, urlOverride: lkUrl);
    } catch (e) {
      debugPrint('❌ LiveKit join failed: $e');
    }
  }

  Future<void> _startLiveKitPublisher(
    String room,
    String avatarId,
    String voiceId,
  ) async {
    // GUARD: Verhindere doppelte /session/start Calls für denselben Room!
    // SYNCHRON setzen BEVOR await kommt - sonst starten parallele Calls alle durch!
    final now = DateTime.now();
    if (_activeMuseTalkRoom == room && _museTalkSessionStartedAt != null) {
      final age = now.difference(_museTalkSessionStartedAt!);
      if (age.inSeconds > 240) {
        // 4 Min = 240s
        debugPrint(
          '🔄 MuseTalk session timeout (${age.inSeconds}s) - reset guard',
        );
        _activeMuseTalkRoom = null;
        _museTalkSessionStartedAt = null;
      } else {
        debugPrint(
          '⏭️ MuseTalk session bereits aktiv für room=$room (skip, age: ${age.inSeconds}s)',
        );
        return;
      }
    } else if (_activeMuseTalkRoom == room) {
      debugPrint('⏭️ MuseTalk session bereits aktiv für room=$room (skip)');
      return;
    }

    // WICHTIG: Guard SOFORT setzen (synchron), BEVOR await kommt!
    // Sonst können parallele Calls alle durchkommen!
    _activeMuseTalkRoom = room;
    _museTalkSessionStartedAt = now;
    debugPrint('🔒 MuseTalk Guard gesetzt für room=$room');

    try {
      // Get idle video URL + frames.zip URL + latents URL from Firestore
      String? idleVideoUrl;
      String? framesZipUrl;
      String? latentsUrl;
      if (_avatarData != null) {
        final doc = await FirebaseFirestore.instance
            .collection('avatars')
            .doc(_avatarData!.id)
            .get();

        if (doc.exists) {
          final data = doc.data();
          final dynamics = data?['dynamics'] as Map<String, dynamic>?;
          final basicDynamics = dynamics?['basic'] as Map<String, dynamic>?;
          idleVideoUrl = basicDynamics?['idleVideoUrl'] as String?;
          framesZipUrl = basicDynamics?['framesZipUrl'] as String?;
          latentsUrl = basicDynamics?['latentsUrl'] as String?;
        }
      }

      // Erlaube Start auch nur mit Frames, ohne idleVideoUrl
      if ((idleVideoUrl == null || idleVideoUrl.isEmpty) &&
          (framesZipUrl == null || framesZipUrl.isEmpty) &&
          (latentsUrl == null || latentsUrl.isEmpty)) {
        debugPrint('❌ No idle video, frames_zip or latents for MuseTalk');
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
          'idle_video_url': idleVideoUrl, // MuseTalk kann mp4 nutzen…
          if (framesZipUrl != null && framesZipUrl.isNotEmpty)
            'frames_zip_url':
                framesZipUrl, // …bevorzugt aber vorbereitete Frames
        }),
      );

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
        // FASTEST: Pre-computed latents (0.5s Cold Start!)
        if (latentsUrl != null && latentsUrl.isNotEmpty) {
          payload['latents_url'] = latentsUrl;
          debugPrint('⚡ Using pre-computed latents (fast path!)');
        } else if (framesZipUrl != null && framesZipUrl.isNotEmpty) {
          payload['frames_zip_url'] = framesZipUrl;
        } else if (idleVideoUrl != null && idleVideoUrl.isNotEmpty) {
          payload['idle_video_url'] = idleVideoUrl;
        }
        await http.post(
          Uri.parse(mtUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        );
        debugPrint('✅ MuseTalk session started (room=$room)');
      } catch (e) {
        debugPrint('⚠️ MuseTalk session start failed: $e');
        // Bei Fehler: Guard zurücksetzen, damit Retry möglich ist
        _activeMuseTalkRoom = null;
        _museTalkSessionStartedAt = null;
      }
    } catch (e) {
      debugPrint('❌ Publisher start error: $e');
      // Bei Fehler: Guard zurücksetzen, damit Retry möglich ist
      _activeMuseTalkRoom = null;
      _museTalkSessionStartedAt = null;
    }
  }

  Future<void> _stopLiveKitPublisher(String room) async {
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
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        debugPrint('✅ LiveKit publisher stopped');
      }

      // Auch MuseTalk Session stoppen
      try {
        final mtUrl = AppConfig.museTalkHttpUrl.endsWith('/')
            ? '${AppConfig.museTalkHttpUrl}session/stop'
            : '${AppConfig.museTalkHttpUrl}/session/stop';
        await http.post(
          Uri.parse(mtUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'room': room}),
        );
        _activeMuseTalkRoom = null; // Reset Guard!
        _museTalkSessionStartedAt = null; // Reset Timestamp!
        debugPrint('✅ MuseTalk session stopped (room=$room)');
      } catch (e) {
        debugPrint('⚠️ MuseTalk session stop failed: $e');
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

    // Initialize Lipsync Strategy
    _lipsync = LipsyncFactory.create(
      mode: AppConfig.lipsyncMode,
      backendUrl: AppConfig.backendUrl,
      orchestratorUrl: AppConfig.orchestratorUrl,
    );

    // Callback für Streaming Playback Status
    _lipsync.onPlaybackStateChanged = (isPlaying) async {
      if (!mounted) return;
      if (_isStreamingSpeaking != isPlaying) {
        debugPrint('🎙️ _isStreamingSpeaking: $isPlaying');
        setState(() => _isStreamingSpeaking = isPlaying);

        // WICHTIG: MuseTalk Session wird NUR EINMAL beim Chat-Eintritt gestartet (_initLiveAvatar)!
        // NICHT bei jedem Audio-Playback starten - das würde zu vielen Container-Starts führen!
        // Der Guard verhindert bereits doppelte Starts, aber wir vermeiden hier unnötige Calls.

        // Optional: Session stoppen wenn Playback endet (normalerweise bleibt Session warm für Re-Use)
        // DEAKTIVIERT: Lassen Session warm für nächstes Audio (spart Container-Startzeit!)
        /*
        final roomName = LiveKitService().roomName;
        if (!isPlaying && roomName != null && roomName.isNotEmpty) {
          // Debounce: warte kurz, ob noch weitere Audio‑Chunks kommen
          await Future.delayed(const Duration(milliseconds: 350));
          if (!_isStreamingSpeaking) {
            await _stopLiveKitPublisher(roomName);
          }
        }
        */
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
      _visemeSub = _lipsync.visemeStream!.listen((ev) {
        // Während Sprechen Canvas sichtbar halten
        if (mounted && !_isStreamingSpeaking) {
          setState(() => _isStreamingSpeaking = true);
        }
        debugPrint('👄 Viseme: ${ev.viseme} @ ${ev.ptsMs}ms');
        // Viseme an LivePortrait-Canvas weiterleiten (falls vorhanden)
        _lpKey.currentState?.sendViseme(ev.viseme, ev.ptsMs, ev.durationMs);
      });
    }

    // PCM-Stream → LivePortrait (Audio-Treiber)
    if (_lipsync.pcmStream != null) {
      _pcmSub = _lipsync.pcmStream!.listen((chunk) {
        final bytes = Uint8List.fromList(chunk.bytes);
        _lpKey.currentState?.sendAudioChunk(bytes, chunk.ptsMs);
      });
    }
    // Empfange AvatarData SOFORT (synchron) von der vorherigen Seite
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final args = ModalRoute.of(context)?.settings.arguments;

      // SOFORT setzen, wenn als Argument übergeben (KEIN await!)
      if (args is AvatarData && _avatarData == null) {
        setState(() {
          _avatarData = args;
        });
        // Starte Firestore-Listener für Live-Updates
        _startAvatarListener(args.id);
      }

      // Priorisiere widget.avatarId (Overlay-Chat) - nur wenn noch nicht gesetzt
      if (widget.avatarId != null && _avatarData == null) {
        final doc = await FirebaseFirestore.instance
            .collection('avatars')
            .doc(widget.avatarId)
            .get();
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
        if (!manual) {
          await _maybeJoinLiveKit();
        }
        // History & Assets parallel laden (nicht blockierend!)
        unawaited(_loadHistory());
        unawaited(_initLiveAvatar(_avatarData!.id));

        // Begrüßung: für Tests JEDES Mal beim Öffnen abspielen
        final greet = (_avatarData?.greetingText?.trim().isNotEmpty == true)
            ? _avatarData!.greetingText!
            : ((_partnerName ?? '').isNotEmpty
                  ? _friendlyGreet(_partnerName ?? '')
                  : 'Hallo, schön, dass Du vorbeischaust. Magst Du mir Deinen Namen verraten?');
        debugPrint('🎙️ Greeting (immer): voiceId=$_cachedVoiceId');
        unawaited(_botSay(greet));
      }
    });
  }

  Future<void> _initLiveAvatar(String avatarId) async {
    try {
      // Lade Avatar-Assets-URLs aus Firestore
      final doc = await FirebaseFirestore.instance
          .collection('avatars')
          .doc(avatarId)
          .get();

      if (!doc.exists) {
        debugPrint('⚠️ Dynamics-Video: Avatar nicht gefunden in Firestore');
        if (!mounted) return;
        setState(() => _liveAvatarEnabled = false);
        return;
      }

      final data = doc.data();
      // Checke nach dynamics.basic (statt liveAvatar)
      final dynamics = data?['dynamics'] as Map<String, dynamic>?;
      final basicDynamics = dynamics?['basic'] as Map<String, dynamic>?;

      if (basicDynamics == null || basicDynamics['status'] != 'ready') {
        debugPrint(
          '⚠️ Dynamics-Video: Kein "basic" Dynamics vorhanden für $avatarId\n'
          '→ Fallback: Nur Hero-Image wird angezeigt',
        );
        if (!mounted) return;
        setState(() {
          _liveAvatarEnabled = false;
          _hasIdleDynamics = false; // Kein idle.mp4 → Hero Image zeigen!
        });
        return;
      }

      // idle.mp4 existiert in Firestore!
      if (!mounted) return;
      setState(() => _hasIdleDynamics = true);

      // URLs aus Firebase Storage (+ Cache-Buster)
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

        // 1. Chunk1 laden (2s, ~1-2 MB, lädt in 0.5s!)
        final chunk1Ctrl = VideoPlayerController.networkUrl(
          Uri.parse(chunk1Url),
        );
        await chunk1Ctrl.initialize();
        chunk1Ctrl.play();

        _chunk1Controller?.dispose();
        _chunk1Controller = chunk1Ctrl;
        _chunk1Url = chunk1Url;
        _currentChunk = 1;

        if (!mounted) return;
        setState(() => _liveAvatarEnabled = true);
        debugPrint(
          '✅ Chunk1 (2s) läuft! Preload Chunk2+3+idle.mp4 im Hintergrund...',
        );

        // 2. PARALLEL im Hintergrund: Chunk2, Chunk3, idle.mp4 laden (non-blocking!)
        unawaited(_preloadChunks(chunk2Url, chunk3Url, idleUrl));

        // 3. Sequential Playback: Chunk1 → Chunk2 → Chunk3 → idle.mp4
        chunk1Ctrl.addListener(() {
          if (!chunk1Ctrl.value.isPlaying &&
              chunk1Ctrl.value.position >= chunk1Ctrl.value.duration &&
              _currentChunk == 1) {
            _playChunk2();
          }
        });
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

      // MuseTalk Session EINMAL vorbereiten (wenn LiveKit aktiv + idle.mp4 vorhanden)
      final roomName = LiveKitService().roomName;
      if (roomName != null &&
          roomName.isNotEmpty &&
          _avatarData?.id != null &&
          _cachedVoiceId != null &&
          _activeMuseTalkRoom == null) {
        // Nur wenn noch nicht aktiv!
        debugPrint('🎬 Preparing MuseTalk session (once) for room=$roomName');
        unawaited(
          _startLiveKitPublisher(roomName, _avatarData!.id, _cachedVoiceId!),
        );
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

    // Hero Image als Placeholder bis idle.mp4 READY ist!
    // Sobald idle.mp4 ready (_liveAvatarEnabled = true) → wird automatisch im Stack überlagert
    final backgroundImage = _liveAvatarEnabled
        ? null // idle.mp4 READY → kein Hero Image mehr (Bandbreite sparen)
        : (_currentBackgroundImage ??
              _avatarData
                  ?.avatarImageUrl); // idle.mp4 lädt → Hero Image als Placeholder

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 56,
        titleSpacing: 0,
        leading: (widget.onClose == null)
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  } else {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/avatar-list',
                      (route) => false,
                    );
                  }
                },
              )
            : const SizedBox(width: 48),
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
          AnimatedBuilder(
            animation: LiveKitService().connectionStatus,
            builder: (context, _) {
              final s = LiveKitService().connectionStatus.value;
              Color bg = Colors.black.withValues(alpha: 0.6);
              if (s == 'connected') bg = Colors.green.withValues(alpha: 0.7);
              if (s == 'reconnecting') {
                bg = Colors.orange.withValues(alpha: 0.7);
              }
              if (s == 'disconnected') bg = Colors.red.withValues(alpha: 0.7);
              if (s == 'ended') bg = Colors.grey.withValues(alpha: 0.7);
              final room = LiveKitService().roomName ?? '-';
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'LK: $s',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'MT room: $room',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SizedBox.expand(
        child: Stack(
          children: [
            // Hero-Animation für nahtlosen Übergang vom Explorer!
            // Positioned MUSS außen sein, Hero innen!
            Positioned.fill(
              child: Hero(
                tag: 'avatar-${_avatarData?.id}',
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
                    if (backgroundImage != null && backgroundImage.isNotEmpty) {
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
                    // Chat-Nachrichten
                    SizedBox(height: 200, child: _buildChatMessages()),

                    // Input-Bereich
                    _buildInputArea(),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
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
    // Prüfe ob von "Meine Avatare" gekommen (onClose == null = normale Navigation)
    final showBackButton = widget.onClose == null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Row(
        children: [
          // Zurück-Pfeil nur wenn von "Meine Avatare" (nicht von Home/Explore)
          if (showBackButton)
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            )
          else
            const SizedBox(width: 48),
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
          // Symmetrischer Platzhalter rechts (entspricht IconButton-Breite)
          const SizedBox(width: 48),
          // KEINE Suche im Chat!
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
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          if (_messages.isNotEmpty && _hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 6.0, bottom: 2.0),
              child: TextButton.icon(
                onPressed: _isLoadingMore ? null : _loadMoreHistory,
                icon: const Icon(
                  Icons.history,
                  color: Colors.white70,
                  size: 18,
                ),
                label: Builder(
                  builder: (context) {
                    final t = (_isLoadingMore)
                        ? 'chat.loadingOlder'
                        : 'chat.showOlder';
                    return Text(
                      context.read<LocalizationService>().t(t),
                      style: const TextStyle(color: Colors.white70),
                    );
                  },
                ),
              ),
            ),
          // Nachrichten-Liste
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return _buildMessageBubble(_messages[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    // Kein Platzhalter – der Avatar begrüßt automatisch
    return const SizedBox.shrink();
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          // Mini-Avatar (KI) ausgeblendet
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? Colors.black : Colors.grey.shade800,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: GestureDetector(
                      onTap: () async {
                        if (!isUser) {
                          if (message.audioPath != null) {
                            await _playAudioAtPath(message.audioPath!);
                          } else {
                            final p = await _ensureTtsForText(message.text);
                            if (p != null) {
                              // persist audioPath into this message
                              final idx = _messages.indexOf(message);
                              if (idx >= 0) {
                                setState(() {
                                  _messages[idx] = ChatMessage(
                                    text: message.text,
                                    isUser: false,
                                    audioPath: p,
                                    timestamp: message.timestamp,
                                  );
                                });
                              }
                              await _playAudioAtPath(p);
                            } else {
                              _showSystemSnack('TTS nicht verfügbar');
                            }
                          }
                        }
                      },
                      child: Text(
                        message.text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  if (!isUser)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            if (_player.playing) {
                              await _player.pause();
                              setState(() => _isFileSpeaking = false);
                            } else {
                              if (_player.processingState ==
                                      ProcessingState.completed ||
                                  _player.processingState ==
                                      ProcessingState.idle) {
                                // Restart from beginning
                                if (message.audioPath != null) {
                                  await _playAudioAtPath(message.audioPath!);
                                } else {
                                  final p = await _ensureTtsForText(
                                    message.text,
                                  );
                                  if (p != null) {
                                    final idx = _messages.indexOf(message);
                                    if (idx >= 0) {
                                      setState(() {
                                        _messages[idx] = ChatMessage(
                                          text: message.text,
                                          isUser: false,
                                          audioPath: p,
                                          timestamp: message.timestamp,
                                        );
                                      });
                                    }
                                    await _playAudioAtPath(p);
                                  }
                                }
                              } else {
                                // Resume
                                await _player.play();
                                setState(() => _isFileSpeaking = true);
                              }
                            }
                          },
                          child: const SizedBox(
                            width: 36,
                            height: 36,
                            child: Center(
                              child: Icon(
                                Icons.volume_up,
                                color: Colors.white70,
                                size: 20,
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
          // Mini-Avatar (User) ausgeblendet
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return SafeArea(
      top: false,
      bottom: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        decoration: const BoxDecoration(
          color: Color(0x20000000),
          border: Border(top: BorderSide(color: Color(0x40FFFFFF))),
        ),
        child: Row(
          children: [
            // Mikrofon-Button
            GestureDetector(
              onTap: _toggleRecording,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _isRecording ? Colors.red : Colors.black,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (_isRecording ? Colors.red : Colors.black)
                          .withValues(alpha: 0.3),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  _isRecording ? Icons.stop : Icons.mic,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),

            const SizedBox(width: 12),

            // Text-Eingabe
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
                child: const _ChatInputField(),
              ),
            ),

            const SizedBox(width: 12),

            // Senden-Button
            GestureDetector(
              onTap: _sendMessage,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.black,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.send, color: Colors.white, size: 24),
              ),
            ),
          ],
        ),
      ),
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
      _showSystemSnack('Aufnahme läuft…');
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
      final resp = await req.send();
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
    if (_messageController.text.trim().isNotEmpty) {
      // Aktuellen Stream sauber beenden, nur bei explizitem Senden
      try {
        await _lipsync.stop();
      } catch (_) {}

      final text = _messageController.text.trim();
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
        _addMessage(text, true);
        _messageController.clear();
        return;
      }
      _addMessage(text, true);
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

      // Name-Erkennung: explizit -> sofort merken; sonst lose Heuristik mit optionaler Nachfrage
      if ((_partnerName == null || _partnerName!.isEmpty)) {
        final explicit = _extractNameExplicit(text);
        if (explicit != null && explicit.isNotEmpty) {
          _isKnownPartner = true;
          _savePartnerName(explicit);
          _botSay(_friendlyGreet(_shortFirstName(_partnerName ?? explicit)));
          return;
        }
        final loose = _extractNameLoose(text);
        if (loose != null && loose.isNotEmpty) {
          final authName = FirebaseAuth.instance.currentUser?.displayName;
          if (authName != null && authName.isNotEmpty) {
            final ln = loose.toLowerCase();
            final an = authName.toLowerCase();
            final starts =
                an.startsWith("$ln ") || an.startsWith("$ln-") || an == ln;
            if (starts && authName.length > loose.length) {
              _pendingLooseName = _capitalize(loose);
              _pendingFullName = authName;
              _pendingIsKnownPartner = true;
              _awaitingNameConfirm = true;
              _botSay(_friendlyConfirmPendingName(_pendingFullName ?? ''));
              return;
            }
          }
          // kein bekannter Vollname → direkt übernehmen
          _isKnownPartner = true;
          _savePartnerName(loose);
          _botSay(_friendlyGreet(_shortFirstName(_partnerName ?? loose)));
          return;
        }
        // Sonderfall: mögliche Namenseingabe mit Leerzeichen/Typo (z. B. "Ha ja")
        final splitName = _extractNameFromSplitTypos(text);
        if (splitName != null && splitName.isNotEmpty) {
          _pendingLooseName = splitName;
          _pendingFullName = null;
          _pendingIsKnownPartner = true;
          _awaitingNameConfirm = true;
          await _botSay('Ach, das ist interessant – heißt du "$splitName"?');
          return;
        }
        // Ultimativer Fallback: Ein-Wort-Name direkt übernehmen
        final onlyWord = RegExp(r'^[A-Za-zÄÖÜäöüß\-]{2,24}$');
        if (onlyWord.hasMatch(text)) {
          final nm = _capitalize(
            text.replaceAll(RegExp(r'[^A-Za-zÄÖÜäöüß\-]'), ''),
          );
          if (nm.isNotEmpty) {
            _isKnownPartner = true;
            _savePartnerName(nm);
            _botSay(_friendlyGreet(_shortFirstName(nm)));
            return;
          }
        }
      }

      // Kosenamen-Erkennung: ohne Nachfrage speichern
      final pet = _extractPetName(text);
      if (pet != null && pet.isNotEmpty) {
        _savePartnerPetName(pet);
        _botSay("Alles klar – ich nenne dich ab jetzt '$pet'.");
        return;
      }

      _chatWithBackend(_messages.last.text);
    }
  }

  Future<void> _botSay(String text) async {
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

    // PRIORITÄT: Streaming (schnell!)
    if (_lipsync.visemeStream != null &&
        _cachedVoiceId != null &&
        _cachedVoiceId!.isNotEmpty) {
      _addMessage(text, false);
      debugPrint('🚀 _botSay: Using STREAMING (cached voiceId)');
      await _lipsync.speak(text, _cachedVoiceId!);
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
        _addMessage(text, false);
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
          _showSystemSnack('TTS-Fehler: leere Antwort');
        }
      } else {
        _showSystemSnack(
          'TTS-HTTP: ${res.statusCode} ${res.body.substring(0, res.body.length > 120 ? 120 : res.body.length)}',
        );
      }
    } catch (e) {
      _showSystemSnack('TTS-Fehler: $e');
    }
    _addMessage(text, false, audioPath: path);
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
      );
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
          .get();
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

  void _addMessage(String text, bool isUser, {String? audioPath}) {
    if (!mounted) return;
    setState(() {
      _messages.add(
        ChatMessage(text: text, isUser: isUser, audioPath: audioPath),
      );
    });
    _scrollToBottom();
    _persistMessage(text: text, isUser: isUser);
  }

  Future<void> _chatWithBackend(String userText) async {
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
              .get();
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
        _addMessage(answer, false);

        // DEBUG: Check Streaming Conditions
        debugPrint(
          '💬 Chat Response: stream=${_lipsync.visemeStream != null}, voiceId=${_cachedVoiceId != null ? _cachedVoiceId!.substring(0, 8) : "NULL"}',
        );

        // PRIORITÄT: Streaming (schnell, < 500ms)
        if (_lipsync.visemeStream != null &&
            _cachedVoiceId != null &&
            _cachedVoiceId!.isNotEmpty) {
          debugPrint('🚀 Chat: Using STREAMING audio');
          unawaited(_lipsync.speak(answer, _cachedVoiceId!));
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

  Future<void> _loadHistory() async {
    try {
      if (_avatarData == null) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final fs = FirebaseFirestore.instance;
      final snap = await fs
          .collection('users')
          .doc(uid)
          .collection('avatars')
          .doc(_avatarData?.id ?? '')
          .collection('chat')
          .orderBy('createdAt')
          .limit(_pageSize)
          .get();
      final List<ChatMessage> loaded = [];
      for (final d in snap.docs) {
        final data = d.data();
        final text = (data['text'] as String?) ?? '';
        if (text.isEmpty) continue;
        final isUser = (data['isUser'] as bool?) ?? false;
        loaded.add(ChatMessage(text: text, isUser: isUser));
      }
      if (mounted && loaded.isNotEmpty) {
        setState(() {
          _messages
            ..clear()
            ..addAll(loaded);
          _oldestDoc = snap.docs.isNotEmpty ? snap.docs.first : null;
          _hasMore = snap.docs.length == _pageSize;
        });
        _scrollToBottom();
      }
    } catch (_) {}
  }

  Future<void> _persistMessage({
    required String text,
    required bool isUser,
  }) async {
    try {
      if (_avatarData == null) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final fs = FirebaseFirestore.instance;
      await fs
          .collection('users')
          .doc(uid)
          .collection('avatars')
          .doc(_avatarData?.id ?? '')
          .collection('chat')
          .add({
            'text': text,
            'isUser': isUser,
            'createdAt': FieldValue.serverTimestamp(),
          });
    } catch (_) {}
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
          .get();
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
            .get();
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

  Future<void> _loadMoreHistory() async {
    if (_avatarData == null || _isLoadingMore || _oldestDoc == null) return;
    setState(() => _isLoadingMore = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final fs = FirebaseFirestore.instance;
      final q = fs
          .collection('users')
          .doc(uid)
          .collection('avatars')
          .doc(_avatarData?.id ?? '')
          .collection('chat')
          .orderBy('createdAt')
          .endBeforeDocument(_oldestDoc!)
          .limitToLast(_pageSize);
      final snap = await q.get();
      if (snap.docs.isEmpty) {
        setState(() {
          _hasMore = false;
        });
        return;
      }
      final List<ChatMessage> older = [];
      for (final d in snap.docs) {
        final data = d.data();
        final text = (data['text'] as String?) ?? '';
        if (text.isEmpty) continue;
        final isUser = (data['isUser'] as bool?) ?? false;
        older.add(ChatMessage(text: text, isUser: isUser));
      }
      if (mounted && older.isNotEmpty) {
        setState(() {
          _messages.insertAll(0, older);
          _oldestDoc = snap.docs.first;
          _hasMore = snap.docs.length == _pageSize;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
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
      );
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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

    _chunk2Controller!.addListener(() {
      if (!_chunk2Controller!.value.isPlaying &&
          _chunk2Controller!.value.position >=
              _chunk2Controller!.value.duration &&
          _currentChunk == 2) {
        _playChunk3();
      }
    });
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

    _chunk3Controller!.addListener(() {
      if (!_chunk3Controller!.value.isPlaying &&
          _chunk3Controller!.value.position >=
              _chunk3Controller!.value.duration &&
          _currentChunk == 3) {
        _playIdleLoop();
      }
    });
  }

  void _playIdleLoop() {
    if (_idleController == null || !_idleController!.value.isInitialized) {
      debugPrint('⚠️ idle.mp4 noch nicht ready → Warte...');
      Future.delayed(const Duration(milliseconds: 500), _playIdleLoop);
      return;
    }

    debugPrint('▶️ Playing idle.mp4 (10s Loop)...');
    _currentChunk = 4;
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
    // Lipsync Strategy aufräumen (schließt WebSocket!)
    _lipsync.dispose();

    // WICHTIG: LiveKit/MuseTalk NICHT stoppen beim Chat-Verlassen!
    // → Wenn User raus/rein geht, sollte Session WARM bleiben (schneller 2. Start!)
    // → MuseTalk Container stirbt automatisch nach 3 Min (scaledown_window)
    // → LiveKit bleibt connected (kostet fast nix)
    debugPrint(
      '🔄 Chat dispose - LiveKit/MuseTalk bleiben WARM (für schnellen Re-Entry)',
    );

    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;
}

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
    return TextField(
      controller: controller,
      decoration: const InputDecoration(
        hintText: 'Nachricht eingeben...',
        hintStyle: TextStyle(color: Colors.white70),
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      style: const TextStyle(color: Colors.white),
      maxLines: null,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => state._sendMessage(),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final String? audioPath;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.audioPath,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
