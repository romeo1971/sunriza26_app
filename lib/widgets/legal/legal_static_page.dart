import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

class LegalStaticPage extends StatelessWidget {
  final String title;
  final String assetPath; // e.g. assets/legal/privacy.html

  const LegalStaticPage({super.key, required this.title, required this.assetPath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(assetPath),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final content = snap.data ?? '';
          if (content.isEmpty) {
            return Center(
              child: Text(
                'Keine Inhalte verfügbar',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 16),
              ),
            );
          }
          final text = _stripHtmlToText(content);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5),
            ),
          );
        },
      ),
    );
  }

  static String _stripHtmlToText(String html) {
    var s = html.replaceAll(RegExp(r'(?i)<br\s*/?>'), '\n');
    s = s.replaceAll(RegExp(r'(?i)</p>'), '\n\n');
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');
    return s.trim();
  }
}

class PrivacyPage extends LegalStaticPage {
  const PrivacyPage({super.key})
      : super(title: 'Datenschutz', assetPath: 'assets/legal/privacy.html');
}

class TermsPage extends LegalStaticPage {
  const TermsPage({super.key})
      : super(title: 'AGB', assetPath: 'assets/legal/terms.html');
}

class ImprintPage extends LegalStaticPage {
  const ImprintPage({super.key})
      : super(title: 'Impressum', assetPath: 'assets/legal/imprint.html');
}


