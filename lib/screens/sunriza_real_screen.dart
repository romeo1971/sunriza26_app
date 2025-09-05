import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

class SunrizaRealScreen extends StatefulWidget {
  const SunrizaRealScreen({super.key});

  @override
  State<SunrizaRealScreen> createState() => _SunrizaRealScreenState();
}

class _SunrizaRealScreenState extends State<SunrizaRealScreen> {
  Map<String, dynamic>? sunrizaData;
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    loadSunrizaContent();
  }

  Future<void> loadSunrizaContent() async {
    try {
      final String response = await rootBundle.loadString(
        'assets/sunriza_complete/complete_sunriza_content.json',
      );
      final data = json.decode(response);
      if (mounted) {
        setState(() {
          sunrizaData = data;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = 'Fehler beim Laden der Inhalte: $e';
          isLoading = false;
        });
      }
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

    if (errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            errorMessage!,
            style: const TextStyle(color: Colors.red, fontSize: 16),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'Sunriza.com - Original',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mobile Layout wie www.sunriza.com
            _buildHeroSection(),
            const SizedBox(height: 16),
            _buildVideoSection(),
            const SizedBox(height: 16),
            _buildImagesSection(),
            const SizedBox(height: 16),
            _buildFeaturesSection(),
            const SizedBox(height: 16),
            _buildTextContentSection(),
            const SizedBox(height: 16),
            _buildTextFilesSection(),
            const SizedBox(height: 16),
            _buildCallToActionSection(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroSection() {
    final hero = sunrizaData!['hero'] as Map<String, dynamic>;
    return Container(
      height: 300, // Mobil-optimierte Höhe
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage(hero['background_image']),
          fit: BoxFit.cover,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.3),
              Colors.black.withOpacity(0.7),
            ],
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(
              hero['logo'],
              height: 60, // Kleineres Logo für mobil
              width: 150,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 12),
            Text(
              hero['title'],
              style: const TextStyle(
                fontSize: 32, // Kleinere Schrift für mobil
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              hero['subtitle'],
              style: const TextStyle(
                fontSize: 16, // Kleinere Schrift für mobil
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                hero['description'],
                style: const TextStyle(fontSize: 14, color: Colors.white),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagesSection() {
    final images = sunrizaData!['images'] as List<dynamic>? ?? [];

    if (images.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Galerie - Echte Sunriza.com Bilder',
            style: TextStyle(
              fontSize: 20, // Kleinere Überschrift für mobil
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 1, // Mobile: eine Spalte wie auf sunriza.com
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 2.5, // Breiteres Format für mobile
            ),
            itemCount: images.length,
            itemBuilder: (context, index) {
              final image = images[index];
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF00FF94), width: 2),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(10),
                        ),
                        child: Image.asset(
                          image['path'],
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey[800],
                              child: const Center(
                                child: Icon(
                                  Icons.image_not_supported,
                                  color: Colors.white,
                                  size: 40,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          Text(
                            image['title'],
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            image['description'],
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildVideoSection() {
    final videos = sunrizaData!['videos'] as List<dynamic>? ?? [];

    if (videos.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Videos - Echte Sunriza.com Videos',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: videos.length,
            itemBuilder: (context, index) {
              final video = videos[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () async {
                        if (video['type'] == 'youtube') {
                          final url = Uri.parse(
                            'https://www.youtube.com/watch?v=${video['id']}',
                          );
                          if (await canLaunchUrl(url)) {
                            await launchUrl(
                              url,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        } else if (video['type'] == 'local') {
                          // Für lokale Videos - könnte später implementiert werden
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Lokales Video - Feature kommt bald!',
                              ),
                            ),
                          );
                        }
                      },
                      child: Container(
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF00FF94),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                video['type'] == 'youtube'
                                    ? Icons.play_circle_fill
                                    : Icons.videocam,
                                size: 60,
                                color: Colors.white.withOpacity(0.8),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                video['type'] == 'youtube'
                                    ? 'YouTube Video'
                                    : 'Lokales Video',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      video['title'],
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      video['description'],
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturesSection() {
    final features = sunrizaData!['features'] as List<dynamic>? ?? [];

    if (features.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Spirituelle Features',
            style: TextStyle(
              fontSize: 20, // Kleinere Überschrift für mobil
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, // Bleibe bei 2 Spalten für Features
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.0, // Quadratisches Format
            ),
            itemCount: features.length,
            itemBuilder: (context, index) {
              final feature = features[index];
              IconData iconData;
              switch (feature['icon']) {
                case 'self_improvement':
                  iconData = Icons.self_improvement;
                  break;
                case 'psychology':
                  iconData = Icons.psychology;
                  break;
                case 'favorite':
                  iconData = Icons.favorite;
                  break;
                case 'wb_sunny':
                  iconData = Icons.wb_sunny;
                  break;
                case 'auto_awesome':
                  iconData = Icons.auto_awesome;
                  break;
                case 'spa':
                  iconData = Icons.spa;
                  break;
                default:
                  iconData = Icons.help_outline;
              }
              return Container(
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF00FF94), width: 1),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(iconData, color: const Color(0xFF00FF94), size: 40),
                    const SizedBox(height: 12),
                    Text(
                      feature['title'],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      feature['description'],
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTextContentSection() {
    final texts = sunrizaData!['texts'] as List<dynamic>? ?? [];

    if (texts.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Über Sunriza.com',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          ...texts.map((textBlock) {
            String type = textBlock['type'];
            String content = textBlock['content'];
            TextStyle style;
            EdgeInsets margin;

            switch (type) {
              case 'h1':
                style = const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                );
                margin = const EdgeInsets.only(bottom: 20);
                break;
              case 'h2':
                style = const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                );
                margin = const EdgeInsets.only(bottom: 16);
                break;
              case 'h3':
                style = const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                );
                margin = const EdgeInsets.only(bottom: 12);
                break;
              default: // 'p'
                style = const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  height: 1.6,
                );
                margin = const EdgeInsets.only(bottom: 16);
            }

            return Container(
              margin: margin,
              child: Text(content, style: style),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCallToActionSection() {
    final callToAction =
        sunrizaData!['call_to_action'] as Map<String, dynamic>?;

    if (callToAction == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [Colors.black, const Color(0xFF00FF94).withOpacity(0.2)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Bereit für Ihre spirituelle Reise?',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Entdecken Sie die Kraft der digitalen Spiritualität mit Sunriza!',
            style: const TextStyle(fontSize: 16, color: Colors.white70),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () {
                  // Handle primary action
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
                child: Text(
                  callToAction['primary_button'],
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              OutlinedButton(
                onPressed: () {
                  // Handle secondary action
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
                child: Text(
                  callToAction['secondary_button'],
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextFilesSection() {
    final textFiles = sunrizaData!['text_files'] as List<dynamic>? ?? [];

    if (textFiles.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Alle Sunriza.com Textinhalte',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 2.5,
            ),
            itemCount: textFiles.length,
            itemBuilder: (context, index) {
              final textFile = textFiles[index] as String;
              final fileName = textFile.split('/').last.replaceAll('.txt', '');
              final displayName = fileName
                  .replaceAll('text_', '')
                  .replaceAll('_', ' ')
                  .split(' ')
                  .map(
                    (word) => word.isNotEmpty
                        ? word[0].toUpperCase() + word.substring(1)
                        : word,
                  )
                  .join(' ');

              return GestureDetector(
                onTap: () async {
                  try {
                    final content = await rootBundle.loadString(textFile);
                    if (mounted) {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: Colors.grey[900],
                          title: Text(
                            displayName,
                            style: const TextStyle(color: Colors.white),
                          ),
                          content: SingleChildScrollView(
                            child: Text(
                              content,
                              style: const TextStyle(
                                color: Colors.white70,
                                height: 1.5,
                              ),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text(
                                'Schließen',
                                style: TextStyle(color: Color(0xFF00FF94)),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Fehler beim Laden: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF00FF94),
                      width: 1,
                    ),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.description,
                        color: Color(0xFF00FF94),
                        size: 24,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
