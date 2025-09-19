import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../screens/user_profile_screen.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final authService = Provider.of<AuthService>(context, listen: false);

    return Drawer(
      backgroundColor: Colors.black,
      child: Column(
        children: [
          // Header mit Benutzerinfo
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.accentGreenDark, AppColors.greenBlue],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white,
                  backgroundImage: user?.photoURL != null
                      ? NetworkImage(user!.photoURL!)
                      : null,
                  child: user?.photoURL == null
                      ? const Icon(
                          Icons.person,
                          size: 30,
                          color: AppColors.accentGreenDark,
                        )
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  user?.displayName ?? 'Benutzer',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  user?.email ?? '',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),

          // Menü-Einträge
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildDrawerItem(
                  context,
                  icon: Icons.bolt,
                  title: 'Firebase Test',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/firebase-test');
                  },
                ),
                const Divider(color: Colors.grey),
                _buildDrawerItem(
                  context,
                  icon: Icons.person,
                  title: 'Profil bearbeiten',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const UserProfileScreen(),
                      ),
                    );
                  },
                ),

                _buildDrawerItem(
                  context,
                  icon: Icons.description,
                  title: 'AGB',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/legal-terms');
                  },
                ),

                _buildDrawerItem(
                  context,
                  icon: Icons.info,
                  title: 'Impressum',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/legal-imprint');
                  },
                ),

                _buildDrawerItem(
                  context,
                  icon: Icons.privacy_tip,
                  title: 'Datenschutz',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/legal-privacy');
                  },
                ),

                const Divider(color: Colors.grey),

                _buildDrawerItem(
                  context,
                  icon: Icons.payment,
                  title: 'Zahlungsmethoden',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/payment-methods');
                  },
                ),

                _buildDrawerItem(
                  context,
                  icon: Icons.settings,
                  title: 'Einstellungen',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/settings');
                  },
                ),

                _buildDrawerItem(
                  context,
                  icon: Icons.help,
                  title: 'Hilfe & Support',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/support');
                  },
                ),
              ],
            ),
          ),

          // Footer mit Logout
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey.shade800)),
            ),
            child: ListTile(
              leading: const Icon(
                Icons.logout,
                color: AppColors.accentGreenDark,
              ),
              title: const Text(
                'Abmelden',
                style: TextStyle(
                  color: AppColors.accentGreenDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () async {
                Navigator.pop(context);
                await authService.signOut();
              },
              hoverColor: AppColors.accentGreenDark.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? textColor,
  }) {
    return ListTile(
      leading: Icon(icon, color: textColor ?? Colors.white),
      title: Text(
        title,
        style: TextStyle(color: textColor ?? Colors.white, fontSize: 16),
      ),
      onTap: onTap,
      hoverColor: AppColors.accentGreenDark.withValues(alpha: 0.1),
    );
  }
}
