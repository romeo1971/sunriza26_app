import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import '../models/avatar_data.dart';
import '../services/video_stream_service.dart';
import '../services/bithuman_service.dart';
import '../services/env_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http_parser/http_parser.dart';

class AvatarChatScreen extends StatefulWidget {
  const AvatarChatScreen({super.key});

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
  StreamSubscription<PlayerState>? _playerStateSub;
  String? _partnerName;
  // entfernt – nicht mehr benötigt
  // Pending-Bestätigung bei unsicherem Kurz-Namen
  String? _pendingFullName;
  String? _pendingLooseName;
  bool _awaitingNameConfirm = false;
  bool _pendingIsKnownPartner = false;
  bool _isKnownPartner = false;
  String? _partnerPetName;
  String? _partnerRole;
  // Paging
  static const int _pageSize = 30;
  DocumentSnapshot<Map<String, dynamic>>? _oldestDoc;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  AvatarData? _avatarData;
  // Aufnahme temporär deaktiviert
  // final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  String? _lastRecordingPath;
  final VideoStreamService _videoService = VideoStreamService();
  final Record _recorder = Record();
  // final AIService _ai = AIService(); // Nicht mehr benötigt mit BitHuman
  StreamSubscription<Amplitude>? _ampSub;
  DateTime? _segmentStartAt;
  int _silenceMs = 0;
  bool _sttBusy = false;
  bool _segmentClosing = false;

  // VAD-ähnliche Parameter
  static const int _silenceThresholdDb = -40; // dBFS Schwelle
  static const int _silenceHoldMs = 800; // Stille-Dauer bis Segment-Ende
  static const int _minSegmentMs = 1200; // minimale Segmentlänge
  // VAD/Auto-Senden global abschalten – nur manuelles Stop sendet
  static const bool kAutoSend = false;

  // Verhindert mehrfaches automatisches Abspielen der Begrüßung
  bool _greetedOnce = false;

  /// Initialisiert BitHuman SDK
  Future<void> _initializeBitHuman() async {
    try {
      await dotenv.load();

      await BitHumanService.initialize();
      print('✅ BitHuman SDK initialisiert');
    } catch (e) {
      print('❌ BitHuman Initialisierung fehlgeschlagen: $e');
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

  Future<Map<String, String?>> _ensureFigure() async {
    String? figureId;
    String? modelHash;
    try {
      final bh = _avatarData?.training?['bithuman'] as Map<String, dynamic>?;
      figureId = (bh?['figureId'] as String?)?.trim();
      modelHash = (bh?['modelHash'] as String?)?.trim();
    } catch (_) {}

    if ((figureId != null && figureId.isNotEmpty) || _avatarData == null) {
      return {'figureId': figureId, 'modelHash': modelHash};
    }

    // Krone-Bild holen
    final imageUrl = _avatarData!.avatarImageUrl;
    if (imageUrl == null || imageUrl.isEmpty) {
      return {'figureId': null, 'modelHash': null};
    }
    final base = dotenv.env['BITHUMAN_BASE_URL']?.trim();
    if (base == null || base.isEmpty) {
      return {'figureId': null, 'modelHash': null};
    }
    final imgFile = await _downloadToTemp(imageUrl, suffix: '.png');
    if (imgFile == null) return {'figureId': null, 'modelHash': null};

    try {
      final uri = Uri.parse('$base/figure/create');
      final req = http.MultipartRequest('POST', uri);
      req.files.add(await http.MultipartFile.fromPath('image', imgFile.path));
      final res = await req.send();
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final body = await res.stream.bytesToString();
        final data = jsonDecode(body) as Map<String, dynamic>;
        figureId = (data['figure_id'] as String?)?.trim();
        modelHash = (data['runtime_model_hash'] as String?)?.trim();
        // Debug-Ausgabe & UI-Hinweis
        try {
          print(
            '🧩 BitHuman Figure erstellt: figureId=' +
                (figureId ?? 'null') +
                ', modelHash=' +
                (modelHash ?? 'null'),
          );
          _showSystemSnack(
            'BitHuman Figure: ' +
                (figureId ?? '—') +
                ' | Model: ' +
                (modelHash ?? '—'),
          );
        } catch (_) {}
        // Persistieren in Firestore unter users/<uid>/avatars/<id>
        try {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid != null) {
            final fs = FirebaseFirestore.instance;
            final docRef = fs
                .collection('users')
                .doc(uid)
                .collection('avatars')
                .doc(_avatarData!.id);
            final snap = await docRef.get();
            final existing = snap.data() ?? {};
            final training = Map<String, dynamic>.from(
              existing['training'] ?? {},
            );
            final bh = Map<String, dynamic>.from(training['bithuman'] ?? {});
            if ((figureId ?? '').isNotEmpty) bh['figureId'] = figureId;
            if ((modelHash ?? '').isNotEmpty) bh['modelHash'] = modelHash;
            training['bithuman'] = bh;
            await docRef.set({
              'training': training,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        } catch (_) {}
      }
    } catch (_) {}

    return {'figureId': figureId, 'modelHash': modelHash};
  }

  @override
  void initState() {
    super.initState();

    // BitHuman SDK initialisieren
    _initializeBitHuman();

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
    // Empfange AvatarData von der vorherigen Seite
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is AvatarData) {
        setState(() {
          _avatarData = args;
        });
        _loadPartnerName().then((_) async {
          // Prewarm Chat/CF Endpunkte für schnellere erste Antwort
          unawaited(_prewarmChatEndpoints());
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
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final backgroundImage = _avatarData?.avatarImageUrl;
    // BP: Wenn Krone‑Video vorhanden, KEIN Bild als Hintergrund zeigen –
    // stattdessen wird oben das Video‑Standbild eingeblendet.
    final tr = Map<String, dynamic>.from(_avatarData?.training ?? {});
    final provider = (tr['videoProvider'] as String?)?.toLowerCase();
    final isBP = provider == 'bp' || provider == 'beyond_presence';
    final bp = Map<String, dynamic>.from(tr['beyondPresence'] ?? {});
    final hasCrownVideo =
        ((bp['crownVideoUrl'] as String?)?.trim().isNotEmpty ?? false);
    final useBgDecoration = !_videoService.isReady && !(isBP && hasCrownVideo);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: useBgDecoration
            ? BoxDecoration(
                image: DecorationImage(
                  image: (backgroundImage != null && backgroundImage.isNotEmpty)
                      ? NetworkImage(backgroundImage)
                      : const AssetImage(
                              'assets/sunriza_complete/images/sunset1.jpg',
                            )
                            as ImageProvider,
                  fit: BoxFit.cover,
                ),
              )
            : null,
        child: SafeArea(
          child: Column(
            children: [
              // App Bar
              _buildAppBar(),

              // Avatar-Bild (bildschirmfüllend)
              Expanded(flex: 3, child: _buildAvatarImage()),

              // Chat-Nachrichten
              Expanded(flex: 2, child: _buildChatMessages()),

              // Input-Bereich
              _buildInputArea(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const SizedBox(width: 12),
          // Mini-Avatar in der AppBar ausgeblendet
          const SizedBox(width: 0),
          Expanded(
            child: Text(
              _avatarData?.displayName ?? 'Avatar Chat',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Settings-Icon entfernt
        ],
      ),
    );
  }

  Widget _buildAvatarImage() {
    final hasImage = _avatarData?.avatarImageUrl != null;
    final training = _avatarData?.training ?? {};
    final providerVal = (training['videoProvider'] as String?)?.toLowerCase();
    final isBP = providerVal == 'bp' || providerVal == 'beyond_presence';
    final crownVideoUrl = (training['beyondPresence'] is Map)
        ? ((training['beyondPresence']['crownVideoUrl'] as String?)?.trim())
        : null;

    return Container(
      width: double.infinity,
      decoration: null,
      child: Stack(
        children: [
          // BP: Krone-Video Standbild (wenn Player noch nicht aktiv)
          if (isBP && (crownVideoUrl ?? '').isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _videoService.isReady ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 150),
                  child: FutureBuilder<Uint8List?>(
                    future: _bpCrownThumb(crownVideoUrl!),
                    builder: (context, snap) {
                      if (snap.hasData && snap.data != null) {
                        return Image.memory(snap.data!, fit: BoxFit.cover);
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ),
          // Video-Overlay (zeigt sobald Player bereit ist, unabhängig vom Audio)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _videoService.isReady ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 120),
                child: StreamBuilder<VideoStreamState>(
                  stream: _videoService.stateStream,
                  builder: (context, snapshot) {
                    final controller = _videoService.controller;
                    if (controller == null || !controller.value.isInitialized) {
                      return const SizedBox.shrink();
                    }
                    final size = controller.value.size;
                    return FittedBox(
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: size.width == 0 ? 1920 : size.width,
                        height: size.height == 0 ? 1080 : size.height,
                        child: VideoPlayer(controller),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          // Avatar-Bild nur anzeigen wenn kein Background-Bild
          if (!hasImage)
            Center(
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Icon(
                    Icons.person,
                    size: 120,
                    color: Colors.deepPurple,
                  ),
                ),
              ),
            ),

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
        ],
      ),
    );
  }

  Future<Uint8List?> _bpCrownThumb(String url) async {
    try {
      final data = await vt.VideoThumbnail.thumbnailData(
        video: url,
        imageFormat: vt.ImageFormat.JPEG,
        maxWidth: 720,
        quality: 60,
      );
      return data;
    } catch (_) {
      return null;
    }
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
                label: Text(
                  _isLoadingMore
                      ? 'Lade ältere Nachrichten…'
                      : 'Ältere Nachrichten anzeigen',
                  style: const TextStyle(color: Colors.white70),
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        message.text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (!isUser)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.volume_up,
                          color: Colors.white70,
                          size: 18,
                        ),
                      ),
                  ],
                ),
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
    // macOS/iOS: kein eigener Pfad übergeben → Plugin erzeugt gültige File-URL
    await _recorder.start(encoder: AudioEncoder.wav, samplingRate: 16000);
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

      // Nur wenn voiceId verfügbar ist, starte Lipsync
      if (voiceId != null) {
        _startLipsync(text);
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

  // _uploadAudioToFirebase entfernt - nicht mehr benötigt mit BitHuman

  Future<String?> _ensureTtsForText(String text) async {
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

  Future<void> _startLipsync(String text) async {
    try {
      // Generiere TTS Audio zuerst
      final audioPath = await _ensureTtsForText(text);
      if (audioPath == null) return;

      // Referenzen aus Avatar (Bild optional für Fallback)
      final imageUrl = _avatarData?.avatarImageUrl ?? '';

      // Provider-Weiche (training.videoProvider)
      final training = _avatarData?.training ?? {};
      final providerVal = (training['videoProvider'] as String?)
          ?.trim()
          .toLowerCase();
      final useBP =
          providerVal == 'bp' ||
          providerVal == 'beyond_presence' ||
          (dotenv.env['BP_PRIMARY'] == '1');

      if (useBP) {
        // avatarId ist Pflicht für BP
        final bpMap = Map<String, dynamic>.from(
          training['beyondPresence'] ?? {},
        );
        final avatarId = (bpMap['avatarId'] as String?)?.trim();
        final crownVideoUrl = (bpMap['crownVideoUrl'] as String?)?.trim();
        if ((avatarId ?? '').isEmpty) {
          _showSystemSnack(
            'Bitte Avatar generieren (Krone‑Video zu BP hochladen)',
          );
          return;
        }
        // Beyond Presence: Direkt gegen BP API
        final rawBase = (dotenv.env['BP_API_BASE_URL'] ?? '').trim();
        final apiKey = (dotenv.env['BP_API_KEY'] ?? '').trim();
        if (rawBase.isEmpty || apiKey.isEmpty) {
          _showSystemSnack('BP_API_BASE_URL/BP_API_KEY fehlt (.env)');
          return;
        }
        final String bpBase = rawBase.endsWith('/v1') ? rawBase : '$rawBase/v1';
        final uri = Uri.parse('$bpBase/speech-to-video');
        final req = http.MultipartRequest('POST', uri)
          ..headers.addAll({
            'Authorization': 'Bearer $apiKey',
            'X-API-Key': apiKey,
          });
        req.files.add(await http.MultipartFile.fromPath('audio', audioPath));
        req.fields['avatarId'] = avatarId!;
        if (imageUrl.isNotEmpty) {
          req.fields['avatarImageUrl'] = imageUrl;
        }
        if (crownVideoUrl != null && crownVideoUrl.isNotEmpty) {
          req.fields['avatarVideoUrl'] = crownVideoUrl;
        }
        final streamed = await req.send();
        if (streamed.statusCode >= 200 && streamed.statusCode < 300) {
          final bytes = await streamed.stream.toBytes();
          final dir = await getTemporaryDirectory();
          final out = File(
            '${dir.path}/bp_${DateTime.now().millisecondsSinceEpoch}.mp4',
          );
          await out.writeAsBytes(bytes, flush: true);
          await _videoService.startStreamingFromUrl(out.path);
        } else {
          final body = await streamed.stream.bytesToString();
          _showSystemSnack(
            'BP speech-to-video fehlgeschlagen: ${streamed.statusCode} ${body.isNotEmpty ? body : ''}',
          );
        }
        return;
      }

      // BitHuman: Figure sicherstellen
      final fig = await _ensureFigure();
      final figureId = fig['figureId'];
      final modelHash = fig['modelHash'];

      final base = dotenv.env['BITHUMAN_BASE_URL']?.trim();
      if (base == null || base.isEmpty) return;

      if (imageUrl.isEmpty) return;
      final imgFile = await _downloadToTemp(imageUrl, suffix: '.png');
      if (imgFile == null) return;

      // Backend-Request: generate-avatar
      final uri = Uri.parse('$base/generate-avatar');
      final req = http.MultipartRequest('POST', uri);
      req.files.add(await http.MultipartFile.fromPath('image', imgFile.path));
      req.files.add(await http.MultipartFile.fromPath('audio', audioPath));
      if ((figureId ?? '').isNotEmpty) req.fields['figure_id'] = figureId!;
      if ((modelHash ?? '').isNotEmpty) {
        req.fields['runtime_model_hash'] = modelHash!;
      }
      final streamed = await req.send();
      if (streamed.statusCode >= 200 && streamed.statusCode < 300) {
        final bytes = await streamed.stream.toBytes();
        final dir = await getTemporaryDirectory();
        final out = File(
          '${dir.path}/chat_avatar_${DateTime.now().millisecondsSinceEpoch}.mp4',
        );
        await out.writeAsBytes(bytes, flush: true);

        // 1) Sofort lokal abspielen (ohne Upload-Wartezeit)
        try {
          await _videoService.startStreamingFromUrl(
            out.path,
            onProgress: (msg) => print('📊 BitHuman Local Progress: $msg'),
            onError: (err) => print('❌ BitHuman Local Error: $err'),
          );
        } catch (e) {
          print('⚠️ Lokale Videowiedergabe fehlgeschlagen: $e');
        }

        // Kein Upload für Chat-Antworten – nur lokale Wiedergabe
      } else {
        final body = await streamed.stream.bytesToString();
        print('❌ BitHuman generate-avatar: ${streamed.statusCode} $body');
      }
    } catch (e) {
      print('💥 BITHUMAN LIPSYNC FEHLER: $e');
      // Ignorieren – TTS läuft als Fallback weiter
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
      // Hedge/Race: Primär sofort, CF nach 1.5s parallel; nimm erste valide Antwort
      final completer = Completer<Map<String, dynamic>?>();
      bool done = false;

      Future<Map<String, dynamic>?> primary() async {
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
              }),
            )
            .timeout(const Duration(seconds: 4));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          return jsonDecode(res.body) as Map<String, dynamic>;
        }
        return null;
      }

      Future<Map<String, dynamic>?> cf() async {
        try {
          final cfUri = Uri.parse(
            'https://us-central1-sunriza26.cloudfunctions.net/generateAvatarResponse',
          );
          final res = await http
              .post(
                cfUri,
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'userId': uid,
                  'query': userText,
                  'maxTokens': 180,
                  'temperature': 0.6,
                }),
              )
              .timeout(const Duration(seconds: 6));
          if (res.statusCode >= 200 && res.statusCode < 300) {
            final m = jsonDecode(res.body) as Map<String, dynamic>;
            return {'answer': (m['response'] as String?)?.trim()};
          }
        } catch (_) {}
        return null;
      }

      void tryComplete(Map<String, dynamic>? data) {
        if (done) return;
        final ans = (data?['answer'] as String?)?.trim();
        if (ans != null && ans.isNotEmpty) {
          done = true;
          completer.complete(data);
        }
      }

      // Beide sofort starten; erste gültige Antwort gewinnt
      primary().then(tryComplete).catchError((_) {});
      cf().then(tryComplete).catchError((_) {});

      final first = await completer.future.timeout(
        const Duration(seconds: 7),
        onTimeout: () => null,
      );

      if (first == null) {
        // Nichts brauchbares → klassischer Fallback
        await _chatViaFunctions(userText);
      } else {
        final answer = (first['answer'] as String?)?.trim();
        if (answer != null && answer.isNotEmpty) {
          _addMessage(answer, false);
          // TTS: benutze falls vorhanden, sonst on-demand
          final tts = first['tts_audio_b64'] as String?;
          if (tts != null && tts.isNotEmpty) {
            try {
              final bytes = base64Decode(tts);
              final dir = await getTemporaryDirectory();
              final file = File(
                '${dir.path}/avatar_tts_${DateTime.now().millisecondsSinceEpoch}.mp3',
              );
              await file.writeAsBytes(bytes, flush: true);
              _lastRecordingPath = file.path;
              unawaited(_playAudioAtPath(file.path));
            } catch (_) {}
          } else {
            // Erzeuge TTS schnell über Memory‑API
            unawaited(() async {
              try {
                final baseTts = EnvService.memoryApiBaseUrl();
                if (baseTts.isEmpty) return;
                final ttsUri = Uri.parse('$baseTts/avatar/tts');
                final tRes = await http
                    .post(
                      ttsUri,
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({
                        'text': answer,
                        'voice_id': (voiceId is String && voiceId.isNotEmpty)
                            ? voiceId
                            : null,
                      }),
                    )
                    .timeout(const Duration(seconds: 8));
                if (tRes.statusCode >= 200 && tRes.statusCode < 300) {
                  final Map<String, dynamic> j =
                      jsonDecode(tRes.body) as Map<String, dynamic>;
                  final String? b64 = j['audio_b64'] as String?;
                  if (b64 != null && b64.isNotEmpty) {
                    final bytes = base64Decode(b64);
                    final dir = await getTemporaryDirectory();
                    final file = File(
                      '${dir.path}/avatar_tts_${DateTime.now().millisecondsSinceEpoch}.mp3',
                    );
                    await file.writeAsBytes(bytes, flush: true);
                    unawaited(_playAudioAtPath(file.path));
                  }
                }
              } catch (_) {}
            }());
          }
          // Lipsync parallel
          unawaited(_startLipsync(answer));
        }
      }
    } catch (e) {
      // Fallback zu Cloud Function bei Socket-/HTTP-Fehlern
      await _chatViaFunctions(userText);
    } finally {
      if (mounted) setState(() => _isTyping = false);
    }
  }

  Future<void> _prewarmChatEndpoints() async {
    try {
      final base = EnvService.memoryApiBaseUrl();
      if (base.isNotEmpty) {
        final uri = Uri.parse('$base/healthz');
        unawaited(http.get(uri).timeout(const Duration(seconds: 3)));
      }
      unawaited(
        http
            .get(
              Uri.parse(
                'https://us-central1-sunriza26.cloudfunctions.net/generateAvatarResponse',
              ),
            )
            .timeout(const Duration(seconds: 3))
            .then((resp) => resp)
            .catchError((err) => err),
      );
    } catch (_) {}
  }

  Future<void> _chatViaFunctions(String userText) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSystemSnack('Nicht angemeldet');
        return;
      }
      final uid = user.uid;
      final uri = Uri.parse(
        'https://us-central1-sunriza26.cloudfunctions.net/generateAvatarResponse',
      );
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': uid,
          'query': userText,
          'maxTokens': 180,
          'temperature': 0.6,
        }),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final answer = (data['response'] as String?)?.trim();
        if (answer != null && answer.isNotEmpty) {
          // TTS über Cloud Function tts
          String? path;
          try {
            final baseTts = EnvService.memoryApiBaseUrl();
            if (baseTts.isEmpty) return;
            final ttsUri = Uri.parse('$baseTts/avatar/tts');
            final String? voiceId = (_avatarData?.training != null)
                ? (_avatarData?.training?['voice'] != null
                      ? (_avatarData?.training?['voice']?['elevenVoiceId']
                            as String?)
                      : null)
                : null;
            if (voiceId == null) {
              _showSystemSnack('Keine geklonte Stimme verfügbar');
              return;
            }
            final ttsRes = await http
                .post(
                  ttsUri,
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({'text': answer, 'voice_id': voiceId}),
                )
                .timeout(const Duration(seconds: 8));
            if (ttsRes.statusCode >= 200 && ttsRes.statusCode < 300) {
              final Map<String, dynamic> j =
                  jsonDecode(ttsRes.body) as Map<String, dynamic>;
              final String? b64 = j['audio_b64'] as String?;
              if (b64 != null && b64.isNotEmpty) {
                final bytes = base64Decode(b64);
                final dir = await getTemporaryDirectory();
                final file = File(
                  '${dir.path}/avatar_tts_fallback_${DateTime.now().millisecondsSinceEpoch}.mp3',
                );
                await file.writeAsBytes(bytes, flush: true);
                path = file.path;
              }
            }
          } catch (_) {}
          _addMessage(answer, false, audioPath: path);
          if (path != null) await _playAudioAtPath(path);
        }
      } else {
        _showSystemSnack('Chat-Fehler: ${res.statusCode} (CF)');
      }
    } catch (e) {
      _showSystemSnack('Chat-Fehler (CF): $e');
    }
  }

  // Future<void> _recordVoice() async {}

  // Future<void> _stopAndSave() async {}

  // _playLastRecording entfernt – direkte Wiedergabe über _playAudioAtPath

  Future<void> _playAudioAtPath(String path) async {
    try {
      await _player.setFilePath(path);
      await _player.play();
    } catch (e) {
      _showSystemSnack('Wiedergabefehler: $e');
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
      'Klingst nach $first – bist Du’s?$roleTail',
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
    _videoService.dispose();
    _playerStateSub?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
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
