import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import '../models/moment.dart';
import '../theme/app_theme.dart';
import 'dart:math' as math;

class MomentViewer extends StatefulWidget {
  final List<Moment> moments;
  final int initialIndex;

  const MomentViewer({super.key, required this.moments, required this.initialIndex});

  @override
  State<MomentViewer> createState() => _MomentViewerState();
}

class _MomentViewerState extends State<MomentViewer> {
  late final PageController _pageController;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.moments.length - 1);
    _pageController = PageController(initialPage: _index);
  }

  void _next() {
    if (_index + 1 < widget.moments.length) {
      _pageController.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  void _prev() {
    if (_index - 1 >= 0) {
      _pageController.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Shortcuts(
        shortcuts: <LogicalKeySet, Intent>{
          LogicalKeySet(LogicalKeyboardKey.arrowRight): const NextFocusIntent(),
          LogicalKeySet(LogicalKeyboardKey.arrowLeft): const PreviousFocusIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            NextFocusIntent: CallbackAction<Intent>(onInvoke: (_) { _next(); return null; }),
            PreviousFocusIntent: CallbackAction<Intent>(onInvoke: (_) { _prev(); return null; }),
          },
          child: Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _index = i),
                itemCount: widget.moments.length,
                itemBuilder: (context, i) {
                  final m = widget.moments[i];
                  final url = (m.storedUrl.isNotEmpty) ? m.storedUrl : m.originalUrl;
                  switch (m.type) {
                    case 'image':
                      return Center(
                        child: InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 3.0,
                          child: Image.network(url, fit: BoxFit.contain),
                        ),
                      );
                    case 'video':
                      return _MomentVideo(url: url);
                    case 'audio':
                      return _MomentAudio(url: url, title: m.originalFileName ?? 'Audio');
                    case 'document':
                    default:
                      return _MomentDocument(url: url, filename: m.originalFileName);
                  }
                },
              ),
              // Top bar
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          (widget.moments[_index].originalFileName ?? '').isNotEmpty
                              ? widget.moments[_index].originalFileName!
                              : widget.moments[_index].storedUrl.split('/').last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.chevron_left, color: Colors.white70),
                        onPressed: _prev,
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right, color: Colors.white70),
                        onPressed: _next,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MomentVideo extends StatefulWidget {
  final String url;
  const _MomentVideo({required this.url});

  @override
  State<_MomentVideo> createState() => _MomentVideoState();
}

class _MomentVideoState extends State<_MomentVideo> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) { if (mounted) setState(() => _ready = true); })
      ..setLooping(true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _ready
          ? AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  VideoPlayer(_controller),
                  _ControlsOverlay(controller: _controller),
                  VideoProgressIndicator(_controller, allowScrubbing: true),
                ],
              ),
            )
          : const CircularProgressIndicator(),
    );
  }
}

class _ControlsOverlay extends StatelessWidget {
  final VideoPlayerController controller;
  const _ControlsOverlay({required this.controller});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { controller.value.isPlaying ? controller.pause() : controller.play(); },
      child: Stack(
        children: <Widget>[
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: controller.value.isPlaying
                ? const SizedBox.shrink()
                : const Center(
                    child: Icon(Icons.play_arrow, color: Colors.white70, size: 64),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MomentAudio extends StatefulWidget {
  final String url;
  final String title;
  const _MomentAudio({required this.url, required this.title});

  @override
  State<_MomentAudio> createState() => _MomentAudioState();
}

class _MomentAudioState extends State<_MomentAudio> {
  final AudioPlayer _player = AudioPlayer();
  bool _ready = false;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.setUrl(widget.url).then((_) async {
      _duration = _player.duration ?? Duration.zero;
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 16)),
              const SizedBox(height: 16),
              // Waveform + Controls
              StreamBuilder<Duration>(
                stream: _player.positionStream,
                builder: (context, snap) {
                  final pos = snap.data ?? Duration.zero;
                  final dur = _duration.inMilliseconds > 0 ? _duration : (_player.duration ?? Duration.zero);
                  final progress = (dur.inMilliseconds > 0)
                      ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                      : 0.0;
                  return Column(
                    children: [
                      SizedBox(
                        height: 120,
                        child: CustomPaint(
                          painter: _WaveformPainter(progress: progress),
                          size: const Size(double.infinity, double.infinity),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.replay_10, color: Colors.white70),
                            onPressed: () async { final p = _player.position; await _player.seek(p - const Duration(seconds: 10)); },
                          ),
                          IconButton(
                            icon: Icon(_player.playing ? Icons.pause_circle_filled : Icons.play_circle_fill, color: AppColors.lightBlue, size: 48),
                            onPressed: () async { _player.playing ? await _player.pause() : await _player.play(); },
                          ),
                          IconButton(
                            icon: const Icon(Icons.forward_10, color: Colors.white70),
                            onPressed: () async { final p = _player.position; await _player.seek(p + const Duration(seconds: 10)); },
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress; // 0..1
  _WaveformPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final grad = const LinearGradient(
      colors: [Color(0xFFE91E63), AppColors.lightBlue, Color(0xFF00E5FF)],
    );
    final shader = grad.createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    final fgPaint = Paint()
      ..shader = shader
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final barWidth = 3.0;
    final spacing = 3.0;
    final totalBars = (size.width / (barWidth + spacing)).floor();
    final maxBar = size.height * 0.9;
    final minBar = size.height * 0.1;
    final rand = math.Random(12345);

    for (int i = 0; i < totalBars; i++) {
      final x = i * (barWidth + spacing) + barWidth / 2;
      final rnd = 0.2 + rand.nextDouble() * 0.8;
      final h = minBar + rnd * (maxBar - minBar);
      final y1 = (size.height - h) / 2;
      final y2 = y1 + h;
      final isProgress = (i / totalBars) <= progress;
      canvas.drawLine(Offset(x, y1), Offset(x, y2), isProgress ? fgPaint : bgPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) => old.progress != progress;
}

class _MomentDocument extends StatelessWidget {
  final String url; final String? filename;
  const _MomentDocument({required this.url, this.filename});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.description, size: 72, color: Colors.white70),
          const SizedBox(height: 12),
          Text(filename ?? 'Dokument', style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () async {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) { await launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank'); }
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Öffnen'),
          ),
        ],
      ),
    );
  }
}


