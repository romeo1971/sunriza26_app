/// Debug Auth Screen für Testing
/// Stand: 04.09.2025

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';

class DebugAuthScreen extends StatefulWidget {
  const DebugAuthScreen({super.key});

  @override
  State<DebugAuthScreen> createState() => _DebugAuthScreenState();
}

class _DebugAuthScreenState extends State<DebugAuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  String _status = 'Bereit';
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        title: const Text('Debug Auth', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF111111),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Status
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Status: $_status',
                style: const TextStyle(color: Colors.white),
              ),
            ),

            const SizedBox(height: 20),

            // E-Mail Input
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'E-Mail',
                labelStyle: TextStyle(color: Color(0xFF00FF94)),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF333333)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF00FF94)),
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),

            const SizedBox(height: 16),

            // Password Input
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Passwort',
                labelStyle: TextStyle(color: Color(0xFF00FF94)),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF333333)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF00FF94)),
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),

            const SizedBox(height: 20),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _testRegistration,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00FF94),
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('Registrierung testen'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _testLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF333333),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Login testen'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Firebase Auth Status
            StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator();
                }

                final user = snapshot.data;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Firebase Auth Status:',
                        style: const TextStyle(
                          color: Color(0xFF00FF94),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Eingeloggt: ${user != null ? "Ja" : "Nein"}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      if (user != null) ...[
                        Text(
                          'E-Mail: ${user.email ?? "N/A"}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        Text(
                          'E-Mail verifiziert: ${user.emailVerified ? "Ja" : "Nein"}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        Text(
                          'UID: ${user.uid}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testRegistration() async {
    setState(() {
      _isLoading = true;
      _status = 'Registrierung läuft...';
    });

    try {
      final userCredential = await _authService.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (userCredential != null) {
        setState(() {
          _status = 'Registrierung erfolgreich! E-Mail-Verifizierung gesendet.';
        });

        // User ausloggen nach Registrierung
        await _authService.signOut();
      } else {
        setState(() {
          _status =
              'Registrierung fehlgeschlagen: Kein UserCredential zurückgegeben';
        });
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _status = 'Registrierung fehlgeschlagen: ${e.code} - ${e.message}';
      });
    } catch (e) {
      setState(() {
        _status = 'Registrierung fehlgeschlagen: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testLogin() async {
    setState(() {
      _isLoading = true;
      _status = 'Login läuft...';
    });

    try {
      final userCredential = await _authService.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (userCredential != null) {
        setState(() {
          _status = 'Login erfolgreich!';
        });
      } else {
        setState(() {
          _status = 'Login fehlgeschlagen: Kein UserCredential zurückgegeben';
        });
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _status = 'Login fehlgeschlagen: ${e.code} - ${e.message}';
      });
    } catch (e) {
      setState(() {
        _status = 'Login fehlgeschlagen: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
