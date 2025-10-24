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
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2C34), // WhatsApp Dark Background
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                        bottomLeft: Radius.circular(2),
                        bottomRight: Radius.circular(8),
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
                        // Message Text
                        Text(
                          message.text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            height: 1.35,
                          ),
                        ),
                        
                        const SizedBox(height: 4),
                        
                        // Bottom Row: Delete (links) + Zeit (rechts)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Delete Button (klein, links)
                            GestureDetector(
                              onTap: () => _showDeleteConfirm(context),
                              child: Icon(
                                Icons.close,
                                size: 10,
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                            
                            // Timestamp (rechts)
                            Text(
                              _formatTime(message.timestamp),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 10,
                              ),
                            ),
                          ],
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

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _showDeleteConfirm(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0A),
        title: const Text('Nachricht löschen?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Diese Nachricht wird dauerhaft gelöscht.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      onIconChanged(message, null); // Entfernt auch Highlight
      // TODO: Firebase Message löschen
    }
  }

  void _showIconPicker(BuildContext context) {
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    HeroChatIconPicker.showCentered(
      context,
      alignRight: false,
      selectedIcon: message.highlightIcon,
      onIconSelected: (icon) => onIconChanged(message, icon),
      onRemove: () => onIconChanged(message, null),
    );
  }
}

