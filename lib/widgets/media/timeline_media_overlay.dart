import 'package:flutter/material.dart';
import 'dart:async';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../models/media_models.dart';
import '../../theme/app_theme.dart';
import 'blur_pixelation_filter.dart';
import '../../services/audio_cover_service.dart';

/// Fullsize Overlay für Timeline Media Items
/// Zeigt das Medium in voller Größe mit Kauf-/Annahme-Optionen
class TimelineMediaOverlay extends StatefulWidget {
  final AvatarMedia media;
  final bool isPurchased; // true = bereits gekauft
  final VoidCallback onPurchase; // Callback für Kauf/Annahme
  final String? avatarId; // für lazy Cover-Load bei Audio

  const TimelineMediaOverlay({
    super.key,
    required this.media,
    required this.isPurchased,
    required this.onPurchase,
    this.avatarId,
  });

  @override
  State<TimelineMediaOverlay> createState() => _TimelineMediaOverlayState();
}

class _TimelineMediaOverlayState extends State<TimelineMediaOverlay> {
  AudioPlayer? _audioPlayer;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;
  List<AudioCoverImage>? _covers;
  final PageController _coverController = PageController();
  Timer? _coverTimer;
  int _coverIndex = 0;
  bool _hasCompleted = false;

  @override
  void initState() {
    super.initState();
    // Lazy Cover Load für Audio, falls nötig
    if (widget.media.type == AvatarMediaType.audio) {
      final existing = widget.media.coverImages;
      if ((existing == null || existing.isEmpty) && widget.avatarId != null) {
        AudioCoverService()
            .getCoverImages(
              avatarId: widget.avatarId!,
              audioId: widget.media.id,
              audioUrl: widget.media.url,
            )
            .then((list) {
          if (!mounted) return;
          setState(() => _covers = list);
          _maybeStartCoverSlideshow();
        }).catchError((_) {});
      } else {
        _covers = existing;
        _maybeStartCoverSlideshow();
      }
    }
  }

  @override
  void dispose() {
    _audioPlayer?.stop();
    _audioPlayer?.dispose();
    _audioPlayer = null;
    _coverTimer?.cancel();
    _coverController.dispose();
    super.dispose();
  }

  // Stabil bei Hot‑Reload/Save (reassemble wird nur im Debug aufgerufen)
  @override
  void reassemble() {
    // Stoppe laufenden Audio‑Player und Slideshow‑Timer, um Crashes zu vermeiden
    try { _audioPlayer?.stop(); } catch (_) {}
    _coverTimer?.cancel();
    // Slideshow danach neu anstoßen
    _maybeStartCoverSlideshow();
    super.reassemble();
  }

  void _maybeStartCoverSlideshow() {
    _coverTimer?.cancel();
    final list = _covers;
    if (list != null && list.length > 1) {
      _coverTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (!mounted) return;
        _coverIndex = (_coverIndex + 1) % list.length;
        _coverController.animateToPage(
          _coverIndex,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      });
    }
  }
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
    // Titel + Künstler aus originalFileName extrahieren
    final fileName = widget.media.originalFileName ?? _getMediaTypeLabel();
    final parts = fileName.split(' - ');
    final title = parts.length > 1 ? parts[1].replaceAll('.mp3', '').replaceAll('.wav', '') : fileName;
    final artist = parts.isNotEmpty ? parts[0] : '';
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (artist.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              artist,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
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
    return Column(
      children: [
        Expanded(child: _VideoPlayerWidget(url: widget.media.url)),
        const SizedBox(height: 8),
        _buildControlsRow(isVideo: true),
      ],
    );
  }

  Widget _buildAudioContent() {
    // Audio-Ansicht: große Cover-Slideshow + kompakte Waveform + Controls
    return Column(
      children: [
        // Große Cover‑Slideshow
        SizedBox(
          height: 220,
          child: Stack(
            children: [
              PageView.builder(
                controller: _coverController,
                itemCount: (_covers ?? widget.media.coverImages)?.length ?? 0,
                itemBuilder: (context, index) {
                  final covers = _covers ?? widget.media.coverImages;
                  final img = covers![index];
                  final ar = (img.aspectRatio == 0) ? (9 / 16) : img.aspectRatio;
                  return Center(
                    child: AspectRatio(
                      aspectRatio: ar,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          img.url,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (((_covers ?? widget.media.coverImages)?.length ?? 0) > 1) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.chevron_left, size: 32, color: Colors.white),
                    onPressed: () {
                      final total = (_covers ?? widget.media.coverImages)!.length;
                      _coverIndex = (_coverIndex - 1 + total) % total;
                      _coverController.animateToPage(
                        _coverIndex,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: const Icon(Icons.chevron_right, size: 32, color: Colors.white),
                    onPressed: () {
                      final total = (_covers ?? widget.media.coverImages)!.length;
                      _coverIndex = (_coverIndex + 1) % total;
                      _coverController.animateToPage(
                        _coverIndex,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Waveform + Controls overlay (1:1 wie media_gallery)
        SizedBox(
          height: 120,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final totalW = constraints.maxWidth * 0.9;
              final totalH = constraints.maxHeight * 0.7;
              final progress = _duration.inMilliseconds == 0
                  ? 0.0
                  : _position.inMilliseconds / _duration.inMilliseconds;

              return Center(
                child: SizedBox(
                  width: totalW,
                  height: totalH,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Waveform Hintergrund
                      CustomPaint(
                        size: Size(totalW, totalH),
                        painter: _StaticWaveformPainter(),
                      ),
                      // Controls über Waveform
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Play/Pause Button
                          GestureDetector(
                            onTap: () async {
                              await _ensureAudio();
                              if (_isPlaying) {
                                await _audioPlayer?.pause();
                              } else {
                                if (_hasCompleted) {
                                  await _audioPlayer?.seek(Duration.zero);
                                  setState(() => _hasCompleted = false);
                                }
                                await _audioPlayer?.resume();
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFFE91E63),
                                    AppColors.lightBlue,
                                    Color(0xFF00E5FF),
                                  ],
                                  stops: [0.0, 0.5, 1.0],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Icon(
                                _isPlaying ? Icons.pause : Icons.play_arrow,
                                size: 32,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          // Reload Button
                          if (progress > 0.0 || _isPlaying) ...[
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () async {
                                await _ensureAudio();
                                await _audioPlayer?.seek(Duration.zero);
                                setState(() => _hasCompleted = false);
                                await _audioPlayer?.play(UrlSource(widget.media.url));
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.6),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.3),
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(Icons.replay, size: 20, color: Colors.white),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 8),
        // Zeit-Anzeige
        Text(
          '${_formatTime(_position)} / ${_formatTime(_duration)}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildControlsRow({required bool isVideo}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.replay, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(), // simple close+resume
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.pause, color: Colors.white),
          onPressed: () {},
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.play_arrow, color: Colors.white),
          onPressed: () {},
        ),
      ],
    );
  }

  String _formatTime(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _ensureAudio() async {
    if (_audioPlayer != null) return;
    final p = AudioPlayer();
    _audioPlayer = p;
    p.onDurationChanged.listen((d) => setState(() => _duration = d));
    p.onPositionChanged.listen((pos) => setState(() => _position = pos));
    p.onPlayerStateChanged.listen((s) => setState(() => _isPlaying = s == PlayerState.playing));
    p.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _hasCompleted = true;
        _isPlaying = false;
        _position = Duration.zero;
      });
    });
    await p.play(UrlSource(widget.media.url));
  }

  // 1:1 Waveform wie Galerie
  Widget _buildCompactWaveformOverlay({
    required double availableWidth,
    double progress = 0.0,
  }) {
    final barCount = (availableWidth / 1.4).floor().clamp(50, 300);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(barCount, (index) {
        final heights = [
          0.3, 0.5, 0.7, 0.9, 0.6, 0.4, 0.8, 0.5, 0.7, 0.3, 0.6, 0.8, 0.4,
          0.9, 0.5, 0.7, 0.3, 0.6, 0.4, 0.8, 0.5, 0.7, 0.6, 0.9, 0.4, 0.8,
          0.5, 0.6, 0.3, 0.7, 0.4, 0.6, 0.8, 0.5, 0.9, 0.3, 0.7, 0.6, 0.4,
          0.8, 0.5, 0.7, 0.4, 0.6, 0.9, 0.3, 0.8, 0.5, 0.7, 0.4,
        ];
        final height = heights[index % heights.length];
        final barPosition = index / barCount;
        final isPlayed = barPosition <= progress;
        return Container(
          width: 1.2,
          height: 54.43 * height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(0.6),
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: isPlayed
                  ? [
                      const Color(0xFF00E5FF).withValues(alpha: 0.4),
                      const Color(0xFF00E5FF).withValues(alpha: 0.7),
                      const Color(0xFF00E5FF).withValues(alpha: 0.9),
                    ]
                  : [
                      Colors.transparent,
                      Colors.transparent,
                      Colors.transparent,
                    ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      }),
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
          // Preis dezent ohne Icon
          Text(
            isFree ? 'KOSTENLOS' : '${price.toStringAsFixed(2)} €',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Buttons
          Row(
            children: [
              // X Button
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
              
              const Spacer(),
              
              // Annehmen mit GMBC Gradient Text
              if (!widget.isPurchased)
                ElevatedButton(
                  onPressed: widget.onPurchase,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [AppColors.magenta, AppColors.lightBlue],
                    ).createShader(bounds),
                    child: Text(
                      isFree ? 'Annehmen' : 'Kaufen',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
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

// Simple statische Waveform (ähnlich zur Galerie)
class _StaticWaveformPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = LinearGradient(
        colors: [
          AppColors.magenta.withValues(alpha: 0.25),
          AppColors.lightBlue.withValues(alpha: 0.25),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Offset.zero & size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
      bg,
    );

    final barPaint = Paint()..color = Colors.white.withValues(alpha: 0.7);
    final barWidth = 3.0;
    final gap = 2.0;
    final maxBars = (size.width / (barWidth + gap)).floor();
    for (int i = 0; i < maxBars; i++) {
      final t = (i * 37) % 100 / 100.0; // deterministische Variation
      final h = (size.height * (0.25 + 0.65 * (t < 0.5 ? t * 2 : (1 - t) * 2))).clamp(8.0, size.height - 8.0);
      final x = i * (barWidth + gap).toDouble();
      final rect = Rect.fromLTWH(x, (size.height - h) / 2, barWidth, h);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

