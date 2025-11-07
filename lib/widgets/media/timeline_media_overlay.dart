import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
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
  // Preview-Logik für Audio
  Duration? _audioPreviewCap; // maximale Vorspielzeit
  bool _isLoopingAudio = false; // Guard gegen Mehrfach-Loop
  List<AudioCoverImage>? _covers;
  final PageController _coverController = PageController();
  Timer? _coverTimer;
  int _coverIndex = 0;
  bool _hasCompleted = false;
  bool _audioBusy = false;

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

    // Kostenlos: niemals blurren; kostenpflichtig: Vorschau-Regeln
    final price = widget.media.price ?? 0.0;
    final isFree = price == 0.0;
    final isPreview = !widget.isPurchased && !isFree;

    if (isPreview) {
      if (widget.media.type == AvatarMediaType.image ||
          widget.media.type == AvatarMediaType.document) {
        // Bilder/Dokumente stark blurren, kein Schloss
        content = BlurPixelationFilter(
          isBlurred: true,
          blurAmount: 20.0,
          showLockIcon: false,
          child: content,
        );
      } else if (widget.media.type == AvatarMediaType.audio) {
        // Audio: Preview-Dauer wird in _ensureAudio berechnet und durchgesetzt
      } else if (widget.media.type == AvatarMediaType.video) {
        // Video: Preview handled im Player-Widget (per Listener)
      }
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
        Expanded(
          child: _VideoPlayerWidget(
            url: widget.media.url,
            preview: (!widget.isPurchased && (widget.media.price ?? 0.0) > 0.0),
          ),
        ),
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
          height: 200,
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

        const SizedBox(height: 12),

        // Waveform + Controls overlay (mit Progress-Färbung)
        SizedBox(
          height: 100,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final totalW = constraints.maxWidth * 0.9;
              final totalH = constraints.maxHeight * 0.7;
              final effectiveDur = _audioPreviewCap ?? _duration;
              final progress = effectiveDur.inMilliseconds == 0
                  ? 0.0
                  : _position.inMilliseconds / effectiveDur.inMilliseconds;

              return Center(
                child: SizedBox(
                  width: totalW,
                  height: totalH,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Waveform Hintergrund mit Progress
                      CustomPaint(
                        size: Size(totalW, totalH),
                        painter: _StaticWaveformPainter(progress: progress.clamp(0.0, 1.0)),
                      ),
                      // Controls über Waveform
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Play/Pause Button
                          GestureDetector(
                            onTap: () async {
                              if (_audioBusy) return;
                              _audioBusy = true;
                              try {
                                var player = _audioPlayer;
                                if (player == null) {
                                  await _ensureAudio();
                                  player = _audioPlayer;
                                  if (player == null) return;
                                }

                                // Liegen wir am Preview‑Limit? → immer harter Replay
                                bool atLimit = false;
                                if (_audioPreviewCap != null) {
                                  final cap = _audioPreviewCap!;
                                  final safeCap = Duration(
                                    milliseconds: cap.inMilliseconds > 300 ? cap.inMilliseconds - 300 : cap.inMilliseconds,
                                  );
                                  atLimit = _position >= safeCap;
                                }

                                if (_hasCompleted || atLimit) {
                                  try {
                                    await player.stop();
                                  } catch (_) {}
                                  setState(() {
                                    _hasCompleted = false;
                                    _position = Duration.zero;
                                  });
                                  // Frisch starten ohne release/Neuinstanz
                                  await player.play(UrlSource(widget.media.url));
                                  return;
                                }

                                if (_isPlaying) {
                                  await player.pause();
                                } else {
                                  try {
                                    await player.resume();
                                  } catch (_) {}
                                }
                              } finally {
                                _audioBusy = false;
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
                                if (_audioBusy) return;
                                _audioBusy = true;
                                try {
                                  await _ensureAudio();
                                  final player = _audioPlayer;
                                  if (player == null) return;
                                  try {
                                    await player.stop();
                                  } catch (_) {}
                                  setState(() => _hasCompleted = false);
                                  // Seek to zero, then start cleanly
                                  try {
                                    await player.seek(Duration.zero).timeout(const Duration(seconds: 5));
                                  } catch (_) {}
                                  await player.play(UrlSource(widget.media.url));
                                } finally {
                                  _audioBusy = false;
                                }
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

        // Slider zum Vorspulen
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: AppColors.lightBlue,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
              thumbColor: AppColors.magenta,
            ),
            child: Slider(
              value: () {
                final durMs = (_audioPreviewCap ?? _duration).inMilliseconds;
                final posMs = _position.inMilliseconds;
                if (durMs <= 0) return 0.0;
                return (posMs / durMs).clamp(0.0, 1.0);
              }(),
              onChanged: (value) async {
                final durMs = (_audioPreviewCap ?? _duration).inMilliseconds;
                if (durMs <= 0) return;
                final player = _audioPlayer;
                if (player == null) return;
                
                setState(() => _hasCompleted = false);
                Duration newPos = Duration(milliseconds: (value * durMs).toInt());
                // Sicher: nicht direkt auf das harte Ende springen
                if (_audioPreviewCap != null) {
                  final cap = _audioPreviewCap!;
                  final safeCap = Duration(
                    milliseconds: cap.inMilliseconds > 300 ? cap.inMilliseconds - 300 : cap.inMilliseconds,
                  );
                  if (newPos >= safeCap) newPos = safeCap;
                }
                if (_audioBusy) return;
                _audioBusy = true;
                try {
                  // Seek fehlschläge nicht durchreichen: unawaited mit catchError
                  unawaited(
                    player
                        .seek(newPos)
                        .timeout(const Duration(seconds: 3))
                        .catchError((_) {}),
                  );
                  // Nur fortsetzen wenn wir NICHT am safeCap sind (Preview-Limit)
                  final shouldResume = () {
                    if (_audioPreviewCap == null) return true;
                    final cap = _audioPreviewCap!;
                    final safeCap = Duration(
                      milliseconds: cap.inMilliseconds > 300 ? cap.inMilliseconds - 300 : cap.inMilliseconds,
                    );
                    return newPos < safeCap;
                  }();
                  if (shouldResume) {
                    if (player.state != PlayerState.playing) {
                      unawaited(player.resume().catchError((_) {}));
                    }
                  } else {
                    // Am Limit: sicherstellen, dass pausiert bleibt
                    unawaited(player.pause().catchError((_) {}));
                  }
                } finally {
                  _audioBusy = false;
                }
              },
            ),
          ),
        ),
        // Zeit-Anzeige
        Text(
          '${_formatTime(_position)} / ${_formatTime(_audioPreviewCap ?? _duration)}',
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        const SizedBox(height: 4),
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
    await p.setReleaseMode(ReleaseMode.stop);
    p.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d);
      // Preview-Cap berechnen: 15% der Länge, min 5s, max 45s
      final isPreview = !widget.isPurchased && (widget.media.price ?? 0.0) > 0.0;
      if (isPreview && d.inMilliseconds > 0) {
        final secs = d.inSeconds;
        final cap = (secs * 0.15).clamp(5, 25);
        _audioPreviewCap = Duration(seconds: cap.toInt());
      } else {
        _audioPreviewCap = null;
      }
    });
    p.onPositionChanged.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
      // Preview-Limit erzwingen: statt Pause → LOOP auf 00:00
      if (_audioPreviewCap != null) {
        final ms = _audioPreviewCap!.inMilliseconds;
        final safeCap = Duration(milliseconds: ms > 200 ? ms - 200 : ms);
        if (pos >= safeCap) {
          _loopAudioToStart();
        }
      }
    });
    p.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _isPlaying = s == PlayerState.playing);
    });
    p.onPlayerComplete.listen((_) {
      // Natürliches Ende → ebenfalls loopen
      _loopAudioToStart();
    });
    await p.play(UrlSource(widget.media.url));
  }

  void _loopAudioToStart() {
    final p = _audioPlayer;
    if (p == null || _isLoopingAudio) return;
    _isLoopingAudio = true;
    () async {
      try {
        try { await p.pause(); } catch (_) {}
        try { await p.seek(Duration.zero).timeout(const Duration(milliseconds: 500)); } catch (_) {}
        try { await p.resume(); } catch (_) {}
        if (mounted) {
          setState(() {
            _hasCompleted = false;
            _position = Duration.zero;
            _isPlaying = true;
          });
        }
      } finally {
        _isLoopingAudio = false;
      }
    }();
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
          // Preis: Cash + Credits
          if (isFree)
            Text(
              'KOSTENLOS',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Cash-Preis
                Text(
                  '${price.toStringAsFixed(2)} €',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 12),
                // Credits-Preis mit GMBC Diamant
                Row(
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [
                          Color(0xFFE91E63), // Magenta
                          AppColors.lightBlue, // Blue
                          Color(0xFF00E5FF), // Cyan
                        ],
                      ).createShader(bounds),
                      child: const Icon(
                        Icons.diamond,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${(price / 0.1).round()}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
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
  final bool preview; // true = auf Vorschaudauer begrenzen

  const _VideoPlayerWidget({required this.url, this.preview = false});

  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  Duration? _previewCap;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _isInitialized = true);
          _controller.play();
          if (widget.preview) {
            final d = _controller.value.duration;
            if (d.inMilliseconds > 0) {
              final secs = d.inSeconds;
              final cap = (secs * 0.15).clamp(5, 25);
              _previewCap = Duration(seconds: cap.toInt());
              _controller.addListener(_enforcePreview);
            }
          }
        }
      });
  }

  @override
  void dispose() {
    _controller.removeListener(_enforcePreview);
    _controller.dispose();
    super.dispose();
  }

  void _enforcePreview() {
    if (!mounted) return;
    if (_previewCap == null) return;
    if (!_controller.value.isInitialized) return;
    final pos = _controller.value.position;
    final dur = _controller.value.duration;
    // Sicherheitsabstand 200ms und nie über tatsächliche Dauer
    final rawCap = _previewCap!;
    final capBase = (dur.inMilliseconds > 0 && rawCap > dur) ? dur : rawCap;
    final cap = Duration(milliseconds: capBase.inMilliseconds > 200 ? capBase.inMilliseconds - 200 : capBase.inMilliseconds);
    if (pos >= cap) {
      try {
        // LOOP: auf 0 setzen und weiter abspielen
        _controller.seekTo(Duration.zero);
        _controller.play();
      } catch (_) {}
    }
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

// Waveform mit Progress-Färbung (1:1 wie media_gallery)
class _StaticWaveformPainter extends CustomPainter {
  final double progress;

  _StaticWaveformPainter({this.progress = 0.0});

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = 1.0;
    final spacing = 1.5;
    final totalBars = (size.width / (barWidth + spacing)).floor();
    final random = Random(12345);

    for (int i = 0; i < totalBars; i++) {
      final x = i * (barWidth + spacing);
      final barProgress = i / totalBars;

      // Realistische Höhenverteilung
      double heightFactor;
      final randomVal = random.nextDouble();
      if (randomVal < 0.05) {
        heightFactor = 0.85 + random.nextDouble() * 0.15;
      } else if (randomVal < 0.15) {
        heightFactor = 0.65 + random.nextDouble() * 0.2;
      } else if (randomVal < 0.40) {
        heightFactor = 0.4 + random.nextDouble() * 0.25;
      } else if (randomVal < 0.70) {
        heightFactor = 0.25 + random.nextDouble() * 0.15;
      } else {
        heightFactor = 0.1 + random.nextDouble() * 0.15;
      }

      final barHeight = size.height * heightFactor;
      final y1 = (size.height - barHeight) / 2;
      final y2 = y1 + barHeight;

      // Farbe: GMBC Gradient für abgespielte Bars, grau für Rest
      final paint = Paint()
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.square;

      if (barProgress <= progress) {
        // Abgespielt: GMBC Gradient
        final gradientProgress = barProgress / (progress == 0 ? 1 : progress);
        final color = Color.lerp(
          const Color(0xFFE91E63), // Magenta
          const Color(0xFF00E5FF), // Cyan
          gradientProgress,
        )!;
        paint.color = color;
      } else {
        // Noch nicht abgespielt: dunkelgrau
        paint.color = Colors.black.withValues(alpha: 0.6);
      }

      canvas.drawLine(Offset(x, y1), Offset(x, y2), paint);
    }
  }

  @override
  bool shouldRepaint(_StaticWaveformPainter oldDelegate) => oldDelegate.progress != progress;
}

