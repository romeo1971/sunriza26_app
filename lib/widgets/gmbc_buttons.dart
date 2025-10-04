import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Gradient-Button (GMBC) auf Basis des Upload-Buttons
/// Verwendbar für beliebige IconButtons
class GmbcIconButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final double width;
  final double height;
  final double borderRadius;

  const GmbcIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.width = 40,
    this.height = 32,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFFE91E63),
                AppColors.lightBlue,
                Color(0xFF00E5FF),
              ],
            ),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: Center(child: Icon(icon, color: Colors.white)),
        ),
      ),
    );
  }
}

/// Gradient-TextButton (GMBC) – Variante mit einem Text (z. B. „X“)
/// Styling angelehnt an den Upload-Button (gleicher Gradient, gleiche Rundung)
class GmbcTextButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String text;
  final double width;
  final double height;
  final double borderRadius;
  final bool transparentBackground;
  final bool outlined;
  final Color? background;
  final Color? borderColor;

  const GmbcTextButton({
    super.key,
    this.onPressed,
    this.text = 'X',
    this.width = 40,
    this.height = 32,
    this.borderRadius = 8,
    this.transparentBackground = false,
    this.outlined = false,
    this.background,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: transparentBackground
              ? (background ?? Colors.transparent)
              : Colors.white,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          side: outlined
              ? BorderSide(color: borderColor ?? Colors.white24)
              : null,
        ),
        child: transparentBackground
            ? Center(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            : Ink(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFE91E63),
                      AppColors.lightBlue,
                      Color(0xFF00E5FF),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(borderRadius),
                ),
                child: Center(
                  child: Text(
                    text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
