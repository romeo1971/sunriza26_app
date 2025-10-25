import 'package:flutter/material.dart';
import '../../models/media_models.dart';
import '../../theme/app_theme.dart';
import 'blur_pixelation_filter.dart';
import 'audio_cover_rotation_widget.dart';

/// Universal Timeline Media Slider - zeigt alle Media-Typen slidend von unten nach oben
/// Unterstützt: Image, Video, Audio, Document
/// Position: Links am Bildrand, 20% Breite
/// Animation: 3 Phasen (Slide In → Display → Slide Out)
class TimelineMediaSlider extends StatefulWidget {
  final AvatarMedia media;
  final Duration slidingDuration; // 1-3 Minuten
  final bool isBlurred; // true = noch nicht gekauft
  final VoidCallback? onTap;

  const TimelineMediaSlider({
    super.key,
    required this.media,
    required this.slidingDuration,
    this.isBlurred = false,
    this.onTap,
  });

  @override
  State<TimelineMediaSlider> createState() => _TimelineMediaSliderState();
}

class _TimelineMediaSliderState extends State<TimelineMediaSlider>
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
            child: _buildMediaContent(),
          ),
        );
      },
    );
  }

  Widget _buildMediaContent() {
    Widget content;

    // Type-spezifischer Content
    switch (widget.media.type) {
      case AvatarMediaType.image:
        content = _buildImageContent();
        break;
      case AvatarMediaType.video:
        content = _buildVideoContent();
        break;
      case AvatarMediaType.audio:
        content = _buildAudioContent();
        break;
      case AvatarMediaType.document:
        content = _buildDocumentContent();
        break;
    }

    // Wrap mit Blur Filter wenn nicht gekauft
    final filteredContent = BlurPixelationFilter(
      isBlurred: widget.isBlurred,
      blurAmount: 15.0,
      showLockIcon: true,
      child: content,
    );

    // Wrap mit GestureDetector für Tap
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
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: filteredContent,
          ),
        ),
      ),
    );
  }

  Widget _buildImageContent() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Image
        Image.network(
          widget.media.thumbUrl ?? widget.media.url,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => _buildFallbackIcon(Icons.image),
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
        
        // Price Badge
        _buildPriceBadge(),
      ],
    );
  }

  Widget _buildVideoContent() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Video Thumbnail
        Image.network(
          widget.media.thumbUrl ?? widget.media.url,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => _buildFallbackIcon(Icons.videocam),
        ),
        
        // Play Icon Overlay
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.play_arrow,
              size: 40,
              color: Colors.white,
            ),
          ),
        ),
        
        // Price Badge
        _buildPriceBadge(),
      ],
    );
  }

  Widget _buildAudioContent() {
    // Audio mit Cover Images Rotation
    if (widget.media.coverImages != null && widget.media.coverImages!.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          AudioCoverRotationWidget(
            coverImages: widget.media.coverImages!,
            displayDuration: widget.slidingDuration,
            onTap: widget.onTap,
          ),
          
          // Price Badge
          _buildPriceBadge(),
        ],
      );
    }

    // Fallback: Default Audio Icon
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildFallbackIcon(Icons.music_note),
        _buildPriceBadge(),
      ],
    );
  }

  Widget _buildDocumentContent() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Document Thumbnail (falls vorhanden)
        if (widget.media.thumbUrl != null && widget.media.thumbUrl!.isNotEmpty)
          Image.network(
            widget.media.thumbUrl!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => _buildFallbackIcon(Icons.description),
          )
        else
          _buildFallbackIcon(Icons.description),
        
        // Price Badge
        _buildPriceBadge(),
      ],
    );
  }

  Widget _buildFallbackIcon(IconData icon) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.magenta.withValues(alpha: 0.3),
            AppColors.lightBlue.withValues(alpha: 0.3),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          icon,
          size: 64,
          color: Colors.white54,
        ),
      ),
    );
  }

  Widget _buildPriceBadge() {
    final price = widget.media.price ?? 0.0;
    final isFree = price == 0.0;

    return Positioned(
      bottom: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isFree 
              ? AppColors.lightBlue.withValues(alpha: 0.9)
              : AppColors.magenta.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          isFree ? 'KOSTENLOS' : '${price.toStringAsFixed(2)} €',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

