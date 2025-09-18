/// Auth Screen für Login/Registration
/// Stand: 04.09.2025 - Basierend auf struppi-Implementation
library;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider;
import '../widgets/primary_button.dart';
import '../services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  var _isLogin = true;
  var _enteredEmail = '';
  var _enteredPassword = '';
  var _isLoading = false;
  bool _isEmailValid = false;
  bool _isPasswordValid = false;

  // GoogleSignIn wird über AuthService genutzt
  final AuthService _authService = AuthService();

  bool get _isFormValid => _isEmailValid && _isPasswordValid;

  void _validateEmail(String value) {
    setState(() {
      _isEmailValid = value.contains('@') && value.trim().isNotEmpty;
    });
  }

  void _validatePassword(String value) {
    setState(() {
      _isPasswordValid = value.trim().length >= 6;
    });
  }

  void _submit() async {
    if (!_form.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (_isLogin) {
        await _authService.signInWithEmailAndPassword(
          email: _enteredEmail,
          password: _enteredPassword,
        );
      } else {
        await _authService.createUserWithEmailAndPassword(
          email: _enteredEmail,
          password: _enteredPassword,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Registrierung erfolgreich! Bitte bestätige deine E-Mail-Adresse. Prüfe dein Postfach.',
              ),
              backgroundColor: Color(0xFF00FF94),
            ),
          );
          setState(() {
            _isLogin = true;
            _enteredEmail = '';
            _enteredPassword = '';
            _isEmailValid = false;
            _isPasswordValid = false;
            _emailController.clear();
            _passwordController.clear();
          });
          await _authService.signOut();
          return;
        }
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();

        // Deutsche Fehlermeldungen
        String errorMessage;
        switch (error.code) {
          case 'invalid-email':
            errorMessage = 'Bitte gib eine gültige E-Mail-Adresse ein.';
            break;
          case 'user-disabled':
            errorMessage = 'Dieser Account wurde deaktiviert.';
            break;
          case 'user-not-found':
            errorMessage = 'Kein Nutzer mit dieser E-Mail gefunden.';
            break;
          case 'wrong-password':
            errorMessage = 'Das Passwort ist falsch.';
            break;
          case 'email-already-in-use':
            errorMessage = 'Diese E-Mail wird bereits verwendet.';
            break;
          case 'weak-password':
            errorMessage = 'Das Passwort ist zu schwach (mind. 6 Zeichen).';
            break;
          case 'missing-email':
            errorMessage = 'Bitte gib eine E-Mail-Adresse ein.';
            break;
          default:
            errorMessage =
                error.message ??
                'Ein Authentifizierungsfehler ist aufgetreten.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage,
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (kIsWeb) {
        // Web: Firebase Popup-Flow (kein google_sign_in Plugin nötig)
        final provider = GoogleAuthProvider();
        provider.setCustomParameters({'prompt': 'select_account'});
        await FirebaseAuth.instance.signInWithPopup(provider);
      } else {
        // Mobile: zentral über AuthService (legt User-Dokument in Firestore an)
        await _authService.signInWithGoogle();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erfolgreich mit Google angemeldet!'),
            backgroundColor: Color(0xFF00FF94),
          ),
        );
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        String errorMessage;
        switch (error.code) {
          case 'popup-closed-by-user':
            errorMessage = 'Anmeldung abgebrochen.';
            break;
          case 'cancelled-popup-request':
            errorMessage = 'Anfrage abgebrochen.';
            break;
          case 'operation-not-allowed':
            errorMessage = 'Google Sign-In ist nicht aktiviert.';
            break;
          case 'unauthorized-domain':
            errorMessage =
                'Domain nicht autorisiert. Füge localhost in Firebase hinzu.';
            break;
          case 'invalid-credential':
            errorMessage = 'Ungültige Anmeldedaten.';
            break;
          default:
            errorMessage = error.message ?? 'Google-Anmeldung fehlgeschlagen.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage,
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Fehler: ${e.toString()}',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF000000), Color(0xFF111111)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Logo/Branding
                Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FF94).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(60),
                  ),
                  child: const Icon(
                    Icons.psychology,
                    color: Color(0xFF00FF94),
                    size: 60,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'SUNRIZA26',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 32,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Erwecke mit Sunriza Erinnerungen zum Leben',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFFCCCCCC),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 40),

                // Login/Registration Form
                Form(
                  key: _form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Email TextField
                      TextFormField(
                        decoration: InputDecoration(
                          labelText: 'E-Mail-Adresse',
                          labelStyle: const TextStyle(color: Color(0xFFCCCCCC)),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF333333),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF333333),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF00FF94),
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.red),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.red),
                          ),
                          filled: true,
                          fillColor: const Color(
                            0xFF111111,
                          ).withValues(alpha: 0.5),
                          errorStyle: const TextStyle(color: Colors.red),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        textCapitalization: TextCapitalization.none,
                        style: const TextStyle(color: Colors.white),
                        validator: (value) {
                          if (value == null ||
                              value.trim().isEmpty ||
                              !value.contains('@')) {
                            return 'Bitte gib eine gültige E-Mail-Adresse ein.';
                          }
                          return null;
                        },
                        controller: _emailController,
                        onSaved: (value) {
                          _enteredEmail = value!;
                        },
                        onChanged: (value) {
                          _validateEmail(value);
                          _enteredEmail = value;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Password TextField
                      TextFormField(
                        decoration: InputDecoration(
                          labelText: 'Passwort',
                          labelStyle: const TextStyle(color: Color(0xFFCCCCCC)),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF333333),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF333333),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF00FF94),
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.red),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.red),
                          ),
                          filled: true,
                          fillColor: const Color(
                            0xFF111111,
                          ).withValues(alpha: 0.5),
                          errorStyle: const TextStyle(color: Colors.red),
                        ),
                        obscureText: true,
                        style: const TextStyle(color: Colors.white),
                        validator: (value) {
                          if (value == null || value.trim().length < 6) {
                            return 'Das Passwort muss mindestens 6 Zeichen lang sein.';
                          }
                          return null;
                        },
                        controller: _passwordController,
                        onSaved: (value) {
                          _enteredPassword = value!;
                        },
                        onChanged: (value) {
                          _validatePassword(value);
                          _enteredPassword = value;
                        },
                      ),
                      const SizedBox(height: 20),

                      // Loading Indicator
                      if (_isLoading)
                        const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF00FF94),
                          ),
                        ),

                      // Submit Button
                      if (!_isLoading)
                        PrimaryButton(
                          text: _isLogin ? 'Anmelden' : 'Registrieren',
                          onPressed: _isFormValid ? _submit : null,
                        ),

                      // Toggle Login/Registration
                      if (!_isLoading)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isLogin = !_isLogin;
                            });
                          },
                          child: Text(
                            _isLogin
                                ? 'Noch kein Konto? Registrieren'
                                : 'Bereits registriert? Anmelden',
                            style: const TextStyle(color: Color(0xFF00FF94)),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Divider
                const Row(
                  children: [
                    Expanded(child: Divider(color: Color(0xFF333333))),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        'ODER',
                        style: TextStyle(color: Color(0xFF666666)),
                      ),
                    ),
                    Expanded(child: Divider(color: Color(0xFF333333))),
                  ],
                ),

                const SizedBox(height: 20),

                // Google Sign-In Button
                if (!_isLoading)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.login, color: Colors.white),
                    label: const Text(
                      'Mit Google anmelden',
                      style: TextStyle(color: Colors.white),
                    ),
                    onPressed: _isLoading ? null : _handleGoogleSignIn,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF333333)),
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),

                // Password Reset Button
                if (_isLogin && !_isLoading)
                  TextButton(
                    onPressed: () {
                      _showPasswordResetDialog();
                    },
                    child: const Text(
                      'Passwort vergessen?',
                      style: TextStyle(color: Color(0xFF666666)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPasswordResetDialog() {
    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isValidEmail = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          backgroundColor: const Color(0xFF111111),
          title: const Text(
            'Passwort zurücksetzen',
            style: TextStyle(color: Colors.white),
          ),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: emailController,
              decoration: InputDecoration(
                labelText: 'E-Mail-Adresse',
                labelStyle: const TextStyle(color: Color(0xFFCCCCCC)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF333333)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF333333)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF00FF94)),
                ),
                filled: true,
                fillColor: const Color(0xFF000000).withValues(alpha: 0.5),
              ),
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white),
              onChanged: (value) {
                setState(() {
                  isValidEmail = value.contains('@') && value.trim().isNotEmpty;
                });
              },
              validator: (value) {
                if (value == null ||
                    value.trim().isEmpty ||
                    !value.contains('@')) {
                  return 'Bitte eine gültige E-Mail-Adresse eingeben.';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Abbrechen',
                style: TextStyle(color: Color(0xFF00FF94)),
              ),
            ),
            PrimaryButton(
              text: 'Passwort zurücksetzen',
              onPressed: isValidEmail
                  ? () async {
                      if (formKey.currentState!.validate()) {
                        try {
                          await FirebaseAuth.instance.sendPasswordResetEmail(
                            email: emailController.text.trim(),
                          );
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'E-Mail zum Zurücksetzen des Passworts wurde gesendet.',
                                  style: TextStyle(color: Colors.white),
                                ),
                                backgroundColor: Color(0xFF00FF94),
                              ),
                            );
                          }
                        } on FirebaseAuthException catch (e) {
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(
                                content: Text('Fehler: ${e.message}'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      }
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
