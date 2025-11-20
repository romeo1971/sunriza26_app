/// Auth Screen für Login/Registration
/// Stand: 04.09.2025 - Basierend auf struppi-Implementation
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider;
import 'package:provider/provider.dart';
import '../widgets/custom_text_field.dart';
import '../theme/app_theme.dart';
import '../theme/app_layout.dart';
import '../services/auth_service.dart';
import '../services/language_service.dart';
import '../services/localization_service.dart';
import 'language_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  var _enteredEmail = '';
  var _enteredPassword = '';
  var _isLoading = false;
  var _isAuthenticating = false; // Flag: Verhindert Dialog nach Login

  // GoogleSignIn wird über AuthService genutzt
  final AuthService _authService = AuthService();
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _initializeLanguage();
    // Schließt jedes offene Auth-Dialog-Fenster sofort, sobald ein User eingeloggt ist
    _authSubscription =
        FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (!mounted) return;
      if (user != null) {
        // Alle offenen Dialoge schließen und Auth-UI blockieren
        while (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        setState(() => _isAuthenticating = true);
      }
    });
  }

  // Device-Locale als Startsprache setzen (falls noch keine gesetzt)
  void _initializeLanguage() {
    final languageService = context.read<LanguageService>();
    if (languageService.languageCode == null ||
        languageService.languageCode!.isEmpty) {
      // Device-Locale auslesen
      final deviceLocale = WidgetsBinding.instance.platformDispatcher.locale;
      final languageCode = deviceLocale.languageCode; // z.B. "de", "en", "fr"

      // Unterstützte Sprachen prüfen und setzen
      const supportedLanguages = [
        'ar',
        'bn',
        'cs',
        'da',
        'de',
        'el',
        'en',
        'es',
        'fa',
        'fi',
        'fr',
        'hi',
        'hu',
        'id',
        'it',
        'he',
        'ja',
        'ko',
        'mr',
        'ms',
        'nl',
        'no',
        'pa',
        'pl',
        'pt',
        'ro',
        'ru',
        'sv',
        'te',
        'th',
        'tr',
        'uk',
        'ur',
        'vi',
        'zh',
      ];

      if (supportedLanguages.contains(languageCode)) {
        languageService.setLanguage(languageCode);
      } else {
        languageService.setLanguage('en'); // Fallback: Englisch
      }
    }
  }

  // Flag-Emoji für Sprachcode
  String _getFlagEmoji(String? languageCode) {
    const Map<String, String> flags = {
      'ar': '🇸🇦', // Arabisch → Saudi-Arabien
      'bn': '🇧🇩', // Bangla → Bangladesch
      'cs': '🇨🇿', // Tschechisch → Tschechien
      'da': '🇩🇰', // Dänisch → Dänemark
      'de': '🇩🇪', // Deutsch → Deutschland
      'el': '🇬🇷', // Griechisch → Griechenland
      'en': '🇬🇧', // Englisch → UK
      'es': '🇪🇸', // Spanisch → Spanien
      'fa': '🇮🇷', // Persisch → Iran
      'fi': '🇫🇮', // Finnisch → Finnland
      'fr': '🇫🇷', // Französisch → Frankreich
      'hi': '🇮🇳', // Hindi → Indien
      'hu': '🇭🇺', // Ungarisch → Ungarn
      'id': '🇮🇩', // Indonesisch → Indonesien
      'it': '🇮🇹', // Italienisch → Italien
      'he': '🇮🇱', // Hebräisch → Israel
      'ja': '🇯🇵', // Japanisch → Japan
      'ko': '🇰🇷', // Koreanisch → Südkorea
      'mr': '🇮🇳', // Marathi → Indien
      'ms': '🇲🇾', // Malaiisch → Malaysia
      'nl': '🇳🇱', // Niederländisch → Niederlande
      'no': '🇳🇴', // Norwegisch → Norwegen
      'pa': '🇮🇳', // Punjabi → Indien
      'pl': '🇵🇱', // Polnisch → Polen
      'pt': '🇵🇹', // Portugiesisch → Portugal
      'ro': '🇷🇴', // Rumänisch → Rumänien
      'ru': '🇷🇺', // Russisch → Russland
      'sv': '🇸🇪', // Schwedisch → Schweden
      'te': '🇮🇳', // Telugu → Indien
      'th': '🇹🇭', // Thai → Thailand
      'tr': '🇹🇷', // Türkisch → Türkei
      'uk': '🇺🇦', // Ukrainisch → Ukraine
      'ur': '🇵🇰', // Urdu → Pakistan
      'vi': '🇻🇳', // Vietnamesisch → Vietnam
      'zh': '🇨🇳', // Chinesisch → China
    };
    return flags[languageCode] ?? '🇬🇧'; // Default: UK
  }

  // Auth-Dialog (Login/Registrierung in einem)
  void _showAuthDialog({bool isLogin = true}) {
    // NICHT öffnen wenn bereits eingeloggt!
    if (FirebaseAuth.instance.currentUser != null || _isAuthenticating) {
      return;
    }
    
    final gradients = Theme.of(context).extension<AppGradients>()!;
    final loc = Provider.of<LocalizationService>(context, listen: false);
    final formKey = GlobalKey<FormState>();
    bool currentIsLogin = isLogin;

    // Lokale Controller für den Dialog
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    bool isEmailValid = false;
    bool isPasswordValid = false;
    String enteredEmail = '';
    String enteredPassword = '';

    showDialog(
      context: context,
      barrierDismissible: true,
      useSafeArea: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          // Language Keys
          final loginText = loc.t('auth.login');
          final registerText = loc.t('auth.register');
          final emailText = loc.t('auth.email');
          final passwordText = loc.t('auth.password');
          final emailErrorText = loc.t('auth.emailValidError');
          final passwordErrorText = loc.t('auth.passwordLengthError');
          final orText = loc.t('auth.or');
          final googleSignInText = loc.t('auth.googleSignIn');
          final passwordForgotText = loc.t('auth.passwordForgot');
          final noAccountText = loc.t('auth.noAccount');
          final hasAccountText = loc.t('auth.hasAccount');

          return Dialog(
            backgroundColor: const Color(0xFF111111),
            insetPadding: EdgeInsets.zero,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
            child: SizedBox(
              width: MediaQuery.of(dialogContext).size.width,
              height: MediaQuery.of(dialogContext).size.height,
              child: Stack(
                children: [
                  // Scrollbarer Inhalt mit Content Wrapper
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: 300,
                        maxWidth: AppLayout.maxContentWidth,
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 60,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Title
                            Center(
                              child: ShaderMask(
                                shaderCallback: (bounds) =>
                                    gradients.magentaBlue.createShader(bounds),
                                child: Text(
                                  currentIsLogin ? loginText : registerText,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 32,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 40),
                            // Form Content
                            Form(
                              key: formKey,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Email TextField
                                  CustomTextField(
                                    label: emailText,
                                    controller: emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty ||
                                          !value.contains('@')) {
                                        return emailErrorText;
                                      }
                                      return null;
                                    },
                                    onChanged: (value) {
                                      setDialogState(() {
                                        isEmailValid =
                                            value.contains('@') &&
                                            value.trim().isNotEmpty;
                                        enteredEmail = value;
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 16),

                                  // Password TextField
                                  CustomTextField(
                                    label: passwordText,
                                    controller: passwordController,
                                    obscureText: true,
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().length < 6) {
                                        return passwordErrorText;
                                      }
                                      return null;
                                    },
                                    onChanged: (value) {
                                      setDialogState(() {
                                        isPasswordValid =
                                            value.trim().length >= 6;
                                        enteredPassword = value;
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 24),

                                  // Loading Indicator
                                  if (_isLoading)
                                    ShaderMask(
                                      shaderCallback: (bounds) => gradients
                                          .magentaBlue
                                          .createShader(bounds),
                                      child: const CircularProgressIndicator(
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    ),

                                  // Submit Button
                                  if (!_isLoading)
                                    Container(
                                      width: double.infinity,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        color: (isEmailValid && isPasswordValid)
                                            ? Colors.white
                                            : Colors.white.withValues(
                                                alpha: 0.2,
                                              ),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.3,
                                          ),
                                          width: 1,
                                        ),
                                      ),
                                      child: ElevatedButton(
                                        onPressed:
                                            (isEmailValid && isPasswordValid)
                                            ? () {
                                                if (formKey.currentState!
                                                    .validate()) {
                                                  Navigator.of(
                                                    dialogContext,
                                                  ).pop();
                                                  setState(() {
                                                    _enteredEmail =
                                                        enteredEmail;
                                                    _enteredPassword =
                                                        enteredPassword;
                                                  });
                                                  if (currentIsLogin) {
                                                    _submitLogin(dialogContext);
                                                  } else {
                                                    _submitRegistration(dialogContext);
                                                  }
                                                }
                                              }
                                            : null,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          shadowColor: Colors.transparent,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                        child: (isEmailValid && isPasswordValid)
                                            ? ShaderMask(
                                                shaderCallback: (bounds) =>
                                                    gradients.magentaBlue
                                                        .createShader(bounds),
                                                child: Text(
                                                  currentIsLogin
                                                      ? loginText
                                                      : registerText,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              )
                                            : Text(
                                                currentIsLogin
                                                    ? loginText
                                                    : registerText,
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.5),
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                      ),
                                    ),

                                  const SizedBox(height: 16),

                                  // Toggle zwischen Login/Registrierung
                                  if (!_isLoading)
                                    TextButton(
                                      onPressed: () {
                                        setDialogState(() {
                                          currentIsLogin = !currentIsLogin;
                                        });
                                      },
                                      style: TextButton.styleFrom(
                                        overlayColor: Colors.transparent,
                                      ),
                                      child: ShaderMask(
                                        shaderCallback: (bounds) => gradients
                                            .magentaBlue
                                            .createShader(bounds),
                                        child: Text(
                                          currentIsLogin
                                              ? noAccountText
                                              : hasAccountText,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ),

                                  const SizedBox(height: 16),

                                  // Divider
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Divider(
                                          color: Color(0xFF333333),
                                          thickness: 1,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12.0,
                                        ),
                                        child: Text(
                                          orText,
                                          style: const TextStyle(
                                            color: Color(0xFFAAAAAA),
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const Expanded(
                                        child: Divider(
                                          color: Color(0xFF333333),
                                          thickness: 1,
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 16),

                                  // Google Sign-In Button
                                  if (!_isLoading)
                                    Container(
                                      width: double.infinity,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        gradient: gradients.magentaBlue,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Container(
                                        margin: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF111111),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: ElevatedButton.icon(
                                          icon: const Icon(
                                            Icons.login,
                                            color: Colors.white,
                                          ),
                                          label: Text(
                                            googleSignInText,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          onPressed: _isLoading
                                              ? null
                                              : () => _handleGoogleSignIn(dialogContext),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                  const SizedBox(height: 16),

                                  // Password Reset Button (nur bei Login) oder Platzhalter
                                  TextButton(
                                    onPressed: currentIsLogin
                                        ? () {
                                            Navigator.of(dialogContext).pop();
                                            _showPasswordResetDialog();
                                          }
                                        : null,
                                    style: TextButton.styleFrom(
                                      overlayColor: Colors.transparent,
                                    ),
                                    child: Text(
                                      currentIsLogin ? passwordForgotText : '',
                                      style: TextStyle(
                                        color: currentIsLogin
                                            ? const Color(0xFF888888)
                                            : Colors.transparent,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Close Button oben rechts
                  Positioned(
                    top: 0,
                    right: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.of(dialogContext).pop(),
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _submitLogin(BuildContext dialogContext) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.signInWithEmailAndPassword(
        email: _enteredEmail,
        password: _enteredPassword,
      );

      // Dialog schließen nach erfolgreichem Login
      if (mounted) {
        // Schließe ALLE offenen Dialoge
        while (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        setState(() => _isAuthenticating = true);
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        final loc = Provider.of<LocalizationService>(context, listen: false);

        String errorMessage;
        switch (error.code) {
          case 'invalid-email':
            errorMessage = loc.t('auth.errorInvalidEmail');
            break;
          case 'user-disabled':
            errorMessage = loc.t('auth.errorUserDisabled');
            break;
          case 'user-not-found':
            errorMessage = loc.t('auth.errorUserNotFound');
            break;
          case 'wrong-password':
            errorMessage = loc.t('auth.errorWrongPassword');
            break;
          case 'invalid-credential':
            errorMessage = loc.t('auth.errorInvalidCredential');
            break;
          case 'too-many-requests':
            errorMessage = loc.t('auth.errorTooManyRequests');
            break;
          case 'network-request-failed':
            errorMessage = loc.t('auth.errorNetworkFailed');
            break;
          default:
            errorMessage = loc.t('auth.errorDefault');
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

  void _submitRegistration(BuildContext dialogContext) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.createUserWithEmailAndPassword(
        email: _enteredEmail,
        password: _enteredPassword,
      );

      if (mounted) {
        final loc = Provider.of<LocalizationService>(context, listen: false);
        // Schließe ALLE offenen Dialoge
        while (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        setState(() => _isAuthenticating = true); // Flag NACH Dialog schließen
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.t('auth.registerSuccess')),
            backgroundColor: const Color(0xFF00FF94),
          ),
        );
        setState(() {
          _enteredEmail = '';
          _enteredPassword = '';
          _emailController.clear();
          _passwordController.clear();
        });
        // User bleibt eingeloggt → AuthGate leitet zu Home/Explorer weiter
        return;
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        final loc = Provider.of<LocalizationService>(context, listen: false);

        String errorMessage;
        switch (error.code) {
          case 'invalid-email':
            errorMessage = loc.t('auth.errorInvalidEmail');
            break;
          case 'user-disabled':
            errorMessage = loc.t('auth.errorUserDisabled');
            break;
          case 'user-not-found':
            errorMessage = loc.t('auth.errorUserNotFound');
            break;
          case 'wrong-password':
            errorMessage = loc.t('auth.errorWrongPassword');
            break;
          case 'email-already-in-use':
            errorMessage = loc.t('auth.errorEmailInUse');
            break;
          case 'weak-password':
            errorMessage = loc.t('auth.errorWeakPassword');
            break;
          case 'missing-email':
            errorMessage = loc.t('auth.errorMissingEmail');
            break;
          case 'invalid-credential':
            errorMessage = loc.t('auth.errorInvalidCredential');
            break;
          case 'too-many-requests':
            errorMessage = loc.t('auth.errorTooManyRequests');
            break;
          case 'network-request-failed':
            errorMessage = loc.t('auth.errorNetworkFailed');
            break;
          default:
            errorMessage = loc.t('auth.errorDefault');
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

  void _handleGoogleSignIn(BuildContext dialogContext) async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (kIsWeb) {
        // Web: immer Popup nutzen, Redirect macht auf iOS/Safari Probleme
        final provider = GoogleAuthProvider()
          ..setCustomParameters({
            'prompt': 'select_account',
          });
        final result = await FirebaseAuth.instance.signInWithPopup(provider);
        if (result.user != null) {
          await _authService.createUserProfile(result.user!);
        }
      } else {
        // Mobile: zentral über AuthService (legt User-Dokument in Firestore an)
        await _authService.signInWithGoogle();
      }

      if (mounted) {
        final loc = Provider.of<LocalizationService>(context, listen: false);
        // Schließe ALLE offenen Dialoge
        while (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        setState(() => _isAuthenticating = true); // Flag NACH Dialog schließen
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.t('auth.googleSignInSuccess')),
            backgroundColor: const Color(0xFF00FF94),
          ),
        );
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        final loc = Provider.of<LocalizationService>(context, listen: false);
        String errorMessage;
        switch (error.code) {
          case 'popup-closed-by-user':
            return; // Keine Meldung wenn User abbricht
          case 'cancelled-popup-request':
            return; // Keine Meldung wenn User abbricht
          case 'operation-not-allowed':
            errorMessage = loc.t('auth.errorOperationNotAllowed');
            break;
          case 'unauthorized-domain':
            errorMessage = loc.t('auth.errorUnauthorizedDomain');
            break;
          case 'invalid-credential':
            errorMessage = loc.t('auth.errorInvalidCredential');
            break;
          default:
            errorMessage =
                error.message ?? loc.t('auth.errorGoogleSignInFailed');
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
      // GoogleSignInException wenn User abbricht - KEINE Meldung
      if (e.toString().contains('canceled') ||
          e.toString().contains('cancelled')) {
        return;
      }
      if (mounted) {
        final loc = Provider.of<LocalizationService>(context, listen: false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              loc.t('auth.errorGeneric', params: {'msg': e.toString()}),
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
    final gradients = Theme.of(context).extension<AppGradients>()!;
    final languageService = context.watch<LanguageService>();
    final loc = context.watch<LocalizationService>();
    final currentFlag = _getFlagEmoji(languageService.languageCode);

    // Wenn gerade eingeloggt wird, zeige Loading
    if (_isAuthenticating) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF000000), Color(0xFF111111)],
          ),
        ),
        child: const Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00FF94)),
            ),
          ),
        ),
      );
    }

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
        child: Column(
          children: [
            // Top Navigation - Sprache + Login/Register
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Landesflagge (aktuelle Sprache) - größerer Touch-Bereich
                    InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const LanguageScreen(),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          currentFlag,
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Textlinks für Login/Register - größere Touch-Bereiche
                    TextButton(
                      onPressed: _isAuthenticating ? null : () => _showAuthDialog(isLogin: true),
                      style: TextButton.styleFrom(
                        overlayColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: const Size(80, 44),
                      ),
                      child: Text(
                        loc.t('auth.login'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const Text(
                      '/',
                      style: TextStyle(color: Color(0xFF444444), fontSize: 16),
                    ),
                    TextButton(
                      onPressed: _isAuthenticating ? null : () => _showAuthDialog(isLogin: false),
                      style: TextButton.styleFrom(
                        overlayColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: const Size(100, 44),
                      ),
                      child: Text(
                        loc.t('auth.register'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Main Content - scrollable
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const SizedBox(height: 20),
                      // Logo - 70vw Breite, NICHT umbrechend
                      Center(
                        child: Image.asset(
                          'assets/logo/logo_hauau.png',
                          width: MediaQuery.of(context).size.width * 0.7,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Claim 1 - Hauptslogan (70vw, auto-resize)
                      Center(
                        child: SizedBox(
                          width: MediaQuery.of(context).size.width * 0.7,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: const Text(
                              'DEIN AVATAR IN 2 MINUTEN LIVE',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w300,
                                fontSize: 24,
                                height: 1,
                                fontFamily: 'Roboto',
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Sub-Text unter Claim 1
                      Center(
                        child: SizedBox(
                          width: MediaQuery.of(context).size.width * 0.7,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: const Text(
                              'Uploade Dein Foto und Deine Stimmprobe und los geht\'s',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFFBBBBBB),
                                fontWeight: FontWeight.w300,
                                fontSize: 18,
                                height: 1,
                                fontFamily: 'Roboto',
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Claim 2 - Beschreibung (responsive fontSize, center)
                      Center(
                        child: SizedBox(
                          width: MediaQuery.of(context).size.width * 0.7,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final double responsiveFontSize =
                                  constraints.maxWidth > 300 ? 15 : 13;
                              return Text(
                                'Im privaten 1:1 Chat antwortet Dein Avatar 24/7 weltweit mit Deiner Stimme. Sieht aus wie du und klingt und antwortet wie du.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: const Color(0xFFBBBBBB),
                                  fontSize: responsiveFontSize,
                                  fontWeight: FontWeight.w300,
                                  height: 1.4,
                                  fontFamily: 'Roboto',
                                  letterSpacing: 0.2,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Claim 3 - Use Cases
                      Center(
                        child: SizedBox(
                          width: MediaQuery.of(context).size.width * 0.7,
                          child: Column(
                            children: [
                              ShaderMask(
                                shaderCallback: (bounds) =>
                                    gradients.magentaBlue.createShader(bounds),
                                child: const Text(
                                  'Wer erreicht wen?',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Roboto',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Artists → Fans, Marketer → Kunden, Coaches → Schüler',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  height: 1.5,
                                  fontFamily: 'Roboto',
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Sei erreichbar und antworte, wenn Du grad kein Zeit hast.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  height: 1.5,
                                  fontFamily: 'Roboto',
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Menschen bleiben unvergessen - lege z.B. einen Avatar für geliebte Menschen an, die nicht mehr da sind und halte sie und ihre Geschichten am Leben.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w300,
                                  height: 1.6,
                                  fontFamily: 'Roboto',
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 60),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPasswordResetDialog() {
    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isValidEmail = false;
    final gradients = Theme.of(context).extension<AppGradients>()!;
    final loc = Provider.of<LocalizationService>(context, listen: false);

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          backgroundColor: const Color(0xFF111111),
          title: ShaderMask(
            shaderCallback: (bounds) =>
                gradients.magentaBlue.createShader(bounds),
            child: Text(
              loc.t('auth.passwordResetTitle'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          content: Form(
            key: formKey,
            child: CustomTextField(
              label: loc.t('auth.email'),
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null ||
                    value.trim().isEmpty ||
                    !value.contains('@')) {
                  return loc.t('auth.emailValidError');
                }
                return null;
              },
              onChanged: (value) {
                setState(() {
                  isValidEmail = value.contains('@') && value.trim().isNotEmpty;
                });
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: TextButton.styleFrom(overlayColor: Colors.transparent),
              child: Text(
                loc.t('buttons.cancel'),
                style: const TextStyle(
                  color: Color(0xFF888888),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              height: 40,
              decoration: BoxDecoration(
                gradient: isValidEmail ? gradients.magentaBlue : null,
                color: isValidEmail ? null : Colors.grey.shade800,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ElevatedButton(
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
                                SnackBar(
                                  content: Text(
                                    loc.t('auth.passwordResetSuccess'),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  backgroundColor: AppColors.primaryGreen,
                                ),
                              );
                            }
                          } on FirebaseAuthException catch (e) {
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    loc.t(
                                      'auth.errorGeneric',
                                      params: {'msg': e.message ?? ''},
                                    ),
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  loc.t('auth.passwordResetButton'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
