import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../models/transaction_model.dart' as app;
import 'package:intl/intl.dart';

/// Transaktions-Screen mit eRechnung Download
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _dateFormat = DateFormat('dd.MM.yyyy HH:mm');
  String _filter = 'all'; // all, credits, media

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
          'Transaktionen',
          style: TextStyle(color: Colors.white, fontSize: 20),
        ),
        actions: [
          // Filter-Buttons
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list, color: Colors.white),
            onSelected: (value) => setState(() => _filter = value),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('Alle')),
              const PopupMenuItem(value: 'credits', child: Text('Nur Credits')),
              const PopupMenuItem(value: 'media', child: Text('Nur Media')),
            ],
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('transactions')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Fehler: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final transactions = snapshot.data!.docs
              .map((doc) => app.Transaction.fromFirestore(doc))
              .where((t) {
                if (_filter == 'credits') {
                  return t.type == app.TransactionType.creditPurchase;
                } else if (_filter == 'media') {
                  return t.type == app.TransactionType.creditSpent ||
                      t.type == app.TransactionType.mediaPurchase;
                }
                return true;
              })
              .toList();

          if (transactions.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_long,
                    size: 64,
                    color: Colors.white.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Noch keine Transaktionen',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: transactions.length,
            itemBuilder: (context, index) {
              return _buildTransactionCard(transactions[index]);
            },
          );
        },
      ),
    );
  }

  /// Transaktionskarte
  Widget _buildTransactionCard(app.Transaction transaction) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showTransactionDetails(transaction),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Icon
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
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        transaction.typeIcon,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            transaction.typeDescription,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _dateFormat.format(transaction.createdAt),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Betrag/Credits
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (transaction.amount != null)
                          Text(
                            transaction.formattedAmount,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        if (transaction.credits != null)
                          Text(
                            transaction.formattedCredits,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 14,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),

                // Rechnung verfügbar?
                if (transaction.invoiceNumber != null) ...[
                  const SizedBox(height: 12),
                  Divider(color: Colors.white.withOpacity(0.1)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.description,
                        size: 16,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Rechnung: ${transaction.invoiceNumber}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      if (transaction.invoicePdfUrl != null)
                        TextButton.icon(
                          onPressed: () => _downloadInvoice(transaction),
                          icon: const Icon(Icons.download, size: 16),
                          label: const Text('PDF'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.lightBlue,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],

                // Status
                if (transaction.status != 'completed') ...[
                  const SizedBox(height: 12),
                  _buildStatusChip(transaction.status),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Status-Chip
  Widget _buildStatusChip(String status) {
    Color color;
    String label;
    switch (status) {
      case 'pending':
        color = Colors.orange;
        label = 'Ausstehend';
        break;
      case 'failed':
        color = Colors.red;
        label = 'Fehlgeschlagen';
        break;
      case 'refunded':
        color = Colors.blue;
        label = 'Rückerstattet';
        break;
      default:
        color = Colors.green;
        label = 'Abgeschlossen';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Zeigt Transaktions-Details
  void _showTransactionDetails(app.Transaction transaction) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Text(transaction.typeIcon, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                transaction.typeDescription,
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow(
                'Datum',
                _dateFormat.format(transaction.createdAt),
              ),
              if (transaction.amount != null)
                _buildDetailRow('Betrag', transaction.formattedAmount),
              if (transaction.credits != null)
                _buildDetailRow('Credits', transaction.formattedCredits),
              if (transaction.currency != null)
                _buildDetailRow('Währung', transaction.currency!.toUpperCase()),
              if (transaction.exchangeRate != null &&
                  transaction.exchangeRate != 1.0)
                _buildDetailRow(
                  'Wechselkurs',
                  '1 EUR = ${transaction.exchangeRate!.toStringAsFixed(4)} USD',
                ),
              if (transaction.invoiceNumber != null)
                _buildDetailRow('Rechnungsnr.', transaction.invoiceNumber!),
              if (transaction.stripeSessionId != null)
                _buildDetailRow(
                  'Stripe ID',
                  transaction.stripeSessionId!,
                  mono: true,
                ),
              _buildDetailRow('Status', transaction.status),

              // Media-Details
              if (transaction.mediaName != null) ...[
                const SizedBox(height: 16),
                const Divider(color: Colors.white24),
                const SizedBox(height: 16),
                _buildDetailRow('Medium', transaction.mediaName!),
                if (transaction.mediaType != null)
                  _buildDetailRow(
                    'Typ',
                    _getMediaTypeLabel(transaction.mediaType!),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          if (transaction.invoicePdfUrl != null)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _downloadInvoice(transaction);
              },
              icon: const Icon(Icons.download),
              label: const Text('Rechnung herunterladen'),
              style: TextButton.styleFrom(foregroundColor: AppColors.lightBlue),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getMediaTypeLabel(app.PurchasedMediaType type) {
    switch (type) {
      case app.PurchasedMediaType.image:
        return 'Bild';
      case app.PurchasedMediaType.video:
        return 'Video';
      case app.PurchasedMediaType.audio:
        return 'Audio';
      case app.PurchasedMediaType.bundle:
        return 'Bundle';
    }
  }

  /// Lädt Rechnung herunter
  Future<void> _downloadInvoice(app.Transaction transaction) async {
    if (transaction.invoicePdfUrl == null) return;

    try {
      final uri = Uri.parse(transaction.invoicePdfUrl!);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Kann URL nicht öffnen');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler beim Download: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
