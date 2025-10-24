import 'package:flutter/material.dart';
import '../../screens/avatar_chat_screen.dart';
import '../hero_chat_icon_picker.dart';

/// Avatar Message Bubble (Links, WhatsApp-Style)
class AvatarMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final Function(ChatMessage, String?) onIconChanged;
  final String? avatarImageUrl;
  
  const AvatarMessageBubble({
    super.key,
    required this.message,
    required this.onIconChanged,
    this.avatarImageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => _showIconPicker(context),
      child: Padding(
        padding: const EdgeInsets.only(
          left: 8,
          right: 64,
          bottom: 4,
        ),
        child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Message Container
                  Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A3E),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(18),
                        topRight: Radius.circular(18),
                        bottomLeft: Radius.circular(4),
                        bottomRight: Radius.circular(18),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Delete Timer (wenn aktiv)
                        if (message.deleteTimerStart != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: _buildDeleteTimer(),
                          ),
                        
                        // Message Text
                        Text(
                          message.text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            height: 1.4,
                          ),
                        ),
                        
                        // Timestamp (klein, rechts unten)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _formatTime(message.timestamp),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Highlight Icon (unter der Blase)
                  if (message.highlightIcon != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, left: 4),
                      child: Text(
                        message.highlightIcon!,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                ],
        ),
      ),
    );
  }

  Widget _buildDeleteTimer() {
    final remainingSeconds = message.remainingDeleteSeconds ?? 0;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.timer, color: Colors.white, size: 11),
              const SizedBox(width: 3),
              Text(
                '${remainingSeconds}s',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  void _showIconPicker(BuildContext context) {
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    
    // Box OBERHALB der Blase positionieren (mit 8px Abstand)
    final boxY = position.dy - 120; // 120px = ca. Höhe der Icon-Box
    
    // Falls zu nah am oberen Rand, nach unten verschieben
    final finalY = boxY < 100 ? position.dy + 60 : boxY;

    HeroChatIconPicker.showAtPosition(
      context,
      position: Offset(position.dx, finalY),
      alignRight: false,
      selectedIcon: message.highlightIcon,
      onIconSelected: (icon) => onIconChanged(message, icon),
      onRemove: () => onIconChanged(message, null),
    );
  }
}

