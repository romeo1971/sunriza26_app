import 'dart:ui';
import 'package:flutter/material.dart';

/// Blur/Pixelation Filter Widget für nicht gekaufte Timeline Items
/// Legt einen visuellen Filter über das Content Widget
class BlurPixelationFilter extends StatelessWidget {
  final Widget child;
  final bool isBlurred; // true = Blur aktiv, false = kein Blur
  final double blurAmount; // Blur-Stärke (default: 1.0 – sehr dezent)
  final bool showLockIcon; // Zeige Schloss-Icon über dem Blur

  const BlurPixelationFilter({
    super.key,
    required this.child,
    this.isBlurred = true,
    this.blurAmount = 1.0,
    this.showLockIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!isBlurred) {
      return child;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Original Content mit Blur
        ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: blurAmount,
            sigmaY: blurAmount,
            tileMode: TileMode.decal,
          ),
          child: child,
        ),
        
        // Dark Overlay für bessere Sichtbarkeit des Lock Icons
        Container(
          color: Colors.black.withValues(alpha: 0.3),
        ),
        
        // Lock Icon in der Mitte
        if (showLockIcon)
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock,
                size: 48,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }
}

/// Pixelation Filter (Alternative zu Blur)
/// Verwendet einen Pixelations-Effekt statt Blur
class PixelationFilter extends StatelessWidget {
  final Widget child;
  final bool isPixelated;
  final double pixelSize; // Pixel-Größe (default: 10.0)
  final bool showLockIcon;

  const PixelationFilter({
    super.key,
    required this.child,
    this.isPixelated = true,
    this.pixelSize = 10.0,
    this.showLockIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!isPixelated) {
      return child;
    }

    // Pixelation = starker Blur + reduzierte Auflösung
    return Stack(
      fit: StackFit.expand,
      children: [
        // Pixelated Content
        ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: pixelSize,
            sigmaY: pixelSize,
            tileMode: TileMode.decal,
          ),
          child: Transform.scale(
            scale: 0.3, // Reduziere Auflösung
            child: Transform.scale(
              scale: 1 / 0.3, // Skaliere zurück
              child: child,
            ),
          ),
        ),
        
        // Dark Overlay
        Container(
          color: Colors.black.withValues(alpha: 0.3),
        ),
        
        // Lock Icon
        if (showLockIcon)
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock,
                size: 48,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }
}

