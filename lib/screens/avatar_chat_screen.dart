import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import '../models/avatar_data.dart';
import '../services/video_stream_service.dart';
import '../services/bithuman_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AvatarChatScreen extends StatefulWidget {
  const AvatarChatScreen({super.key});

  @override
  State<AvatarChatScreen> createState() => _AvatarChatScreenState();
}

class _AvatarChatScreenState extends State<AvatarChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final bool _isRecording = false;
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
  // final AIService _ai = AIService(); // Nicht mehr benötigt mit BitHuman

  /// Initialisiert BitHuman SDK
  Future<void> _initializeBitHuman() async {
    try {
      await dotenv.load();
      final apiKey = dotenv.env['BITHUMAN_API_KEY'] ?? 'demo_key';

      await BitHumanService.initialize();
      print('✅ BitHuman SDK initialisiert');
    } catch (e) {
      print('❌ BitHuman Initialisierung fehlgeschlagen: $e');
    }
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
        _loadPartnerName().then((_) {
          _loadHistory().then((_) {
            if (_messages.isEmpty) {
              if ((_partnerName ?? '').isNotEmpty) {
                _botSay(_friendlyGreet(_partnerName ?? ''));
              } else {
                _botSay(
                  'Hallo, schön, dass Du vorbeischaust. Magst Du mir Deinen Namen verraten?',
                );
              }
            }
          });
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final backgroundImage = _avatarData?.avatarImageUrl;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration:
            (backgroundImage != null && !(_videoService.isReady && _isSpeaking))
            ? BoxDecoration(
                image: DecorationImage(
                  image: NetworkImage(backgroundImage),
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
        color: Colors.deepPurple,
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

    return Container(
      width: double.infinity,
      decoration: hasImage
          ? null
          : BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.deepPurple.shade800,
                  Colors.deepPurple.shade900,
                  Colors.black,
                ],
              ),
            ),
      child: Stack(
        children: [
          // Video-Overlay (nur wenn Audio spielt und Video bereit ist)
          if (_isSpeaking)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _videoService.isReady ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 120),
                  child: StreamBuilder<VideoStreamState>(
                    stream: _videoService.stateStream,
                    builder: (context, snapshot) {
                      final controller = _videoService.controller;
                      if (controller == null) return const SizedBox.shrink();
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

          // Video-Overlay (Lipsync) — einmalig und ganz oben
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _videoService.isReady ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: StreamBuilder<VideoStreamState>(
                  stream: _videoService.stateStream,
                  builder: (context, snapshot) {
                    final controller = _videoService.controller;
                    if (controller == null) return const SizedBox.shrink();
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
                color: isUser ? Colors.deepPurple : Colors.grey.shade800,
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0x20000000),
        border: Border(top: BorderSide(color: Color(0x40FFFFFF))),
      ),
      child: Row(
        children: [
          // Mikrofon-Button
          GestureDetector(
            // Aufnahme deaktiviert: Buttons ohne Aktion
            onTap: () {
              _showSystemSnack('Sprachaufnahme vorübergehend deaktiviert');
            },
            onLongPressStart: (_) {},
            onLongPressEnd: (_) {},
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: _isRecording ? Colors.red : Colors.deepPurple,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (_isRecording ? Colors.red : Colors.deepPurple)
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
                border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
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
                color: Colors.deepPurple,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurple.withValues(alpha: 0.3),
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
    );
  }

  // void _toggleRecording() {}

  // void _startRecording() {}

  // void _stopRecording() {}

  void _sendMessage() async {
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
      final String? voiceId = (_avatarData?.training != null)
          ? (_avatarData?.training?['voice'] != null
                ? (_avatarData?.training?['voice']?['elevenVoiceId'] as String?)
                : null)
          : null;

      // Nur wenn voiceId verfügbar ist, starte Lipsync
      if (voiceId != null) {
        _startLipsync(text);
      }

      final uri = Uri.parse(
        'https://us-central1-sunriza26.cloudfunctions.net/tts',
      );
      final payload = <String, dynamic>{'text': text};
      // Immer die geklonte Stimme verwenden
      if (voiceId != null) {
        payload['voiceId'] = voiceId;
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
      if (stability != null) payload['stability'] = stability;
      if (similarity != null) payload['similarity'] = similarity;
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (res.statusCode >= 200 &&
          res.statusCode < 300 &&
          res.bodyBytes.isNotEmpty) {
        final dir = await getTemporaryDirectory();
        final file = File(
          '${dir.path}/bot_local_tts_${DateTime.now().millisecondsSinceEpoch}.mp3',
        );
        await file.writeAsBytes(res.bodyBytes, flush: true);
        path = file.path;
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
      final uri = Uri.parse(
        'https://us-central1-sunriza26.cloudfunctions.net/tts',
      );
      final String? voiceId = (_avatarData?.training != null)
          ? (_avatarData?.training?['voice'] != null
                ? (_avatarData?.training?['voice']?['elevenVoiceId'] as String?)
                : null)
          : null;
      final payload = <String, dynamic>{'text': text};
      // Immer die geklonte Stimme verwenden
      if (voiceId != null) {
        payload['voiceId'] = voiceId;
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
      if (res.statusCode >= 200 &&
          res.statusCode < 300 &&
          res.bodyBytes.isNotEmpty) {
        final dir = await getTemporaryDirectory();
        final file = File(
          '${dir.path}/tts_on_demand_${DateTime.now().millisecondsSinceEpoch}.mp3',
        );
        await file.writeAsBytes(res.bodyBytes, flush: true);
        return file.path;
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

  Future<void> _startLipsync(String text) async {
    try {
      // Generiere TTS Audio zuerst
      final audioPath = await _ensureTtsForText(text);
      if (audioPath == null) return;

      // Hole Crown Image URL (avatarImageUrl ist das Crown-Bild)
      final imageUrl = _avatarData?.avatarImageUrl;
      if (imageUrl == null) return;

      print('🎬 STARTE BITHUMAN LIPSYNC:');
      print('📝 Text: $text');
      print('🖼️ Image: $imageUrl');
      print('🎵 Audio: $audioPath');

      // BitHuman SDK verwenden
      final videoUrl = await BitHumanService.createAvatarWithAudio(
        imagePath: imageUrl,
        audioPath: audioPath,
      );

      if (videoUrl != null) {
        print('🎥 BitHuman Video erhalten: $videoUrl');
        await _videoService.startStreamingFromUrl(
          videoUrl,
          onProgress: (msg) => print('📊 BitHuman Progress: $msg'),
          onError: (err) => print('❌ BitHuman Error: $err'),
        );
      } else {
        print('❌ BitHuman Video-Generierung fehlgeschlagen');
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
      final uri = Uri.parse('${dotenv.env['MEMORY_API_BASE_URL']}/avatar/chat');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': uid,
          'avatar_id': _avatarData?.id ?? '',
          'message': userText,
          'top_k': 5,
          'voice_id': _avatarData?.training != null
              ? (_avatarData?.training?['voice'] != null
                    ? (_avatarData?.training?['voice']?['elevenVoiceId'])
                    : null)
              : null,
          'avatar_name': _avatarData?.displayName,
        }),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final answer = (data['answer'] as String?)?.trim();
        String? audioPath;
        final tts = data['tts_audio_b64'] as String?;
        if (tts != null && tts.isNotEmpty) {
          final bytes = base64Decode(tts);
          final dir = await getTemporaryDirectory();
          final file = File(
            '${dir.path}/avatar_tts_${DateTime.now().millisecondsSinceEpoch}.mp3',
          );
          await file.writeAsBytes(bytes, flush: true);
          _lastRecordingPath = file.path;
          audioPath = file.path;
          await _playLastRecording();
        }
        if (answer != null && answer.isNotEmpty) {
          _addMessage(answer, false, audioPath: audioPath);
        }
      } else {
        // Fallback zu Cloud Function
        await _chatViaFunctions(userText);
      }
    } catch (e) {
      // Fallback zu Cloud Function bei Socket-/HTTP-Fehlern
      await _chatViaFunctions(userText);
    } finally {
      if (mounted) setState(() => _isTyping = false);
    }
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
            final ttsUri = Uri.parse(
              'https://us-central1-sunriza26.cloudfunctions.net/tts',
            );
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
            final ttsRes = await http.post(
              ttsUri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'text': answer, 'voiceId': voiceId}),
            );
            if (ttsRes.statusCode >= 200 &&
                ttsRes.statusCode < 300 &&
                ttsRes.bodyBytes.isNotEmpty) {
              final dir = await getTemporaryDirectory();
              final file = File(
                '${dir.path}/avatar_tts_fallback_${DateTime.now().millisecondsSinceEpoch}.mp3',
              );
              await file.writeAsBytes(ttsRes.bodyBytes, flush: true);
              path = file.path;
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

  Future<void> _playLastRecording() async {
    if (_lastRecordingPath == null) return;
    try {
      await _player.setFilePath(_lastRecordingPath!);
      await _player.play();
    } catch (e) {
      _showSystemSnack('Wiedergabefehler: $e');
    }
  }

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

  Future<void> _savePartnerRole(String role) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || _avatarData == null) return;
      final fs = FirebaseFirestore.instance;
      await fs
          .collection('users')
          .doc(uid)
          .collection('avatars')
          .doc(_avatarData?.id ?? '')
          .set({
            'partnerRole': role,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      await fs
          .collection('users')
          .doc(uid)
          .collection('profile')
          .doc('global')
          .set({
            'partnerRole': role,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      await _saveInsight(
        'Beziehungsrolle: $role',
        source: 'profile',
        fileName: 'relationship.txt',
      );
    } catch (_) {}
  }

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
      final uri = Uri.parse(
        '${dotenv.env['MEMORY_API_BASE_URL']}/avatar/memory/insert',
      );
      final payload = {
        'user_id': uid,
        'avatar_id': _avatarData?.id ?? '',
        'full_text': fullText,
        'source': source,
        if (fileName != null) 'file_name': fileName,
      };
      await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
    } catch (_) {}
  }

  Future<void> _maybeConfirmGlobalInsight(String text) async {
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Darf ich mir das merken?'),
        content: const Text(
          'Soll ich diese Information dauerhaft für den Avatar speichern (für alle künftigen Gespräche)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Nein'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ja, speichern'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _saveInsight(
        text,
        source: 'insight_global',
        fileName: 'global_insights.txt',
      );
    }
  }

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
