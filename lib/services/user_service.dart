import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as p;
import '../models/user_profile.dart';

class UserService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseStorage _st = FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get _col => _fs.collection('users');

  Future<UserProfile> upsertCurrentUserProfile({String? displayName}) async {
    final u = _auth.currentUser!;
    final now = DateTime.now().millisecondsSinceEpoch;

    final doc = _col.doc(u.uid);
    final snap = await doc.get();
    if (snap.exists) {
      await doc.update({
        'email': u.email,
        'displayName': displayName ?? u.displayName,
        'updatedAt': now,
      });
    } else {
      await doc.set({
        'uid': u.uid,
        'email': u.email,
        'displayName': displayName ?? u.displayName,
        'photoUrl': u.photoURL,
        'isOnboarded': false,
        'createdAt': now,
        'updatedAt': now,
      });
    }
    final data = (await doc.get()).data()!;
    return UserProfile.fromMap(data);
  }

  Future<UserProfile?> getCurrentUserProfile() async {
    final u = _auth.currentUser;
    if (u == null) return null;
    final snap = await _col.doc(u.uid).get();
    if (!snap.exists) return null;
    return UserProfile.fromMap(snap.data()!);
  }

  Future<String?> uploadUserPhoto(File file) async {
    final u = _auth.currentUser!;
    final name =
        '${DateTime.now().millisecondsSinceEpoch}_${p.basename(file.path)}';
    final ref = _st.ref('users/${u.uid}/photos/$name');
    final snap = await ref.putFile(file);
    final url = await snap.ref.getDownloadURL();
    await _col.doc(u.uid).update({
      'photoUrl': url,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
    return url;
  }

  Future<bool> deleteUserPhoto() async {
    final u = _auth.currentUser!;
    final doc = await _col.doc(u.uid).get();
    final url = (doc.data() ?? {})['photoUrl'] as String?;
    if (url == null) return true;
    try {
      await _st.refFromURL(url).delete();
    } catch (_) {}
    await _col.doc(u.uid).update({
      'photoUrl': null,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
    return true;
  }

  Future<void> markOnboarded(bool value) async {
    final u = _auth.currentUser!;
    await _col.doc(u.uid).update({
      'isOnboarded': value,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // Erweiterte Profil-Update-Methode
  Future<void> updateUserProfile(UserProfile profile) async {
    await _col.doc(profile.uid).set(profile.toMap(), SetOptions(merge: true));
  }
}
