import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_options.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'auth_gate.dart';
import 'services/ai_service.dart';
import 'services/video_stream_service.dart';
import 'services/auth_service.dart';
import 'screens/avatar_upload_memories_screen.dart';
import 'screens/avatar_details_screen.dart';
import 'screens/avatar_chat_screen.dart';
import 'screens/avatar_list_screen.dart';
import 'screens/legal_page_screen.dart';
import 'screens/firebase_test_screen.dart';
import 'screens/avatar_creation_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme/app_theme.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // .env laden (für Firebase Web API Key etc.) – fehlende Datei tolerieren
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    // .env optional – still starten ohne Logausgabe
  }

  // Firebase immer initialisieren
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Google Sign-In initialisieren (7.x)
  await GoogleSignIn.instance.initialize();

  // Firebase Auth Sprache auf Gerätesprache setzen
  await FirebaseAuth.instance.setLanguageCode(null);

  // Debug: Base-URL ausgeben
  // print('BASE=${EnvService.memoryApiBaseUrl()}');

  runApp(const SunrizaApp());
}

class SunrizaApp extends StatelessWidget {
  const SunrizaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isMacOS = defaultTargetPlatform == TargetPlatform.macOS;

    final Widget app = MaterialApp(
      title: 'Sunriza26 - Live AI Assistant',
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
            borderSide: const BorderSide(color: Color(0xFF00FF94), width: 2),
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
        '/avatar-upload': (context) => const AvatarUploadMemoriesScreen(),
        '/avatar-details': (context) => const AvatarDetailsScreen(),
        '/avatar-chat': (context) => const AvatarChatScreen(),
        '/avatar-list': (context) => const AvatarListScreen(),
        '/legal-terms': (context) => const LegalPageScreen(type: 'terms'),
        '/legal-imprint': (context) => const LegalPageScreen(type: 'imprint'),
        '/legal-privacy': (context) => const LegalPageScreen(type: 'privacy'),
        '/firebase-test': (context) => const FirebaseTestScreen(),
        '/avatar-creation': (context) => const AvatarCreationScreen(),
        // Avatar Editor wird jetzt über Avatar Details aufgerufen
      },
    );

    return MultiProvider(
      providers: [
        Provider<AIService>(create: (_) => AIService()),
        Provider<VideoStreamService>(create: (_) => VideoStreamService()),
        Provider<AuthService>(create: (_) => AuthService()),
      ],
      child: isMacOS ? ExcludeSemantics(child: app) : app,
    );
  }
}
