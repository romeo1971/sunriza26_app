import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/avatar_data.dart';

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

  AvatarData? _avatarData;
  // Aufnahme temporär deaktiviert
  // final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  String? _lastRecordingPath;

  @override
  void initState() {
    super.initState();
    // Empfange AvatarData von der vorherigen Seite
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is AvatarData) {
        setState(() {
          _avatarData = args;
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
        decoration: backgroundImage != null
            ? BoxDecoration(
                image: DecorationImage(
                  image: NetworkImage(backgroundImage),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    Colors.black.withOpacity(0.7),
                    BlendMode.darken,
                  ),
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
            color: Colors.black.withOpacity(0.3),
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
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
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
          // Avatar-Bild
          Center(
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: _avatarData?.avatarImageUrl != null
                  ? ClipOval(
                      child: Image.network(
                        _avatarData!.avatarImageUrl!,
                        width: 200,
                        height: 200,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const CircleAvatar(
                              backgroundColor: Colors.white,
                              child: Icon(
                                Icons.person,
                                size: 120,
                                color: Colors.deepPurple,
                              ),
                            ),
                      ),
                    )
                  : const CircleAvatar(
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
                    color: Colors.black.withOpacity(0.7),
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
        ],
      ),
    );
  }

  Widget _buildChatMessages() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0x20000000),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // Nachrichten-Liste
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: (_messages.length >= 2) ? 2 : _messages.length,
                    itemBuilder: (context, index) {
                      final startIndex = (_messages.length >= 2)
                          ? _messages.length - 2
                          : 0;
                      return _buildMessageBubble(_messages[startIndex + index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.white70),
          const SizedBox(height: 16),
          Text(
            'Starte eine Unterhaltung',
            style: TextStyle(
              fontSize: 18,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Schreibe eine Nachricht oder nutze das Mikrofon',
            style: TextStyle(fontSize: 14, color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? Colors.deepPurple : Colors.grey.shade800,
                borderRadius: BorderRadius.circular(20),
              ),
              child: GestureDetector(
                onTap: () {
                  if (message.text.startsWith('🎤')) {
                    _playLastRecording();
                  }
                },
                child: Text(
                  message.text,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
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
                        .withOpacity(0.3),
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
                border: Border.all(color: Colors.white.withOpacity(0.5)),
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
                    color: Colors.deepPurple.withOpacity(0.3),
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

  void _sendMessage() {
    if (_messageController.text.trim().isNotEmpty) {
      _addMessage(_messageController.text.trim(), true);
      _messageController.clear();
      _simulateAvatarResponse();
    }
  }

  void _addMessage(String text, bool isUser) {
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: isUser));
    });
    _scrollToBottom();
  }

  void _simulateAvatarResponse() {
    if (!mounted) return;
    setState(() {
      _isTyping = true;
    });

    // Simulate thinking time
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _isTyping = false;
        _addMessage(
          'Das ist eine interessante Nachricht! Erzähl mir mehr darüber.',
          false,
        );
      });
    });
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

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person, color: Colors.deepPurple),
              title: const Text(
                'Avatar bearbeiten',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                // TODO: Navigate to avatar edit
              },
            ),
            ListTile(
              leading: const Icon(Icons.history, color: Colors.deepPurple),
              title: const Text(
                'Chat-Verlauf',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                // TODO: Show chat history
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings, color: Colors.deepPurple),
              title: const Text(
                'Einstellungen',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                // TODO: Show settings
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
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

  ChatMessage({required this.text, required this.isUser, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();
}
