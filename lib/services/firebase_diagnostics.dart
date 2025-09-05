import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_database/firebase_database.dart';

class FirebaseDiagnostics {
  static final _auth = FirebaseAuth.instance;
  static final _fs = FirebaseFirestore.instance;
  static final _rt = FirebaseDatabase.instance;
  static final _st = FirebaseStorage.instance;

  static Future<Map<String, dynamic>> runAll() async {
    final result = <String, dynamic>{};

    // Auth
    final user = _auth.currentUser;
    result['auth'] = {'signedIn': user != null, 'uid': user?.uid};

    // Firestore write/read (avatars/_diagnostics)
    try {
      final doc = _fs
          .collection('avatars')
          .doc('_diagnostics_${user?.uid ?? 'anon'}');
      final now = DateTime.now().millisecondsSinceEpoch;
      await doc.set({
        'userId': user?.uid ?? 'anon',
        'updatedAt': now,
        'firstName': 'Diag',
      });
      final snap = await doc.get();
      result['firestore'] = {
        'ok': snap.exists,
        'updatedAt': snap.data()?['updatedAt'],
      };
    } catch (e) {
      result['firestore'] = {'ok': false, 'error': e.toString()};
    }

    // Realtime DB write/read (/diagnostics/uid)
    try {
      final key = _rt.ref('diagnostics/${user?.uid ?? 'anon'}');
      final num = Random().nextInt(100000);
      await key.set({'ts': ServerValue.timestamp, 'rand': num});
      final snap = await key.get();
      result['rtdb'] = {'ok': snap.exists, 'rand': snap.child('rand').value};
    } catch (e) {
      result['rtdb'] = {'ok': false, 'error': e.toString()};
    }

    // Storage list (avatars/uid)
    try {
      if (user != null) {
        final list = await _st.ref('avatars/${user.uid}').listAll();
        result['storage'] = {'ok': true, 'files': list.items.length};
      } else {
        result['storage'] = {'ok': true, 'files': 0};
      }
    } catch (e) {
      result['storage'] = {'ok': false, 'error': e.toString()};
    }

    return result;
  }
}
