import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

/// Tab-Button für Media Navigation (Images/Videos)
class MediaTabButton extends StatelessWidget {
  final String tab;
  final IconData icon;
  final String currentTab;
  final ValueChanged<String> onTabChanged;

  const MediaTabButton({
    super.key,
    required this.tab,
    required this.icon,
    required this.currentTab,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = currentTab == tab;

    return SizedBox(
      height: 35,
      child: TextButton(
        onPressed: () => onTabChanged(tab),
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          minimumSize: const WidgetStatePropertyAll(Size(60, 35)),
          backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (selected) {
              return const Color(0x26FFFFFF); // ausgewählt: hellgrau
            }
            return Colors.transparent;
          }),
          overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused) ||
                states.contains(WidgetState.pressed)) {
              final mix = Color.lerp(
                AppColors.magenta,
                AppColors.lightBlue,
                0.5,
              )!;
              return mix.withValues(alpha: 0.12);
            }
            return null;
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          shape: WidgetStateProperty.resolveWith<OutlinedBorder>((states) {
            final isHover =
                states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused);
            if (selected || isHover) {
              return const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              );
            }
            return RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            );
          }),
        ),
        child: Icon(
          icon,
          size: 22,
          color: selected ? Colors.white : Colors.white54,
        ),
      ),
    );
  }
}
