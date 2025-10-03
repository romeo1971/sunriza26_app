import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
// import 'dart:typed_data'; // nicht mehr benötigt
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
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:video_player/video_player.dart';
import '../services/playlist_service.dart';
import '../services/media_service.dart';
import '../services/shared_moments_service.dart';
import '../models/media_models.dart';
import 'package:extended_image/extended_image.dart';

class AvatarChatScreen extends StatefulWidget {
  final String? avatarId; // Optional: Für Overlay-Chat
  final VoidCallback? onClose; // Optional: Für Overlay-Chat

  const AvatarChatScreen({super.key, this.avatarId, this.onClose});

  @override
  State<AvatarChatScreen> createState() => _AvatarChatScreenState();
}

class _AvatarChatScreenState extends State<AvatarChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isRecording = false;
  bool _isTyping = false;
  bool _isSpeaking = false;
  bool _isMuted =
      false; // UI Mute (wirkt auf TTS-Player; LiveKit bleibt unverändert)
  bool _isStoppingPlayback = false;
  StreamSubscription<PlayerState>? _playerStateSub;

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
  final AudioPlayer _player = AudioPlayer();
  String? _lastRecordingPath;
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _ampSub;
  DateTime? _segmentStartAt;
  int _silenceMs = 0;
  bool _sttBusy = false;
  bool _segmentClosing = false;

  static const int _silenceThresholdDb = -40;
  static const int _silenceHoldMs = 800;
  static const int _minSegmentMs = 1200;
  static const bool kAutoSend = false;

  bool _greetedOnce = false;

  // Playlist/Teaser
  final PlaylistService _playlistSvc = PlaylistService();
  final MediaService _mediaSvc = MediaService();
  final SharedMomentsService _momentsSvc = SharedMomentsService();
  Timer? _teaserTimer;
  AvatarMedia? _pendingTeaserMedia;
  OverlayEntry? _teaserEntry;

  Future<void> _maybeJoinLiveKit() async {
    try {
      if ((dotenv.env['LIVEKIT_ENABLED'] ?? '').trim() != '1') return;
      final base = EnvService.memoryApiBaseUrl();
      if (base.isEmpty) return;
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
      final uri = Uri.parse('$base/livekit/token');
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
      if (res.statusCode < 200 || res.statusCode >= 300) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final token = (data['token'] as String?)?.trim();
      final room = (data['room'] as String?)?.trim() ?? 'sunriza';
      final lkUrl = (data['url'] as String?)?.trim();
      if (token == null || token.isEmpty) return;
      // Token für möglichen Reconnect hinterlegen (nur im Flutter-Prozess)
      try {
        // Achtung: .env ist nur für Boot-Config; hier nur in-memory speichern wäre sauberer.
        // Wir verwenden dotenv hier nicht zum Schreiben; daher nur Service-intern.
        // Falls gewünscht, könnte man einen kleinen TokenCache-Service ergänzen.
      } catch (_) {}
      // Mapping wie im PDF: NEXT_PUBLIC_LIVEKIT_URL == LIVEKIT_URL → vom Backend geliefert
      await LiveKitService().join(room: room, token: token, urlOverride: lkUrl);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();

    // Hör auf Audio-Player-Status, um Sprech-Indikator zu steuern
    _playerStateSub = _player.playerStateStream.listen((state) {
      final speaking =
          state.playing &&
          state.processingState != ProcessingState.completed &&
          state.processingState != ProcessingState.idle;
      if (_isSpeaking != speaking && mounted) {
        setState(() => _isSpeaking = speaking);
      }
    });
    // Empfange AvatarData SOFORT (synchron) von der vorherigen Seite
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final args = ModalRoute.of(context)?.settings.arguments;

      // SOFORT setzen, wenn als Argument übergeben (KEIN await!)
      if (args is AvatarData && _avatarData == null) {
        setState(() {
          _avatarData = args;
        });
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
        }
      }

      // Weiter mit Loading + Greeting
      if (_avatarData != null) {
        await _loadPartnerName();
        final manual = (dotenv.env['LIVEKIT_MANUAL_START'] ?? '').trim() == '1';
        if (!manual) {
          await _maybeJoinLiveKit();
        }
        await _loadHistory();
        final hasAny = _messages.isNotEmpty;
        final lastIsBot = hasAny ? !_messages.last.isUser : false;
        if (!_greetedOnce && !lastIsBot) {
          _greetedOnce = true;
          final greet = (_avatarData?.greetingText?.trim().isNotEmpty == true)
              ? _avatarData!.greetingText!
              : ((_partnerName ?? '').isNotEmpty
                    ? _friendlyGreet(_partnerName ?? '')
                    : 'Hallo, schön, dass Du vorbeischaust. Magst Du mir Deinen Namen verraten?');
          _botSay(greet);
        }
        // Starte Teaser-Scheduling
        _scheduleTeaser();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final backgroundImage = _avatarData?.avatarImageUrl;
    // Hintergrund wird stets mit Avatar-Bild gefüllt; LiveKit/Video-Overlay liegt darüber

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
              if (_avatarData?.firstNamePublic == true)
                parts.add(_avatarData!.firstName);
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
        actions: const [SizedBox(width: 48)],
      ),
      body: SizedBox.expand(
        child: Stack(
          children: [
            // Background Image FULLSCREEN (height: 100%, width: auto)
            if (backgroundImage != null && backgroundImage.isNotEmpty)
              Positioned.fill(
                child: ExtendedImage.network(
                  backgroundImage,
                  fit: BoxFit.cover,
                  cache: true,
                  height: double.infinity,
                  width: double.infinity,
                  loadStateChanged: (state) {
                    switch (state.extendedImageLoadState) {
                      case LoadState.loading:
                        return Container(color: Colors.black);
                      case LoadState.completed:
                        return ExtendedRawImage(
                          image: state.extendedImageInfo?.image,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                        );
                      case LoadState.failed:
                        return Container(color: Colors.black);
                    }
                  },
                ),
              )
            else
              Container(color: Colors.black),
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

  Widget _buildAvatarImage() {
    final hasImage = _avatarData?.avatarImageUrl != null;

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
                  if (s == 'idle') return const SizedBox.shrink();
                  Color bg = Colors.black.withValues(alpha: 0.6);
                  String label = s;
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
                      child: GestureDetector(
                        onTap: () async {
                          if (_player.playing) {
                            await _player.pause();
                            setState(() => _isSpeaking = false);
                          } else {
                            if (_player.processingState ==
                                    ProcessingState.completed ||
                                _player.processingState ==
                                    ProcessingState.idle) {
                              // Restart from beginning
                              if (message.audioPath != null) {
                                await _playAudioAtPath(message.audioPath!);
                              }
                            } else {
                              // Resume
                              await _player.play();
                              setState(() => _isSpeaking = true);
                            }
                          }
                        },
                        child: Icon(
                          _player.playing ? Icons.pause : Icons.volume_up,
                          color: Colors.white70,
                          size: 18,
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

    String? path;
    try {
      String? voiceId = (_avatarData?.training != null)
          ? (_avatarData?.training?['voice'] != null
                ? (_avatarData?.training?['voice']?['elevenVoiceId'] as String?)
                : null)
          : null;

      // Fallback: neu aus Firestore laden, falls noch nicht vorhanden
      if (voiceId == null || voiceId.isEmpty) {
        voiceId = await _reloadVoiceIdFromFirestore();
      }

      final base = EnvService.memoryApiBaseUrl();
      if (base.isEmpty) {
        _showSystemSnack('Backend-URL fehlt (.env MEMORY_API_BASE_URL)');
        return;
      }
      final uri = Uri.parse('$base/avatar/tts');
      final payload = <String, dynamic>{'text': text};
      // Immer die geklonte Stimme verwenden
      if (voiceId != null) {
        payload['voice_id'] = voiceId;
      } else {
        _showSystemSnack('Keine geklonte Stimme verfügbar');
        return;
      }
      // Voice-Parameter aus training.voice übernehmen
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
        // Erwartet JSON { audio_b64: "..." }
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

  @override
  void dispose() {
    // _videoService.dispose(); // entfernt – kein lokales Lipsync mehr
    _playerStateSub?.cancel();
    _stopPlayback();
    _player.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _ampSub?.cancel();
    _recorder.dispose();
    // Teaser aufräumen
    _teaserTimer?.cancel();
    _teaserEntry?.remove();
    // LiveKit sauber trennen (no-op wenn Feature deaktiviert)
    unawaited(LiveKitService().leave());
    super.dispose();
  }
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
                      await widget.onDecision?.call('rejected');
                      if (mounted) Navigator.pop(context);
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
              'Verpixelt – tippe „Anzeigen“',
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
