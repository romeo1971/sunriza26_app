import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../services/language_service.dart';
import 'package:provider/provider.dart';
import '../services/localization_service.dart';

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  String? _pendingLang;

  // Übersetzte Bezeichnungen der Sprachen je UI‑Sprache
  static const Map<String, String> _deNames = {
    'ar': 'Arabisch',
    'bn': 'Bangla',
    'cs': 'Tschechisch',
    'da': 'Dänisch',
    'de': 'Deutsch',
    'el': 'Griechisch',
    'en': 'Englisch',
    'es': 'Spanisch',
    'fa': 'Persisch',
    'fi': 'Finnisch',
    'fr': 'Französisch',
    'hi': 'Hindi',
    'hu': 'Ungarisch',
    'id': 'Indonesisch',
    'it': 'Italienisch',
    'he': 'Hebräisch',
    'ja': 'Japanisch',
    'ko': 'Koreanisch',
    'mr': 'Marathi',
    'ms': 'Malaiisch',
    'nl': 'Niederländisch',
    'no': 'Norwegisch',
    'pa': 'Punjabi',
    'pl': 'Polnisch',
    'pt': 'Portugiesisch',
    'ro': 'Rumänisch',
    'ru': 'Russisch',
    'sv': 'Schwedisch',
    'te': 'Telugu',
    'th': 'Thai',
    'tl': 'Tagalog',
    'tr': 'Türkisch',
    'uk': 'Ukrainisch',
    'vi': 'Vietnamesisch',
    'zh-Hans': 'Chinesisch (vereinfacht)',
    'zh-Hant': 'Chinesisch (traditionell)',
  };

  static const Map<String, String> _enNames = {
    'ar': 'Arabic',
    'bn': 'Bangla',
    'cs': 'Czech',
    'da': 'Danish',
    'de': 'German',
    'el': 'Greek',
    'en': 'English',
    'es': 'Spanish',
    'fa': 'Persian',
    'fi': 'Finnish',
    'fr': 'French',
    'hi': 'Hindi',
    'hu': 'Hungarian',
    'id': 'Indonesian',
    'it': 'Italian',
    'he': 'Hebrew',
    'ja': 'Japanese',
    'ko': 'Korean',
    'mr': 'Marathi',
    'ms': 'Malay',
    'nl': 'Dutch',
    'no': 'Norwegian',
    'pa': 'Punjabi',
    'pl': 'Polish',
    'pt': 'Portuguese',
    'ro': 'Romanian',
    'ru': 'Russian',
    'sv': 'Swedish',
    'te': 'Telugu',
    'th': 'Thai',
    'tl': 'Tagalog',
    'tr': 'Turkish',
    'uk': 'Ukrainian',
    'vi': 'Vietnamese',
    'zh-Hans': 'Chinese (Simplified)',
    'zh-Hant': 'Chinese (Traditional)',
  };

  // Spanisch
  static const Map<String, String> _esNames = {
    'ar': 'Árabe',
    'bn': 'Bengalí',
    'cs': 'Checo',
    'da': 'Danés',
    'de': 'Alemán',
    'el': 'Griego',
    'en': 'Inglés',
    'es': 'Español',
    'fa': 'Persa',
    'fi': 'Finés',
    'fr': 'Francés',
    'hi': 'Hindi',
    'hu': 'Húngaro',
    'id': 'Indonesio',
    'it': 'Italiano',
    'he': 'Hebreo',
    'ja': 'Japonés',
    'ko': 'Coreano',
    'mr': 'Maratí',
    'ms': 'Malayo',
    'nl': 'Neerlandés',
    'no': 'Noruego',
    'pa': 'Punyabí',
    'pl': 'Polaco',
    'pt': 'Portugués',
    'ro': 'Rumano',
    'ru': 'Ruso',
    'sv': 'Sueco',
    'te': 'Télugu',
    'th': 'Tailandés',
    'tl': 'Tagalo',
    'tr': 'Turco',
    'uk': 'Ucraniano',
    'vi': 'Vietnamita',
    'zh-Hans': 'Chino (simplificado)',
    'zh-Hant': 'Chino (tradicional)',
  };

  // Griechisch
  static const Map<String, String> _elNames = {
    'ar': 'Αραβικά',
    'bn': 'Βεγγαλικά',
    'cs': 'Τσέχικα',
    'da': 'Δανικά',
    'de': 'Γερμανικά',
    'el': 'Ελληνικά',
    'en': 'Αγγλικά',
    'es': 'Ισπανικά',
    'fa': 'Περσικά',
    'fi': 'Φινλανδικά',
    'fr': 'Γαλλικά',
    'hi': 'Χίντι',
    'hu': 'Ουγγρικά',
    'id': 'Ινδονησιακά',
    'it': 'Ιταλικά',
    'he': 'Εβραϊκά',
    'ja': 'Ιαπωνικά',
    'ko': 'Κορεατικά',
    'mr': 'Μαραθικά',
    'ms': 'Μαλαισιανά',
    'nl': 'Ολλανδικά',
    'no': 'Νορβηγικά',
    'pa': 'Παντζαμπικά',
    'pl': 'Πολωνικά',
    'pt': 'Πορτογαλικά',
    'ro': 'Ρουμανικά',
    'ru': 'Ρωσικά',
    'sv': 'Σουηδικά',
    'te': 'Τελούγκου',
    'th': 'Ταϊλανδέζικα',
    'tl': 'Ταγκάλογκ',
    'tr': 'Τουρκικά',
    'uk': 'Ουκρανικά',
    'vi': 'Βιετναμικά',
    'zh-Hans': 'Κινέζικα (Απλοποιημένα)',
    'zh-Hant': 'Κινέζικα (Παραδοσιακά)',
  };

  String _translatedNameFor(
    String code,
    String uiLang,
    String fallbackFromLabel,
  ) {
    if (uiLang == 'de') {
      return _deNames[code] ?? fallbackFromLabel;
    }
    if (uiLang == 'es') {
      return _esNames[code] ?? fallbackFromLabel;
    }
    if (uiLang == 'el') {
      return _elNames[code] ?? fallbackFromLabel;
    }
    // Default Englisch
    return _enNames[code] ?? fallbackFromLabel;
  }

  static const supported = [
    // code, label, emoji flag (erweitert gemäß Screenshot)
    ['ar', 'العربية (Arabic)', '🇸🇦'],
    ['bn', 'বাংলা (Bangla)', '🇧🇩'],
    ['cs', 'Čeština (Czech)', '🇨🇿'],
    ['da', 'Dansk (Danish)', '🇩🇰'],
    ['de', 'Deutsch (German)', '🇩🇪'],
    ['el', 'Ελληνικά (Greek)', '🇬🇷'],
    ['en', 'English (English)', '🇬🇧'],
    ['es', 'Español (Spanish)', '🇪🇸'],
    ['fa', 'فارسی (Persian)', '🇮🇷'],
    ['fi', 'Suomi (Finnish)', '🇫🇮'],
    ['fr', 'Français (French)', '🇫🇷'],
    ['hi', 'हिंदी (Hindi)', '🇮🇳'],
    ['hu', 'Magyar (Hungarian)', '🇭🇺'],
    ['id', 'Bahasa Indonesia (Indonesian)', '🇮🇩'],
    ['it', 'Italiano (Italian)', '🇮🇹'],
    ['he', 'עברית (Hebrew)', '🇮🇱'],
    ['ja', '日本語 (Japanese)', '🇯🇵'],
    ['ko', '한국어 (Korean)', '🇰🇷'],
    ['mr', 'मराठी (Marathi)', '🇮🇳'],
    ['ms', 'Bahasa Malaysia (Malay)', '🇲🇾'],
    ['nl', 'Nederlands (Dutch)', '🇳🇱'],
    ['no', 'Norsk (Norwegian)', '🇳🇴'],
    ['pa', 'ਪੰਜਾਬੀ (Punjabi)', '🇮🇳'],
    ['pl', 'Polski (Polish)', '🇵🇱'],
    ['pt', 'Português (Portuguese)', '🇵🇹'],
    ['ro', 'Română (Romanian)', '🇷🇴'],
    ['ru', 'Русский (Russian)', '🇷🇺'],
    ['sv', 'Svenska (Swedish)', '🇸🇪'],
    ['te', 'తెలుగు (Telugu)', '🇮🇳'],
    ['th', 'ภาษาไทย (Thai)', '🇹🇭'],
    ['tl', 'Tagalog (Tagalog)', '🇵🇭'],
    ['tr', 'Türkçe (Turkish)', '🇹🇷'],
    ['uk', 'Українська (Ukrainian)', '🇺🇦'],
    ['vi', 'Tiếng Việt (Vietnamese)', '🇻🇳'],
    ['zh-Hans', '简体中文 (Chinese Simplified)', '🇨🇳'],
    ['zh-Hant', '正體中文 (Chinese Traditional)', '🇨🇳'],
  ];

  Future<String?> _userLang() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    return doc.data()?['language'] as String?;
  }

  Future<void> _save(String code) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'language': code,
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    // AppBar-Titel abhängig von aktuell ausgewählter Sprache
    final loc = context.read<LocalizationService>();
    // Vorschau auf die aktuell ausgewählte Sprache (noch nicht gespeichert)
    if (_pendingLang != null && _pendingLang!.isNotEmpty) {
      loc.setPreviewLanguage(_pendingLang!);
    } else {
      loc.clearPreview();
    }
    return Scaffold(
      appBar: AppBar(
        title: Consumer<LocalizationService>(
          builder: (context, l, _) => Text(l.t('language.chooseTitle')),
        ),
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: Colors.white,
          onPressed: () async {
            if ((_pendingLang ?? '').isNotEmpty) {
              final code = _pendingLang!;
              await _save(code);
              if (mounted) {
                // App-weit aktualisieren
                context.read<LanguageService>().setLanguage(code);
              }
            }
            if (mounted) Navigator.pop(context);
          },
        ),
      ),
      backgroundColor: Colors.black,
      body: FutureBuilder<String?>(
        future: _userLang(),
        builder: (context, snap) {
          final current = snap.data;
          // Anzeige der aktuell/neu gewählten Sprache oberhalb des Grids
          String? selCode = _pendingLang ?? current;
          String? currentLabel;
          String? currentFlag;
          if ((selCode ?? '').isNotEmpty) {
            try {
              final found = supported.firstWhere((e) => e[0] == selCode);
              currentFlag = found[2];
              currentLabel = (found[1]).split('(').first.trim();
            } catch (_) {}
          }
          final uiLang = (context.read<LanguageService>().languageCode ?? 'de')
              .split('-')
              .first;
          final badgeLang = (selCode ?? uiLang).split('-').first;
          // Badge-Übersetzungen kommen aus LocalizationService → keine Locale-Override mehr nötig
          final headerText = loc.t('language.header');
          final hintText = loc.t('language.hint');
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((currentLabel ?? '').isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (currentFlag != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Text(
                              currentFlag,
                              style: const TextStyle(fontSize: 56),
                            ),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                headerText,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                currentLabel ?? '',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                hintText,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: GridView.builder(
                    padding: EdgeInsets.zero,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, // 3 Sprachen pro Zeile
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      // Etwas geringere Höhe, kombiniert mit kleinerem Flaggen- und Textbereich → kein Overflow
                      mainAxisExtent: 156,
                    ),
                    itemCount: supported.length,
                    itemBuilder: (context, i) {
                      final code = supported[i][0];
                      final label = supported[i][1];
                      final flag = supported[i][2];
                      final selected = ((_pendingLang ?? current) == code);
                      // Label in Native (vor Klammer) und Übersetzung (in Klammern)
                      String native = label;
                      String translation = "";
                      final p = label.split('(');
                      if (p.isNotEmpty) {
                        native = p.first.trim();
                        final fallback = p.length > 1
                            ? p.sublist(1).join('(').replaceAll(')', '').trim()
                            : '';
                        // Nur JSON‑Namen (ausgewählte Sprache), sonst Fallback‑Mapping
                        translation = loc.t('lang.$code');
                        if (translation == 'lang.$code' ||
                            translation.isEmpty) {
                          translation = _translatedNameFor(
                            code,
                            badgeLang,
                            fallback,
                          );
                        }
                      }
                      return InkWell(
                        onTap: () async {
                          setState(() => _pendingLang = code);
                        },
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.lightBlue
                                      : Colors.white24,
                                ),
                                color: selected
                                    ? AppColors.lightBlue.withValues(alpha: 0.1)
                                    : Colors.white10,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const SizedBox(height: 4),
                                  Align(
                                    alignment: Alignment.topCenter,
                                    child: Text(
                                      flag,
                                      style: const TextStyle(fontSize: 78),
                                    ),
                                  ),
                                  const Spacer(),
                                  // Native Bezeichnung: reservierter Platz für 2 Zeilen,
                                  // bei id/ms minimal kleinere Schrift, damit nichts überläuft
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: SizedBox(
                                      height: 30,
                                      child: Center(
                                        child: Text(
                                          native,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                ],
                              ),
                            ),
                            // Übersetzung klein oben rechts in der Kachel
                            if (translation.isNotEmpty)
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    translation,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ),
                            // Auswahl-Häkchen oben links mit Gradient (wie Trash)
                            if (selected)
                              Positioned(
                                top: 6,
                                left: 6,
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(
                                      colors: [
                                        AppColors.magenta,
                                        AppColors.lightBlue,
                                      ],
                                    ),
                                    border: Border.all(
                                      color: AppColors.lightBlue.withValues(
                                        alpha: 0.7,
                                      ),
                                    ),
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.check,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
