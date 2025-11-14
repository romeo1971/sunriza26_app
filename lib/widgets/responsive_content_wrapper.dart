import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import '../theme/app_theme.dart';
import 'dart:math' as math;

/// Wrapper für Web/macOS: Begrenzt Content auf iPad-Breite, außen animierter GMBC-Gradient
class ResponsiveContentWrapper extends StatefulWidget {
  final Widget child;
  const ResponsiveContentWrapper({super.key, required this.child});

  @override
  State<ResponsiveContentWrapper> createState() => _ResponsiveContentWrapperState();
}

class _ResponsiveContentWrapperState extends State<ResponsiveContentWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Nur für Web/macOS animieren
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.macOS) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 10), // Langsamer für sanftere Bewegung
      )..repeat();
    }
  }

  @override
  void dispose() {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.macOS) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mobile: kein Wrapper, direkt child
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.macOS) {
      return widget.child;
    }

    // Web/macOS: iPad-Breite (768px) + chaotischer animierter Gradient
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        
        // Sanfte Farbmischung: ruhige, durchmischende Verläufe
        final phase1 = (math.sin(t * 2 * math.pi) + 1) / 2; // 0..1
        final phase2 = (math.cos(t * 1.5 * math.pi) + 1) / 2;
        final phase3 = (math.sin((t + 0.4) * 1.8 * math.pi) + 1) / 2;
        
        // Farben sanft durchmischen - linke Farben auch rechts, rechte auch links
        final color1 = Color.lerp(
          AppColors.magenta,
          AppColors.lightBlue,
          phase1,
        )!;
        final color2 = Color.lerp(
          const Color(0xFF00E5FF), // Cyan
          AppColors.magenta,
          phase2,
        )!;
        final color3 = Color.lerp(
          AppColors.lightBlue,
          const Color(0xFF00E5FF),
          phase3,
        )!;
        final color4 = Color.lerp(
          AppColors.magenta,
          const Color(0xFF9EC5FF),
          phase1 * 0.5 + phase2 * 0.5,
        )!;
        
        return Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: const [0.0, 0.33, 0.66, 1.0],
              colors: [color1, color2, color3, color4],
            ),
          ),
          child: Center(
            child: SizedBox(
              width: 768, // iPad Portrait Breite - feste Breite
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}

