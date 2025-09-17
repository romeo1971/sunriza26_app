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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // .env laden (für Firebase Web API Key etc.)
  await dotenv.load(fileName: '.env');

  // Firebase initialisieren
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Google Sign-In initialisieren (7.x)
  await GoogleSignIn.instance.initialize();

  // Firebase Auth Sprache auf Gerätesprache setzen
  await FirebaseAuth.instance.setLanguageCode(null);

  runApp(const SunrizaApp());
}

class SunrizaApp extends StatelessWidget {
  const SunrizaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AIService>(create: (_) => AIService()),
        Provider<VideoStreamService>(create: (_) => VideoStreamService()),
        Provider<AuthService>(create: (_) => AuthService()),
      ],
      child: MaterialApp(
        title: 'Sunriza26 - Live AI Assistant',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF00FF94),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
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
      ),
    );
  }
}
