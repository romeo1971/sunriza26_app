import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Zentraler Credits-Service für einfache Checks im Client.
class CreditsService {
  static final FirebaseFirestore _fs = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Lädt aktuelles Credits-Guthaben des eingeloggten Users.
  static Future<int> getUserCredits() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return 0;
    try {
      final doc = await _fs.collection('users').doc(uid).get();
      final data = doc.data();
      if (data == null) return 0;
      return (data['credits'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }
}


