import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Base ExpansionTile Widget für konsistentes Design
class BaseExpansionTile extends StatelessWidget {
  final String title;
  final String emoji;
  final List<Widget> children;
  final bool initiallyExpanded;
  final Color? backgroundColor;
  final Color? collapsedBackgroundColor;

  const BaseExpansionTile({
    super.key,
    required this.title,
    this.emoji = '',
    required this.children,
    this.initiallyExpanded = false,
    this.backgroundColor,
    this.collapsedBackgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.white24,
        listTileTheme: const ListTileThemeData(iconColor: AppColors.magenta),
      ),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        collapsedBackgroundColor:
            collapsedBackgroundColor ?? Colors.white.withValues(alpha: 0.04),
        backgroundColor:
            backgroundColor ?? Colors.black.withValues(alpha: 0.95),
        collapsedIconColor: AppColors.magenta,
        iconColor: AppColors.lightBlue,
        title: Row(
          children: [
            if (emoji.trim().isNotEmpty) ...[
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
            ],
            Text(title, style: const TextStyle(color: Colors.white)),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}
