import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_options.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:audioplayers/audioplayers.dart';
import 'services/audio_player_service.dart';
import 'auth_gate.dart';
import 'services/ai_service.dart';
import 'services/video_stream_service.dart';
import 'services/auth_service.dart';
import 'services/language_service.dart';
import 'services/localization_service.dart';
import 'screens/avatar_upload_memories_screen.dart';
import 'screens/avatar_details_screen.dart';
import 'screens/avatar_chat_screen.dart';
import 'screens/avatar_list_screen.dart';
import 'screens/media_gallery_screen.dart';
import 'screens/playlist_list_screen.dart';
import 'screens/playlist_scheduler_screen.dart';
import 'screens/playlist_timeline_screen.dart';
import 'screens/shared_moments_screen.dart';
import 'screens/avatar_review_facts_screen.dart';
import 'screens/credits_shop_screen.dart';
import 'screens/payment_overview_screen.dart';
import 'screens/seller_sales_screen.dart';
import 'screens/payment_methods_screen.dart';
import 'screens/home_navigation_screen.dart';
import 'screens/explore_screen.dart';
import 'screens/favorites_screen.dart';
import 'screens/user_profile_public_screen.dart';
import 'models/playlist_models.dart';
import 'screens/legal_page_screen.dart';
import 'screens/firebase_test_screen.dart';
import 'screens/avatar_creation_screen.dart';
import 'screens/language_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme/app_theme.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'l10n/app_localizations.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'boot/engineering_notes.dart';

/// Deaktiviert jegliche Page-Transitions (kein Slide/Fade) für Navigator-Routen
class NoAnimationPageTransitionsBuilder extends PageTransitionsBuilder {
  const NoAnimationPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // WICHTIG: Stoppe evtl. laufenden Player beim App-Start (z.B. nach Hot-Restart)
  // Service stoppen
  await AudioPlayerService().stopAll();

  // ZUSÄTZLICH: Versuche alle AudioPlayer-Instanzen zu stoppen
  try {
    // Release alle Audio-Ressourcen auf System-Ebene
    final tempPlayer = AudioPlayer();
    await tempPlayer.dispose();
  } catch (e) {
    debugPrint('Audio System Cleanup: $e');
  }

  // .env zwingend laden (fehlende Keys sollen hart fehlschlagen)
  await dotenv.load(fileName: '.env');

  // Alle Keys in .env sind Pflicht: leer/fehlend -> harter Fehler
  _validateAllEnvStrict();

  // Firebase immer initialisieren
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Firestore: Offline-Persistenz deaktivieren, um LevelDB-LOCKs zu vermeiden (z.B. bei parallel laufenden Instanzen)
  try {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );
  } catch (_) {
    // still starten – falls Settings bereits gesetzt wurden
  }

  // Google Sign-In initialisieren (7.x)
  await GoogleSignIn.instance.initialize();

  // Firebase Auth Sprache auf Gerätesprache setzen
  await FirebaseAuth.instance.setLanguageCode(null);

  // Sprache laden: Firebase ist Master, Prefs ist Cache
  String initialLang = 'en';

  // 1) Zuerst aus Prefs laden (schnell, ohne Flackern)
  try {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('language_code');
    if (saved != null && saved.isNotEmpty) initialLang = saved;
  } catch (_) {}

  // 2) Falls User eingeloggt: Firebase-Sprache holen (Master)
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 2));

      final fbLang = (doc.data()?['language'] as String?)?.trim();
      if (fbLang != null && fbLang.isNotEmpty) {
        // Firebase hat Sprache → das ist der Master
        initialLang = fbLang;
        // In Prefs cachen für nächsten Start
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('language_code', fbLang);
        } catch (_) {}
      } else {
        // Firebase hat noch keine Sprache → Default 'en' setzen
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'language': 'en',
        }, SetOptions(merge: true));
        initialLang = 'en';
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('language_code', 'en');
        } catch (_) {}
      }
    }
  } catch (_) {
    // Timeout oder Fehler → mit Prefs-Wert weitermachen
  }

  // Debug: Base-URL ausgeben
  // print('BASE=${EnvService.memoryApiBaseUrl()}');

  // Engineering-Anker: Log nur bei Fehlern, optional beim Boot in Debug
  registerEngineeringAnchors(alwaysLogOnBoot: false);

  runApp(SunrizaApp(initialLanguageCode: initialLang));
}

void _validateAllEnvStrict() {
  final Map<String, String> env = dotenv.env;
  final missing = <String>[];
  env.forEach((k, v) {
    // Erlaube Kommentare/Meta-Keys nicht; prüfe nur echte Einträge
    final key = k.trim();
    final val = v.trim();
    if (key.isEmpty) return;
    if (val.isEmpty) missing.add(key);
  });
  if (missing.isNotEmpty) {
    // Nur loggen, App nicht stoppen (gewünschtes Verhalten)
    // Hinweis: Kritische Fehler zeigen sich später im Feature selbst
    // (z.B. Pinecone/ElevenLabs), aber der Start bleibt stabil.
    // ignore: avoid_print
    print('⚠️ Fehlende/leer .env Keys: ${missing.join(', ')}');
  }
}

class SunrizaApp extends StatelessWidget {
  final String initialLanguageCode;
  const SunrizaApp({super.key, this.initialLanguageCode = 'en'});

  @override
  Widget build(BuildContext context) {
    final bool isMacOS = defaultTargetPlatform == TargetPlatform.macOS;

    final Widget app = Consumer<LanguageService>(
      builder: (context, langSvc, _) {
        Locale? forced;
        final lc = langSvc.languageCode;
        if (lc != null && lc.isNotEmpty) {
          if (lc == 'zh-Hans') {
            forced = const Locale.fromSubtags(
              languageCode: 'zh',
              scriptCode: 'Hans',
            );
          } else if (lc == 'zh-Hant') {
            forced = const Locale.fromSubtags(
              languageCode: 'zh',
              scriptCode: 'Hant',
            );
          } else if (lc.length == 2) {
            forced = Locale(lc);
          }
        }
        // LocalizationService mit der aktuell gewählten Sprache synchronisieren
        final locSvc = context.read<LocalizationService>();
        final desiredCode = lc ?? 'en';
        if (locSvc.activeCode != desiredCode) {
          // außerhalb des Builds ausführen
          Future.microtask(() => locSvc.useLanguageCode(desiredCode));
        }
        return MaterialApp(
          title: 'Sunriza26 - Live AI Assistant',
          localizationsDelegates: [
            ...AppLocalizations.localizationsDelegates,
            const LocaleNamesLocalizationsDelegate(),
          ],
          supportedLocales: const [
            Locale('en'),
            Locale('de'),
            Locale('es'),
            Locale('fr'),
            Locale('it'),
            Locale('pt'),
            Locale('ro'),
            Locale('ru'),
            Locale('sv'),
            Locale('pl'),
            Locale('cs'),
            Locale('da'),
            Locale('fi'),
            Locale('nl'),
            Locale('no'),
            Locale('hu'),
            Locale('el'),
            Locale('he'),
            Locale('ar'),
            Locale('fa'),
            Locale('hi'),
            Locale('bn'),
            Locale('id'),
            Locale('ms'),
            Locale('ta'),
            Locale('te'),
            Locale('th'),
            Locale('tr'),
            Locale('uk'),
            Locale('vi'),
            Locale('ja'),
            Locale('ko'),
            Locale('pa'),
            Locale('mr'),
            Locale('tl'),
            Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
            Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
          ],
          locale: forced,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primaryGreen,
              onPrimary: Colors.black,
              secondary: AppColors.accentGreenDark,
              onSecondary: Colors.black,
              surface: AppColors.darkSurface,
              onSurface: Colors.white,
            ),
            scaffoldBackgroundColor: AppColors.black,
            canvasColor: AppColors.black,
            appBarTheme: const AppBarTheme(
              centerTitle: true,
              elevation: 0,
              backgroundColor: Color(0xFF000000),
              foregroundColor: Colors.white,
            ),
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: NoAnimationPageTransitionsBuilder(),
                TargetPlatform.iOS: NoAnimationPageTransitionsBuilder(),
                TargetPlatform.macOS: NoAnimationPageTransitionsBuilder(),
                TargetPlatform.linux: NoAnimationPageTransitionsBuilder(),
                TargetPlatform.windows: NoAnimationPageTransitionsBuilder(),
                TargetPlatform.fuchsia: NoAnimationPageTransitionsBuilder(),
              },
            ),
            extensions: <ThemeExtension<dynamic>>[AppGradients.defaultDark()],
            // Näher am Google‑Sans Look (fällt auf Plus Jakarta zurück, Headlines versuchen 'GoogleSans')
            textTheme: GoogleFonts.plusJakartaSansTextTheme(
              const TextTheme(
                headlineLarge: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  fontSize: 40,
                  fontFamily: 'GoogleSans',
                ),
                headlineMedium: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  fontSize: 30,
                  fontFamily: 'GoogleSans',
                ),
                headlineSmall: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 22,
                  fontFamily: 'GoogleSans',
                ),
                titleLarge: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  fontFamily: 'GoogleSans',
                ),
                titleMedium: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
                bodyLarge: TextStyle(
                  color: Color(0xFFEAEAEA),
                  height: 1.4,
                  fontSize: 16,
                ),
                bodyMedium: TextStyle(
                  color: Color(0xFFCCCCCC),
                  height: 1.4,
                  fontSize: 14,
                ),
                labelLarge: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentGreenDark,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accentGreenDark,
                side: const BorderSide(
                  color: AppColors.accentGreenDark,
                  width: 1.5,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accentGreenDark,
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            floatingActionButtonTheme: const FloatingActionButtonThemeData(
              backgroundColor: AppColors.accentGreenDark,
              foregroundColor: Colors.black,
            ),
            chipTheme: const ChipThemeData(
              backgroundColor: Color(0x1400DFA8),
              selectedColor: AppColors.accentGreenDark,
              labelStyle: TextStyle(color: Colors.white),
              secondaryLabelStyle: TextStyle(color: Colors.black),
              side: BorderSide(color: AppColors.accentGreenDark),
              shape: StadiumBorder(),
            ),
            switchTheme: const SwitchThemeData(
              thumbColor: WidgetStatePropertyAll(AppColors.accentGreenDark),
              trackColor: WidgetStatePropertyAll(Color(0x3300DFA8)),
            ),
            sliderTheme: const SliderThemeData(
              activeTrackColor: AppColors.accentGreenDark,
              inactiveTrackColor: Color(0x3300DFA8),
              thumbColor: AppColors.accentGreenDark,
              overlayColor: Color(0x2200DFA8),
            ),
            iconButtonTheme: IconButtonThemeData(
              style: IconButton.styleFrom(
                foregroundColor: AppColors.accentGreenDark,
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0x1400FF94), // dezentes Grün-Overlay
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white24),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFF00FF94),
                  width: 2,
                ),
              ),
              hintStyle: const TextStyle(color: Colors.white54),
              labelStyle: const TextStyle(color: Colors.white70),
            ),
            snackBarTheme: const SnackBarThemeData(
              backgroundColor: Color(0xFF0A0A0A),
              contentTextStyle: TextStyle(color: Colors.white),
              behavior: SnackBarBehavior.floating,
            ),
          ),
          home: const AuthGate(),
          debugShowCheckedModeBanner: false,
          routes: {
            '/home': (context) => const HomeNavigationScreen(),
            '/explore': (context) => const ExploreScreen(),
            '/favorites': (context) => const FavoritesScreen(),
            '/profile': (context) => const UserProfilePublicScreen(),
            '/avatar-upload': (context) => const AvatarUploadMemoriesScreen(),
            '/avatar-details': (context) => const AvatarDetailsScreen(),
            '/avatar-chat': (context) => const AvatarChatScreen(),
            '/avatar-list': (context) => const AvatarListScreen(),
            '/credits-shop': (context) => const CreditsShopScreen(),
            '/payment-overview': (context) => const PaymentOverviewScreen(),
            '/seller-sales': (context) => const SellerSalesScreen(),
            '/payment-methods': (context) => const PaymentMethodsScreen(),
            '/media-gallery': (context) {
              final args = ModalRoute.of(context)!.settings.arguments as Map?;
              final avatarId = (args?['avatarId'] as String?) ?? '';
              final fromScreen = args?['fromScreen'] as String?;
              return MediaGalleryScreen(
                avatarId: avatarId,
                fromScreen: fromScreen,
              );
            },
            '/playlist-list': (context) {
              final args = ModalRoute.of(context)!.settings.arguments as Map?;
              final avatarId = (args?['avatarId'] as String?) ?? '';
              final fromScreen = args?['fromScreen'] as String?;
              return PlaylistListScreen(
                avatarId: avatarId,
                fromScreen: fromScreen,
              );
            },
            '/playlist-edit': (context) {
              final p = ModalRoute.of(context)!.settings.arguments as Playlist;
              return PlaylistSchedulerScreen(playlist: p);
            },
            '/playlist-timeline': (context) {
              final p = ModalRoute.of(context)!.settings.arguments as Playlist;
              return PlaylistTimelineScreen(playlist: p);
            },
            '/shared-moments': (context) {
              final args = ModalRoute.of(context)!.settings.arguments as Map?;
              final avatarId = (args?['avatarId'] as String?) ?? '';
              final fromScreen = args?['fromScreen'] as String?;
              return SharedMomentsScreen(
                avatarId: avatarId,
                fromScreen: fromScreen,
              );
            },
            '/avatar-review-facts': (context) {
              final args = ModalRoute.of(context)!.settings.arguments as Map?;
              final avatarId = (args?['avatarId'] as String?) ?? '';
              final fromScreen = args?['fromScreen'] as String?;
              return AvatarReviewFactsScreen(
                avatarId: avatarId,
                fromScreen: fromScreen,
              );
            },
            '/legal-terms': (context) => const LegalPageScreen(type: 'terms'),
            '/legal-imprint': (context) =>
                const LegalPageScreen(type: 'imprint'),
            '/legal-privacy': (context) =>
                const LegalPageScreen(type: 'privacy'),
            '/firebase-test': (context) => const FirebaseTestScreen(),
            '/avatar-creation': (context) => const AvatarCreationScreen(),
            '/language': (context) => const LanguageScreen(),
            // Avatar Editor wird jetzt über Avatar Details aufgerufen
          },
          navigatorObservers: <NavigatorObserver>[engineeringNavigatorObserver],
        );
      },
    );
    return MultiProvider(
      providers: [
        Provider<AIService>(create: (_) => AIService()),
        Provider<VideoStreamService>(create: (_) => VideoStreamService()),
        Provider<AuthService>(create: (_) => AuthService()),
        ChangeNotifierProvider<LanguageService>(
          create: (_) =>
              LanguageService(initialLanguageCode: initialLanguageCode),
        ),
        ChangeNotifierProvider<LocalizationService>(
          create: (_) =>
              LocalizationService()..useLanguageCode(initialLanguageCode),
        ),
      ],
      child: isMacOS ? ExcludeSemantics(child: app) : app,
    );
  }
}
