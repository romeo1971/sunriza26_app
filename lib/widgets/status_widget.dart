/// Status Widget für AI-Assistenten
/// Stand: 04.09.2025 - Zeigt Generierungs-Status und Fehler an
library;

import 'package:flutter/material.dart';

class StatusWidget extends StatelessWidget {
  final String message;
  final bool isGenerating;
  final String? errorMessage;

  const StatusWidget({
    super.key,
    required this.message,
    this.isGenerating = false,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _getBackgroundColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _getBorderColor(context), width: 1),
      ),
      child: Row(
        children: [
          // Status-Icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getIconBackgroundColor(context),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getStatusIcon(),
              color: _getIconColor(context),
              size: 20,
            ),
          ),

          const SizedBox(width: 16),

          // Status-Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getStatusTitle(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _getTitleColor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 13,
                    color: _getMessageColor(context),
                  ),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Colors.red[700],
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            errorMessage!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Loading Indicator
          if (isGenerating)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Color _getBackgroundColor(BuildContext context) {
    if (errorMessage != null) {
      return Colors.red[50]!;
    } else if (isGenerating) {
      return Colors.blue[50]!;
    } else {
      return Theme.of(context).colorScheme.surfaceContainerHighest;
    }
  }

  Color _getBorderColor(BuildContext context) {
    if (errorMessage != null) {
      return Colors.red[200]!;
    } else if (isGenerating) {
      return Colors.blue[200]!;
    } else {
      return Theme.of(context).colorScheme.outline;
    }
  }

  Color _getIconBackgroundColor(BuildContext context) {
    if (errorMessage != null) {
      return Colors.red[100]!;
    } else if (isGenerating) {
      return Colors.blue[100]!;
    } else {
      return Theme.of(context).colorScheme.primaryContainer;
    }
  }

  Color _getIconColor(BuildContext context) {
    if (errorMessage != null) {
      return Colors.red[700]!;
    } else if (isGenerating) {
      return Colors.blue[700]!;
    } else {
      return Theme.of(context).colorScheme.onPrimaryContainer;
    }
  }

  Color _getTitleColor(BuildContext context) {
    if (errorMessage != null) {
      return Colors.red[800]!;
    } else if (isGenerating) {
      return Colors.blue[800]!;
    } else {
      return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  Color _getMessageColor(BuildContext context) {
    if (errorMessage != null) {
      return Colors.red[700]!;
    } else if (isGenerating) {
      return Colors.blue[700]!;
    } else {
      return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  IconData _getStatusIcon() {
    if (errorMessage != null) {
      return Icons.error_outline;
    } else if (isGenerating) {
      return Icons.sync;
    } else {
      return Icons.check_circle_outline;
    }
  }

  String _getStatusTitle() {
    if (errorMessage != null) {
      return 'Fehler';
    } else if (isGenerating) {
      return 'Generiere Video...';
    } else {
      return 'Bereit';
    }
  }
}
