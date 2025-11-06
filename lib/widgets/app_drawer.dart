import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/localization_service.dart';
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
                colors: [
                  Color(0xFFE91E63), // Magenta
                  AppColors.lightBlue, // Blue
                  Color(0xFF00E5FF), // Cyan
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white,
                  foregroundImage: user?.photoURL != null
                      ? NetworkImage(user!.photoURL!)
                      : null,
                  onForegroundImageError: (_, __) {},
                  child: const Icon(
                    Icons.person,
                    size: 30,
                    color: AppColors.accentGreenDark,
                  ),
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
                  title: context.read<LocalizationService>().t('profile'),
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
                  title: context.read<LocalizationService>().t('terms'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/legal-terms');
                  },
                ),

                _buildDrawerItem(
                  context,
                  icon: Icons.info,
                  title: context.read<LocalizationService>().t('imprint'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/legal-imprint');
                  },
                ),

                _buildDrawerItem(
                  context,
                  icon: Icons.privacy_tip,
                  title: context.read<LocalizationService>().t('privacy'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/legal-privacy');
                  },
                ),

                const Divider(color: Colors.grey),

                _buildDrawerItem(
                  context,
                  icon: Icons.account_balance_wallet,
                  title: 'Zahlungen & Credits',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/payment-overview');
                  },
                ),

                _buildDrawerItem(
                  context,
                  icon: Icons.language,
                  title: context.read<LocalizationService>().t('menuLanguage'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/language');
                  },
                ),

                _buildDrawerItem(
                  context,
                  icon: Icons.help,
                  title: context.read<LocalizationService>().t('help'),
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
              leading: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [
                    Color(0xFFE91E63),
                    AppColors.lightBlue,
                    Color(0xFF00E5FF),
                  ],
                ).createShader(bounds),
                child: const Icon(
                  Icons.logout,
                  color: Colors.white,
                ),
              ),
              title: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [
                    Color(0xFFE91E63),
                    AppColors.lightBlue,
                    Color(0xFF00E5FF),
                  ],
                ).createShader(bounds),
                child: Text(
                  context.read<LocalizationService>().t('logout'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              onTap: () async {
                Navigator.pop(context);
                await authService.signOut();
              },
              hoverColor: Colors.white.withValues(alpha: 0.1),
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
