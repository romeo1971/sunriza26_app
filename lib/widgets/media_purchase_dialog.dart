import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../models/media_models.dart';
import '../models/user_profile.dart';
import '../services/media_purchase_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Dialog für Media-Kauf (Credits oder Stripe)
class MediaPurchaseDialog extends StatefulWidget {
  final AvatarMedia media;
  final VoidCallback? onPurchaseSuccess;

  const MediaPurchaseDialog({
    super.key,
    required this.media,
    this.onPurchaseSuccess,
  });

  @override
  State<MediaPurchaseDialog> createState() => _MediaPurchaseDialogState();
}

class _MediaPurchaseDialogState extends State<MediaPurchaseDialog> {
  final _purchaseService = MediaPurchaseService();
  UserProfile? _userProfile;
  bool _loading = true;
  bool _purchasing = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (doc.exists && mounted) {
        setState(() {
          _userProfile = UserProfile.fromMap(doc.data()!);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Fehler beim Laden des Profils: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = widget.media.price ?? 0.0;
    final currency = widget.media.currency ?? '€';
    final requiredCredits = (price / 0.1).round();
    final userCredits = _userProfile?.credits ?? 0;
    final hasEnoughCredits = userCredits >= requiredCredits;
    final canUseStripe = price >= 2.0;

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
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
            child: Icon(
              _getMediaIcon(widget.media.type),
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.media.originalFileName ?? 'Media',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: _loading
          ? const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Preis
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFFE91E63).withOpacity(0.3),
                          AppColors.lightBlue.withOpacity(0.3),
                          Color(0xFF00E5FF).withOpacity(0.3),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Preis:',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                        Text(
                          '${price.toStringAsFixed(2)} $currency',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Credits-Info
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Benötigt:',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      Row(
                        children: [
                          const Icon(
                            Icons.diamond,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$requiredCredits Credits',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Verfügbar:',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      Row(
                        children: [
                          const Icon(
                            Icons.diamond,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$userCredits Credits',
                            style: TextStyle(
                              color: hasEnoughCredits
                                  ? Colors.green
                                  : Colors.red,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  if (!hasEnoughCredits) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning,
                            color: Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Nicht genug Credits! Du brauchst noch ${requiredCredits - userCredits} Credits.',
                              style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (!canUseStripe && !hasEnoughCredits) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withOpacity(0.5)),
                      ),
                      child: const Text(
                        'Zahlungen unter 2€ sind nur mit Credits möglich.',
                        style: TextStyle(color: Colors.blue, fontSize: 13),
                      ),
                    ),
                  ],
                ],
              ),
            ),
      actions: [
        // Credits kaufen
        if (!hasEnoughCredits)
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/credits-shop');
            },
            icon: const Icon(Icons.diamond),
            label: const Text('Credits kaufen'),
            style: TextButton.styleFrom(foregroundColor: AppColors.lightBlue),
          ),

        // Abbrechen
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),

        // Mit Credits zahlen
        if (hasEnoughCredits)
          ElevatedButton.icon(
            onPressed: _purchasing ? null : _purchaseWithCredits,
            icon: _purchasing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.diamond),
            label: Text(_purchasing ? 'Kaufe...' : 'Mit Credits zahlen'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.lightBlue,
              disabledBackgroundColor: Colors.grey,
            ),
          ),

        // Mit Karte zahlen (Stripe)
        if (canUseStripe)
          ElevatedButton.icon(
            onPressed: _purchasing ? null : _purchaseWithStripe,
            icon: _purchasing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.credit_card),
            label: Text(_purchasing ? 'Kaufe...' : 'Mit Karte zahlen'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              disabledBackgroundColor: Colors.grey,
            ),
          ),
      ],
    );
  }

  Future<void> _purchaseWithCredits() async {
    setState(() => _purchasing = true);

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final success = await _purchaseService.purchaseMediaWithCredits(
      userId: userId,
      media: widget.media,
    );

    if (!mounted) return;

    if (success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Kauf erfolgreich!'),
          backgroundColor: Colors.green,
        ),
      );
      widget.onPurchaseSuccess?.call();
    } else {
      setState(() => _purchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Kauf fehlgeschlagen'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _purchaseWithStripe() async {
    setState(() => _purchasing = true);

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      final checkoutUrl = await _purchaseService.purchaseMediaWithStripe(
        userId: userId,
        media: widget.media,
      );

      if (checkoutUrl == null) throw Exception('Keine Checkout-URL erhalten');

      if (!mounted) return;
      Navigator.pop(context);

      final uri = Uri.parse(checkoutUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Kann URL nicht öffnen');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _purchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Fehler: $e'), backgroundColor: Colors.red),
      );
    }
  }

  IconData _getMediaIcon(AvatarMediaType type) {
    switch (type) {
      case AvatarMediaType.image:
        return Icons.image;
      case AvatarMediaType.video:
        return Icons.videocam;
      case AvatarMediaType.audio:
        return Icons.audiotrack;
      case AvatarMediaType.document:
        return Icons.description;
    }
  }
}
