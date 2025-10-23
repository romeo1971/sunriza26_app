import 'package:flutter/material.dart';

/// Icon-Picker Dialog für Hero Chat Highlights
/// Wird AN der Chat-Blase positioniert beim Tap
class HeroChatIconPicker extends StatelessWidget {
  final String? selectedIcon;
  final Function(String) onIconSelected;
  final VoidCallback onClose;
  final bool alignRight; // true = User (rechts), false = Avatar (links)

  const HeroChatIconPicker({
    super.key,
    this.selectedIcon,
    required this.onIconSelected,
    required this.onClose,
    required this.alignRight,
  });

  static const List<String> icons = [
    '🐣', '🔥', '🍻', '🌈', '🍀', '❤️', '😂', '😱', '💪', '👍',
    '🥰', '🥳', '😘', '🖖', '😢', '😡', '🤯', '🤮', '🫶', '🙌',
    '👏', '😎', '🤪', '🤓',
  ];

  /// Zeigt den Icon-Picker Dialog AN der Blase
  static void showAtPosition(
    BuildContext context, {
    required Offset position,
    required bool alignRight,
    String? selectedIcon,
    required Function(String) onIconSelected,
    required VoidCallback onRemove,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Tap ins Leere schließt den Dialog
          Positioned.fill(
            child: GestureDetector(
              onTap: () => entry.remove(),
              child: Container(color: Colors.transparent),
            ),
          ),
          // Icon-Picker AN der Blase positioniert
          Positioned(
            left: alignRight ? null : position.dx,
            right: alignRight ? MediaQuery.of(context).size.width - position.dx : null,
            top: position.dy,
            child: Material(
              color: Colors.transparent,
              child: HeroChatIconPicker(
                selectedIcon: selectedIcon,
                alignRight: alignRight,
                onIconSelected: (icon) {
                  onIconSelected(icon);
                  entry.remove();
                },
                onClose: () {
                  if (selectedIcon != null) {
                    onRemove();
                  }
                  entry.remove();
                },
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Title
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              selectedIcon != null ? 'Icon ändern' : 'Icon wählen',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // Icons Grid
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: alignRight ? WrapAlignment.end : WrapAlignment.start,
            children: icons.map((icon) => _buildIconButton(icon)).toList(),
          ),
          // Remove Button (wenn Icon bereits gesetzt)
          if (selectedIcon != null) ...[
            const SizedBox(height: 8),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 8),
            _buildRemoveButton(),
          ],
        ],
      ),
    );
  }

  Widget _buildIconButton(String icon) {
    final isSelected = selectedIcon == icon;
    return GestureDetector(
      onTap: () => onIconSelected(icon),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? Colors.white.withValues(alpha: 0.8)
                : Colors.white.withValues(alpha: 0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            icon,
            style: const TextStyle(fontSize: 24),
          ),
        ),
      ),
    );
  }

  Widget _buildRemoveButton() {
    return GestureDetector(
      onTap: onClose,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.red.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.close, color: Colors.red, size: 16),
            const SizedBox(width: 6),
            const Text(
              'Icon entfernen',
              style: TextStyle(
                color: Colors.red,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

