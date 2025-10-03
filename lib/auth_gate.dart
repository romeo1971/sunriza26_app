/// Auth Gate - Route Protection
/// Stand: 04.09.2025 - Basierend auf struppi-Implementation
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'screens/auth_screen.dart';
import 'screens/home_navigation_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Zeigt einen Ladeindikator, während der Auth-Status geprüft wird
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

        final user = snapshot.data;
        if (user == null) {
          return const AuthScreen();
        }

        // Falls der User in Firebase entfernt wurde, lokale Session säubern
        return FutureBuilder<void>(
          future: user.reload(),
          builder: (context, reloadSnap) {
            // Bei Fehlern (z.B. user-not-found) → ausloggen
            if (reloadSnap.hasError) {
              FirebaseAuth.instance.signOut();
              return const AuthScreen();
            }

            final current = FirebaseAuth.instance.currentUser;
            if (current == null || !(current.emailVerified)) {
              if (current != null && !(current.emailVerified)) {
                FirebaseAuth.instance.signOut();
              }
              return const AuthScreen();
            }

            return const HomeNavigationScreen();
          },
        );

        /* if (user == null || !user.emailVerified) {
          // Wenn User eingeloggt, aber nicht verifiziert, sofort ausloggen
          if (user != null && !user.emailVerified) {
            FirebaseAuth.instance.signOut();
          }
          // Nicht eingeloggt ODER E-Mail nicht bestätigt: AuthScreen anzeigen
          return const AuthScreen();
        }

        // Nur wenn eingeloggt UND E-Mail bestätigt: WelcomeScreen anzeigen
        return const MainNavigationScreen(); */
      },
    );
  }
}
