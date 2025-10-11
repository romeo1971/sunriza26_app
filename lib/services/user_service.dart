import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
      final updateData = <String, dynamic>{
        'email': u.email,
        'updatedAt': now,
      };
      if (displayName != null) {
        updateData['displayName'] = displayName;
      }
      await doc.update(updateData);
    } else {
      await doc.set({
        'uid': u.uid,
        'email': u.email,
        'displayName': displayName ?? u.displayName,
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

  Future<String?> uploadProfileImage(File file) async {
    final u = _auth.currentUser!;

    debugPrint('🔍 Deleting old photos from: users/${u.uid}/images/profileImage/');

    // 1. Lösche ALLE alten Fotos im profileImage/ Ordner
    final profileImageDir = _st.ref('users/${u.uid}/images/profileImage/');
    try {
      final listResult = await profileImageDir.listAll();
      debugPrint('📋 Found ${listResult.items.length} files to delete');

      for (final item in listResult.items) {
        debugPrint('🗑️ Deleting: ${item.fullPath}');
        await item.delete();
        debugPrint('✅ Deleted: ${item.name}');
      }
    } catch (e) {
      debugPrint('⚠️ Could not delete old photos: $e');
    }

    // 2. Lade neues Foto hoch
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ref = _st.ref(
      'users/${u.uid}/images/profileImage/profile_$timestamp.jpg',
    );
    debugPrint('📤 Uploading to: ${ref.fullPath}');

    final snap = await ref.putFile(file);
    final url = await snap.ref.getDownloadURL();
    debugPrint('✅ New photo uploaded: $url');

    // 3. Update Firestore - wird vom Screen gemacht
    // (Screen macht das über updateUserProfile mit copyWith)
    return url;
  }

  Future<bool> deleteProfileImage() async {
    final u = _auth.currentUser!;
    final doc = await _col.doc(u.uid).get();
    final url = (doc.data() ?? {})['profileImageUrl'] as String?;
    if (url == null) return true;
    try {
      await _st.refFromURL(url).delete();
    } catch (_) {}
    await _col.doc(u.uid).update({
      'profileImageUrl': null,
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
