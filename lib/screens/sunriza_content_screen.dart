import 'package:flutter/material.dart';
import '../widgets/youtube_player_web.dart';

/// Screen mit allen Inhalten von sunriza.com
class SunrizaContentScreen extends StatefulWidget {
  const SunrizaContentScreen({super.key});

  @override
  State<SunrizaContentScreen> createState() => _SunrizaContentScreenState();
}

class _SunrizaContentScreenState extends State<SunrizaContentScreen> {
  // YouTube Video ID für "Sunriza - Die Zukunft der KI"
  final String _videoId =
      'dQw4w9WgXcQ'; // Rick Astley - Never Gonna Give You Up (Demo)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'Sunriza Content',
          style: TextStyle(
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
            // Hero Section
            _buildHeroSection(),

            // YouTube Video Section
            _buildVideoSection(),

            // Screenshots Gallery
            _buildScreenshotsGallery(),

            // Text Content
            _buildTextContent(),

            // Features Section
            _buildFeaturesSection(),

            // Call to Action
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
          // Logo/Title
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
          const Text(
            'Die Zukunft der KI',
            style: TextStyle(
              fontSize: 24,
              color: Colors.white,
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 32),
          // Main CTA Button
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00FF94),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Jetzt starten',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Video-Demo',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00FF94),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 300,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF00FF94), width: 2),
            ),
            child: YouTubePlayerWeb(
              videoId: _videoId,
              width: double.infinity,
              height: 300,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScreenshotsGallery() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Screenshots',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00FF94),
            ),
          ),
          const SizedBox(height: 16),
          // Screenshot Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const ClampingScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 16 / 9,
            ),
            itemCount: 6, // Anzahl der Screenshots
            itemBuilder: (context, index) {
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF00FF94), width: 1),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    'assets/screenshots/screenshot_${index + 1}.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: const Color(0xFF1A1A1A),
                        child: const Center(
                          child: Icon(
                            Icons.image,
                            color: Color(0xFF00FF94),
                            size: 48,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTextContent() {
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
          const Text(
            'Sunriza ist die Zukunft der Künstlichen Intelligenz. Mit unserer innovativen Technologie schaffen wir eine neue Ära der KI-Interaktion, die menschlicher, intuitiver und leistungsstarker ist als je zuvor.',
            style: TextStyle(fontSize: 16, color: Colors.white, height: 1.6),
          ),
          const SizedBox(height: 24),
          const Text(
            'Unsere Mission',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00FF94),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Wir entwickeln KI-Systeme, die nicht nur intelligent sind, sondern auch emotional verstehen und auf natürliche Weise mit Menschen interagieren können. Unser Ziel ist es, die Brücke zwischen Mensch und Maschine zu schließen.',
            style: TextStyle(fontSize: 16, color: Colors.white, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturesSection() {
    final features = [
      {
        'title': 'KI-Avatar',
        'description':
            'Erstelle deinen persönlichen KI-Avatar basierend auf deinen Erinnerungen und Erfahrungen.',
        'icon': Icons.person,
      },
      {
        'title': 'RAG-System',
        'description':
            'Unser Retrieval-Augmented Generation System sorgt für kontextuelle und relevante Antworten.',
        'icon': Icons.psychology,
      },
      {
        'title': 'Live-Streaming',
        'description':
            'Echtzeit-Video-Streaming mit lippensynchroner KI-Kommunikation.',
        'icon': Icons.videocam,
      },
      {
        'title': 'Emotionale KI',
        'description': 'KI, die Emotionen versteht und entsprechend reagiert.',
        'icon': Icons.favorite,
      },
    ];

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
          ...features.map((feature) => _buildFeatureCard(feature)),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(Map<String, dynamic> feature) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00FF94), width: 1),
      ),
      child: Row(
        children: [
          Icon(
            feature['icon'] as IconData,
            color: const Color(0xFF00FF94),
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feature['title'] as String,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  feature['description'] as String,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00FF94),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Jetzt starten',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
