import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../models/media_models.dart';
import '../../theme/app_theme.dart';
import 'blur_pixelation_filter.dart';

/// Fullsize Overlay für Timeline Media Items
/// Zeigt das Medium in voller Größe mit Kauf-/Annahme-Optionen
class TimelineMediaOverlay extends StatefulWidget {
  final AvatarMedia media;
  final bool isPurchased; // true = bereits gekauft
  final VoidCallback onPurchase; // Callback für Kauf/Annahme

  const TimelineMediaOverlay({
    super.key,
    required this.media,
    required this.isPurchased,
    required this.onPurchase,
  });

  @override
  State<TimelineMediaOverlay> createState() => _TimelineMediaOverlayState();
}

class _TimelineMediaOverlayState extends State<TimelineMediaOverlay> {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header mit Close Button
            _buildHeader(),
            
            // Media Content
            Expanded(
              child: _buildMediaContent(),
            ),
            
            // Footer mit Preis und Buttons
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.media.originalFileName ?? _getMediaTypeLabel(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaContent() {
    Widget content;

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

    // Kostenlos: niemals blurren; kostenpflichtig nur blurren, wenn nicht gekauft
    final price = widget.media.price ?? 0.0;
    final isFree = price == 0.0;
    if (!widget.isPurchased && !isFree) {
      content = BlurPixelationFilter(
        isBlurred: true,
        blurAmount: 20.0,
        showLockIcon: true,
        child: content,
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: content,
    );
  }

  Widget _buildImageContent() {
    return Center(
      child: Image.network(
        widget.media.url,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) => _buildErrorWidget(),
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
    );
  }

  Widget _buildVideoContent() {
    return _VideoPlayerWidget(url: widget.media.url);
  }

  Widget _buildAudioContent() {
    // Audio Player mit Cover
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Cover Image (falls vorhanden)
          if (widget.media.coverImages != null && widget.media.coverImages!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                widget.media.coverImages!.first.url,
                width: 300,
                height: 300,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => _buildMusicIcon(),
              ),
            )
          else
            _buildMusicIcon(),
          
          const SizedBox(height: 24),
          
          // Audio Info
          Text(
            widget.media.originalFileName ?? 'Audio File',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 8),
          
          // Duration
          if (widget.media.durationMs != null)
            Text(
              _formatDuration(widget.media.durationMs!),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDocumentContent() {
    // Document Preview (Thumbnail oder Icon)
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Thumbnail (falls vorhanden)
          if (widget.media.thumbUrl != null && widget.media.thumbUrl!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                widget.media.thumbUrl!,
                width: 300,
                height: 400,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => _buildDocumentIcon(),
              ),
            )
          else
            _buildDocumentIcon(),
          
          const SizedBox(height: 24),
          
          // Document Info
          Text(
            widget.media.originalFileName ?? 'Document',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMusicIcon() {
    return Container(
      width: 300,
      height: 300,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [
            AppColors.magenta.withValues(alpha: 0.3),
            AppColors.lightBlue.withValues(alpha: 0.3),
          ],
        ),
      ),
      child: const Icon(
        Icons.music_note,
        size: 100,
        color: Colors.white54,
      ),
    );
  }

  Widget _buildDocumentIcon() {
    return Container(
      width: 300,
      height: 400,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [
            AppColors.magenta.withValues(alpha: 0.3),
            AppColors.lightBlue.withValues(alpha: 0.3),
          ],
        ),
      ),
      child: const Icon(
        Icons.description,
        size: 100,
        color: Colors.white54,
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.white.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Fehler beim Laden',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final price = widget.media.price ?? 0.0;
    final isFree = price == 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Preis
          if (!widget.isPurchased)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isFree ? Icons.card_giftcard : Icons.euro,
                  color: isFree ? AppColors.lightBlue : AppColors.magenta,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  isFree ? 'KOSTENLOS' : '${price.toStringAsFixed(2)} €',
                  style: TextStyle(
                    color: isFree ? AppColors.lightBlue : AppColors.magenta,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          
          const SizedBox(height: 16),
          
          // Buttons
          Row(
            children: [
              // Abbrechen
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Abbrechen'),
                ),
              ),
              
              const SizedBox(width: 12),
              
              // Kaufen/Annehmen
              if (!widget.isPurchased)
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: widget.onPurchase,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isFree ? AppColors.lightBlue : AppColors.magenta,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                      isFree ? 'Annehmen' : 'Kaufen',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _getMediaTypeLabel() {
    switch (widget.media.type) {
      case AvatarMediaType.image:
        return 'Bild';
      case AvatarMediaType.video:
        return 'Video';
      case AvatarMediaType.audio:
        return 'Audio';
      case AvatarMediaType.document:
        return 'Dokument';
    }
  }

  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

// Video Player Widget
class _VideoPlayerWidget extends StatefulWidget {
  final String url;

  const _VideoPlayerWidget({required this.url});

  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _isInitialized = true);
          _controller.play();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.lightBlue),
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: VideoPlayer(_controller),
      ),
    );
  }
}

