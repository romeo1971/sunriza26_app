import 'package:flutter/material.dart';
import '../../screens/avatar_chat_screen.dart';
import '../hero_chat_icon_picker.dart';

/// User Message Bubble (Rechts, WhatsApp-Style)
class UserMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final Function(ChatMessage, String?) onIconChanged;
  final Function(ChatMessage)? onDelete;

  const UserMessageBubble({
    super.key,
    required this.message,
    required this.onIconChanged,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => _showIconPicker(context),
      child: Padding(
        padding: const EdgeInsets.only(
          left: 64,
          right: 8,
          bottom: 4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Message Container (White + GMBC gradient 0.2 opacity)
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFFFD5F4), // White + 20% Magenta
                    Color(0xFFE8F0FE), // White + 20% LightBlue
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Message Text
                  Padding(
                    padding: const EdgeInsets.only(right: 50),
                    child: Text(
                      message.text,
                      style: const TextStyle(
                        color: Color(0xFF2E2E2E), // dark grey
                        fontSize: 14.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                  
                  // Timestamp (rechts unten, halbe Höhe letzte Zeile)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Text(
                      _formatTime(message.timestamp),
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.4),
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Highlight Icon (unter der Blase)
            if (message.highlightIcon != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 4),
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


  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showIconPicker(BuildContext context) {
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    HeroChatIconPicker.showCentered(
      context,
      alignRight: true,
      selectedIcon: message.highlightIcon,
      onIconSelected: (icon) => onIconChanged(message, icon),
      onRemove: () => onIconChanged(message, null),
      onDelete: onDelete != null ? () => onDelete!(message) : null,
    );
  }
}

