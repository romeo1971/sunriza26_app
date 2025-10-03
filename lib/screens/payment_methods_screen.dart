import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../theme/app_theme.dart';
import '../models/user_profile.dart';

/// Zahlungsmethoden verwalten (Karten + Stripe Connect für Seller)
class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  UserProfile? _userProfile;
  List<PaymentMethodData> _paymentMethods = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      await _loadUserProfile();
      await _loadPaymentMethods();
    } catch (e) {
      debugPrint('Fehler beim Laden: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadUserProfile() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();
    if (doc.exists) {
      _userProfile = UserProfile.fromMap(doc.data()!);
    }
  }

  Future<void> _loadPaymentMethods() async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'getPaymentMethods',
      );
      final result = await callable.call();
      final methods = (result.data['paymentMethods'] as List<dynamic>?) ?? [];

      setState(() {
        _paymentMethods = methods
            .map((m) => PaymentMethodData.fromMap(m))
            .toList();
      });
    } catch (e) {
      debugPrint('Fehler beim Laden der Zahlungsmethoden: $e');
    }
  }

  Future<void> _addPaymentMethod() async {
    try {
      // Setup Intent erstellen
      final callable = FirebaseFunctions.instance.httpsCallable(
        'createSetupIntent',
      );
      final result = await callable.call();
      final clientSecret = result.data['clientSecret'] as String?;

      if (clientSecret == null) {
        throw Exception('Kein Client Secret erhalten');
      }

      // Hier würde normalerweise Stripe.js oder flutter_stripe aufgerufen werden
      // Für jetzt: Placeholder-Dialog
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text(
            'Karte hinzufügen',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Stripe Checkout wird hier integriert.\n\n'
            'In Production: flutter_stripe Package verwenden.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Schließen'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deletePaymentMethod(String paymentMethodId) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'deletePaymentMethod',
      );
      await callable.call({'paymentMethodId': paymentMethodId});

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Karte gelöscht')));

      // Neu laden
      _loadPaymentMethods();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _setDefaultPaymentMethod(String paymentMethodId) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'setDefaultPaymentMethod',
      );
      await callable.call({'paymentMethodId': paymentMethodId});

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Standard-Karte gesetzt')));

      // Neu laden
      _loadPaymentMethods();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _openStripeDashboard() async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'createSellerDashboardLink',
      );
      final result = await callable.call();
      final url = result.data['url'] as String?;

      if (url == null) {
        throw Exception('Keine Dashboard-URL erhalten');
      }

      // URL öffnen (url_launcher)
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stripe Dashboard wird geöffnet...')),
      );

      // TODO: url_launcher integrieren
      debugPrint('Dashboard URL: $url');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
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
          'Zahlungsmethoden',
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
                  // Gespeicherte Karten
                  _buildSavedCardsSection(),
                  const SizedBox(height: 32),

                  // Stripe Connect (nur für Seller)
                  if (_userProfile?.isSeller == true) ...[
                    _buildStripeConnectSection(),
                    const SizedBox(height: 32),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildSavedCardsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '💳 Gespeicherte Karten',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Optional: Schnellerer Checkout ohne erneute Karteneingabe',
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14),
        ),
        const SizedBox(height: 16),

        // + Karte hinzufügen
        ElevatedButton.icon(
          onPressed: _addPaymentMethod,
          icon: const Icon(Icons.add),
          label: const Text('Karte hinzufügen'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.lightBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Karten-Liste
        if (_paymentMethods.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.credit_card_off,
                  color: Colors.white.withOpacity(0.3),
                  size: 32,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Keine gespeicherten Karten',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          ..._paymentMethods.map((pm) => _buildPaymentMethodCard(pm)),
      ],
    );
  }

  Widget _buildPaymentMethodCard(PaymentMethodData pm) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: pm.isDefault
              ? AppColors.lightBlue
              : Colors.white.withOpacity(0.1),
          width: pm.isDefault ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Karten-Icon
            Icon(_getCardIcon(pm.brand), color: Colors.white, size: 32),
            const SizedBox(width: 16),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_getBrandName(pm.brand)} ****${pm.last4}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Läuft ab: ${pm.expMonth.toString().padLeft(2, '0')}/${pm.expYear}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 13,
                    ),
                  ),
                  if (pm.isDefault)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.lightBlue.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Standard',
                        style: TextStyle(
                          color: AppColors.lightBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Aktionen
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (value) {
                if (value == 'standard') {
                  _setDefaultPaymentMethod(pm.id);
                } else if (value == 'delete') {
                  _showDeleteConfirmation(pm);
                }
              },
              itemBuilder: (context) => [
                if (!pm.isDefault)
                  const PopupMenuItem(
                    value: 'standard',
                    child: Text('Als Standard setzen'),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Löschen', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(PaymentMethodData pm) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Karte löschen?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Möchtest du die Karte ${_getBrandName(pm.brand)} ****${pm.last4} wirklich löschen?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePaymentMethod(pm.id);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
  }

  Widget _buildStripeConnectSection() {
    final user = _userProfile;
    if (user == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '💰 Auszahlungskonto',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Stripe Connect für Verkäufer-Auszahlungen',
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14),
        ),
        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _getConnectStatusIcon(user.stripeConnectStatus),
                    color: _getConnectStatusColor(user.stripeConnectStatus),
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Status: ${_getConnectStatusLabel(user.stripeConnectStatus)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (user.payoutsEnabled)
                          Text(
                            'Auszahlungen aktiviert ✓',
                            style: TextStyle(
                              color: Colors.green.shade400,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Earnings
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ausstehend',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${user.pendingEarnings.toStringAsFixed(2)} €',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gesamt verdient',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${user.totalEarnings.toStringAsFixed(2)} €',
                        style: const TextStyle(
                          color: Colors.green,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Dashboard öffnen
              ElevatedButton.icon(
                onPressed: _openStripeDashboard,
                icon: const Icon(Icons.dashboard),
                label: const Text('Stripe Dashboard öffnen'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF635BFF), // Stripe Color
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _getCardIcon(String brand) {
    switch (brand.toLowerCase()) {
      case 'visa':
        return Icons.credit_card;
      case 'mastercard':
        return Icons.credit_card;
      case 'amex':
        return Icons.credit_card;
      default:
        return Icons.credit_card;
    }
  }

  String _getBrandName(String brand) {
    return brand[0].toUpperCase() + brand.substring(1).toLowerCase();
  }

  IconData _getConnectStatusIcon(String? status) {
    switch (status) {
      case 'active':
        return Icons.check_circle;
      case 'pending':
        return Icons.pending;
      case 'restricted':
        return Icons.warning;
      case 'disabled':
        return Icons.block;
      default:
        return Icons.help_outline;
    }
  }

  Color _getConnectStatusColor(String? status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'restricted':
        return Colors.red;
      case 'disabled':
        return Colors.grey;
      default:
        return Colors.white70;
    }
  }

  String _getConnectStatusLabel(String? status) {
    switch (status) {
      case 'active':
        return 'Verifiziert';
      case 'pending':
        return 'In Prüfung';
      case 'restricted':
        return 'Eingeschränkt';
      case 'disabled':
        return 'Deaktiviert';
      default:
        return 'Nicht verbunden';
    }
  }
}

class PaymentMethodData {
  final String id;
  final String brand;
  final String last4;
  final int expMonth;
  final int expYear;
  final bool isDefault;

  PaymentMethodData({
    required this.id,
    required this.brand,
    required this.last4,
    required this.expMonth,
    required this.expYear,
    required this.isDefault,
  });

  factory PaymentMethodData.fromMap(Map<String, dynamic> map) {
    return PaymentMethodData(
      id: map['id'] as String,
      brand: map['brand'] as String,
      last4: map['last4'] as String,
      expMonth: (map['expMonth'] as num).toInt(),
      expYear: (map['expYear'] as num).toInt(),
      isDefault: (map['isDefault'] as bool?) ?? false,
    );
  }
}
