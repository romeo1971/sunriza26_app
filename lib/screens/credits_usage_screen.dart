import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';

/// Credits-Verbrauchsübersicht für User.
/// Zeigt alle Transaktionen (service_spent) chronologisch sortiert.
class CreditsUsageScreen extends StatefulWidget {
  const CreditsUsageScreen({super.key});

  @override
  State<CreditsUsageScreen> createState() => _CreditsUsageScreenState();
}

class _CreditsUsageScreenState extends State<CreditsUsageScreen> {
  final List<Map<String, dynamic>> _transactions = [];
  bool _loading = true;
  int _totalCreditsSpent = 0;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() => _loading = false);
        return;
      }

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('transactions')
          .where('type', isEqualTo: 'service_spent')
          .orderBy('createdAt', descending: true)
          .limit(200)
          .get();

      final txs = snap.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'service': data['service'] as String? ?? 'unknown',
          'credits': (data['credits'] as num?)?.toInt() ?? 0,
          'avatarId': data['avatarId'] as String?,
          'metadata': data['metadata'] as Map<String, dynamic>?,
          'createdAt': (data['createdAt'] as Timestamp?)?.toDate(),
        };
      }).toList();

      int total = 0;
      for (final tx in txs) {
        total += (tx['credits'] as int?) ?? 0;
      }

      if (mounted) {
        setState(() {
          _transactions.clear();
          _transactions.addAll(txs);
          _totalCreditsSpent = total;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[CreditsUsageScreen] Fehler beim Laden: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _serviceLabel(String service) {
    switch (service) {
      case 'dynamics':
        return 'Dynamics';
      case 'liveAvatar':
        return 'LiveAvatar';
      case 'voiceClone':
        return 'VoiceClone';
      case 'voiceCloneChat':
        return 'VoiceClone Chat';
      case 'stt':
        return 'Spracheingabe (STT)';
      default:
        return service;
    }
  }

  IconData _serviceIcon(String service) {
    switch (service) {
      case 'dynamics':
        return Icons.play_circle_outline;
      case 'liveAvatar':
        return Icons.video_call;
      case 'voiceClone':
        return Icons.mic;
      case 'voiceCloneChat':
        return Icons.chat_bubble_outline;
      case 'stt':
        return Icons.record_voice_over;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Credits-Verbrauch',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _transactions.isEmpty
              ? const Center(
                  child: Text(
                    'Noch keine Transaktionen',
                    style: TextStyle(color: Colors.black54, fontSize: 16),
                  ),
                )
              : Column(
                  children: [
                    // Summary Card
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.magenta, AppColors.lightBlue],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Gesamt verbraucht',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '$_totalCreditsSpent Credits',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Transaction List
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _transactions.length,
                        itemBuilder: (context, index) {
                          final tx = _transactions[index];
                          final service = tx['service'] as String? ?? 'unknown';
                          final credits = tx['credits'] as int? ?? 0;
                          final createdAt = tx['createdAt'] as DateTime?;
                          final metadata = tx['metadata'] as Map<String, dynamic>?;

                          String subtitle = '';
                          if (metadata != null) {
                            if (service == 'stt' && metadata['seconds'] != null) {
                              final sec = metadata['seconds'] as int;
                              final min = (sec / 60).floor();
                              final remainSec = sec % 60;
                              subtitle = '$min Min $remainSec Sek';
                            } else if (service == 'voiceCloneChat' &&
                                metadata['chars'] != null) {
                              subtitle = '${metadata['chars']} Zeichen';
                            }
                          }

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ListTile(
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.lightBlue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  _serviceIcon(service),
                                  color: AppColors.magenta,
                                  size: 22,
                                ),
                              ),
                              title: Text(
                                _serviceLabel(service),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (subtitle.isNotEmpty)
                                    Text(
                                      subtitle,
                                      style: const TextStyle(
                                          fontSize: 13, color: Colors.black54),
                                    ),
                                  if (createdAt != null)
                                    Text(
                                      DateFormat('dd.MM.yyyy HH:mm')
                                          .format(createdAt),
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.black45),
                                    ),
                                ],
                              ),
                              trailing: Text(
                                '−$credits',
                                style: const TextStyle(
                                  color: AppColors.magenta,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

