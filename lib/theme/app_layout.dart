import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// Zentrale Layout-Konstanten für die App
class AppLayout {
  AppLayout._();

  /// Maximalbreite für den eigentlichen Content-Bereich.
  ///
  /// Ziel: "Mobile View" – auch auf großen Screens keine unendlich breite UI.
  /// Wir orientieren uns an typischen iPhone‑Breiten und lassen etwas Luft.
  static const double maxContentWidth = 430; // z.B. iPhone 14/15 Pro Portrait

  /// Berechnet die sinnvolle Content‑Breite für den aktuellen Screen.
  ///
  /// - Auf Mobile: volle Breite (MediaQuery)
  /// - Auf Web/Desktop: min(Fensterbreite, maxContentWidth)
  static double contentWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    // Mobile: einfach die verfügbare Breite nutzen
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android)) {
      return width;
    }

    // Web / Desktop: auf maxContentWidth begrenzen, damit es immer "mobile" wirkt
    return width > maxContentWidth ? maxContentWidth : width;
  }
}


