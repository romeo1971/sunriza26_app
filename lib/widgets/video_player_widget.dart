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
      autoPlay: false, // Kein automatisches Abspielen – verhindert Doppel-Start
      looping: false,
      allowFullScreen: true,
      allowMuting: true,
      showOptions: false, // verhindert überbreite Options-Controls
      showControls: false, // Inline: keine Controls → kein Overflow
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
