import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/media_models.dart';
import '../../theme/app_theme.dart';

/// Audio Cover Rotation Widget - zeigt Cover Images rotierend an
/// Wird im Chat Screen verwendet wenn Audio abgespielt wird
/// Slided von unten nach oben mit 1-3 Min Anzeigedauer
class AudioCoverRotationWidget extends StatefulWidget {
  final List<AudioCoverImage> coverImages;
  final Duration displayDuration; // 1-3 Minuten
  final VoidCallback? onTap;

  const AudioCoverRotationWidget({
    super.key,
    required this.coverImages,
    required this.displayDuration,
    this.onTap,
  });

  @override
  State<AudioCoverRotationWidget> createState() => _AudioCoverRotationWidgetState();
}

class _AudioCoverRotationWidgetState extends State<AudioCoverRotationWidget>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  Timer? _rotationTimer;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    
    // Fade Animation Setup
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _fadeController.forward();

    // Start Rotation Timer (wechselt alle 3-5 Sekunden zwischen Covern)
    if (widget.coverImages.length > 1) {
      _startRotation();
    }
  }

  void _startRotation() {
    _rotationTimer?.cancel();
    
    // Rotation Speed: Je nach Anzahl Cover, damit alle während displayDuration gezeigt werden
    final rotationInterval = widget.displayDuration.inMilliseconds ~/ 
        (widget.coverImages.length * 2); // 2x durchlaufen
    
    _rotationTimer = Timer.periodic(
      Duration(milliseconds: rotationInterval.clamp(10000, 20000)), // min 3s, max 8s
      (timer) {
        if (!mounted) return;
        
        // Fade Out
        _fadeController.reverse().then((_) {
          if (!mounted) return;
          
          // Nächstes Cover
          setState(() {
            _currentIndex = (_currentIndex + 1) % widget.coverImages.length;
          });
          
          // Fade In
          _fadeController.forward();
        });
      },
    );
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.coverImages.isEmpty) {
      return _buildFallback();
    }

    final currentCover = widget.coverImages[_currentIndex];

    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Cover Image mit Fade Animation
              FadeTransition(
                opacity: _fadeAnimation,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    currentCover.url,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => _buildFallback(),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: progress.expectedTotalBytes != null
                              ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                              : null,
                          color: AppColors.lightBlue,
                        ),
                      );
                    },
                  ),
                ),
              ),
              
              // Gradient Overlay (für bessere Lesbarkeit von Badges)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.3),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.5),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Rotation Indicator (nur wenn mehrere Cover)
              // if (widget.coverImages.length > 1)
              //   Positioned(
              //     top: 8,
              //     right: 8,
              //     child: Container(
              //       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              //       decoration: BoxDecoration(
              //         color: Colors.black.withValues(alpha: 0.7),
              //         borderRadius: BorderRadius.circular(12),
              //       ),
              //       child: Text(
              //         '${_currentIndex + 1}/${widget.coverImages.length}',
              //         style: const TextStyle(
              //           color: Colors.white,
              //           fontSize: 11,
              //           fontWeight: FontWeight.bold,
              //         ),
              //       ),
              //     ),
              //   ),
              
              // Aspect Ratio Badge
              // Positioned(
              //   bottom: 8,
              //   right: 8,
              //   child: Container(
              //     padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              //     decoration: BoxDecoration(
              //       gradient: const LinearGradient(
              //         colors: [AppColors.magenta, AppColors.lightBlue],
              //       ),
              //       borderRadius: BorderRadius.circular(4),
              //     ),
              //     child: Text(
              //       currentCover.aspectRatio > 1 ? '16:9' : '9:16',
              //       style: const TextStyle(
              //         color: Colors.white,
              //         fontSize: 10,
              //         fontWeight: FontWeight.bold,
              //       ),
              //     ),
              //   ),
              // ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallback() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.magenta.withValues(alpha: 0.3),
            AppColors.lightBlue.withValues(alpha: 0.3),
          ],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.music_note,
          size: 48,
          color: Colors.white54,
        ),
      ),
    );
  }
}

