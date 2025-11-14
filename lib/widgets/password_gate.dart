import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

/// Passwort-Overlay für Web (nur während Testphase)
class PasswordGate extends StatefulWidget {
  final Widget child;
  const PasswordGate({super.key, required this.child});

  @override
  State<PasswordGate> createState() => _PasswordGateState();
}

class _PasswordGateState extends State<PasswordGate> {
  final TextEditingController _passwordController = TextEditingController();
  bool _isAuthenticated = false;
  bool _isLoading = true;
  bool _showError = false;

  @override
  void initState() {
    super.initState();
    _checkPassword();
  }

  Future<void> _checkPassword() async {
    if (!kIsWeb) {
      // Nicht Web → direkt durchlassen
      setState(() {
        _isAuthenticated = true;
        _isLoading = false;
      });
      return;
    }

    // Web: Prüfe ob Passwort bereits eingegeben wurde
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool('web_password_verified') ?? false;
      setState(() {
        _isAuthenticated = saved;
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _verifyPassword() async {
    if (_passwordController.text.trim() != 'mallorca2026') {
      setState(() {
        _showError = true;
      });
      return;
    }

    // Passwort korrekt → speichern
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('web_password_verified', true);
      setState(() {
        _isAuthenticated = true;
        _showError = false;
      });
    } catch (_) {
      // Fehler ignorieren
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return widget.child;
    }

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentGreenDark),
          ),
        ),
      );
    }

    if (!_isAuthenticated) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'HAU·AU',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 48),
                const Text(
                  'Bitte Passwort eingeben',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppColors.accentGreenDark,
                        width: 2,
                      ),
                    ),
                    hintText: 'Passwort',
                    hintStyle: const TextStyle(color: Colors.white54),
                  ),
                  onSubmitted: (_) => _verifyPassword(),
                ),
                if (_showError) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Falsches Passwort',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 14,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _verifyPassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentGreenDark,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Bestätigen',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return widget.child;
  }
}

