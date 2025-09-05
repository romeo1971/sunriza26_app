import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'auth_gate.dart';
import 'services/ai_service.dart';
import 'services/video_stream_service.dart';
import 'services/auth_service.dart';
import 'screens/avatar_upload_memories_screen.dart';
import 'screens/avatar_details_screen.dart';
import 'screens/avatar_chat_screen.dart';
import 'screens/avatar_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase initialisieren
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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
        },
      ),
    );
  }
}
