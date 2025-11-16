import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Zentraler Credits-Service für einfache Checks im Client.
class CreditsService {
  static final FirebaseFirestore _fs = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;

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

  /// Lädt den kumulierten VoiceClone-Chat-Zeichenzähler (für 250er-Zyklen).
  static Future<int> getVoiceCloneChatChars() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return 0;
    try {
      final doc = await _fs.collection('users').doc(uid).get();
      final data = doc.data();
      if (data == null) return 0;
      return (data['voiceCloneChatChars'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Speichert den kumulierten VoiceClone-Chat-Zeichenzähler.
  static Future<void> setVoiceCloneChatChars(int chars) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _fs
          .collection('users')
          .doc(uid)
          .set({'voiceCloneChatChars': chars}, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Versucht, eine bestimmte Anzahl Credits für eine Aktion zu verbrauchen.
  /// Gibt `true` zurück, wenn genug Credits vorhanden waren und die Abbuchung
  /// erfolgreich war, sonst `false`.
  static Future<bool> trySpendCredits({
    required int credits,
    required String actionType, // z.B. 'dynamics', 'liveAvatar', 'voiceClone'
    String? avatarId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final fn = _functions.httpsCallable('spendServiceCredits');
      final result = await fn.call(<String, dynamic>{
        'credits': credits,
        'service': actionType,
        if (avatarId != null) 'avatarId': avatarId,
        if (metadata != null) 'metadata': metadata,
      });
      final data = result.data as Map?;
      return data?['ok'] == true;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'failed-precondition') {
        // Nicht genug Credits
        return false;
      }
      rethrow;
    } catch (_) {
      return false;
    }
  }
}
