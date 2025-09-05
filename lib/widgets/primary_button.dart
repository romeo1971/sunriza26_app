/// Primary Button Widget
/// Stand: 04.09.2025 - Basierend auf struppi-Implementation

import 'package:flutter/material.dart';

class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double? fontSize;
  final Color? backgroundColor;
  final Color? textColor;

  const PrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.fontSize,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: onPressed != null
            ? const LinearGradient(
                colors: [Color(0xFF00FF94), Color(0xFF00CC7A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: onPressed == null ? const Color(0xFF333333) : backgroundColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: onPressed != null
            ? [
                BoxShadow(
                  color: const Color(0xFF00FF94).withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    text,
                    style: TextStyle(
                      color: textColor ?? Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: fontSize ?? 16,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
