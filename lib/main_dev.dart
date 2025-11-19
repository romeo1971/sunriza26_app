import 'firebase_options_dev.dart';
import 'main.dart' show bootstrapSunrizaApp;

Future<void> main() async {
  await bootstrapSunrizaApp(
    envFileName: '.env.dev',
    firebaseOptions: DefaultFirebaseOptions.currentPlatform,
  );
}


