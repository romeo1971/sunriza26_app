import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Hero Chat FAB Button - oben rechts in chat_screen
/// Zeigt Anzahl der Highlights
class HeroChatFabButton extends StatelessWidget {
  final int highlightCount;
  final VoidCallback onTap;

  const HeroChatFabButton({
    super.key,
    required this.highlightCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.magenta, AppColors.lightBlue],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.magenta.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.bookmark,
              color: Colors.white,
              size: 20,
            ),
            if (highlightCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$highlightCount',
                  style: const TextStyle(
                    color: AppColors.magenta,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

