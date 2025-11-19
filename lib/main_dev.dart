import 'firebase_options_dev.dart';
import 'main.dart' show bootstrapHauauApp;

Future<void> main() async {
  await bootstrapHauauApp(
    envFileName: '.env.dev',
    firebaseOptions: DefaultFirebaseOptions.currentPlatform,
  );
}


