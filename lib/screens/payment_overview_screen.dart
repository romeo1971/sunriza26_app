import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../models/user_profile.dart';
import 'transactions_screen.dart';

/// Zahlungs-Übersicht: Credits, Transaktionen, Zahlungsmethoden, Warenkorb
class PaymentOverviewScreen extends StatefulWidget {
  const PaymentOverviewScreen({super.key});

  @override
  State<PaymentOverviewScreen> createState() => _PaymentOverviewScreenState();
}

class _PaymentOverviewScreenState extends State<PaymentOverviewScreen> {
  UserProfile? _userProfile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        setState(() {
          _userProfile = UserProfile.fromMap(doc.data()!);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Fehler beim Laden des Profils: $e');
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Zahlungen & Credits',
          style: TextStyle(color: Colors.white, fontSize: 20),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Credits-Übersicht
                  _buildCreditsCard(),
                  const SizedBox(height: 24),

                  // Haupt-Aktionen
                  _buildActionCard(
                    icon: Icons.diamond,
                    title: 'Credits kaufen',
                    subtitle: 'Kaufe Credits für bequeme Zahlungen',
                    onTap: () {
                      Navigator.pushNamed(context, '/credits-shop');
                    },
                  ),
                  const SizedBox(height: 16),

                  _buildActionCard(
                    icon: Icons.receipt_long,
                    title: 'Transaktionen',
                    subtitle: 'Alle Käufe & Rechnungen',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const TransactionsScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  _buildActionCard(
                    icon: Icons.payment,
                    title: 'Zahlungsmethoden',
                    subtitle: 'Kreditkarten verwalten',
                    onTap: () {
                      Navigator.pushNamed(context, '/payment-methods');
                    },
                  ),
                  const SizedBox(height: 16),

                  _buildActionCard(
                    icon: Icons.shopping_cart,
                    title: 'Warenkorb',
                    subtitle: 'Vorgemerkte Medien (0)',
                    onTap: () {
                      // FEHLT NOCH Warenkorb-Screen
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Warenkorb folgt bald')),
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }

  /// Credits-Übersichtskarte
  Widget _buildCreditsCard() {
    final credits = _userProfile?.credits ?? 0;
    final purchased = _userProfile?.creditsPurchased ?? 0;
    final spent = _userProfile?.creditsSpent ?? 0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFE91E63), // Magenta
            AppColors.lightBlue, // Blue
            Color(0xFF00E5FF), // Cyan
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.diamond, color: Colors.white, size: 32),
              const SizedBox(width: 12),
              const Text(
                'Deine Credits',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Verfügbare Credits (groß)
          Text(
            '$credits',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 56,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Verfügbar',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),

          const SizedBox(height: 24),
          Divider(color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(height: 16),

          // Statistiken
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildCreditStat('Gekauft', purchased),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withValues(alpha: 0.3),
              ),
              _buildCreditStat('Ausgegeben', spent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCreditStat(String label, int value) {
    return Column(
      children: [
        Text(
          '$value',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  /// Aktions-Karte
  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFE91E63),
                        AppColors.lightBlue,
                        Color(0xFF00E5FF),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white.withValues(alpha: 0.4),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
