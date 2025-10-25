import 'package:flutter/material.dart';
import '../../models/media_models.dart';
import 'audio_cover_rotation_widget.dart';

/// Timeline Audio Slider - zeigt Audio Cover Images slidend von unten nach oben
/// Timing: 1-3 Minuten je nach nächstem Timeline Item
/// Position: Links am Bildrand, 20% Breite
class TimelineAudioSlider extends StatefulWidget {
  final AvatarMedia audioMedia;
  final Duration slidingDuration; // 1-3 Minuten
  final VoidCallback? onTap;

  const TimelineAudioSlider({
    super.key,
    required this.audioMedia,
    required this.slidingDuration,
    this.onTap,
  });

  @override
  State<TimelineAudioSlider> createState() => _TimelineAudioSliderState();
}

class _TimelineAudioSliderState extends State<TimelineAudioSlider>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    
    // Slide Animation Setup
    _slideController = AnimationController(
      duration: widget.slidingDuration,
      vsync: this,
    );

    // 3 Phasen: Slide In (0-20%) → Display (20-80%) → Slide Out (80-100%)
    _slideAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeInOut),
    );

    // Start Animation
    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    
    return AnimatedBuilder(
      animation: _slideAnimation,
      builder: (context, child) {
        // Berechne Position basierend auf Animation Progress
        final progress = _slideAnimation.value;
        double bottomPosition;
        
        if (progress < 0) {
          // Phase 1: Slide In (von unten)
          bottomPosition = progress * screenHeight; // -1.0 → 0.0 = -screenHeight → 0
        } else if (progress < 1.0) {
          // Phase 2: Display (sichtbar)
          bottomPosition = 0;
        } else {
          // Phase 3: Slide Out (nach oben)
          bottomPosition = (progress - 1.0) * screenHeight; // 1.0 → 2.0 = 0 → screenHeight
        }

        return Positioned(
          left: 0,
          bottom: bottomPosition,
          width: screenWidth * 0.2,
          height: screenHeight * 0.4, // 40% der Bildschirmhöhe
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AudioCoverRotationWidget(
              coverImages: widget.audioMedia.coverImages ?? [],
              displayDuration: widget.slidingDuration,
              onTap: widget.onTap,
            ),
          ),
        );
      },
    );
  }
}

