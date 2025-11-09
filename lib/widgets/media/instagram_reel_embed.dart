import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;

class InstagramReelEmbed extends StatefulWidget {
  final String permalink; // z.B. https://www.instagram.com/reel/DOE1q9-CWr6/ (beliebige IG-Post-URL geht)
  final String? thumbnailUrl; // optional: wenn nicht gesetzt, wird via oEmbed geladen
  final double width;
  final double borderRadius;

  const InstagramReelEmbed({
    super.key,
    required this.permalink,
    this.thumbnailUrl,
    this.width = 400,
    this.borderRadius = 8,
  });

  @override
  State<InstagramReelEmbed> createState() => _InstagramReelEmbedState();
}

class _InstagramReelEmbedState extends State<InstagramReelEmbed> {
  String? _thumb;
  bool _loadingThumb = false;

  @override
  void initState() {
    super.initState();
    if (widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty) {
      _thumb = widget.thumbnailUrl;
    } else {
      _fetchThumbnail();
    }
  }

  String _normalizePermalink(String rawUrl) {
    try {
      final uri = Uri.parse(rawUrl.trim());
      final host = uri.host.toLowerCase();
      if (!host.contains('instagram.com')) return rawUrl.split('?').first;
      final parts = uri.pathSegments;
      final idx = parts.indexWhere((s) => s == 'reel' || s == 'p' || s == 'tv');
      if (idx >= 0 && idx + 1 < parts.length) {
        final kind = parts[idx];
        final id = parts[idx + 1];
        return 'https://www.instagram.com/$kind/$id/';
      }
      final base = rawUrl.split('?').first.split('#').first;
      return base.endsWith('/') ? base : '$base/';
    } catch (_) {
      final base = rawUrl.split('?').first.split('#').first;
      return base.endsWith('/') ? base : '$base/';
    }
  }

  Future<void> _fetchThumbnail() async {
    if (_loadingThumb || _thumb != null) return;
    setState(() => _loadingThumb = true);
    try {
      final url = _normalizePermalink(widget.permalink);
      final resp = await http.get(Uri.parse('https://www.instagram.com/oembed/?url=${Uri.encodeComponent(url)}'));
      if (resp.statusCode == 200) {
        final m = jsonDecode(resp.body) as Map<String, dynamic>;
        final t = (m['thumbnail_url'] as String?) ?? '';
        if (mounted && t.isNotEmpty) {
          setState(() => _thumb = t);
        }
      }
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingThumb = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    final r = widget.borderRadius;
    return SizedBox(
      width: w,
      child: AspectRatio(
        aspectRatio: 9 / 16,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(r),
              child: _thumb == null
                  ? Container(
                      color: Colors.white10,
                      child: const Center(child: Icon(Icons.photo, color: Colors.white54)),
                    )
                  : Image.network(
                      _thumb!,
                      fit: BoxFit.cover,
                      headers: const {
                        'User-Agent':
                            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
                        'Referer': 'https://www.instagram.com/',
                        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
                      },
                    ),
            ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _openLightbox(context),
                  child: Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow, color: Colors.white, size: 56),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openLightbox(BuildContext context) async {
    final String permalink = _normalizePermalink(widget.permalink);
    // Instagram erlaubt Embed über /embed
    final String embedUrl = '${permalink}embed';
    final double topInset = MediaQuery.of(context).padding.top + 20;
    final double rightInset = 20;

    await showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (_) {
        InAppWebViewController? controller;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () async {
                  try {
                    await controller?.loadUrl(urlRequest: URLRequest(url: WebUri('about:blank')));
                  } catch (_) {}
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540, maxHeight: 960),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  child: InAppWebView(
                    initialData: InAppWebViewInitialData(
                      data: _buildEmbedHtml(embedUrl),
                      mimeType: 'text/html',
                      encoding: 'utf-8',
                    ),
                    initialSettings: InAppWebViewSettings(
                      transparentBackground: false,
                      javaScriptEnabled: true,
                      mediaPlaybackRequiresUserGesture: false,
                      disableContextMenu: true,
                      supportZoom: false,
                    ),
                    onWebViewCreated: (c) {
                      controller = c;
                    },
                  ),
                ),
              ),
            ),
            Positioned(
              top: topInset,
              right: rightInset,
              child: GestureDetector(
                onTap: () async {
                  try {
                    await controller?.loadUrl(urlRequest: URLRequest(url: WebUri('about:blank')));
                  } catch (_) {}
                  if (context.mounted) Navigator.pop(context);
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _buildEmbedHtml(String iframeSrc) {
    // Minimales HTML mit iframe wie im Beispiel; Stop erfolgt in Flutter via about:blank
    return '''
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    html, body { margin:0; padding:0; background:#000; height:100%; }
    .wrap { width:100%; height:100%; display:flex; align-items:center; justify-content:center; }
    iframe { width:80vw; max-width:540px; height:80vh; max-height:960px; border:none; border-radius:8px; }
    @media (max-width: 600px) {
      iframe { width: 100vw; height: 80vh; border-radius:0; }
    }
  </style>
</head>
<body>
  <div class="wrap">
    <iframe src="$iframeSrc"
      allowfullscreen
      allow="autoplay; clipboard-write; encrypted-media; picture-in-picture; web-share"></iframe>
  </div>
</body>
</html>
''';
  }
}


