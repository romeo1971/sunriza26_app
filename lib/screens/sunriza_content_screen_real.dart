import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../widgets/youtube_player_web.dart';

/// Screen mit ECHTEN Inhalten von sunriza.com
class SunrizaContentScreenReal extends StatefulWidget {
  const SunrizaContentScreenReal({super.key});

  @override
  State<SunrizaContentScreenReal> createState() =>
      _SunrizaContentScreenRealState();
}

class _SunrizaContentScreenRealState extends State<SunrizaContentScreenReal> {
  Map<String, dynamic>? sunrizaData;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadSunrizaContent();
  }

  Future<void> loadSunrizaContent() async {
    try {
      final String response = await rootBundle.loadString(
        'assets/scraped/data/sunriza_content.json',
      );
      final data = json.decode(response);
      setState(() {
        sunrizaData = data;
        isLoading = false;
      });
    } catch (e) {
      print('Fehler beim Laden der Sunriza Daten: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF00FF94)),
        ),
      );
    }

    if (sunrizaData == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'Fehler beim Laden der Inhalte',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          sunrizaData!['title'] ?? 'Sunriza',
          style: const TextStyle(
            color: Color(0xFF00FF94),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeroSection(),
            _buildVideoSection(),
            _buildFeaturesSection(),
            _buildTextContentSection(),
            _buildCallToAction(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1A1A), Colors.black],
        ),
      ),
      child: Column(
        children: [
          const Text(
            'SUNRIZA',
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00FF94),
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            sunrizaData!['description'] ?? 'Die Zukunft der KI',
            style: const TextStyle(
              fontSize: 18,
              color: Colors.white,
              fontWeight: FontWeight.w300,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {
              // Navigate to AI Assistant
              Navigator.of(context).pushReplacementNamed('/ai-assistant');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00FF94),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'KI-Assistent starten',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoSection() {
    final videos = sunrizaData!['videos'] as List<dynamic>? ?? [];

    if (videos.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Video-Demos',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00FF94),
            ),
          ),
          const SizedBox(height: 16),
          ...videos.map((video) => _buildVideoCard(video)),
        ],
      ),
    );
  }

  Widget _buildVideoCard(Map<String, dynamic> video) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            video['title'] ?? 'Video',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          if (video['description'] != null)
            Text(
              video['description'],
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          const SizedBox(height: 12),
          Container(
            height: 250,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF00FF94), width: 2),
            ),
            child: YouTubePlayerWeb(
              videoId: video['video_id'] ?? '',
              width: double.infinity,
              height: 250,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturesSection() {
    final features = sunrizaData!['features'] as List<dynamic>? ?? [];

    if (features.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Features',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00FF94),
            ),
          ),
          const SizedBox(height: 24),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.0,
            ),
            itemCount: features.length,
            itemBuilder: (context, index) {
              final feature = features[index];
              return _buildFeatureCard(feature);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(Map<String, dynamic> feature) {
    IconData iconData;
    switch (feature['icon']) {
      case 'person':
        iconData = Icons.person;
        break;
      case 'psychology':
        iconData = Icons.psychology;
        break;
      case 'videocam':
        iconData = Icons.videocam;
        break;
      case 'favorite':
        iconData = Icons.favorite;
        break;
      case 'record_voice_over':
        iconData = Icons.record_voice_over;
        break;
      case 'tune':
        iconData = Icons.tune;
        break;
      default:
        iconData = Icons.star;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00FF94), width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(iconData, color: const Color(0xFF00FF94), size: 40),
          const SizedBox(height: 12),
          Text(
            feature['title'] ?? '',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            feature['description'] ?? '',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildTextContentSection() {
    final texts = sunrizaData!['texts'] as List<dynamic>? ?? [];

    if (texts.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Über Sunriza',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00FF94),
            ),
          ),
          const SizedBox(height: 16),
          ...texts.map((textItem) => _buildTextItem(textItem)),
        ],
      ),
    );
  }

  Widget _buildTextItem(Map<String, dynamic> textItem) {
    final type = textItem['type'] ?? 'p';
    final content = textItem['content'] ?? '';

    TextStyle style;
    EdgeInsets margin;

    switch (type) {
      case 'h1':
        style = const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: Color(0xFF00FF94),
        );
        margin = const EdgeInsets.only(bottom: 16, top: 24);
        break;
      case 'h2':
        style = const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Color(0xFF00FF94),
        );
        margin = const EdgeInsets.only(bottom: 12, top: 20);
        break;
      case 'h3':
        style = const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        );
        margin = const EdgeInsets.only(bottom: 8, top: 16);
        break;
      default: // 'p'
        style = const TextStyle(fontSize: 16, color: Colors.white, height: 1.6);
        margin = const EdgeInsets.only(bottom: 16);
    }

    return Container(
      margin: margin,
      child: Text(content, style: style),
    );
  }

  Widget _buildCallToAction() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black, Color(0xFF1A1A1A)],
        ),
      ),
      child: Column(
        children: [
          const Text(
            'Bereit für die Zukunft?',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Starte jetzt deine Reise mit Sunriza und erlebe die Zukunft der KI.',
            style: TextStyle(fontSize: 18, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: () {
                  // Navigate to AI Assistant
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF94),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'KI-Assistent',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              OutlinedButton(
                onPressed: () {
                  // Show more info
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF00FF94),
                  side: const BorderSide(color: Color(0xFF00FF94)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Mehr erfahren',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
