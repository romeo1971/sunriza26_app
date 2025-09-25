/// Video Player Widget für Live-Streaming
/// Stand: 04.09.2025 - Optimiert für Echtzeit-Video-Wiedergabe
library;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

class VideoPlayerWidget extends StatefulWidget {
  final VideoPlayerController controller;

  const VideoPlayerWidget({super.key, required this.controller});

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    super.dispose();
  }

  void _initializeChewie() {
    _chewieController?.dispose();
    // Verwende Theme erst hier (nicht in initState)
    final primary = Theme.of(context).colorScheme.primary;
    _chewieController = ChewieController(
      videoPlayerController: widget.controller,
      autoPlay: false,
      looping: false,
      allowFullScreen: false,
      allowMuting: false,
      showOptions: false,
      showControls: true,
      customControls: const _MinimalControls(), // eigene minimalen Controls
      materialProgressColors: ChewieProgressColors(
        playedColor: primary,
        handleColor: primary,
        backgroundColor: Colors.grey[300]!,
        bufferedColor: Colors.grey[200]!,
      ),
      placeholder: Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      ),
      autoInitialize: true,
      additionalOptions: (context) => [],
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initializeChewie();
  }

  @override
  void didUpdateWidget(covariant VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _initializeChewie();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_chewieController == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Chewie(controller: _chewieController!);
  }
}

// Minimalistische Chewie Controls: nur Play/Pause und Progressbar
class _MinimalControls extends StatelessWidget {
  const _MinimalControls();

  String _format(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final chewie = ChewieController.of(context);
    final ctrl = chewie.videoPlayerController;
    final theme = Theme.of(context);
    return Stack(
      children: [
        // Play/Pause zentral
        Align(
          alignment: Alignment.center,
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: ctrl,
            builder: (context, value, _) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  iconSize: 48,
                  color: Colors.white,
                  onPressed: () {
                    if (value.isPlaying) {
                      chewie.pause();
                    } else {
                      chewie.play();
                    }
                  },
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                ),
              );
            },
          ),
        ),
        // Fortschritt unten
        Positioned(
          left: 8,
          right: 8,
          bottom: 8,
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: ctrl,
            builder: (context, value, _) {
              return Row(
                children: [
                  Expanded(
                    child: VideoProgressIndicator(
                      ctrl,
                      allowScrubbing: true,
                      colors: VideoProgressColors(
                        playedColor: theme.colorScheme.primary,
                        bufferedColor: Colors.white30,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _format(value.position), // nur eine laufende Zeit
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
