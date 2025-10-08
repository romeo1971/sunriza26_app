import 'package:flutter/material.dart';

/// Zentrale Farb- und Verlaufsvorgaben der CI
class AppColors {
  AppColors._();

  // Basistöne
  static const Color black = Color(0xFF000000);
  static const Color darkSurface = Color(0xFF0A0A0A);
  static const Color darkGreen = Color(0xFF0C1F17); // sehr dunkles Grün
  static const Color primaryGreen = Color(0xFF00FF94); // CI Grün
  static const Color magenta = Color(0xFFFF2EC8); // CI Magenta
  static const Color lightBlue = Color(0xFF8AB4F8); // helles Blau
  static const Color greenBlue = Color(0xFF00C2FF); // Grün‑Blau Akzent
  static const Color accentLightGreen = Color(0xFF66FFCC); // helles Grün Akzent
  static const Color accentGreenDark = Color(
    0xFF00DFA8,
  ); // dunkleres Grün Akzent
}

/// ThemeExtension für wiederverwendbare Gradients
class AppGradients extends ThemeExtension<AppGradients> {
  final Gradient background; // große Hintergründe
  final Gradient surface; // Card/Container
  final Gradient buttonPrimary; // primärer CTA
  final Gradient buttonSecondary; // sekundärer CTA
  final Gradient magentaBlue; // Magenta → Blau

  const AppGradients({
    required this.background,
    required this.surface,
    required this.buttonPrimary,
    required this.buttonSecondary,
    required this.magentaBlue,
  });

  factory AppGradients.defaultDark() {
    return const AppGradients(
      // Hintergrund: dunkles Grün → Schwarz
      background: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.darkGreen, AppColors.black],
      ),
      // Surface: leichtes Grün‑Blau Overlay
      surface: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0x1400FF94), Color(0x1400C2FF)],
      ),
      // Primärbutton: Dunkleres Grün → Grün‑Blau
      buttonPrimary: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.accentGreenDark, AppColors.greenBlue],
      ),
      // Sekundärbutton: Grün → Grün‑Blau
      buttonSecondary: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.primaryGreen, AppColors.greenBlue],
      ),
      // GMBC: Magenta → LightBlue (CI-konform)
      magentaBlue: LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [AppColors.magenta, AppColors.lightBlue],
      ),
    );
  }

  @override
  AppGradients copyWith({
    Gradient? background,
    Gradient? surface,
    Gradient? buttonPrimary,
    Gradient? buttonSecondary,
    Gradient? magentaBlue,
  }) {
    return AppGradients(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      buttonPrimary: buttonPrimary ?? this.buttonPrimary,
      buttonSecondary: buttonSecondary ?? this.buttonSecondary,
      magentaBlue: magentaBlue ?? this.magentaBlue,
    );
  }

  @override
  AppGradients lerp(ThemeExtension<AppGradients>? other, double t) {
    if (other is! AppGradients) return this;
    // Gradients selbst nicht linar interpolieren – gib einfach 'other' zurück
    return other;
  }
}
