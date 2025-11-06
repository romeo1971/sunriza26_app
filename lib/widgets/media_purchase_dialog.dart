import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../models/media_models.dart';
import '../models/user_profile.dart';
import '../services/media_purchase_service.dart';
import '../services/moments_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../web/web_helpers.dart' as web;

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
                          Color(0xFFE91E63).withValues(alpha: 0.3),
                          AppColors.lightBlue.withValues(alpha: 0.3),
                          Color(0xFF00E5FF).withValues(alpha: 0.3),
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
                        color: Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.5),
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
                        color: Colors.blue.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.5),
                        ),
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

        // Mit Credits zahlen (immer verfügbar, aber disabled wenn nicht genug Credits)
        ElevatedButton.icon(
          onPressed: (_purchasing || !hasEnoughCredits) ? null : _purchaseWithCredits,
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
    debugPrint('🔵 [MediaPurchase] Credit-Kauf gestartet für mediaId=${widget.media.id}, avatarId=${widget.media.avatarId}');
    setState(() => _purchasing = true);

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      debugPrint('🔴 [MediaPurchase] User nicht eingeloggt');
      return;
    }

    final price = widget.media.price ?? 0.0;
    final requiredCredits = (price / 0.1).round();
    debugPrint('🔵 [MediaPurchase] Preis: $price, Credits benötigt: $requiredCredits');

    final success = await _purchaseService.purchaseMediaWithCredits(
      userId: userId,
      media: widget.media,
    );

    if (!mounted) return;

    if (success) {
      // ignore: avoid_print
      print('✅✅✅ [MediaPurchase] Credits abgebucht, erstelle Moment...');
      debugPrint('✅ [MediaPurchase] Credits abgebucht, erstelle Moment...');
      
      // CRITICAL FIX: Moment anlegen + Download starten (wie beim Stripe-Flow)
      String? storedUrl;
      String mediaName = widget.media.originalFileName ?? 'Media';
      String avatarName = 'Avatar';

      try {
        // 1. Moment anlegen
        // ignore: avoid_print
        print('🔵🔵🔵 [MediaPurchase] Rufe saveMoment()...');
        final moment = await MomentsService().saveMoment(
          media: widget.media,
          price: price,
          paymentMethod: 'credits',
        );
        storedUrl = moment.storedUrl;
        // ignore: avoid_print
        print('✅✅✅ [MediaPurchase] Moment angelegt: ${moment.id}, URL: $storedUrl');
        debugPrint('✅ [MediaPurchase] Moment angelegt: ${moment.id}, URL: $storedUrl');

        // 2. Avatar-Name laden für bessere Success-Message
        // ignore: avoid_print
        print('🔵🔵🔵 [MediaPurchase] Lade Avatar-Name...');
        if (widget.media.avatarId.isNotEmpty) {
          try {
            final avatarDoc = await FirebaseFirestore.instance
                .collection('avatars')
                .doc(widget.media.avatarId)
                .get();
            if (avatarDoc.exists) {
              final data = avatarDoc.data()!;
              final nickname = (data['nickname'] as String?)?.trim();
              final firstName = (data['firstName'] as String?)?.trim();
              avatarName = (nickname != null && nickname.isNotEmpty) ? nickname : (firstName ?? 'Avatar');
              // ignore: avoid_print
              print('✅✅✅ [MediaPurchase] Avatar-Name: $avatarName');
            }
          } catch (e) {
            // ignore: avoid_print
            print('⚠️⚠️⚠️ [MediaPurchase] Avatar-Name Fehler: $e');
            debugPrint('⚠️ [MediaPurchase] Avatar-Name konnte nicht geladen werden: $e');
          }
        }

        // 3. Download automatisch starten
        // ignore: avoid_print
        print('🔵🔵🔵 [MediaPurchase] Starte Download... URL: $storedUrl, isEmpty: ${storedUrl.isEmpty}');
        if (storedUrl.isNotEmpty) {
          try {
            final uri = Uri.parse(storedUrl);
            // ignore: avoid_print
            print('🔵🔵🔵 [MediaPurchase] canLaunchUrl check...');
            if (await canLaunchUrl(uri)) {
              // ignore: avoid_print
              print('🔵🔵🔵 [MediaPurchase] Launching URL...');
              await launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
                webOnlyWindowName: '_blank',
              );
              // ignore: avoid_print
              print('✅✅✅ [MediaPurchase] Download gestartet!');
              debugPrint('✅ [MediaPurchase] Download gestartet');
            } else {
              // ignore: avoid_print
              print('⚠️⚠️⚠️ [MediaPurchase] canLaunchUrl = false');
            }
          } catch (e, stackTrace) {
            // ignore: avoid_print
            print('⚠️⚠️⚠️ [MediaPurchase] Download fehlgeschlagen: $e');
            print('StackTrace: $stackTrace');
            debugPrint('⚠️ [MediaPurchase] Download fehlgeschlagen: $e');
          }
        } else {
          // ignore: avoid_print
          print('⚠️⚠️⚠️ [MediaPurchase] storedUrl ist null oder leer!');
        }
      } catch (e, stackTrace) {
        // ignore: avoid_print
        print('🔴🔴🔴 [MediaPurchase] FEHLER beim Moment anlegen: $e');
        print('StackTrace: $stackTrace');
        debugPrint('🔴 [MediaPurchase] Fehler beim Moment anlegen: $e');
        if (!mounted) {
          // ignore: avoid_print
          print('🔴🔴🔴 [MediaPurchase] Widget not mounted, return');
          return;
        }
        setState(() => _purchasing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Fehler beim Speichern: $e'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // ignore: avoid_print
      print('🔵🔵🔵 [MediaPurchase] Check mounted: $mounted');
      if (!mounted) {
        // ignore: avoid_print
        print('🔴🔴🔴 [MediaPurchase] Widget not mounted vor Navigator.pop, return');
        return;
      }
      
      // ignore: avoid_print
      print('🔵🔵🔵 [MediaPurchase] Schließe Purchase-Dialog...');
      Navigator.pop(context);

      // ignore: avoid_print
      print('🔵🔵🔵 [MediaPurchase] Zeige Success-Dialog...');
      // 4. Success-Dialog mit echten Daten (wie beim Stripe-Flow)
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Zahlung bestätigt', style: TextStyle(color: Colors.white)),
          content: Text(
            '"$mediaName" von "$avatarName" wurde zu deinen Momenten hinzugefügt. Der Download wurde gestartet.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              // onPressed: () => Navigator.pop(context),
              onPressed: () {
                  final nLocal = Navigator.of(context, rootNavigator: false);
                  if (nLocal.canPop()) nLocal.pop();
                  final nRoot = Navigator.of(context, rootNavigator: true);
                  if (nRoot.canPop()) nRoot.pop();
                },
              child: const Text('Schließen', style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () async {
                if (storedUrl != null && storedUrl.isNotEmpty) {
                  try {
                    final uri = Uri.parse(storedUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
                    }
                  } catch (_) {}
                }
              },
              child: const Text('Download', style: TextStyle(color: Color(0xFF00FF94))),
            ),
          ],
        ),
      );

      // ignore: avoid_print
      print('✅✅✅ [MediaPurchase] Success-Dialog geschlossen');
      
      // Markiere als confirmed im Chat (für Timeline-Filter)
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && widget.media.avatarId.isNotEmpty) {
          // Versuche playlistId aus Context zu holen (optional)
          // Falls kein Playlist-Kontext: überspringen
          await FirebaseFirestore.instance
              .collection('avatars')
              .doc(widget.media.avatarId)
              .collection('confirmedItems')
              .doc('${uid}_${widget.media.id}')
              .set({
            'userId': uid,
            'mediaId': widget.media.id,
            'confirmedAt': FieldValue.serverTimestamp(),
          });
        }
      } catch (e) {
        debugPrint('⚠️ Confirmed-Item konnte nicht gesetzt werden: $e');
      }
      
      widget.onPurchaseSuccess?.call();
      debugPrint('✅ [MediaPurchase] Credit-Kauf abgeschlossen');
    } else {
      // ignore: avoid_print
      print('🔴🔴🔴 [MediaPurchase] Credit-Kauf fehlgeschlagen (success=false)');
      debugPrint('🔴 [MediaPurchase] Credit-Kauf fehlgeschlagen');
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
      Navigator.pop(context); // Schließe Purchase-Dialog

      // Hole Avatar-Name
      String avatarName = 'Avatar';
      try {
        final avatarDoc = await FirebaseFirestore.instance
            .collection('avatars')
            .doc(widget.media.avatarId)
            .get();
        if (avatarDoc.exists) {
          final data = avatarDoc.data()!;
          final nickname = (data['nickname'] as String?)?.trim();
          final firstName = (data['firstName'] as String?)?.trim();
          avatarName = (nickname != null && nickname.isNotEmpty) ? nickname : (firstName ?? 'Avatar');
        }
      } catch (_) {}

      // Zeige Stripe Checkout in iframe IM CHAT
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _StripeCheckoutDialog(
          checkoutUrl: checkoutUrl,
          mediaName: widget.media.originalFileName ?? 'Media',
          avatarName: avatarName,
        ),
      );
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

/// Stripe Checkout Dialog mit iframe
class _StripeCheckoutDialog extends StatefulWidget {
  final String checkoutUrl;
  final String mediaName;
  final String avatarName;

  const _StripeCheckoutDialog({
    required this.checkoutUrl,
    required this.mediaName,
    required this.avatarName,
  });

  @override
  State<_StripeCheckoutDialog> createState() => _StripeCheckoutDialogState();
}

class _StripeCheckoutDialogState extends State<_StripeCheckoutDialog> {
  String? _downloadUrl;
  @override
  void initState() {
    super.initState();
    _setupMessageListener();
  }
  
  void _setupMessageListener() {
    debugPrint('🔵🔵🔵 [StripeIframe] Setup listener...');
    // Lausche auf postMessage von Stripe-Success-URL
    web.windowMessages().listen((event) async {
      debugPrint('🔵🔵🔵 [StripeIframe] Message received: ${event?.data}');
      debugPrint('🔵🔵🔵 [StripeIframe] Origin: ${event?.origin}');
      
      if (event.data.toString().contains('stripe-success')) {
        debugPrint('✅✅✅ [StripeIframe] SUCCESS erkannt!');
        
        if (!mounted) return;
        
        // Schließe iframe-Dialog
        Navigator.of(context, rootNavigator: false).pop();
        
        // Warte kurz damit Dialog geschlossen ist
        await Future.delayed(const Duration(milliseconds: 300));
        
        if (!mounted) return;
        
        // Versuche automatisch die zuletzt erworbene Datei zu finden und Download zu starten
        try {
          final url = await _findMomentDownloadUrl();
          if (url != null && url.isNotEmpty) {
            setState(() => _downloadUrl = url);
            try {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
              } else {
                _triggerBrowserDownload(url);
              }
            } catch (_) {
              _triggerBrowserDownload(url);
            }
          }
        } catch (_) {}
        
        // Zeige Success-Dialog
        await showDialog(
          context: context,
          barrierDismissible: false,
          useRootNavigator: false,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: const Text('Zahlung bestätigt ✓', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '"${widget.mediaName}"',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  'von ${widget.avatarName}',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 16),
                const Text(
                  'wurde zu deinen Momenten hinzugefügt.',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final url = _downloadUrl ?? await _findMomentDownloadUrl();
                  if (url != null && url.isNotEmpty) {
                    try {
                      final uri = Uri.parse(url);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
                      } else {
                        _triggerBrowserDownload(url);
                      }
                    } catch (_) {
                      _triggerBrowserDownload(url);
                    }
                  }
                },
                child: const Text('Download', style: TextStyle(color: Color(0xFF00FF94), fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: () {
                  final nLocal = Navigator.of(context, rootNavigator: false);
                  if (nLocal.canPop()) nLocal.pop();
                  final nRoot = Navigator.of(context, rootNavigator: true);
                  if (nRoot.canPop()) nRoot.pop();
                },
                child: const Text('Schließen', style: TextStyle(color: Color(0xFF00FF94), fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        
        debugPrint('✅✅✅ [StripeIframe] Success-Dialog geschlossen');
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Text(
                    'Stripe Checkout',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // iframe
            Expanded(
              child: web.buildIframeView('stripe-checkout-${widget.checkoutUrl.hashCode}'),
            ),
          ],
        ),
      ),
    );
  }

  void _triggerBrowserDownload(String url, {String? filename}) async {
    // Erzwinge Download-Header für Firebase-URLs
    try {
      if (url.contains('firebasestorage.googleapis.com')) {
        final hasQuery = url.contains('?');
        final encoded = Uri.encodeComponent('attachment; filename="${filename ?? 'download'}"');
        final param = 'response-content-disposition=$encoded';
        if (!url.contains('response-content-disposition=')) {
          url = url + (hasQuery ? '&' : '?') + param;
        }
      }
    } catch (_) {}
    // 1) Versuche als Blob zu laden und direkt zu speichern (zuverlässigster Weg)
    await web.downloadUrlCompat(url, filename: filename);
  }

  Future<String?> _findMomentDownloadUrl() async {
    try {
      String? avatarId;
      try {
        final raw = web.getSessionStorage('stripe_media_success');
        if (raw != null && raw.isNotEmpty) {
          final data = raw;
          // primitive parse to avoid bringing in dart:convert just for small read
          final aidMatch = RegExp(r'"avatarId"\s*:\s*"(.*?)"').firstMatch(data);
          if (aidMatch != null) avatarId = aidMatch.group(1);
        }
      } catch (_) {}
      final moments = await MomentsService().listMoments(avatarId: avatarId);
      if (moments.isEmpty) return null;
      final byName = moments.firstWhere(
        (m) => (m.originalFileName ?? '').trim() == widget.mediaName.trim(),
        orElse: () => moments.first,
      );
      return (byName.storedUrl.isNotEmpty) ? byName.storedUrl : byName.originalUrl;
    } catch (_) {
      return null;
    }
  }

  void _createIframe() {
    web.registerViewFactory(
      'stripe-checkout-${widget.checkoutUrl.hashCode}',
      (int viewId) => web.createIFrame(widget.checkoutUrl),
    );
  }
}
