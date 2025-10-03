/// Welcome Screen - Post-Login Startseite
/// Stand: 04.09.2025 - Moderne Startseite im Firebase/Apple Stil
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
// import 'ai_assistant_screen.dart';
import '../services/auth_service.dart';
import '../widgets/app_drawer.dart';
import '../services/localization_service.dart';

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

  static const List<String> _rotatingMessageKeys = [
    'welcome.rotate1',
    'welcome.rotate2',
    'welcome.rotate3',
  ];

  @override
  void initState() {
    super.initState();
    _rotationTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted) return;
      setState(() {
        _messageIndex = (_messageIndex + 1) % _rotatingMessageKeys.length;
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
    final size = MediaQuery.of(context).size;
    final vPad = size.height < 740 ? 24.0 : 80.0;
    final loc = context.watch<LocalizationService>();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: vPad),
      decoration: BoxDecoration(
        gradient:
            Theme.of(context).extension<AppGradients>()?.background
                as LinearGradient?,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
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
                              TextSpan(
                                text: loc.t('welcome.headlineAltSuffix'),
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
                              TextSpan(
                                text: loc.t('welcome.headlineDefaultSuffix'),
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
                    loc.t(_rotatingMessageKeys[_messageIndex]),
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
      ),
    );
  }

  // Obsolete Sektionen entfernt

  // Obsolete Helper entfernt

  /// Start Button
  Widget _buildStartButton(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    final btnW = math.min(320.0, w - 48.0);
    final btnH = h < 740 ? 60.0 : 72.0;
    return Container(
      width: btnW,
      height: btnH,
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
            Navigator.of(context).pushReplacementNamed('/home');
          },
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    loc.t('welcome.ctaPrimary'),
                    textAlign: TextAlign.center,
                    maxLines: 1,
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
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    loc.t('welcome.ctaSubtext'),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w300,
                      fontSize: 12,
                      height: 1.2,
                    ),
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
