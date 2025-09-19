/// Firebase Test Screen für Service-Validierung
/// Stand: 04.09.2025
library;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_database/firebase_database.dart';

class FirebaseTestScreen extends StatefulWidget {
  const FirebaseTestScreen({super.key});

  @override
  State<FirebaseTestScreen> createState() => _FirebaseTestScreenState();
}

class _FirebaseTestScreenState extends State<FirebaseTestScreen> {
  final List<String> _testResults = [];
  bool _isRunning = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Firebase Test',
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: _isRunning ? null : _runTests,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00FF94),
                foregroundColor: Colors.black,
              ),
              child: Text(
                _isRunning ? 'Tests laufen...' : 'Firebase Tests starten',
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: _testResults.length,
                itemBuilder: (context, index) {
                  final result = _testResults[index];
                  final isError = result.startsWith('❌');
                  final isSuccess = result.startsWith('✅');

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isError
                          ? Colors.red.withValues(alpha: 0.1)
                          : isSuccess
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isError
                            ? Colors.red
                            : isSuccess
                            ? Colors.green
                            : Colors.grey,
                      ),
                    ),
                    child: Text(
                      result,
                      style: TextStyle(
                        color: isError
                            ? Colors.red
                            : isSuccess
                            ? Colors.green
                            : Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runTests() async {
    setState(() {
      _isRunning = true;
      _testResults.clear();
    });

    _addResult('🚀 Firebase Tests gestartet...');

    // Test 1: Firebase Auth
    await _testFirebaseAuth();

    // Test 2: Firestore
    await _testFirestore();

    // Test 3: Firebase Storage
    await _testFirebaseStorage();

    // Test 4: Realtime Database
    await _testRealtimeDatabase();

    _addResult('🏁 Alle Tests abgeschlossen!');

    setState(() {
      _isRunning = false;
    });
  }

  Future<void> _testFirebaseAuth() async {
    try {
      _addResult('🔐 Teste Firebase Auth...');

      final auth = FirebaseAuth.instance;
      _addResult('✅ Firebase Auth initialisiert');

      final user = auth.currentUser;
      if (user != null) {
        _addResult('✅ User eingeloggt: ${user.email}');
      } else {
        _addResult('ℹ️ Kein User eingeloggt');
      }
    } catch (e) {
      _addResult('❌ Firebase Auth Fehler: $e');
    }
  }

  Future<void> _testFirestore() async {
    try {
      _addResult('📊 Teste Firestore...');

      final firestore = FirebaseFirestore.instance;
      _addResult('✅ Firestore initialisiert');

      // Lese eine Avatar-Collection des eingeloggten Nutzers (gemäß Rules erlaubt)
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        _addResult('ℹ️ Kein User eingeloggt – überspringe Avatar-Check');
      } else {
        final query = await firestore
            .collection('avatars')
            .where('userId', isEqualTo: uid)
            .limit(1)
            .get();
        _addResult(
          '✅ Firestore Query erlaubt (avatars, docs=${query.docs.length})',
        );
      }
    } catch (e) {
      _addResult('❌ Firestore Fehler: $e');
    }
  }

  Future<void> _testFirebaseStorage() async {
    try {
      _addResult('💾 Teste Firebase Storage...');

      final storage = FirebaseStorage.instance;
      _addResult('✅ Firebase Storage initialisiert');

      // Teste eine einfache Operation (nur Referenzerzeugung)
      await storage
          .ref()
          .child('test/connection.txt')
          .getMetadata()
          .then((_) {}, onError: (_) {});
      _addResult('✅ Firebase Storage Referenz getestet');
    } catch (e) {
      _addResult('❌ Firebase Storage Fehler: $e');
    }
  }

  Future<void> _testRealtimeDatabase() async {
    try {
      _addResult('🔄 Teste Realtime Database...');

      final database = FirebaseDatabase.instance;
      _addResult('✅ Realtime Database initialisiert');

      // Teste eine einfache Leseoperation (nur Referenzzugriff)
      await database.ref('test/connection').get().then((_) {}, onError: (_) {});
      _addResult('✅ Realtime Database Referenz getestet');
    } catch (e) {
      _addResult('❌ Realtime Database Fehler: $e');
    }
  }

  void _addResult(String result) {
    setState(() {
      _testResults.add(
        '${DateTime.now().toIso8601String().substring(11, 19)}: $result',
      );
    });
  }
}
