/// Text Input Widget für AI-Assistenten
/// Stand: 04.09.2025 - Mit Validierung und Charakter-Zähler
library;

import 'package:flutter/material.dart';

class TextInputWidget extends StatefulWidget {
  final TextEditingController controller;
  final bool enabled;
  final String hintText;
  final int maxLines;
  final int? maxLength;
  final Function(String)? onChanged;

  const TextInputWidget({
    super.key,
    required this.controller,
    this.enabled = true,
    this.hintText = 'Text eingeben...',
    this.maxLines = 1,
    this.maxLength,
    this.onChanged,
  });

  @override
  State<TextInputWidget> createState() => _TextInputWidgetState();
}

class _TextInputWidgetState extends State<TextInputWidget> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          enabled: widget.enabled,
          maxLines: widget.maxLines,
          maxLength: widget.maxLength,
          onChanged: widget.onChanged,
          decoration: InputDecoration(
            hintText: widget.hintText,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[400]!),
            ),
            filled: true,
            fillColor: widget.enabled
                ? Theme.of(context).colorScheme.surface
                : Colors.grey[200],
            contentPadding: const EdgeInsets.all(16),
          ),
          style: TextStyle(
            fontSize: 16,
            color: widget.enabled
                ? Theme.of(context).colorScheme.onSurface
                : Colors.grey[600],
          ),
        ),

        if (widget.maxLength != null) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Zeichen: ${widget.controller.text.length}/${widget.maxLength}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (widget.controller.text.length > (widget.maxLength! * 0.9))
                Text(
                  'Warnung: Text wird zu lang',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
