import 'package:flutter/material.dart';
import '../screens/avatar_chat_screen.dart';
import '../models/avatar_data.dart';

/// Hero Chat Screen - Zeigt nur highlighted Nachrichten
/// Background: Hero Image
/// Filter: Icons (colored/greyscale)
class HeroChatScreen extends StatefulWidget {
  final AvatarData avatarData;
  final List<ChatMessage> messages;
  final Function(ChatMessage, String?) onIconChanged; // null = remove
  
  const HeroChatScreen({
    super.key,
    required this.avatarData,
    required this.messages,
    required this.onIconChanged,
  });

  @override
  State<HeroChatScreen> createState() => _HeroChatScreenState();
}

class _HeroChatScreenState extends State<HeroChatScreen> {
  final Set<String> _activeFilters = {}; // Icons die aktiv sind (colored)
  bool _showAllIcons = true; // Alle anzeigen oder nur gefilterte

  @override
  void initState() {
    super.initState();
    // Initial: Alle Icons aktiv
    _initializeFilters();
  }

  void _initializeFilters() {
    final Set<String> allIcons = {};
    for (final msg in widget.messages) {
      if (msg.highlightIcon != null) {
        allIcons.add(msg.highlightIcon!);
      }
    }
    setState(() {
      _activeFilters.addAll(allIcons);
    });
  }

  List<ChatMessage> get _filteredMessages {
    if (_showAllIcons) {
      return widget.messages.where((m) => m.isHighlighted).toList();
    }
    return widget.messages
        .where((m) => m.highlightIcon != null && _activeFilters.contains(m.highlightIcon!))
        .toList();
  }

  List<String> get _allUsedIcons {
    final Set<String> icons = {};
    for (final msg in widget.messages) {
      if (msg.highlightIcon != null) {
        icons.add(msg.highlightIcon!);
      }
    }
    return icons.toList();
  }

  @override
  Widget build(BuildContext context) {
    final heroImageUrl = widget.avatarData.avatarImageUrl;
    
    return Scaffold(
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          // Wischen nach links = zurück
          if (details.primaryVelocity != null && details.primaryVelocity! < -500) {
            Navigator.pop(context);
          }
        },
        child: Stack(
          children: [
            // Background: Hero Image
            if (heroImageUrl != null && heroImageUrl.isNotEmpty)
              Positioned.fill(
                child: Image.network(
                  heroImageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: Colors.black),
                ),
              ),
            
            // Dark Overlay für bessere Lesbarkeit
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.6),
              ),
            ),

            // Content
            SafeArea(
              child: Column(
                children: [
                  // Header mit Icon-Filtern
                  _buildHeader(),
                  
                  // Messages
                  Expanded(
                    child: _filteredMessages.isEmpty
                        ? _buildEmptyState()
                        : _buildMessageList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Title + Close
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.arrow_back, color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Hero Chat',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '${_filteredMessages.length} Highlights',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Icon Filters
          _buildIconFilters(),
        ],
      ),
    );
  }

  Widget _buildIconFilters() {
    final usedIcons = _allUsedIcons;
    
    if (usedIcons.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // All Toggle
        Row(
          children: [
            Text(
              'Filter:',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                setState(() {
                  _showAllIcons = !_showAllIcons;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _showAllIcons
                      ? Colors.white.withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _showAllIcons
                        ? Colors.white.withValues(alpha: 0.8)
                        : Colors.white.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _showAllIcons ? 'Alle' : 'Gefiltert',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 8),
        
        // Icon Toggles
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: usedIcons.map((icon) => _buildIconToggle(icon)).toList(),
        ),
      ],
    );
  }

  Widget _buildIconToggle(String icon) {
    final isActive = _activeFilters.contains(icon);
    final count = widget.messages.where((m) => m.highlightIcon == icon).length;

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isActive) {
            _activeFilters.remove(icon);
            _showAllIcons = false;
          } else {
            _activeFilters.add(icon);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive
                ? Colors.white.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon (colored wenn aktiv, greyscale wenn nicht)
            Opacity(
              opacity: isActive ? 1.0 : 0.3,
              child: Text(
                icon,
                style: TextStyle(
                  fontSize: 18,
                  color: isActive ? null : Colors.grey,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                color: Colors.white.withValues(alpha: isActive ? 0.9 : 0.4),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bookmark_border,
            size: 80,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Keine Highlights',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Markiere Chat-Nachrichten mit Icons',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredMessages.length,
      itemBuilder: (context, index) {
        final message = _filteredMessages[index];
        return _buildMessageCard(message);
      },
    );
  }

  Widget _buildMessageCard(ChatMessage message) {
    final hasDeleteTimer = message.deleteTimerStart != null;
    final remainingSeconds = message.remainingDeleteSeconds ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: message.isUser
            ? Colors.blue.withValues(alpha: 0.2)
            : Colors.purple.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Icon + Timestamp
          Row(
            children: [
              if (message.highlightIcon != null)
                Text(
                  message.highlightIcon!,
                  style: const TextStyle(fontSize: 24),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ),
              // Delete Timer
              if (hasDeleteTimer)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer, color: Colors.red, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '${remainingSeconds}s',
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 8),
              // Remove Icon Button
              GestureDetector(
                onTap: () {
                  // Icon entfernen → Timer starten
                  widget.onIconChanged(message, null);
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.close, color: Colors.red, size: 16),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Message Text
          Text(
            message.text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

