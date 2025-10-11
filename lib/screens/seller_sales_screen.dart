import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../models/earnings_model.dart';
import 'package:intl/intl.dart';

/// Verkäufe des Users (nach Avatar filterbar)
class SellerSalesScreen extends StatefulWidget {
  const SellerSalesScreen({super.key});

  @override
  State<SellerSalesScreen> createState() => _SellerSalesScreenState();
}

class _SellerSalesScreenState extends State<SellerSalesScreen> {
  final _dateFormat = DateFormat('dd.MM.yyyy HH:mm');
  String? _selectedAvatarId; // null = alle Avatare
  Map<String, String> _avatars = {}; // avatarId → name

  @override
  void initState() {
    super.initState();
    _loadAvatars();
  }

  Future<void> _loadAvatars() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('avatars')
        .where('userId', isEqualTo: userId)
        .get();

    setState(() {
      _avatars = {
        for (var doc in snapshot.docs)
          doc.id: doc.data()['name'] as String? ?? 'Unbekannt',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Nicht angemeldet')));
    }

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
          'Meine Verkäufe',
          style: TextStyle(color: Colors.white, fontSize: 20),
        ),
        actions: [
          // Avatar Filter
          if (_avatars.isNotEmpty)
            PopupMenuButton<String?>(
              icon: const Icon(Icons.filter_list, color: Colors.white),
              onSelected: (value) => setState(() => _selectedAvatarId = value),
              itemBuilder: (context) => [
                const PopupMenuItem(value: null, child: Text('Alle Avatare')),
                ..._avatars.entries.map(
                  (e) => PopupMenuItem(value: e.key, child: Text(e.value)),
                ),
              ],
            ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _selectedAvatarId == null
            ? FirebaseFirestore.instance
                  .collection('users')
                  .doc(userId)
                  .collection('sales')
                  .orderBy('createdAt', descending: true)
                  .snapshots()
            : FirebaseFirestore.instance
                  .collection('users')
                  .doc(userId)
                  .collection('sales')
                  .where('avatarId', isEqualTo: _selectedAvatarId)
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Fehler: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final sales = snapshot.data!.docs
              .map((doc) => Sale.fromFirestore(doc))
              .toList();

          if (sales.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_bag,
                    size: 64,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Noch keine Verkäufe',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sales.length,
            itemBuilder: (context, index) {
              return _buildSaleCard(sales[index]);
            },
          );
        },
      ),
    );
  }

  Widget _buildSaleCard(Sale sale) {
    final avatarName = _avatars[sale.avatarId] ?? 'Unbekannt';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Avatar Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFE91E63),
                        AppColors.lightBlue,
                        Color(0xFF00E5FF),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    avatarName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                // Earnings
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '+${sale.sellerEarnings.toStringAsFixed(2)} €',
                      style: const TextStyle(
                        color: Colors.green,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${sale.credits} Credits',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Media Name
            Text(
              sale.mediaName ?? 'Media',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            // Details
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  _dateFormat.format(sale.createdAt),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.remove_circle_outline,
                  size: 14,
                  color: Colors.red.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 4),
                Text(
                  'Provision: ${sale.platformFee.toStringAsFixed(2)} €',
                  style: TextStyle(
                    color: Colors.red.withValues(alpha: 0.8),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
