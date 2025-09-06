import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/legal_page.dart';

class LegalService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Legal Pages aus Firestore laden
  Future<LegalPage?> getLegalPage(String type) async {
    try {
      final doc = await _firestore.collection('legal_pages').doc(type).get();

      if (doc.exists && doc.data() != null) {
        return LegalPage.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      debugPrint('Error loading legal page: $e');
      return null;
    }
  }

  // Legal Page speichern (nur für Admins)
  Future<bool> saveLegalPage(LegalPage page) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final updatedPage = page.copyWith(
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        createdBy: user.uid,
      );

      await _firestore
          .collection('legal_pages')
          .doc(page.type)
          .set(updatedPage.toMap(), SetOptions(merge: true));

      return true;
    } catch (e) {
      debugPrint('Error saving legal page: $e');
      return false;
    }
  }

  // Prüfen ob User Admin ist (vereinfacht)
  Future<bool> isAdmin() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final doc = await _firestore.collection('users').doc(user.uid).get();

      if (doc.exists && doc.data() != null) {
        return (doc.data()!['isAdmin'] as bool?) ?? false;
      }
      return false;
    } catch (e) {
      debugPrint('Error checking admin status: $e');
      return false;
    }
  }

  // Default Legal Pages erstellen falls nicht vorhanden
  Future<void> createDefaultLegalPages() async {
    try {
      final types = ['terms', 'imprint', 'privacy'];
      final now = DateTime.now().millisecondsSinceEpoch;

      for (String type in types) {
        final existing = await getLegalPage(type);
        if (existing == null) {
          final defaultPage = LegalPage(
            id: type,
            type: type,
            title: _getDefaultTitle(type),
            content: _getDefaultContent(type),
            isHtml: false,
            createdAt: now,
            updatedAt: now,
            createdBy: _auth.currentUser?.uid,
          );

          await saveLegalPage(defaultPage);
        }
      }
    } catch (e) {
      debugPrint('Error creating default legal pages: $e');
    }
  }

  String _getDefaultTitle(String type) {
    switch (type) {
      case 'terms':
        return 'Allgemeine Geschäftsbedingungen';
      case 'imprint':
        return 'Impressum';
      case 'privacy':
        return 'Datenschutzerklärung';
      default:
        return 'Rechtliche Informationen';
    }
  }

  String _getDefaultContent(String type) {
    switch (type) {
      case 'terms':
        return '''
1. Geltungsbereich
Diese Allgemeinen Geschäftsbedingungen gelten für alle Leistungen der Sunriza App.

2. Vertragsschluss
Der Vertrag kommt durch die Registrierung in der App zustande.

3. Leistungen
Wir bieten AI-Avatar-Erstellung und Chat-Services.

4. Haftung
Die Haftung richtet sich nach den gesetzlichen Bestimmungen.

Stand: ${DateTime.now().year}
        ''';
      case 'imprint':
        return '''
Angaben gemäß § 5 TMG

Verantwortlich für den Inhalt:
[Firmenname]
[Adresse]
[PLZ Ort]

Kontakt:
E-Mail: info@sunriza.com
Telefon: [Telefonnummer]

Registereintrag:
[Handelsregister-Informationen]

Stand: ${DateTime.now().year}
        ''';
      case 'privacy':
        return '''
Datenschutzerklärung

1. Datenerhebung
Wir erheben personenbezogene Daten nur im Rahmen der App-Nutzung.

2. Verwendung
Die Daten werden zur Bereitstellung unserer Services verwendet.

3. Speicherung
Daten werden sicher in Firebase gespeichert.

4. Ihre Rechte
Sie haben das Recht auf Auskunft, Berichtigung und Löschung.

Stand: ${DateTime.now().year}
        ''';
      default:
        return 'Hier können rechtliche Informationen eingefügt werden.';
    }
  }
}
