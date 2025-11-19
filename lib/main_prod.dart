import 'firebase_options.dart';
import 'main.dart' show bootstrapSunrizaApp;

Future<void> main() async {
  await bootstrapSunrizaApp(
    envFileName: '.env.prod',
    firebaseOptions: DefaultFirebaseOptions.currentPlatform,
  );
}


