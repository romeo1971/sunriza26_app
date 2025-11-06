import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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
  // Pagination
  final int _pageSize = 10;
  int _page = 0; // 0-based
  // OTS-Status je Transaktion (stamped/pending/…)
  final Map<String, String> _anchorStatus = {};
  final Set<String> _anchorStamped = {};
  final Set<String> _anchorFetchInFlight = {};
  final Set<String> _autoUpgradeAttempted = {}; // verhindert wiederholte Upgrades & UI-Flackern
  FirebaseFunctions get _fns => FirebaseFunctions.instanceFor(region: 'us-central1');
  void Function(VoidCallback fn)? _dialogSetState; // Rebuild-Funktion für Details-Dialog

  Widget _gmbcSpinner({double size = 20, double strokeWidth = 2}) {
    return SizedBox(
      width: size,
      height: size,
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => const LinearGradient(
          colors: [Color(0xFFE91E63), AppColors.lightBlue, Color(0xFF00E5FF)],
          stops: [0.0, 0.5, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
        child: CircularProgressIndicator(
          strokeWidth: strokeWidth,
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      ),
    );
  }

  IconData _iconForTxType(app.TransactionType type) {
    switch (type) {
      case app.TransactionType.creditPurchase:
        return Icons.credit_card;
      case app.TransactionType.creditSpent:
        return Icons.diamond;
      case app.TransactionType.mediaPurchase:
        return Icons.shopping_bag;
    }
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
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Noch keine Transaktionen',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            );
          }

          final start = (_page * _pageSize).clamp(0, transactions.length);
          final end = (start + _pageSize).clamp(0, transactions.length);
          final pageItems = transactions.sublist(start, end);

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: pageItems.length,
                  itemBuilder: (context, index) {
                    final tx = pageItems[index];
                    return _buildTransactionCard(tx);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: _page > 0 ? () => setState(() => _page--) : null,
                      child: const Text('Zurück'),
                    ),
                    const SizedBox(width: 8),
                    Text('${start + 1}–$end/${transactions.length}', style: const TextStyle(color: Colors.white70)),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: end < transactions.length ? () => setState(() => _page++) : null,
                      child: const Text('Weiter'),
                    ),
                  ],
                ),
              ),
            ],
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
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
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
                      child: Icon(_iconForTxType(transaction.type), color: Colors.white, size: 24),
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
                              color: Colors.white.withValues(alpha: 0.6),
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
                            '${transaction.credits} Credits',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
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
                  Divider(color: Colors.white.withValues(alpha: 0.1)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.description, size: 16, color: Colors.white70),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _showTransactionDetails(transaction),
                        child: Text(
                          'Rechnung: ${transaction.invoiceNumber}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Rechts: PDF-Download (Icon + "PDF")
                      TextButton(
                        onPressed: () => _downloadInvoice(transaction),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.download, size: 16, color: AppColors.lightBlue),
                            const SizedBox(width: 6),
                            _gradientLinkText('PDF'),
                          ],
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
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
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
  Future<void> _showTransactionDetails(app.Transaction transaction) async {
    // Öffne Details SOFORT, Status wird im Hintergrund aktualisiert
    // Background fetch nur, wenn nicht bereits in Flight
    if (!_anchorFetchInFlight.contains(transaction.id)) {
      _anchorFetchInFlight.add(transaction.id);
      _fns.httpsCallable('getInvoiceAnchorStatus')
        .call({ 'transactionId': transaction.id })
        .then((res) async {
          final data = Map<String, dynamic>.from(res.data as Map);
          final status = (data['status'] as String?) ?? 'unknown';
          if (mounted) {
            setState(() {
              _anchorStatus[transaction.id] = status;
              if (status == 'stamped') _anchorStamped.add(transaction.id);
            });
          }
          // spiegeln
          try {
            final uid = FirebaseAuth.instance.currentUser?.uid;
            if (uid != null) {
              await FirebaseFirestore.instance
                  .collection('users').doc(uid)
                  .collection('transactions').doc(transaction.id)
                  .set({ 'anchorStatus': status }, SetOptions(merge: true));
            }
          } catch (_) {}
        })
        .whenComplete(() { _anchorFetchInFlight.remove(transaction.id); });
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          _dialogSetState = setStateDialog;
          return AlertDialog(
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
                  _buildDetailRow('Datum', _dateFormat.format(transaction.createdAt)),
                  if (transaction.amount != null)
                    _buildDetailRow('Betrag', transaction.formattedAmount),
                  if (transaction.credits != null)
                    _buildDetailRow('Credits', transaction.formattedCredits),
                  if (transaction.currency != null)
                    _buildDetailRow('Währung', transaction.currency!.toUpperCase()),
                  if (transaction.invoiceNumber != null)
                    _buildDetailRow('Rechnungsnr.', transaction.invoiceNumber!),
                  if (transaction.stripeSessionId != null)
                    _buildDetailRow('Stripe ID', transaction.stripeSessionId!, mono: true),
                  _buildDetailRow('Status', transaction.status),
                  if (transaction.mediaName != null) ...[
                    const SizedBox(height: 16),
                    const Divider(color: Colors.white24),
                    const SizedBox(height: 16),
                    _buildDetailRow('Medium', transaction.mediaName!),
                    if (transaction.mediaType != null)
                      _buildDetailRow('Typ', _getMediaTypeLabel(transaction.mediaType!)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () { _dialogSetState = null; Navigator.pop(context); },
                child: const Text('Schließen'),
              ),
            ],
          );
        },
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
                color: Colors.white.withValues(alpha: 0.6),
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

  // GMBC-Gradient-Text für Links
  Widget _gradientLinkText(String text) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Color(0xFFE91E63), AppColors.lightBlue, Color(0xFF00E5FF)],
        stops: [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  // Status-Auflösung: nimmt lokalen Override vor, sonst den aus Firestore-Objekt
  String? _resolveAnchorStatus(app.Transaction tx) {
    return _anchorStatus[tx.id] ?? tx.anchorStatus;
  }

  String _anchorActionLabel(String txId) {
    final s = _anchorStatus[txId];
    if (s == 'stamped') return 'Nachweis anzeigen';
    if (s == 'pending') return 'Nachweis in Prüfung';
    return 'Nachweis erstellen';
  }

  // Triggert bei Anzeige automatisch ein Einzel‑Upgrade für pending
  void _maybeAutoUpgrade(app.Transaction tx) {
    if (_resolveAnchorStatus(tx) != 'pending') return;
    if (_autoUpgradeAttempted.contains(tx.id)) return; // pro Session nur ein Versuch
    if (_anchorFetchInFlight.contains(tx.id)) return;
    _anchorFetchInFlight.add(tx.id);
    _autoUpgradeAttempted.add(tx.id);
    try {
      final upgrade = _fns.httpsCallable('upgradeInvoiceForTransaction');
      upgrade.call({ 'transactionId': tx.id }).whenComplete(() {
        _anchorFetchInFlight.remove(tx.id);
        // Status frisch abfragen
        _fns.httpsCallable('getInvoiceAnchorStatus')
            .call({ 'transactionId': tx.id })
            .then((res) {
          final data = Map<String, dynamic>.from(res.data as Map);
          final s = (data['status'] as String?) ?? 'unknown';
          final prev = _anchorStatus[tx.id];
          if (prev != s && mounted) {
            setState(() {
              _anchorStatus[tx.id] = s;
              if (s == 'stamped') _anchorStamped.add(tx.id);
            });
          }
        }).catchError((_) { _anchorFetchInFlight.remove(tx.id); });
      });
    } catch (_) {
      _anchorFetchInFlight.remove(tx.id);
    }
  }

  Future<void> _handleAnchorAction(app.Transaction transaction) async {
    try {
      // Sofort pending setzen und Button sperren
      setState(() { _anchorStatus[transaction.id] = 'pending'; });
      _dialogSetState?.call(() {});
      final ensure = _fns.httpsCallable('ensureInvoiceForTransaction');
      await ensure.call({ 'transactionId': transaction.id });
      // Versuche sofortiges Upgrade (sofern OTS-Service konfiguriert)
      try {
        final upgrade = _fns.httpsCallable('upgradeInvoiceForTransaction');
        await upgrade.call({ 'transactionId': transaction.id });
      } catch (_) {}
      final statusFn = _fns.httpsCallable('getInvoiceAnchorStatus');
      final res = await statusFn.call({ 'transactionId': transaction.id });
      final data = Map<String, dynamic>.from(res.data as Map);
      final status = (data['status'] as String?) ?? 'unknown';
      final nr = (data['invoiceNumber'] as String?) ?? '';
      final otsUrl = data['otsUrl'] as String?;
      setState(() {
        _anchorStatus[transaction.id] = status;
        if (status == 'stamped') _anchorStamped.add(transaction.id);
      });
      _dialogSetState?.call(() {});
      // Persistiere Status in der Transaktion (vermeidet Flackern beim erneuten Laden)
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          await FirebaseFirestore.instance
              .collection('users').doc(uid)
              .collection('transactions').doc(transaction.id)
              .set({ 'anchorStatus': status }, SetOptions(merge: true));
        }
      } catch (_) {}
      final msg = status == 'stamped'
          ? 'Echtheitsnachweis verifiziert'
          : (status == 'pending' ? 'Erstellung des Nachweises läuft…' : 'Nachweis erstellt');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$msg${nr.isNotEmpty ? ' ($nr)' : ''}')),
        );
      }
      if (status == 'stamped' && otsUrl != null && otsUrl.isNotEmpty) {
        final uri = Uri.parse(otsUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nachweis fehlgeschlagen: $e')),
      );
    }
  }

  /// Lädt Rechnung herunter
  Future<void> _downloadInvoice(app.Transaction transaction) async {
    String? url;
    // Immer ensure aufrufen, um frische Signed URL zu bekommen
    try {
      // Loading‑Dialog während PDF‑Erzeugung
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            content: Row(
              children: [
                _gmbcSpinner(size: 20, strokeWidth: 2),
                const SizedBox(width: 12),
                const Expanded(child: Text('PDF‑Rechnung in Erstellung – Einen Moment bitte', style: TextStyle(color: Colors.white)) ),
              ],
            ),
          ),
        );
      }
      // Nur Dateien sicherstellen – kein OTS‑Start
      final ensure = _fns.httpsCallable('ensureInvoiceFiles');
      final res = await ensure.call({ 'transactionId': transaction.id });
      url = (res.data['invoicePdfUrl'] as String?);
    } catch (_) {
      url = transaction.invoicePdfUrl;
      if (url == null || url.isEmpty) {
        try {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid != null) {
            final snap = await FirebaseFirestore.instance
                .collection('users').doc(uid)
                .collection('transactions').doc(transaction.id)
                .get();
            url = (snap.data()?['invoicePdfUrl'] as String?);
          }
        } catch (_) {}
      }
    }

    if (mounted) {
      // Dialog schließen, bevor Download startet oder Fehler gezeigt wird
      if (Navigator.canPop(context)) Navigator.pop(context);
    }

    if (url == null || url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF-Link nicht verfügbar.')),
      );
      return;
    }

    try {
      final uri = Uri.parse(url);
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
