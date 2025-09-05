import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// YouTube Player für Web (da youtube_player_flutter nicht für Web optimiert ist)
class YouTubePlayerWeb extends StatelessWidget {
  final String videoId;
  final double? width;
  final double? height;

  const YouTubePlayerWeb({
    super.key,
    required this.videoId,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? double.infinity,
      height: height ?? 300,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00FF94), width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _buildYouTubePlayer(),
      ),
    );
  }

  Widget _buildYouTubePlayer() {
    if (kIsWeb) {
      // Für Web: Zeige YouTube Link mit Preview
      return GestureDetector(
        onTap: () {
          // Öffne YouTube Video in neuem Tab
          if (kIsWeb) {
            // Web-spezifischer Code würde hier stehen
          }
        },
        child: Container(
          color: const Color(0xFF1A1A1A),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.play_circle_filled,
                color: Color(0xFF00FF94),
                size: 64,
              ),
              const SizedBox(height: 16),
              const Text(
                'YouTube Video',
                style: TextStyle(
                  color: Color(0xFF00FF94),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Video ID: $videoId',
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 16),
              const Text(
                'Klicken zum Abspielen',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    } else {
      // Für Mobile: Zeige Platzhalter
      return Container(
        color: const Color(0xFF1A1A1A),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.play_circle_filled,
                color: Color(0xFF00FF94),
                size: 64,
              ),
              SizedBox(height: 16),
              Text(
                'YouTube Player',
                style: TextStyle(
                  color: Color(0xFF00FF94),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Mobile Version',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }
  }
}
