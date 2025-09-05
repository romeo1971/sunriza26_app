/// Auth Service für Firebase Authentication
/// Stand: 04.09.2025 - Basierend auf struppi-Implementation
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Aktueller User
  User? get currentUser => _auth.currentUser;

  /// Auth State Stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Ist User eingeloggt?
  bool get isLoggedIn => currentUser != null && currentUser!.emailVerified;

  /// User ID
  String? get userId => currentUser?.uid;

  /// User E-Mail
  String? get userEmail => currentUser?.email;

  /// User Display Name
  String? get userDisplayName => currentUser?.displayName;

  /// E-Mail/Passwort Login
  Future<UserCredential?> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // E-Mail-Verifizierung prüfen
      if (!userCredential.user!.emailVerified) {
        await signOut();
        throw FirebaseAuthException(
          code: 'email-not-verified',
          message: 'Bitte bestätige zuerst deine E-Mail-Adresse.',
        );
      }

      return userCredential;
    } on FirebaseAuthException {
      rethrow;
    }
  }

  /// E-Mail/Passwort Registrierung
  Future<UserCredential?> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // E-Mail-Verifizierung senden
      await userCredential.user?.sendEmailVerification();

      // User-Daten in Firestore speichern
      await _createUserProfile(userCredential.user!);

      return userCredential;
    } on FirebaseAuthException {
      rethrow;
    }
  }

  /// Google Sign-In
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Google Sign-In durchführen
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      // Google Sign-In Credentials abrufen
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Firebase Auth Credentials erstellen
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Mit Firebase anmelden
      final userCredential = await _auth.signInWithCredential(credential);

      // User-Daten in Firestore speichern/aktualisieren
      await _createUserProfile(userCredential.user!);

      return userCredential;
    } on FirebaseAuthException {
      rethrow;
    }
  }

  /// Passwort zurücksetzen
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException {
      rethrow;
    }
  }

  /// E-Mail-Verifizierung erneut senden
  Future<void> sendEmailVerification() async {
    try {
      await currentUser?.sendEmailVerification();
    } on FirebaseAuthException {
      rethrow;
    }
  }

  /// User ausloggen
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
    } catch (e) {
      rethrow;
    }
  }

  /// User-Profil in Firestore erstellen/aktualisieren
  Future<void> _createUserProfile(User user) async {
    try {
      final userDoc = _firestore.collection('users').doc(user.uid);

      final userData = {
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName ?? '',
        'photoURL': user.photoURL ?? '',
        'emailVerified': user.emailVerified,
        'createdAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
        'avatarData': {
          'totalDocuments': 0,
          'lastTrainingAt': null,
          'isTrained': false,
        },
      };

      // User-Daten aktualisieren (merge: true für Updates)
      await userDoc.set(userData, SetOptions(merge: true));
    } catch (e) {
      // print('Fehler beim Erstellen des User-Profils: $e');
      // Nicht rethrow, da Login trotzdem funktionieren soll
    }
  }

  /// User-Profil aktualisieren
  Future<void> updateUserProfile({
    String? displayName,
    String? photoURL,
  }) async {
    try {
      if (currentUser == null) return;

      // Firebase Auth Profile aktualisieren
      await currentUser!.updateDisplayName(displayName);
      if (photoURL != null) {
        await currentUser!.updatePhotoURL(photoURL);
      }

      // Firestore aktualisieren
      await _firestore.collection('users').doc(currentUser!.uid).update({
        'displayName': displayName ?? currentUser!.displayName,
        'photoURL': photoURL ?? currentUser!.photoURL,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      rethrow;
    }
  }

  /// User-Daten aus Firestore abrufen
  Future<Map<String, dynamic>?> getUserData() async {
    try {
      if (currentUser == null) return null;

      final doc = await _firestore
          .collection('users')
          .doc(currentUser!.uid)
          .get();
      return doc.data();
    } catch (e) {
      // print('Fehler beim Abrufen der User-Daten: $e');
      return null;
    }
  }

  /// Avatar-Training-Status aktualisieren
  Future<void> updateAvatarTrainingStatus({
    required int totalDocuments,
    required bool isTrained,
  }) async {
    try {
      if (currentUser == null) return;

      await _firestore.collection('users').doc(currentUser!.uid).update({
        'avatarData.totalDocuments': totalDocuments,
        'avatarData.isTrained': isTrained,
        'avatarData.lastTrainingAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // print('Fehler beim Aktualisieren des Avatar-Status: $e');
    }
  }

  /// User-Daten löschen
  Future<void> deleteUserAccount() async {
    try {
      if (currentUser == null) return;

      // Firestore-Daten löschen
      await _firestore.collection('users').doc(currentUser!.uid).delete();

      // Firebase Auth Account löschen
      await currentUser!.delete();
    } catch (e) {
      rethrow;
    }
  }

  /// Deutsche Fehlermeldungen
  String getGermanErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Bitte gib eine gültige E-Mail-Adresse ein.';
      case 'user-disabled':
        return 'Dieser Account wurde deaktiviert.';
      case 'user-not-found':
        return 'Kein Nutzer mit dieser E-Mail gefunden.';
      case 'wrong-password':
        return 'Das Passwort ist falsch.';
      case 'email-already-in-use':
        return 'Diese E-Mail wird bereits verwendet.';
      case 'weak-password':
        return 'Das Passwort ist zu schwach (mind. 6 Zeichen).';
      case 'missing-email':
        return 'Bitte gib eine E-Mail-Adresse ein.';
      case 'email-not-verified':
        return 'Bitte bestätige zuerst deine E-Mail-Adresse.';
      case 'account-exists-with-different-credential':
        return 'Ein Konto mit dieser E-Mail existiert bereits mit anderen Anmeldedaten.';
      case 'invalid-credential':
        return 'Ungültige Anmeldedaten.';
      case 'operation-not-allowed':
        return 'Diese Anmeldemethode ist nicht aktiviert.';
      case 'network-request-failed':
        return 'Netzwerkfehler. Bitte überprüfe deine Internetverbindung.';
      default:
        return e.message ?? 'Ein Authentifizierungsfehler ist aufgetreten.';
    }
  }
}
