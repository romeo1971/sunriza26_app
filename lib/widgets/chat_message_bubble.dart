import 'package:flutter/material.dart';
import '../screens/avatar_chat_screen.dart';
import '../widgets/hero_chat_icon_picker.dart';

/// Chat Message Bubble mit Tap-Handler für Icon-Auswahl
class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final Function(ChatMessage, String?) onIconChanged; // null = remove
  
  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.onIconChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showIconPicker(context),
      child: Container(
        margin: EdgeInsets.only(
          left: message.isUser ? 60 : 12,
          right: message.isUser ? 12 : 60,
          bottom: 12,
        ),
        child: Column(
          crossAxisAlignment: message.isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            // Message Bubble
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: message.isUser
                    ? const LinearGradient(
                        colors: [Color(0xFF6B4CE6), Color(0xFF9B6CE6)],
                      )
                    : const LinearGradient(
                        colors: [Color(0xFF2A2A3E), Color(0xFF3A3A4E)],
                      ),
                borderRadius: BorderRadius.circular(16),
                border: message.isHighlighted
                    ? Border.all(
                        color: Colors.white.withValues(alpha: 0.5),
                        width: 2,
                      )
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Delete Timer (oben rechts/links klein)
                  if (message.deleteTimerStart != null)
                    _buildDeleteTimer(),
                  
                  // Message Text
                  Text(
                    message.text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            
            // Highlight Icon (klein, unter der Blase)
            if (message.highlightIcon != null)
              Padding(
                padding: EdgeInsets.only(
                  top: 4,
                  left: message.isUser ? 0 : 8,
                  right: message.isUser ? 8 : 0,
                ),
                child: Text(
                  message.highlightIcon!,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeleteTimer() {
    final remainingSeconds = message.remainingDeleteSeconds ?? 0;
    final isUser = message.isUser;
    
    return Container(
      margin: EdgeInsets.only(
        bottom: 6,
        left: isUser ? 0 : 0,
        right: isUser ? 0 : 0,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer, color: Colors.red, size: 12),
          const SizedBox(width: 4),
          Text(
            '${remainingSeconds}s',
            style: const TextStyle(
              color: Colors.red,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void _showIconPicker(BuildContext context) {
    // Finde die Position der Blase für den Dialog
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    // Dialog AN der Blase positionieren
    final dialogPosition = Offset(
      message.isUser ? position.dx + size.width : position.dx,
      position.dy + size.height + 8, // 8px unter der Blase
    );

    HeroChatIconPicker.showAtPosition(
      context,
      position: dialogPosition,
      alignRight: message.isUser,
      selectedIcon: message.highlightIcon,
      onIconSelected: (icon) {
        onIconChanged(message, icon);
      },
      onRemove: () {
        onIconChanged(message, null);
      },
    );
  }
}

