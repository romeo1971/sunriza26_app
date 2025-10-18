import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// LivePortrait Streaming Canvas
/// Empfängt Frames vom LivePortrait WebSocket Server
class LivePortraitCanvas extends StatefulWidget {
  final String wsUrl;
  final Uint8List heroImageBytes;
  final VoidCallback? onReady;
  final VoidCallback? onDone;
  final VoidCallback? onFirstFrame; // signalisiere ersten Frame

  const LivePortraitCanvas({
    super.key,
    required this.wsUrl,
    required this.heroImageBytes,
    this.onReady,
    this.onDone,
    this.onFirstFrame,
  });

  @override
  State<LivePortraitCanvas> createState() => LivePortraitCanvasState();
}

class LivePortraitCanvasState extends State<LivePortraitCanvas> {
  WebSocketChannel? _channel;
  ui.Image? _currentFrame;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(widget.wsUrl));

      // ignore: avoid_print
      print('🎭 LivePortrait connecting: ${widget.wsUrl}');

      // Stream-Listener
      _channel!.stream.listen(
        (message) {
          _handleMessage(message);
        },
        onDone: () {
          // ignore: avoid_print
          print('🔌 LivePortrait WS closed');
          widget.onDone?.call();
        },
        onError: (e) {
          // ignore: avoid_print
          print('❌ LivePortrait WS error: $e');
        },
      );

      // Send Hero Image
      final heroB64 = base64Encode(widget.heroImageBytes);
      _channel!.sink.add(jsonEncode({'type': 'init', 'hero_image': heroB64}));
    } catch (e) {
      // ignore: avoid_print
      print('❌ LivePortrait connect failed: $e');
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      final type = data['type'];

      switch (type) {
        case 'ready':
          // ignore: avoid_print
          print('✅ LivePortrait ready');
          setState(() => _isReady = true);
          widget.onReady?.call();
          break;

        case 'frame':
          _handleFrame(data);
          break;

        case 'done':
          // ignore: avoid_print
          print('✅ LivePortrait done');
          widget.onDone?.call();
          break;

        case 'error':
          // ignore: avoid_print
          print('❌ LivePortrait error: ${data['message']}');
          break;
      }
    } catch (e) {
      // ignore: avoid_print
      print('❌ LivePortrait message parse error: $e');
    }
  }

  Future<void> _handleFrame(Map<String, dynamic> data) async {
    try {
      final frameB64 = data['data'] as String;
      final frameBytes = base64Decode(frameB64);

      // Decode JPEG → ui.Image
      final codec = await ui.instantiateImageCodec(frameBytes);
      final frame = await codec.getNextFrame();

      if (mounted) {
        setState(() {
          _currentFrame = frame.image;
        });
        if (!_isReady && widget.onReady != null) {
          // falls Server kein ready sendet, beim ersten Frame als ready werten
          _isReady = true;
          widget.onReady?.call();
        }
        widget.onFirstFrame?.call();
      }
    } catch (e) {
      // ignore: avoid_print
      print('❌ Frame decode error: $e');
    }
  }

  void sendAudioChunk(Uint8List audioBytes, int ptsMs) {
    if (_channel == null || !_isReady) return;

    _channel!.sink.add(
      jsonEncode({
        'type': 'audio',
        'data': base64Encode(audioBytes),
        'pts_ms': ptsMs,
      }),
    );
  }

  // Optional: Viseme direkt senden (falls Server das unterstützt)
  void sendViseme(String viseme, int ptsMs, int durationMs) {
    if (_channel == null || !_isReady) return;
    _channel!.sink.add(
      jsonEncode({
        'type': 'viseme',
        'value': viseme,
        'pts_ms': ptsMs,
        'duration_ms': durationMs,
      }),
    );
  }

  void stop() {
    if (_channel == null) return;
    _channel!.sink.add(jsonEncode({'type': 'stop'}));
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _currentFrame?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentFrame == null) {
      return Container(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white30)),
      );
    }

    return CustomPaint(
      painter: _FramePainter(_currentFrame!),
      size: Size.infinite,
    );
  }
}

class _FramePainter extends CustomPainter {
  final ui.Image frame;

  _FramePainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high;

    // Frame auf Canvas zeichnen (fit: cover)
    final srcRect = Rect.fromLTWH(
      0,
      0,
      frame.width.toDouble(),
      frame.height.toDouble(),
    );

    final dstRect = Rect.fromLTWH(0, 0, size.width, size.height);

    canvas.drawImageRect(frame, srcRect, dstRect, paint);
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) {
    return oldDelegate.frame != frame;
  }
}
