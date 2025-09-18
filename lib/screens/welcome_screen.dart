/// Welcome Screen - Post-Login Startseite
/// Stand: 04.09.2025 - Moderne Startseite im Firebase/Apple Stil
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
// import 'ai_assistant_screen.dart';
import '../services/auth_service.dart';
import '../widgets/app_drawer.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  Timer? _rotationTimer;
  int _messageIndex = 0;
  bool _headlineAlt = false;
  Timer? _headlineTimer;

  static const List<String> _rotatingMessages = [
    'Menschen verschwinden nicht.\nSie leben weiter – in unseren Erinnerungen.\nUnd in der Art, wie wir sie erzählen.',
    'Erstelle Deinen eigenen unsterblichen Avatar.\nIn nur 5 Minuten berührt Dein Herz die Ewigkeit - heute, morgen und für immer.',
    'Alles, was es braucht, sind ein Bild oder Video von Dir, eine kurze Audioaufnahme Deiner Stimme und ein paar Erinnerungen, die Dir wichtig sind.',
  ];

  @override
  void initState() {
    super.initState();
    _rotationTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted) return;
      setState(() {
        _messageIndex = (_messageIndex + 1) % _rotatingMessages.length;
      });
    });
    _headlineTimer = Timer.periodic(const Duration(seconds: 21), (_) {
      if (!mounted) return;
      setState(() {
        _headlineAlt = !_headlineAlt;
      });
    });
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    _headlineTimer?.cancel();
    super.dispose();
  }

  /// Wort mit Farbverlauf (Magenta→Orange→Grün), nutzt aktuelle Headline‑TextStyle
  Widget _gradientWord(String word, TextStyle? base) {
    final style = (base ?? const TextStyle()).copyWith(
      foreground: Paint()
        ..shader = const LinearGradient(
          colors: [
            AppColors.accentGreenDark, // dunkles Grün
            AppColors.greenBlue, // Grün‑Blau
            AppColors.lightBlue, // helles Blau
          ],
        ).createShader(const Rect.fromLTWH(0, 0, 800, 120)),
    );
    return Text(word, style: style);
  }

  double _headlineSize(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w >= 1200) return 72; // Desktop groß
    if (w >= 900) return 56; // Desktop/Tablet
    if (w >= 600) return 40; // Tablet
    return 34; // Phone
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<AuthService>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: const [],
      ),
      body: SelectionArea(
        child: Column(
          children: [
            _buildTopQuoteBar(context),
            Expanded(child: _buildHeroSection(context)),
          ],
        ),
      ),
    );
  }

  /// Obere Zitatleiste
  Widget _buildTopQuoteBar(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  /// Hero Section mit emotionaler Botschaft
  Widget _buildHeroSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      decoration: BoxDecoration(
        gradient:
            Theme.of(context).extension<AppGradients>()?.background
                as LinearGradient?,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Hauptüberschrift
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 450),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: _headlineAlt
                    ? RichText(
                        key: const ValueKey('headline_alt'),
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: _headlineSize(context),
                            height: 1.1,
                            letterSpacing: -0.2,
                            fontWeight: FontWeight.w300,
                          ),
                          children: [
                            WidgetSpan(
                              alignment: PlaceholderAlignment.baseline,
                              baseline: TextBaseline.alphabetic,
                              child: _gradientWord(
                                'Sunriza',
                                GoogleFonts.plusJakartaSans(
                                  fontSize: _headlineSize(context),
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                            ),
                            const TextSpan(
                              text:
                                  '\nDeine Geschichten, Gedanken und Werte bleiben',
                            ),
                          ],
                        ),
                      )
                    : RichText(
                        key: const ValueKey('headline_default'),
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: _headlineSize(context),
                            height: 1.1,
                            letterSpacing: -0.2,
                            fontWeight: FontWeight.w300,
                          ),
                          children: [
                            WidgetSpan(
                              alignment: PlaceholderAlignment.baseline,
                              baseline: TextBaseline.alphabetic,
                              child: _gradientWord(
                                'Sunriza',
                                GoogleFonts.plusJakartaSans(
                                  fontSize: _headlineSize(context),
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                            ),
                            const TextSpan(
                              text:
                                  '\nGeschichten für die Ewigkeit – erzählt von Dir',
                            ),
                          ],
                        ),
                      ),
              ),

              const SizedBox(height: 24),

              // Subheadline 3‑Texte‑Rotation (7s)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 450),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: Text(
                  _rotatingMessages[_messageIndex],
                  key: ValueKey<int>(_messageIndex),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFFCFE1DA),
                    height: 1.3,
                    fontSize: 14,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),

              const SizedBox(height: 48),

              // CTA Button
              _buildStartButton(context),
            ],
          ),
        ),
      ),
    );
  }

  // Obsolete Sektionen entfernt

  // Obsolete Helper entfernt

  /// Start Button
  Widget _buildStartButton(BuildContext context) {
    return Container(
      width: 320,
      height: 72,
      decoration: BoxDecoration(
        gradient: Theme.of(context).extension<AppGradients>()?.buttonPrimary,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.accentLightGreen.withValues(alpha: 0.28),
            blurRadius: 18,
            spreadRadius: 1,
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Jetzt kostenlos starten',
                  textAlign: TextAlign.center,
                  style:
                      Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 24,
                        letterSpacing: 0.1,
                      ) ??
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 24,
                      ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Sieht so aus wie Du, spricht und erzählt wie Du',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w300,
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
