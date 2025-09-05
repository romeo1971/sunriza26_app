/// Welcome Screen - Post-Login Startseite
/// Stand: 04.09.2025 - Moderne Startseite im Firebase/Apple Stil
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// import 'ai_assistant_screen.dart';
import '../services/firebase_diagnostics.dart';
import '../services/auth_service.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle, color: Color(0xFF00FF94)),
            onSelected: (value) async {
              if (value == 'logout') {
                await authService.signOut();
              } else if (value == 'diag') {
                final res = await FirebaseDiagnostics.runAll();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Diag: ' + res.toString())),
                  );
                }
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    const Icon(Icons.person, color: Color(0xFF00FF94)),
                    const SizedBox(width: 8),
                    Text(authService.userEmail ?? 'User'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'diag',
                child: Row(
                  children: [
                    Icon(Icons.health_and_safety, color: Color(0xFF00FF94)),
                    SizedBox(width: 8),
                    Text('Firebase Test'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Abmelden', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Hero Section
            _buildHeroSection(context),

            // Feature Highlights
            _buildFeatureHighlights(context),

            // RAG Explanation
            _buildRAGExplanation(context),

            // Emotional Closure
            _buildEmotionalClosure(context),
          ],
        ),
      ),
    );
  }

  /// Hero Section mit emotionaler Botschaft
  Widget _buildHeroSection(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Hauptüberschrift
          Text(
            'Erwecke Erinnerungen\nzum Leben.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              height: 1.1,
              fontSize: 48,
            ),
          ),

          const SizedBox(height: 32),

          // Subheadline
          Text(
            'Lade Bilder, Videos und Gedanken einer geliebten Person hoch –\nerschaffe einen KI-Avatar, der ihre Stimme trägt.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: const Color(0xFFCCCCCC),
              fontWeight: FontWeight.w400,
              height: 1.4,
              fontSize: 20,
            ),
          ),

          const SizedBox(height: 48),

          // CTA Button
          _buildStartButton(context),
        ],
      ),
    );
  }

  /// Feature Highlights
  Widget _buildFeatureHighlights(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      child: Column(
        children: [
          // Überschrift
          Text(
            'Deine Erinnerungen – intelligent bewahrt.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 32,
            ),
          ),

          const SizedBox(height: 16),

          // Beschreibung
          Text(
            'Alles, was du hochlädst, wird strukturiert abgelegt und analysiert.\nSo entsteht ein digitaler Zwilling, der nicht nur antwortet – sondern wirklich verstanden wird.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: const Color(0xFFCCCCCC),
              height: 1.5,
              fontSize: 18,
            ),
          ),

          const SizedBox(height: 48),

          // Feature Cards
          Row(
            children: [
              Expanded(
                child: _buildFeatureCard(
                  context,
                  Icons.photo_library,
                  'Bilder & Videos',
                  'Archiviere besondere Momente visuell.',
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _buildFeatureCard(
                  context,
                  Icons.edit_note,
                  'Gedanken & Meinungen',
                  'Halte Weltansichten und Geschichten fest.',
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _buildFeatureCard(
                  context,
                  Icons.psychology,
                  'Persönlichkeit bewahren',
                  'Gib dem Avatar eine echte Grundlage.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// RAG System Erklärung
  Widget _buildRAGExplanation(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      child: Column(
        children: [
          // Überschrift
          Text(
            'Was im Hintergrund passiert:',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 32,
            ),
          ),

          const SizedBox(height: 32),

          // Erklärung
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF333333), width: 1),
            ),
            child: Column(
              children: [
                // RAG Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FF94).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Color(0xFF00FF94),
                    size: 40,
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  'RAG-System (Retrieval-Augmented Generation)',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: const Color(0xFF00FF94),
                    fontWeight: FontWeight.w600,
                    fontSize: 24,
                  ),
                ),

                const SizedBox(height: 16),

                Text(
                  'Alle Inhalte werden durch ein intelligentes System analysiert und gespeichert.\nDiese Technologie ermöglicht es der KI, später authentisch auf Basis der hochgeladenen Daten zu antworten – statt generischer KI-Antworten entsteht ein echter Dialog, der sich vertraut anfühlt.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFFCCCCCC),
                    height: 1.5,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Emotionale Abschluss-Sektion
  Widget _buildEmotionalClosure(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      child: Column(
        children: [
          // Zitat
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF333333), width: 1),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.format_quote,
                  color: Color(0xFF00FF94),
                  size: 48,
                ),

                const SizedBox(height: 24),

                Text(
                  '"Menschen verschwinden nicht. Sie leben weiter – in unseren Erinnerungen. Und in der Art, wie wir sie erzählen."',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w400,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                    fontSize: 24,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 48),

          // Finaler CTA
          _buildStartButton(context),

          const SizedBox(height: 32),

          // Mini Features
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 24,
            runSpacing: 12,
            children: [
              _buildMiniFeature(
                context,
                Icons.security,
                'Sichere Cloud-Speicherung',
              ),
              _buildMiniFeature(
                context,
                Icons.psychology,
                'KI-gestützte Analyse',
              ),
              _buildMiniFeature(
                context,
                Icons.privacy_tip,
                'Datenschutz & Kontrolle',
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Feature Card
  Widget _buildFeatureCard(
    BuildContext context,
    IconData icon,
    String title,
    String description,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF333333), width: 1),
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFF00FF94).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Icon(icon, color: const Color(0xFF00FF94), size: 30),
          ),

          const SizedBox(height: 16),

          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            description,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFFCCCCCC),
              height: 1.4,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// Mini Feature
  Widget _buildMiniFeature(BuildContext context, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xFF00FF94), size: 16),
        const SizedBox(width: 8),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: const Color(0xFFCCCCCC),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  /// Start Button
  Widget _buildStartButton(BuildContext context) {
    return Container(
      width: 200,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00FF94), Color(0xFF00CC7A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00FF94).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () {
            Navigator.of(context).pushReplacementNamed('/avatar-list');
          },
          child: Center(
            child: Text(
              'Jetzt starten',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.black,
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
