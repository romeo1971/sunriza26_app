import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PurchaseSuccessData {
  final String mediaName;
  final String avatarName;
  final String source; // z.B. 'timeline', 'chat', 'home'
  final String variant; // 'credits' | 'cash' | 'accept'
  final String? downloadUrl; // optional

  const PurchaseSuccessData({
    required this.mediaName,
    required this.avatarName,
    required this.source,
    required this.variant,
    this.downloadUrl,
  });
}

Future<void> showPurchaseSuccessDialog({
  required BuildContext context,
  required PurchaseSuccessData data,
}) async {
  final String title = data.variant == 'accept' ? 'Annahme bestätigt' : 'Zahlung bestätigt ✓';

  String actionText;
  switch (data.variant) {
    case 'cash':
      actionText = 'digital bezahlt';
      break;
    case 'credits':
      actionText = 'mit Credits bezahlt';
      break;
    case 'accept':
    default:
      actionText = 'kostenlos hinzugefügt';
  }

  final String body = '"${data.mediaName}" von "${data.avatarName}" wurde $actionText und zu deinen Momenten hinzugefügt.';

  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: Row(
        children: [
          Expanded(
            child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
      content: Text(
        body,
        style: const TextStyle(color: Colors.white70),
      ),
      actions: [
        if (data.downloadUrl != null && data.downloadUrl!.isNotEmpty)
          TextButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('Download', style: TextStyle(color: Color(0xFF00FF94))),
            onPressed: () async {
              try {
                final uri = Uri.parse(data.downloadUrl!);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                    webOnlyWindowName: '_blank',
                  );
                }
              } catch (_) {}
              Navigator.of(dialogContext).pop();
            },
          ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Schließen', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}


