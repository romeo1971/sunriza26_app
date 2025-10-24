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

  /// Zeigt den Icon-Picker zentriert über dem Chat
  static void showCentered(
    BuildContext context, {
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
          // Zentrierter Picker
          Positioned.fill(
            child: Center(
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
          ),
        ],
      ),
    );

    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icons Grid (kompakter)
          Wrap(
            spacing: 4,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: icons.map((icon) => _buildIconButton(icon)).toList(),
          ),
          // Remove Button (wenn Icon bereits gesetzt)
          if (selectedIcon != null) ...[
            const SizedBox(height: 6),
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
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected
              ? Border.all(
                  color: Colors.white.withValues(alpha: 0.5),
                  width: 1.5,
                )
              : null,
        ),
        child: Center(
          child: Text(
            icon,
            style: const TextStyle(fontSize: 20),
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
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Colors.red.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.close, color: Colors.red, size: 14),
            const SizedBox(width: 4),
            const Text(
              'Auswahl aufheben',
              style: TextStyle(
                color: Colors.red,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

