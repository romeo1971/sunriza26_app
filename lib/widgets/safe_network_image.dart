import 'package:flutter/material.dart';

class SafeNetworkImage extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? error;

  const SafeNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.error,
  });

  bool get _isEmpty => url == null || url!.trim().isEmpty;

  String _proxied(String raw) {
    final u = raw.trim();
    // Optionaler Proxy nur wenn PROXY_BASE_URL gesetzt ist (z. B. http://localhost:8001)
    const proxyBase = String.fromEnvironment(
      'PROXY_BASE_URL',
      defaultValue: '',
    );
    if (proxyBase.isEmpty) {
      // Standard: Direkt laden (CORS ist am Bucket konfiguriert)
      return u;
    }
    // Nur Storage-Hosts über Proxy leiten
    final isGcs1 = u.contains('firebasestorage.googleapis.com');
    final isGcs2 = u.contains('storage.googleapis.com');
    final isGcs3 = u.contains('.firebasestorage.app');
    if (!(isGcs1 || isGcs2 || isGcs3)) return u;
    final encoded = Uri.encodeComponent(u);
    return '${proxyBase.replaceAll(RegExp(r"/+$"), '')}/proxy/image?url=$encoded';
  }

  @override
  Widget build(BuildContext context) {
    final Widget fallback = Container(
      color: Colors.grey.shade800,
      alignment: Alignment.center,
      child: const Icon(Icons.broken_image, color: Colors.white54),
    );

    if (_isEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: placeholder ?? fallback,
      );
    }

    final displayUrl = _proxied(url!);

    return Image.network(
      displayUrl,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, err, stackTrace) =>
          SizedBox(width: width, height: height, child: error ?? fallback),
    );
  }
}
