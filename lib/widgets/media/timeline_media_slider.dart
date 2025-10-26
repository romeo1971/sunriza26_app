import 'package:flutter/material.dart';
import '../../models/media_models.dart';
import '../../theme/app_theme.dart';
import 'blur_pixelation_filter.dart';
import 'audio_cover_rotation_widget.dart';
import 'dart:math' as math;
import '../../services/audio_cover_service.dart';

/// Universal Timeline Media Slider - zeigt alle Media-Typen slidend von unten nach oben
/// Unterstützt: Image, Video, Audio, Document
/// Position: Links am Bildrand, 20% Breite
/// Animation: 3 Phasen (Slide In → Display → Slide Out)
class TimelineMediaSlider extends StatefulWidget {
  final AvatarMedia media;
  final Duration slidingDuration; // 1-3 Minuten
  final bool isBlurred; // true = noch nicht gekauft
  final VoidCallback? onTap;
  final String? avatarId; // benötigt, um Audio-Cover ggf. lazy zu laden

  const TimelineMediaSlider({
    super.key,
    required this.media,
    required this.slidingDuration,
    this.isBlurred = false,
    this.onTap,
    this.avatarId,
  });

  @override
  State<TimelineMediaSlider> createState() => _TimelineMediaSliderState();
}

class _TimelineMediaSliderState extends State<TimelineMediaSlider>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<double> _slideAnimation; // 0..1: Slide-In binnen 600ms
  late AnimationController _driftController; // 0..1 über gesamte Displaydauer
  late Animation<double> _driftAnimation;
  List<AudioCoverImage>? _covers; // lazy-geladene Cover für Audio
  bool _loadingCovers = false;

  @override
  void initState() {
    super.initState();
    
    // Schnelles Slide-In (600ms), dann stehen bleiben bis Overlay entfernt wird
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _slideAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOut),
    );
    _slideController.forward();

    // Drift Animation über gesamte Displaydauer (linear von unten nach oben)
    _driftController = AnimationController(
      duration: widget.slidingDuration,
      vsync: this,
    );
    _driftAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _driftController, curve: Curves.linear),
    );
    _driftController.forward();

    // Audio-Cover ggf. lazy laden
    if (widget.media.type == AvatarMediaType.audio) {
      _covers = widget.media.coverImages;
      if ((_covers == null || _covers!.isEmpty) && widget.avatarId != null) {
        _loadCovers();
      }
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    _driftController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    
    // Feste Breite: 125px (laut Anforderung)
    final double panelWidth = 125.0;
    
    // Ziel-Aspect je Typ bestimmen
    double targetAspectRatio;
    switch (widget.media.type) {
      case AvatarMediaType.image:
      case AvatarMediaType.video:
        targetAspectRatio = (widget.media.aspectRatio ?? (9 / 16)).clamp(0.25, 4.0);
        break;
      case AvatarMediaType.audio:
        final coverAR = (widget.media.coverImages != null && widget.media.coverImages!.isNotEmpty)
            ? widget.media.coverImages!.first.aspectRatio
            : (9 / 16);
        targetAspectRatio = coverAR.clamp(0.25, 4.0);
        break;
      case AvatarMediaType.document:
        targetAspectRatio = (widget.media.aspectRatio ?? (9 / 16)).clamp(0.25, 4.0);
        break;
    }
    // Panelhöhe ausschließlich aus Breite/AR
    final double panelHeight = panelWidth / targetAspectRatio;
    
    return AnimatedBuilder(
      animation: Listenable.merge([_slideController, _driftController]),
      builder: (context, child) {
        // Position: Slide-In (600ms) + kontinuierlicher Drift über gesamte Dauer nach oben
        final slideIn = -panelHeight + (_slideAnimation.value * panelHeight);
        final drift = _driftAnimation.value * (screenHeight - panelHeight);
        final bottomPosition = slideIn + drift;

        return Positioned(
          left: 0,
          bottom: bottomPosition,
          width: panelWidth,
          height: panelHeight,
          child: Padding(
            padding: const EdgeInsets.all(8),
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

    // Kein Blur/Schloss mehr anzeigen
    final filteredContent = content;

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
        
      ],
    );
  }

  Widget _buildAudioContent() {
    // Audio mit Cover Images Rotation (alle 3s)
    final effectiveCovers = _covers ?? widget.media.coverImages;
    if (effectiveCovers != null && effectiveCovers.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          AudioCoverRotationWidget(
            coverImages: effectiveCovers,
            displayDuration: const Duration(seconds: 3),
            onTap: widget.onTap,
          ),
        ],
      );
    }

    // Fallback: Default Audio Icon
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildFallbackIcon(Icons.music_note),
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

  Future<void> _loadCovers() async {
    if (_loadingCovers || widget.avatarId == null) return;
    _loadingCovers = true;
    try {
      final svc = AudioCoverService();
      final list = await svc.getCoverImages(
        avatarId: widget.avatarId!,
        audioId: widget.media.id,
        audioUrl: widget.media.url,
      );
      if (list.isNotEmpty && mounted) {
        setState(() => _covers = list);
      }
    } catch (_) {}
    _loadingCovers = false;
  }
}

