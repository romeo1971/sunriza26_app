import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class LanguageService extends ChangeNotifier {
  LanguageService() {
    _sub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) return;
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        _languageCode = (doc.data()?['language'] as String?)?.trim();
        notifyListeners();
      } catch (_) {}
    });
  }

  StreamSubscription<User?>? _sub;
  String? _languageCode;

  String? get languageCode => _languageCode;

  Future<void> setLanguage(String code) async {
    _languageCode = code;
    notifyListeners();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'language': code,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
