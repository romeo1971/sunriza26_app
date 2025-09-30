import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageService extends ChangeNotifier {
  LanguageService({String? initialLanguageCode}) {
    // 0) Sofort mit initialem Code starten (aus main.dart, bereits aus Firebase geladen)
    if (initialLanguageCode != null && initialLanguageCode.isNotEmpty) {
      _languageCode = initialLanguageCode;
    }

    // 1) Dann lokal nachladen (falls sich was geändert hat)
    _loadFromPrefs();

    // 2) Falls bereits angemeldet, einmalig aus Firestore lesen
    final cur = FirebaseAuth.instance.currentUser;
    if (cur != null) {
      _loadFromFirestore(cur.uid);
    }

    // 3) Auf spätere An-/Abmeldungen reagieren
    _sub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) return;
      _loadFromFirestore(user.uid);
    });
  }

  StreamSubscription<User?>? _sub;
  String? _languageCode;

  String? get languageCode => _languageCode;

  Future<void> setLanguage(String code) async {
    _languageCode = code;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('language_code', code);
    } catch (_) {}
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'language': code,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('language_code');
      if (saved != null && saved.isNotEmpty && saved != _languageCode) {
        _languageCode = saved;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _loadFromFirestore(String uid) async {
    try {
      final users = FirebaseFirestore.instance.collection('users');
      final docRef = users.doc(uid);
      final doc = await docRef.get();
      final code = (doc.data()?['language'] as String?)?.trim();
      if (code != null && code.isNotEmpty) {
        if (code != _languageCode) {
          _languageCode = code;
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('language_code', code);
          } catch (_) {}
          notifyListeners();
        }
      } else {
        // Kein language-Feld vorhanden → auf 'en' defaulten und persistieren
        try {
          await docRef.set({'language': 'en'}, SetOptions(merge: true));
          _languageCode = 'en';
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('language_code', 'en');
          } catch (_) {}
          notifyListeners();
        } catch (_) {}
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
