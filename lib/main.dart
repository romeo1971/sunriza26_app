
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models/media_models.dart';
import 'services/moments_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_options.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'auth_gate.dart';
import 'widgets/password_gate.dart';
import 'widgets/responsive_content_wrapper.dart';
import 'screens/auth_screen.dart';
import 'services/bithuman_service.dart';
import 'services/video_stream_service.dart';
import 'services/auth_service.dart';
import 'services/language_service.dart';
import 'services/localization_service.dart';
import 'screens/avatar_upload_memories_screen.dart';
import 'screens/avatar_details_screen.dart';
import 'screens/avatar_chat_screen.dart';
import 'screens/media_gallery_screen.dart';
import 'screens/playlist_list_screen.dart';
import 'screens/playlist_scheduler_screen.dart';
import 'screens/playlist_timeline_screen.dart';
import 'screens/bol_screen.dart';
import 'screens/moments_screen.dart';
import 'screens/avatar_review_facts_screen.dart';
import 'screens/credits_shop_screen.dart';
import 'screens/payment_overview_screen.dart';
import 'screens/seller_sales_screen.dart';
import 'screens/payment_methods_screen.dart';
import 'screens/home_navigation_screen.dart';
import 'screens/explore_screen.dart';
import 'screens/favorites_screen.dart';
import 'screens/user_profile_public_screen.dart';
import 'screens/public_avatar_entry_screen.dart';
import 'models/playlist_models.dart';
import 'widgets/legal/privacy.dart';
import 'widgets/legal/terms.dart';
import 'widgets/legal/imprint.dart';
import 'screens/firebase_test_screen.dart';
import 'screens/avatar_creation_screen.dart';
import 'screens/language_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme/app_theme.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Deaktiviert jegliche Page-Transitions (kein Slide/Fade) für Navigator-Routen - das ist gut ok sehr gut!!
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

Future<void> bootstrapSunrizaApp({
  required String envFileName,
  required FirebaseOptions firebaseOptions,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Hinweis: Keyboard-Assertion ist ein Flutter-Desktop-Issue; kein App-Code-Fix nötig

  // Env-Datei zwingend laden (fehlende Keys sollen hart fehlschlagen)
  await dotenv.load(fileName: envFileName);

  // Orientierung global auf Portrait fixieren (immer "Mobile View")
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Alle Keys in der geladenen Env-Datei sind Pflicht: leer/fehlend -> harter Fehler
  _validateAllEnvStrict();

  // Firebase immer initialisieren (nur wenn noch nicht initialisiert)
  try {
    await Firebase.initializeApp(options: firebaseOptions);
  } catch (e) {
    // Firebase bereits initialisiert (z.B. bei Hot Reload) - ignorieren
    if (!e.toString().contains('duplicate-app')) rethrow;
  }

  // Firestore: Offline-Persistenz deaktivieren, um LevelDB-LOCKs zu vermeiden (z.B. bei parallel laufenden Instanzen)
  try {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );
  } catch (_) {
    // still starten – falls Settings bereits gesetzt wurden
  }

  // BitHuman Service initialisieren
  await BitHumanService.initialize();

  // Google Sign-In initialisieren (7.x)
  await GoogleSignIn.instance.initialize();

  // Firebase Auth Sprache auf Gerätesprache setzen
  await FirebaseAuth.instance.setLanguageCode(null);

  // Debug: Base-URL ausgeben immer
  // debugPrint('BASE=${EnvService.memoryApiBaseUrl()}');

  // Engineering-Anker nur im Debug registrieren (kein Boot-Log)
  // Engineering-Logs vollständig entfernt

  runApp(const HauauApp());
}

Future<void> main() async {
  // Default-Einstieg nutzt Prod-Konfiguration; für explizite Dev/Prod-Builds
  // bitte `main_dev.dart` bzw. `main_prod.dart` verwenden.
  await bootstrapSunrizaApp(
    envFileName: '.env.prod',
    firebaseOptions: DefaultFirebaseOptions.currentPlatform,
  );
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
    debugPrint(
      '⚠️ Fehlende/leer Env-Keys (aktive Env-Datei): ${missing.join(', ')}',
    );
  }
}

class HauauApp extends StatelessWidget {
  const HauauApp({super.key});

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
          title: 'hauau - HOW ARE YOU',
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            LocaleNamesLocalizationsDelegate(),
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
              primary: AppColors.black,
              onPrimary: Colors.white,
              secondary: AppColors.black,
              onSecondary: Colors.white,
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
                backgroundColor: AppColors.magenta,
                foregroundColor: Colors.white,
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
                foregroundColor: AppColors.magenta,
                side: const BorderSide(
                  color: AppColors.magenta,
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
                foregroundColor: AppColors.magenta,
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            floatingActionButtonTheme: const FloatingActionButtonThemeData(
              backgroundColor: AppColors.magenta,
              foregroundColor: Colors.white,
            ),
            chipTheme: const ChipThemeData(
              backgroundColor: Color(0x14FF2EC8),
              selectedColor: AppColors.magenta,
              labelStyle: TextStyle(color: Colors.white),
              secondaryLabelStyle: TextStyle(color: Colors.white),
              side: BorderSide(color: AppColors.magenta),
              shape: StadiumBorder(),
            ),
            switchTheme: const SwitchThemeData(
              thumbColor: WidgetStatePropertyAll(AppColors.magenta),
              trackColor: WidgetStatePropertyAll(Color(0x33FF2EC8)),
            ),
            sliderTheme: const SliderThemeData(
              activeTrackColor: AppColors.magenta,
              inactiveTrackColor: Color(0x33FF2EC8),
              thumbColor: AppColors.magenta,
              overlayColor: Color(0x22FF2EC8),
            ),
            iconButtonTheme: IconButtonThemeData(
              style: IconButton.styleFrom(
                foregroundColor: AppColors.magenta,
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0x00000020), // dezentes BLACK-Overlay
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
            dialogTheme: DialogThemeData(
              backgroundColor: const Color(0xFF1A1A1A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.magenta, width: 3),
              ),
              elevation: 8,
              shadowColor: AppColors.magenta.withValues(alpha: 0.5),
            ),
            popupMenuTheme: PopupMenuThemeData(
              color: const Color(0xFF1A1A1A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: AppColors.magenta, width: 2),
              ),
              elevation: 8,
              shadowColor: AppColors.magenta.withValues(alpha: 0.5),
            ),
          ),
          builder: (context, child) {
            return ResponsiveContentWrapper(
              child: child ?? const SizedBox(),
            );
          },
          home: const _ResumeRouter(
            child: PasswordGate(child: AuthGate()),
          ),
          debugShowCheckedModeBanner: false,
          onGenerateRoute: (settings) {
            final name = settings.name ?? '';
            // Public Avatar Route: /avatar/<slug>
            try {
              final uri = Uri.parse(name);
              if (uri.pathSegments.length == 2 &&
                  uri.pathSegments[0] == 'avatar') {
                final slug = uri.pathSegments[1];
                return MaterialPageRoute(
                  builder: (_) => PublicAvatarEntryScreen(slug: slug),
                  settings: settings,
                );
              }
            } catch (_) {}
            return null; // Standard-Routing benutzen
          },
          routes: {
            '/home': (context) => const HomeNavigationScreen(),
            // Embed-Route: erwartet avatarId via Query (?avatarId=...) oder Route-Args
            '/embed': (context) => const _EmbedAvatarPage(),
            '/explore': (context) => const ExploreScreen(),
            '/favorites': (context) => const FavoritesScreen(),
            '/profile': (context) => const UserProfilePublicScreen(),
            '/avatar-upload': (context) => const AvatarUploadMemoriesScreen(),
            '/avatar-details': (context) => const AvatarDetailsScreen(),
            '/avatar-chat': (context) => const AvatarChatScreen(),
            '/avatar-list': (context) =>
                const HomeNavigationScreen(initialIndex: 1),
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
            // BOL – Book of Life
            '/bol': (context) {
              final args = ModalRoute.of(context)!.settings.arguments as Map?;
              final avatarId = (args?['avatarId'] as String?) ?? '';
              final fromScreen = args?['fromScreen'] as String?;
              return BolScreen(avatarId: avatarId, fromScreen: fromScreen);
            },
            // Neuer Moments-Screen (Bottom‑Nav rechts)
            '/moments': (context) => const MomentsScreen(),
            // Altpfad bleibt erhalten und zeigt nun auf den neuen Moments-Screen
            '/shared-moments': (context) => const MomentsScreen(),
            // Stripe-Return-Ziel – wichtig, damit Uri (inkl. session_id) NICHT verloren geht
            '/media/checkout': (context) => const _MediaCheckoutPage(),
            '/avatar-review-facts': (context) {
              final args = ModalRoute.of(context)!.settings.arguments as Map?;
              final avatarId = (args?['avatarId'] as String?) ?? '';
              final fromScreen = args?['fromScreen'] as String?;
              return AvatarReviewFactsScreen(
                avatarId: avatarId,
                fromScreen: fromScreen,
              );
            },
            '/legal-terms': (context) => const TermsWidget(),
            '/legal-imprint': (context) => const ImprintWidget(),
            '/legal-privacy': (context) => const PrivacyWidget(),
            '/firebase-test': (context) => const FirebaseTestScreen(),
            '/avatar-creation': (context) => const AvatarCreationScreen(),
            '/language': (context) => const LanguageScreen(),
            // Avatar Editor wird jetzt über Avatar Details aufgerufen
          },
          // Engineering-Observer entfernt
        );
      },
    );
    return MultiProvider(
      providers: [
        Provider<VideoStreamService>(create: (_) => VideoStreamService()),
        Provider<AuthService>(create: (_) => AuthService()),
        ChangeNotifierProvider<LanguageService>(
          create: (_) => LanguageService(initialLanguageCode: 'en'),
        ),
        ChangeNotifierProvider<LocalizationService>(
          create: (_) => LocalizationService()..useLanguageCode('en'),
        ),
      ],
      child: isMacOS ? ExcludeSemantics(child: app) : app,
    );
  }
}

/// Fängt App-Resume nach externen Flows (z.B. Stripe Checkout) ab
class _ResumeRouter extends StatefulWidget {
  final Widget child;
  const _ResumeRouter({required this.child});

  @override
  State<_ResumeRouter> createState() => _ResumeRouterState();
}

class _ResumeRouterState extends State<_ResumeRouter> with WidgetsBindingObserver {
  String? _lastHandledSessionId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Direkt nach Build einmal prüfen (Kaltstart)
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleResumeDeepLink());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleResumeDeepLink();
    }
  }

  void _handleResumeDeepLink() {
    try {
      final uri = Uri.base;
      // ignore: avoid_print
      print('🔵🔵🔵 [ResumeRouter] current URI: $uri');
      final sessionId = uri.queryParameters['session_id'];
      // ignore: avoid_print
      print('🔵🔵🔵 [ResumeRouter] session_id: $sessionId');
      if (sessionId == null || sessionId.isEmpty) return;
      if (_lastHandledSessionId == sessionId) return; // doppelte Navigation vermeiden
      _lastHandledSessionId = sessionId;

      final flowType = uri.queryParameters['type'];
      // ignore: avoid_print
      print('🔵🔵🔵 [ResumeRouter] flowType: $flowType, path: ${uri.path}');
      if (uri.path.contains('/media/checkout') || flowType == 'media') {
        // ignore: avoid_print
        print('✅✅✅ [ResumeRouter] Media-Checkout erkannt, Route /media/checkout übernimmt');
        // NICHT hier verarbeiten - lasse _MediaCheckoutPage das übernehmen
        return;
      }

      // ignore: avoid_print
      print('🔵🔵🔵 [ResumeRouter] Standard Payment Overview Navigation');
      final navigator = Navigator.of(context);
      navigator.pushNamed('/payment-overview', arguments: { 'sessionId': sessionId });
    } catch (e, st) {
      // ignore: avoid_print
      print('🔴🔴🔴 [ResumeRouter] Fehler: $e');
      print(st);
    }
  }


  @override
  Widget build(BuildContext context) => widget.child;
}

class _MediaCheckoutPage extends StatefulWidget {
  const _MediaCheckoutPage();

  @override
  State<_MediaCheckoutPage> createState() => _MediaCheckoutPageState();
}

class _MediaCheckoutPageState extends State<_MediaCheckoutPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _process());
  }

  Future<void> _process() async {
    try {
      final uri = Uri.base;
      final sessionId = uri.queryParameters['session_id'];
      final avatarId = uri.queryParameters['avatarId'] ?? '';
      final mediaId = uri.queryParameters['mediaId'] ?? '';
      final mediaType = uri.queryParameters['mediaType'] ?? '';
      final mediaUrlParam = uri.queryParameters['mediaUrl'];

      if (sessionId == null || sessionId.isEmpty) {
        if (mounted) Navigator.of(context).pushReplacementNamed('/home');
        return;
      }

      AvatarMedia? media;
      if (avatarId.isNotEmpty && mediaId.isNotEmpty && mediaType.isNotEmpty) {
        final folder = switch (mediaType) {
          'image' => 'images',
          'video' => 'videos',
          'audio' => 'audios',
          'document' => 'documents',
          _ => 'images',
        };
        final snap = await FirebaseFirestore.instance
            .collection('avatars').doc(avatarId)
            .collection(folder).doc(mediaId).get();
        if (snap.exists) {
          final map = {'id': snap.id, ...snap.data()!};
          media = AvatarMedia.fromMap(map);
        }
      }

      if (media == null && mediaUrlParam != null && mediaUrlParam.isNotEmpty) {
        final type = switch (mediaType) {
          'video' => AvatarMediaType.video,
          'audio' => AvatarMediaType.audio,
          'document' => AvatarMediaType.document,
          _ => AvatarMediaType.image,
        };
        media = AvatarMedia(
          id: mediaId.isNotEmpty ? mediaId : DateTime.now().millisecondsSinceEpoch.toString(),
          avatarId: avatarId,
          type: type,
          url: mediaUrlParam,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );
      }

      String? storedUrl;
      String mediaName = 'Media';
      String avatarName = 'Avatar';
      if (media != null) {
        mediaName = media.originalFileName ?? _guessNameFromUrl(media.url) ?? mediaName;
        final moment = await MomentsService().saveMoment(
          media: media,
          price: media.price ?? 0.0,
          paymentMethod: 'stripe',
          stripePaymentIntentId: sessionId,
        );
        storedUrl = moment.storedUrl;
        
        // Rechnung für Stripe-Transaktion generieren
        try {
          final fns = FirebaseFunctions.instanceFor(region: 'us-central1');
          await fns.httpsCallable('ensureInvoiceFiles').call({'transactionId': sessionId});
          debugPrint('✅ Rechnung generiert für Stripe-Kauf');
        } catch (e) {
          debugPrint('⚠️ Rechnung-Generierung fehlgeschlagen: $e');
        }
      }

      if (avatarId.isNotEmpty) {
        try {
          final doc = await FirebaseFirestore.instance.collection('avatars').doc(avatarId).get();
          if (doc.exists) {
            final d = doc.data()!;
            final nickname = (d['nickname'] as String?)?.trim();
            final firstName = (d['firstName'] as String?)?.trim();
            avatarName = (nickname != null && nickname.isNotEmpty) ? nickname : (firstName ?? avatarName);
          }
        } catch (_) {}
      }

      if (storedUrl != null && storedUrl.isNotEmpty) {
        try {
          final dUri = Uri.parse(storedUrl);
          if (await canLaunchUrl(dUri)) {
            await launchUrl(dUri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
          }
        } catch (_) {}
      }

      try {
        final prefs = await SharedPreferences.getInstance();
        debugPrint('🔵🔵🔵 [MediaCheckout] Speichere avatarId: $avatarId');
        if (avatarId.isNotEmpty) {
          await prefs.setString('pending_open_chat_avatar_id', avatarId);
          await prefs.setString('pending_media_success_name', mediaName);
          await prefs.setString('pending_media_success_avatar', avatarName);
          await prefs.setString('pending_media_success_url', storedUrl ?? '');
          debugPrint('✅✅✅ [MediaCheckout] Daten gespeichert');
        } else {
          debugPrint('🔴🔴🔴 [MediaCheckout] avatarId ist LEER!');
        }
      } catch (e) {
        debugPrint('🔴🔴🔴 [MediaCheckout] Fehler beim Speichern: $e');
      }

      if (mounted) {
        debugPrint('🔵🔵🔵 [MediaCheckout] Navigiere zu /home');
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      }
    } catch (e) {
      debugPrint('🔴🔴🔴 [MediaCheckout] Fehler in _process: $e');
      if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

/// Leichte Embed-Seite: fordert Login, leitet danach in AvatarDetails (embed=true)
class _EmbedAvatarPage extends StatefulWidget {
  const _EmbedAvatarPage();
  @override
  State<_EmbedAvatarPage> createState() => _EmbedAvatarPageState();
}

class _EmbedAvatarPageState extends State<_EmbedAvatarPage> {
  User? _user;
  late final Stream<User?> _authStream;
  String _avatarId = '';
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _authStream = FirebaseAuth.instance.authStateChanges();
    _extractAvatarId();
  }

  void _extractAvatarId() {
    try {
      // 1) Query ?avatarId=...
      final uri = Uri.base;
      final fromQuery = (uri.queryParameters['avatarId'] ?? '').trim();
      if (fromQuery.isNotEmpty) {
        _avatarId = fromQuery;
        return;
      }
      // 2) Pfad /embed/<avatarId>
      final seg = uri.pathSegments;
      if (seg.isNotEmpty && seg.first == 'embed' && seg.length >= 2) {
        _avatarId = seg[1].trim();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, snap) {
        _user = snap.data;
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (_user == null) {
          // Login erforderlich
          return const AuthScreen();
        }
        // Eingeloggt → sauber in Avatar Details navigieren (embed)
        if (!_navigated) {
          _navigated = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context).pushReplacementNamed(
              '/avatar-details',
              arguments: {
                'avatarId': _avatarId,
                'embed': true,
                'fromScreen': 'embed',
              },
            );
          });
        }
        return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}

// Hilfsfunktion: Dateiname aus URL ableiten
String? _guessNameFromUrl(String url) {
  try {
    final u = Uri.parse(url);
    final path = u.path;
    if (path.isEmpty) return null;
    final last = path.split('/').last;
    return last.isEmpty ? null : last;
  } catch (_) {
    return null;
  }
}
