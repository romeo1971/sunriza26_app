import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

class SonicVideoPage extends StatefulWidget {
  final File imageFile;
  final File audioFile;

  const SonicVideoPage({
    super.key,
    required this.imageFile,
    required this.audioFile,
  });

  @override
  State<SonicVideoPage> createState() => _SonicVideoPageState();
}

class _SonicVideoPageState extends State<SonicVideoPage> {
  VideoPlayerController? _controller;
  bool _loading = false;
  String backendUrl =
      "http://127.0.0.1:8000/generate"; // <--- Dein FastAPI-Server

  Future<void> _uploadAndGenerate() async {
    setState(() {
      _loading = true;
    });

    try {
      var request = http.MultipartRequest("POST", Uri.parse(backendUrl));
      request.files.add(
        await http.MultipartFile.fromPath("image", widget.imageFile.path),
      );
      request.files.add(
        await http.MultipartFile.fromPath("audio", widget.audioFile.path),
      );

      var response = await request.send();

      if (response.statusCode == 200) {
        // Video speichern
        final bytes = await response.stream.toBytes();
        final dir = await getTemporaryDirectory();
        final videoPath = "${dir.path}/sonic_result.mp4";
        final file = File(videoPath);
        await file.writeAsBytes(bytes);

        // Player starten
        _controller = VideoPlayerController.file(file)
          ..initialize().then((_) {
            setState(() {
              _loading = false;
              _controller!.play();
            });
          });
      } else {
        setState(() {
          _loading = false;
        });
        throw Exception("Fehler: ${response.statusCode}");
      }
    } catch (e) {
      setState(() {
        _loading = false;
      });
      debugPrint("Upload/Generate Fehler: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    _uploadAndGenerate();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sonic Video Result")),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : _controller != null && _controller!.value.isInitialized
            ? AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              )
            : const Text("Kein Video verfügbar"),
      ),
      floatingActionButton: _controller != null
          ? FloatingActionButton(
              onPressed: () {
                setState(() {
                  _controller!.value.isPlaying
                      ? _controller!.pause()
                      : _controller!.play();
                });
              },
              child: Icon(
                _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            )
          : null,
    );
  }
}
