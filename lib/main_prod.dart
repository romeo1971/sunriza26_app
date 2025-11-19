import 'firebase_options.dart';
import 'main.dart' show bootstrapHauauApp;

Future<void> main() async {
  await bootstrapHauauApp(
    envFileName: '.env.prod',
    firebaseOptions: DefaultFirebaseOptions.currentPlatform,
  );
}


