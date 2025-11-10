import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import 'package:http/http.dart' as http;
import '../custom_text_field.dart';
import 'expansion_tile_base.dart';

class SocialMediaAccount {
  final String id;
  final String providerName;
  final String url;
  final String login;
  final String passwordEnc; // AES verschlüsselt (iv:cipher b64)
  final bool connected;

  SocialMediaAccount({
    required this.id,
    required this.providerName,
    required this.url,
    required this.login,
    required this.passwordEnc,
    required this.connected,
  });

  Map<String, dynamic> toMap() => {
        'providerName': providerName,
        'url': url,
        'login': login,
        'passwordEnc': passwordEnc,
        'connected': connected,
      };

  static SocialMediaAccount fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return SocialMediaAccount(
      id: d.id,
      providerName: (m['providerName'] as String?) ?? detectProviderFromUrl((m['url'] as String?) ?? ''),
      url: (m['url'] as String?) ?? '',
      login: (m['login'] as String?) ?? '',
      passwordEnc: (m['passwordEnc'] as String?) ?? '',
      connected: (m['connected'] as bool?) ?? false,
    );
  }
}

class _SimpleManualUrlsEditor extends StatefulWidget {
  final String title;
  final String providerId; // 'linkedin' | 'x'
  final TextEditingController manualCtrl;
  final String avatarId;
  final Future<void> Function() onSaved;
  const _SimpleManualUrlsEditor({
    required this.title,
    required this.providerId,
    required this.manualCtrl,
    required this.avatarId,
    required this.onSaved,
  });
  @override
  State<_SimpleManualUrlsEditor> createState() => _SimpleManualUrlsEditorState();
}

class _SimpleManualUrlsEditorState extends State<_SimpleManualUrlsEditor> {
  final TextEditingController _addCtrl = TextEditingController();
  int _page = 0;
  int? _dragFromIndex;
  final Map<String, String> _thumbByUrl = <String, String>{};
  final Map<String, String> _titleByUrl = <String, String>{};
  final Map<String, Uint8List> _shotBytesByUrl = <String, Uint8List>{}; // Screenshot-Cache nur für X

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.manualCtrl.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final int perPage = _calcPerPage(context);
    final start = _page * perPage;
    final end = (start + perPage).clamp(0, list.length);
    final slice = list.sublist(start, end);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _addCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Post-URL hinzufügen',
                  hintText: widget.providerId == 'x' ? 'https://x.com/user/status/…' : 'https://www.linkedin.com/feed/update/…',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Builder(builder: (_) {
              final bool _enabled = _isValid(_addCtrl.text);
              return IconButton(
              tooltip: 'Hinzufügen',
              icon: Icon(Icons.check, color: _enabled ? Colors.white : Colors.white24),
              onPressed: _enabled ? () async {
                String u = _addCtrl.text.trim();
                if (widget.providerId == 'x') {
                  final extracted = _extractXStatusUrl(u);
                  if (extracted != null) {
                    u = extracted;
                  }
                }
                final list = widget.manualCtrl.text.split('\n').where((e) => e.trim().isNotEmpty).map((e) => e.trim()).toList();
                list.add(u);
                widget.manualCtrl.text = list.join('\n');
                _addCtrl.clear();
                await FirebaseFirestore.instance.collection('avatars').doc(widget.avatarId)
                    .collection('social_accounts').doc(widget.providerId)
                    .set({
                  'manualUrls': list.take(20).toList(),
                  'connected': true,
                  'updatedAt': DateTime.now().millisecondsSinceEpoch
                }, SetOptions(merge: true));
                _fetchThumb(u);
                setState(() {
                  final int per = _calcPerPage(context);
                  _page = ((list.length - 1) / per).floor();
                });
                await widget.onSaved();
              } : null,
            );}),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (int i = 0; i < slice.length; i++) _tile(list, start + i),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(onPressed: _page > 0 ? () => setState(() => _page--) : null, child: const Text('Zurück')),
            Builder(builder: (_) {
              final int per = _calcPerPage(context);
              final total = ((list.length + per - 1) / per).floor();
              return Text('${_page + 1} / $total', style: const TextStyle(color: Colors.white54, fontSize: 12));
            }),
            TextButton(onPressed: ((start + _calcPerPage(context)) < list.length) ? () => setState(() => _page++) : null, child: const Text('Weiter')),
          ],
        ),
      ],
    );
  }

  int _calcPerPage(BuildContext context) {
    final double width = MediaQuery.of(context).size.width - 32;
    const double tile = 90;
    const double spacing = 10;
    final int columns = max(1, ((width + spacing) / (tile + spacing)).floor());
    const int rows = 2;
    return columns * rows;
  }

  bool _isValid(String s) {
    final u = s.trim();
    if (widget.providerId == 'x') {
      return _extractXStatusUrl(u) != null;
    }
    // LinkedIn: akzeptiere reine URL oder eingebettetes <iframe>/<a> Snippet
    return _extractLinkedInUrl(u) != null;
  }

  String? _extractXStatusUrl(String input) {
    // Support: raw URL, x.com or twitter.com, or full blockquote HTML
    final reUrl = RegExp(r'(https?://(?:x\.com|twitter\.com)/[^/\s]+/status/\d+)', caseSensitive: false);
    final m1 = reUrl.firstMatch(input);
    if (m1 != null) return m1.group(1);
    // Look inside href attributes
    final reHref = RegExp(r'''href=["'](https?://(?:x\.com|twitter\.com)/[^"']+/status/\d+)["']''', caseSensitive: false);
    final m2 = reHref.firstMatch(input);
    if (m2 != null) return m2.group(1);
    return null;
  }

  String? _extractLinkedInUrl(String input) {
    // 1) src="https://www.linkedin.com/embed/feed/update/urn:li:..."
    final reSrc = RegExp(r'''src=["'](https?://[^"']*linkedin\.com/[^"']+)["']''', caseSensitive: false);
    final m1 = reSrc.firstMatch(input);
    if (m1 != null) return m1.group(1);
    // 2) href="https://www.linkedin.com/..."
    final reHref = RegExp(r'''href=["'](https?://[^"']*linkedin\.com/[^"']+)["']''', caseSensitive: false);
    final m2 = reHref.firstMatch(input);
    if (m2 != null) return m2.group(1);
    // 3) Plain URL im Text
    final rePlain = RegExp(r'''(https?://(?:www\.)?linkedin\.com/[^"'\s<>]+)''', caseSensitive: false);
    final m3 = rePlain.firstMatch(input);
    if (m3 != null) return m3.group(1);
    return null;
  }

  Widget _tile(List<String> list, int index) {
    final url = list[index];
    _fetchThumb(url);
    return Draggable<int>(
      data: index,
      onDragStarted: () => _dragFromIndex = index,
      onDragEnd: (_) => _dragFromIndex = null,
      feedback: Opacity(
        opacity: 0.8,
        child: SizedBox(
          width: 90,
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: Container(color: Colors.black54, child: const Icon(Icons.drag_indicator, color: Colors.white)),
          ),
        ),
      ),
      child: DragTarget<int>(
        onWillAccept: (from) => from != null && from != index,
        onAccept: (from) async {
          final item = list.removeAt(from);
          list.insert(index, item);
          widget.manualCtrl.text = list.join('\n');
          await FirebaseFirestore.instance.collection('avatars').doc(widget.avatarId)
              .collection('social_accounts').doc(widget.providerId)
              .set({
            'manualUrls': list.take(20).toList(),
            'connected': list.isNotEmpty,
            'updatedAt': DateTime.now().millisecondsSinceEpoch
          }, SetOptions(merge: true));
          setState(() {});
        },
        builder: (ctx, cand, rej) {
          return Stack(
            children: [
              SizedBox(
                width: 90,
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Builder(builder: (_) {
                      if (widget.providerId == 'x') {
                        final u = _extractXStatusUrl(url) ?? url;
                        final html = _buildTwitterEmbedDoc(u);
                        return InAppWebView(
                          initialData: InAppWebViewInitialData(data: html, mimeType: 'text/html', encoding: 'utf-8'),
                          initialSettings: InAppWebViewSettings(
                            transparentBackground: true,
                            mediaPlaybackRequiresUserGesture: true,
                            disableContextMenu: true,
                            supportZoom: false,
                            allowsInlineMediaPlayback: true,
                          ),
                        );
                      }
                      final thumb = _thumbByUrl[url];
                      if (thumb != null && thumb.isNotEmpty) {
                        final headers = <String, String>{
                          'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
                          'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
                        };
                        if (widget.providerId == 'linkedin') {
                          headers['Referer'] = 'https://www.linkedin.com/';
                        } else if (widget.providerId == 'x') {
                          headers['Referer'] = 'https://x.com/';
                        }
                        return Image.network(
                          thumb.replaceAll('&amp;', '&'),
                          fit: BoxFit.cover,
                          headers: headers,
                        );
                      }
                      // Fallback: Icon
                      return Container(
                        color: Colors.white10,
                        child: Center(
                          child: widget.providerId == 'x'
                              ? const FaIcon(FontAwesomeIcons.xTwitter, color: Colors.white24, size: 32)
                              : const FaIcon(FontAwesomeIcons.linkedin, color: Color(0xFF0A66C2), size: 32),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              if (widget.providerId == 'x')
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: Container(color: const Color.fromARGB(10, 255, 255, 255)),
                  ),
                ),
              // Eye preview unten links für X und LinkedIn
              Positioned(
                left: 4,
                bottom: 4,
                child: InkWell(
                  onTap: () {
                    if (widget.providerId == 'x') {
                      _openXPreview(url);
                    } else if (widget.providerId == 'linkedin') {
                      _openLinkedInPreview(url);
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(Icons.remove_red_eye, size: 16, color: Colors.white70),
                  ),
                ),
              ),
              // Reorder-Dialog unten rechts – wie bei TikTok
              Positioned(
                bottom: 4,
                right: 4,
                child: InkWell(
                  onTap: _openReorderDialog,
                  child: Container(
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.all(2),
                    child: const Icon(Icons.drag_indicator, size: 16, color: Colors.white70),
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: InkWell(
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: const Color(0xFF1E1E1E),
                        title: const Text('Löschen?', style: TextStyle(color: Colors.white)),
                        content: Text(
                          'Diesen ${widget.providerId == 'x' ? 'X' : 'LinkedIn'}‑Eintrag wirklich entfernen?',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen')),
                        ],
                      ),
                    );
                    if (confirm != true) return;
                    list.removeAt(index);
                    widget.manualCtrl.text = list.join('\n');
                    await FirebaseFirestore.instance.collection('avatars').doc(widget.avatarId)
                        .collection('social_accounts').doc(widget.providerId)
                        .set({
                      'manualUrls': list.take(20).toList(),
                      'connected': list.isNotEmpty,
                      'updatedAt': DateTime.now().millisecondsSinceEpoch
                    }, SetOptions(merge: true));
                    setState(() {});
                    await widget.onSaved();
                  },
                  child: Container(
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.all(2),
                    child: const Icon(Icons.delete, size: 16, color: Colors.redAccent),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openXPreview(String postUrl) async {
    final html = _buildTwitterEmbedDoc(postUrl);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (ctx) {
        InAppWebViewController? controller;
        return SafeArea(
          child: Stack(
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: InAppWebView(
                    initialData: InAppWebViewInitialData(data: html, mimeType: 'text/html', encoding: 'utf-8'),
                    initialSettings: InAppWebViewSettings(
                      transparentBackground: false,
                      javaScriptEnabled: true,
                      allowsInlineMediaPlayback: true,
                      mediaPlaybackRequiresUserGesture: true,
                      disableContextMenu: true,
                      supportZoom: false,
                      verticalScrollBarEnabled: true,
                    ),
                    onWebViewCreated: (c) => controller = c,
                  ),
                ),
              ),
              Positioned(
                right: 12,
                top: 8,
                child: GestureDetector(
                  onTap: () async {
                    try { await controller?.loadUrl(urlRequest: URLRequest(url: WebUri('about:blank'))); } catch (_) {}
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openLinkedInPreview(String postUrl) async {
    final u = _normalizeLinkedInEmbedUrl(postUrl);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (ctx) {
        InAppWebViewController? controller;
        return SafeArea(
          child: Stack(
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(u)),
                    initialSettings: InAppWebViewSettings(
                      transparentBackground: false,
                      javaScriptEnabled: true,
                      allowsInlineMediaPlayback: true,
                      mediaPlaybackRequiresUserGesture: true,
                      disableContextMenu: true,
                      supportZoom: false,
                      verticalScrollBarEnabled: true,
                    ),
                    onWebViewCreated: (c) => controller = c,
                  ),
                ),
              ),
              Positioned(
                right: 12,
                top: 8,
                child: GestureDetector(
                  onTap: () async {
                    try { await controller?.loadUrl(urlRequest: URLRequest(url: WebUri('about:blank'))); } catch (_) {}
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _buildTwitterEmbedDoc(String url) {
    final u = _extractXStatusUrl(url) ?? url.trim();
    final block = '<blockquote class="twitter-tweet"><a href="$u"></a></blockquote>';
    return '''
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
    <style>
      html, body { margin:0 !important; padding:0 !important; background:transparent; height:100%; overflow:hidden; }
      .wrap { position:relative; width:100%; height:100%; }
      .inner { position:absolute; inset:0; overflow:auto; display:flex; align-items:flex-start; justify-content:flex-start; }
      blockquote.twitter-tweet { margin:0 !important; padding:0 !important; }
      .twitter-tweet, .twitter-tweet-rendered { margin:0 !important; padding:0 !important; }
      body > div { margin:0 !important; padding:0 !important; }
    </style>
  </head>
  <body>
    <div class="wrap"><div class="inner">$block</div></div>
    <script async src="https://platform.twitter.com/widgets.js"></script>
  </body>
</html>
''';
  }

  String _buildLinkedInEmbedDoc(String url) {
    final u = _normalizeLinkedInEmbedUrl(url);
    return '''
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
    <style>
      html, body { margin:0; padding:0; background:#000; height:100%; overflow:hidden; }
      iframe { width:100%; height:100%; border:0; }
    </style>
  </head>
  <body>
    <iframe src="$u" allow="encrypted-media;" allowfullscreen></iframe>
  </body>
</html>
''';
  }

  String _normalizeLinkedInEmbedUrl(String raw) {
    try {
      final t = _extractLinkedInUrl(raw) ?? raw.trim();
      if (t.contains('linkedin.com/') && !t.contains('/embed/')) {
        // Beispiel: https://www.linkedin.com/feed/update/urn:li:activity:... ->
        //           https://www.linkedin.com/embed/feed/update/urn:li:activity:...
        return t.replaceFirst('linkedin.com/', 'linkedin.com/embed/');
      }
      return t;
    } catch (_) {
      return raw.trim();
    }
  }

  Future<void> _fetchThumb(String url) async {
    if (_thumbByUrl.containsKey(url)) return;
    try {
      // Server-Proxy für X oder LinkedIn
      if (widget.providerId == 'x') {
        final effective = _extractXStatusUrl(url) ?? url;
        final cf = await http.get(
          Uri.parse('https://us-central1-sunriza26.cloudfunctions.net/xThumb?url=${Uri.encodeComponent(effective)}'),
          headers: const {'Accept': 'application/json'},
        );
        print('[X Thumb] CF status: ${cf.statusCode}, body: ${cf.body}');
        if (cf.statusCode == 200) {
          final m = jsonDecode(cf.body) as Map<String, dynamic>;
          final t = (m['thumb'] as String?) ?? '';
          final s = (m['title'] as String?) ?? '';
          if (t.isNotEmpty && mounted) {
            print('[X Thumb] Found: $t');
            final cleaned = t.replaceAll('&amp;', '&');
            // Für X immer über CF-Bild-Proxy laden, um 403 zu vermeiden
            final proxied = 'https://us-central1-sunriza26.cloudfunctions.net/xThumb?img=${Uri.encodeComponent(cleaned)}';
            setState(() { 
              _thumbByUrl[url] = proxied; 
              if (s.isNotEmpty) _titleByUrl[url] = s;
            });
            return;
          }
          // Auch wenn kein Bild kam: versuche Titel aus oEmbed zu ziehen
          if (s.isEmpty) {
            try {
              final o = await http.get(
                Uri.parse('https://publish.twitter.com/oembed?url=${Uri.encodeComponent(effective)}'),
                headers: const {
                  'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
                  'Accept': 'application/json',
                },
              );
              if (o.statusCode == 200) {
                final mo = jsonDecode(o.body) as Map<String, dynamic>;
                final h = (mo['html'] as String?) ?? '';
                if (h.isNotEmpty) {
                  var txt = h.replaceAll(RegExp(r'<[^>]+>'), ' ');
                  txt = txt.replaceAll('&amp;', '&').replaceAll('&quot;', '"').replaceAll('&#39;', "'").trim();
                  if (txt.isNotEmpty && mounted) {
                    setState(() { _titleByUrl[url] = txt; });
                  }
                }
              }
            } catch (_) {}
          }
        }
      } else if (widget.providerId == 'linkedin') {
        final effectiveRaw = _extractLinkedInUrl(url) ?? url;
        // Für Thumbnail immer kanonische Seite nutzen (ohne /embed/ und ohne Query)
        final effective = effectiveRaw.replaceFirst('/embed/', '/').split('?').first;
        final cf = await http.get(
          Uri.parse('https://us-central1-sunriza26.cloudfunctions.net/linkedinThumb?url=${Uri.encodeComponent(effective)}'),
          headers: const {'Accept': 'application/json'},
        );
        print('[LI Thumb] CF status: ${cf.statusCode}, body: ${cf.body}');
        if (cf.statusCode == 200) {
          final m = jsonDecode(cf.body) as Map<String, dynamic>;
          final t = (m['thumb'] as String?) ?? '';
          if (t.isNotEmpty && mounted) {
            print('[LI Thumb] Found: $t');
            setState(() { _thumbByUrl[url] = t.replaceAll('&amp;', '&'); });
            return;
          }
        }
      }
      // Fallback: direktes HTML scrapen
      final String htmlUrl;
      if (widget.providerId == 'x') {
        htmlUrl = _extractXStatusUrl(url) ?? url;
      } else if (widget.providerId == 'linkedin') {
        final lr = _extractLinkedInUrl(url) ?? url;
        htmlUrl = lr.replaceFirst('/embed/', '/').split('?').first;
      } else {
        htmlUrl = url;
      }
      final r = await http.get(
        Uri.parse(htmlUrl),
        headers: const {
          'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
          'Accept': 'text/html',
        },
      );
      if (r.statusCode == 200) {
        final html = r.body;
        final regOg = RegExp(r'''<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']''', caseSensitive: false);
        final regTw = RegExp(r'''<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']+)["']''', caseSensitive: false);
        final regTitle = RegExp(r'''<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']''', caseSensitive: false);
        final regDesc = RegExp(r'''<meta[^>]+property=["']og:description["'][^>]+content=["']([^"']+)["']''', caseSensitive: false);
        final regTwTitle = RegExp(r'''<meta[^>]+name=["']twitter:title["'][^>]+content=["']([^"']+)["']''', caseSensitive: false);
        String img = regOg.firstMatch(html)?.group(1) ?? '';
        if (img.isEmpty) img = regTw.firstMatch(html)?.group(1) ?? '';
        String title = regTitle.firstMatch(html)?.group(1) ?? '';
        if (title.isEmpty) title = regTwTitle.firstMatch(html)?.group(1) ?? '';
        if (title.isEmpty) title = regDesc.firstMatch(html)?.group(1) ?? '';
        if (img.isNotEmpty && mounted) {
          final cleaned = img.replaceAll('&amp;', '&');
          print('[Fallback] Found thumb: $cleaned');
          setState(() {
            _thumbByUrl[url] = cleaned;
            if (title.isNotEmpty) _titleByUrl[url] = title;
          });
        } else {
          setState(() {
            _thumbByUrl[url] = '';
            if (title.isNotEmpty) _titleByUrl[url] = title;
          });
        }
      }
    } catch (e) {
      print('[FetchThumb Error] $e');
    }
  }

  Future<void> _openReorderDialog() async {
    final list = widget.manualCtrl.text.split('\n').where((e) => e.trim().isNotEmpty).map((e) => e.trim()).toList();
    final controller = ScrollController();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Reihenfolge ändern', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 400,
          height: 360,
          child: ReorderableListView.builder(
            scrollController: controller,
            itemCount: list.length,
            onReorder: (oldIndex, newIndex) {
              final from = oldIndex;
              var to = newIndex;
              if (to > from) to -= 1;
              final item = list.removeAt(from);
              list.insert(to, item);
            },
            itemBuilder: (ctx, i) {
              final u = list[i];
              return ListTile(
                key: ValueKey('xli-$i'),
                title: Text(u, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
                trailing: const Icon(Icons.drag_handle, color: Colors.white54),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(context, list), child: const Text('Übernehmen')),
        ],
      ),
    );
    if (result != null) {
      widget.manualCtrl.text = result.join('\n');
      await FirebaseFirestore.instance.collection('avatars').doc(widget.avatarId)
          .collection('social_accounts').doc(widget.providerId)
          .set({
        'manualUrls': result.take(20).toList(),
        'connected': result.isNotEmpty,
        'updatedAt': DateTime.now().millisecondsSinceEpoch
      }, SetOptions(merge: true));
      setState(() {});
      await widget.onSaved();
    }
  }
}

/// Provider aus URL erkennen (Top-Level, für Model und UI nutzbar)
String detectProviderFromUrl(String url) {
  final u = url.toLowerCase();
  if (u.contains('instagram.com')) return 'Instagram';
  if (u.contains('facebook.com')) return 'Facebook';
  if (u.contains('tiktok.com')) return 'TikTok';
  if (u.contains('x.com') || u.contains('twitter.com')) return 'X';
  if (u.contains('linkedin.com')) return 'LinkedIn';
  return 'Website';
}

class SocialMediaExpansionTile extends StatefulWidget {
  final String avatarId;
  const SocialMediaExpansionTile({super.key, required this.avatarId});

  @override
  State<SocialMediaExpansionTile> createState() => _SocialMediaExpansionTileState();
}

class _SocialMediaExpansionTileState extends State<SocialMediaExpansionTile> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _loading = true;
  List<SocialMediaAccount> _items = <SocialMediaAccount>[];
  String? _editingId; // null = kein Edit, 'new' = neuer Eintrag
  final _urlCtrl = TextEditingController();
  final _loginCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  bool _showPassword = false;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _openPreview(String postUrl) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (ctx) {
        return FutureBuilder<InAppWebViewInitialData>(
          future: _buildTikTokEmbedData(postUrl),
          builder: (context, snap) {
            return SafeArea(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                  Expanded(
                    child: !snap.hasData 
                      ? const Center(child: CircularProgressIndicator())
                      : Center(
                          child: AspectRatio(
                            aspectRatio: 9 / 16,
                            child: InAppWebView(
                              initialData: snap.data,
                              initialSettings: InAppWebViewSettings(
                                transparentBackground: true,
                                mediaPlaybackRequiresUserGesture: true,
                                disableContextMenu: true,
                                supportZoom: false,
                              ),
                              onConsoleMessage: (controller, consoleMessage) {
                                // Console-Logs unterdrücken (kein Debug-Spam)
                              },
                            ),
                          ),
                        ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<InAppWebViewInitialData> _buildTikTokEmbedData(String postUrl) async {
    String body = '';
    try {
      final resp = await http.get(Uri.parse('https://www.tiktok.com/oembed?url=${Uri.encodeComponent(postUrl)}'));
      if (resp.statusCode == 200) {
        final m = jsonDecode(resp.body) as Map<String, dynamic>;
        final html = (m['html'] as String?) ?? '';
        body = html;
      }
    } catch (_) {}
    if (body.isEmpty) {
      // Fallback: minimal Embed-Markup
      body =
          '<blockquote class="tiktok-embed" cite="$postUrl" style="max-width:100%;min-width:100%;"></blockquote><script async src="https://www.tiktok.com/embed.js"></script>';
    } else if (!body.contains('embed.js')) {
      body = '$body<script async src="https://www.tiktok.com/embed.js"></script>';
    }
    final doc = '''
<!doctype html>
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
    <style>html,body{height:100%;margin:0;background:#000;display:flex;align-items:center;justify-content:center} .wrap{width:100%}</style>
  </head>
  <body>
    <div class="wrap">$body</div>
  </body>
</html>
''';
    return InAppWebViewInitialData(data: doc, mimeType: 'text/html', encoding: 'utf-8');
  }
  @override
  void dispose() {
    _urlCtrl.dispose();
    _loginCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>> _col() {
    return _fs.collection('avatars').doc(widget.avatarId).collection('social_accounts');
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final qs = await _col().get();
      _items = qs.docs.map(SocialMediaAccount.fromDoc).toList();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  // Alte Editor-/CRUD-Methoden entfernt (ersetzt durch vereinfachten TikTok-Editor)

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.black87),
    );
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (_loading)
        const Center(child: CircularProgressIndicator())
      else ...[
        _buildTikTokTile(),
        const SizedBox(height: 10),
        _buildInstagramTile(),
        const SizedBox(height: 10),
        _buildLinkedInTile(),
        const SizedBox(height: 10),
        _buildXTile(),
      ],
    ];

    return ExpansionTile(
      initiallyExpanded: false,
      collapsedBackgroundColor: Colors.white.withValues(alpha: 0.04),
      backgroundColor: Colors.black.withValues(alpha: 0.95),
      collapsedIconColor: AppColors.magenta, // GMBC Arrow collapsed
      iconColor: AppColors.lightBlue, // GMBC Arrow expanded
      title: const Text('Social Media', style: TextStyle(color: Colors.white)),
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildTikTokTile() {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _col().doc('tiktok').get(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final manualUrls = ((data['manualUrls'] as List?) ?? const []).map((e) => e.toString()).toList();
        final connected = manualUrls.isNotEmpty;
        return InkWell(
          onTap: () => _openTikTokEdit('', manualUrls, connected),
          borderRadius: BorderRadius.circular(8),
          child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const FaIcon(FontAwesomeIcons.tiktok, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('TikTok', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                  Text('Anzahl Posts: ${manualUrls.length}', style: const TextStyle(color: Colors.white70)),
                ],
              ),
              const SizedBox(height: 10),
              const SizedBox(height: 2),
            ],
          ),
        ),
        );
      },
    );
  }

  Widget _buildInstagramTile() {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _col().doc('instagram').get(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final profileUrl = (data['profileUrl'] as String?)?.trim() ?? '';
        final connected = profileUrl.isNotEmpty;
        return InkWell(
          onTap: () => _openIgEdit(profileUrl, connected),
          borderRadius: BorderRadius.circular(8),
          child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const FaIcon(FontAwesomeIcons.instagram, color: Color(0xFFE4405F), size: 20),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Instagram', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                  Flexible(
                    child: Text(
                      connected ? profileUrl : 'Kein Account verknüpft',
                      style: const TextStyle(color: Colors.white70),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        );
      },
    );
  }

  Widget _buildLinkedInTile() {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _col().doc('linkedin').get(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final manualUrls = ((data['manualUrls'] as List?) ?? const []).map((e) => e.toString()).toList();
        final connected = manualUrls.isNotEmpty;
        return InkWell(
          onTap: () => _openGenericEdit(providerId: 'linkedin', initial: manualUrls, title: 'LinkedIn Posts'),
          borderRadius: BorderRadius.circular(8),
          child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const FaIcon(FontAwesomeIcons.linkedin, color: Color(0xFF0A66C2), size: 20),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('LinkedIn', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                  Text('Anzahl Posts: ${manualUrls.length}', style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ],
          ),
        ),
        );
      },
    );
  }

  Widget _buildXTile() {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _col().doc('x').get(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final manualUrls = ((data['manualUrls'] as List?) ?? const []).map((e) => e.toString()).toList();
        final connected = manualUrls.isNotEmpty;
        return InkWell(
          onTap: () => _openGenericEdit(providerId: 'x', initial: manualUrls, title: 'X (Twitter) Posts'),
          borderRadius: BorderRadius.circular(8),
          child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const FaIcon(FontAwesomeIcons.xTwitter, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('X (Twitter)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                  Text('Anzahl Posts: ${manualUrls.length}', style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ],
          ),
        ),
        );
      },
    );
  }

  void _openGenericEdit({required String providerId, required List<String> initial, required String title}) {
    final ctrl = TextEditingController(text: initial.join('\n'));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        final height = MediaQuery.of(ctx).size.height * 0.75;
        return SafeArea(
          child: SizedBox(
            height: height,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
                left: 16, right: 16, top: 16,
              ),
              child: _SimpleManualUrlsEditor(
                title: title,
                providerId: providerId,
                manualCtrl: ctrl,
                avatarId: widget.avatarId,
                onSaved: () async { await _load(); },
              ),
            ),
          ),
        );
      },
    );
  }

  void _openTikTokEdit(String currentProfile, List<String> currentManual, bool connected) {
    final profileCtrl = TextEditingController(text: currentProfile);
    final manualCtrl = TextEditingController(text: currentManual.join('\n'));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        final height = MediaQuery.of(ctx).size.height * 0.75;
        return SafeArea(
          child: SizedBox(
            height: height,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
                left: 16, right: 16, top: 16,
              ),
              child: _TikTokEditor(
                profileCtrl: profileCtrl,
                manualCtrl: manualCtrl,
                avatarId: widget.avatarId,
                connected: connected,
                onSaved: () async { await _load(); },
              ),
            ),
          ),
        );
      },
    );
  }

  void _openIgEdit(String currentProfile, bool connected) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        final height = MediaQuery.of(ctx).size.height * 0.75;
        return SafeArea(
          child: SizedBox(
            height: height,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
                left: 16, right: 16, top: 16,
              ),
              child: _IgAccountEditor(initialProfile: currentProfile, avatarId: widget.avatarId, onSaved: () async { await _load(); }),
            ),
          ),
        );
      },
    );
  }

}

class _IgAccountEditor extends StatefulWidget {
  final String initialProfile;
  final String avatarId;
  final Future<void> Function() onSaved;
  const _IgAccountEditor({required this.initialProfile, required this.avatarId, required this.onSaved});

  @override
  State<_IgAccountEditor> createState() => _IgAccountEditorState();
}

class _IgAccountEditorState extends State<_IgAccountEditor> {
  late final TextEditingController _profileCtrl;
  @override
  void initState() {
    super.initState();
    _profileCtrl = TextEditingController(text: widget.initialProfile);
  }
  @override
  void dispose() {
    _profileCtrl.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Instagram Account', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _profileCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Profil-URL',
                  hintText: 'https://www.instagram.com/username/',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            IconButton(
              tooltip: 'Speichern',
              icon: const Icon(Icons.check, color: Colors.white),
              onPressed: _isValidProfile(_profileCtrl.text) ? () async {
                final url = _normalizeProfileUrl(_profileCtrl.text);
                await FirebaseFirestore.instance.collection('avatars').doc(widget.avatarId)
                    .collection('social_accounts').doc('instagram')
                    .set({
                  'providerName': 'Instagram',
                  'profileUrl': url,
                  'manualUrls': <String>[],
                  'connected': url.isNotEmpty,
                  'updatedAt': DateTime.now().millisecondsSinceEpoch,
                }, SetOptions(merge: true));
                await widget.onSaved();
                if (mounted) Navigator.pop(context);
              } : null,
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text('Beispiel: https://www.instagram.com/ralf_matten/', style: TextStyle(color: Colors.white54, fontSize: 10)),
      ],
    );
  }
  bool _isValidProfile(String s) {
    final u = s.trim();
    return u.startsWith('http') && u.contains('instagram.com/');
  }
  String _normalizeProfileUrl(String raw) {
    final r = raw.trim().split('?').first.split('#').first;
    return r.endsWith('/') ? r : '$r/';
  }
}

class _IgEditor extends StatefulWidget {
  final List<String> initialUrls;
  final String avatarId;
  final Future<void> Function() onSaved;
  const _IgEditor({required this.initialUrls, required this.avatarId, required this.onSaved});

  @override
  State<_IgEditor> createState() => _IgEditorState();
}

class _IgEditorState extends State<_IgEditor> {
  final TextEditingController _addUrlCtrl = TextEditingController();
  final Map<String, String> _thumbByUrl = <String, String>{};
  final Map<String, Uint8List> _thumbBytesByUrl = <String, Uint8List>{};
  late List<String> _urls;
  int _page = 0;
  // dynamisch nach Breite

  @override
  void initState() {
    super.initState();
    _urls = [...widget.initialUrls];
    _thumbByUrl.clear();
  }

  @override
  void dispose() {
    _addUrlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int perPage = _calcPerPage(context);
    final start = _page * perPage;
    final end = (start + perPage).clamp(0, _urls.length);
    final slice = _urls.sublist(start, end);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Instagram Setup', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _addUrlCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Post-URL hinzufügen',
                  hintText: 'https://www.instagram.com/p/... oder /reel/...',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Builder(builder: (_) {
              final bool _enabled = _isValidIg(_addUrlCtrl.text);
              return IconButton(
              tooltip: 'Hinzufügen',
              icon: Icon(Icons.check, color: _enabled ? Colors.white : Colors.white24),
              onPressed: _enabled
                  ? () async {
                      final permalink = _extractInstagramPermalink(_addUrlCtrl.text)!;
                      _urls.add(permalink);
                      _addUrlCtrl.clear();
                      await _persist();
                      _fetchThumb(permalink);
                      setState(() {
                        final int perPage = _calcPerPage(context);
                        _page = ((_urls.length - 1) / perPage).floor();
                      });
                    }
                  : null,
            );}),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Benötigter Link: Instagram Post öffnen → rechts „Link kopieren“ → hier einfügen.',
          style: TextStyle(color: Colors.white54, fontSize: 10),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (int i = 0; i < slice.length; i++) _buildTile(start + i),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(onPressed: _page > 0 ? () => setState(() => _page--) : null, child: const Text('Zurück')),
            Builder(builder: (_) {
              final int perPage = _calcPerPage(context);
              final total = ((_urls.length + perPage - 1) / perPage).floor();
              return Text('${_page + 1} / $total', style: const TextStyle(color: Colors.white54, fontSize: 12));
            }),
            TextButton(
              onPressed: ((start + _calcPerPage(context)) < _urls.length) ? () => setState(() => _page++) : null,
              child: const Text('Weiter'),
            ),
          ],
        ),
      ],
    );
  }

  int _calcPerPage(BuildContext context) {
    final double width = MediaQuery.of(context).size.width - 32;
    const double tile = 90;
    const double spacing = 10;
    final int columns = max(1, ((width + spacing) / (tile + spacing)).floor());
    const int rows = 2;
    return columns * rows;
  }

  bool _isValidIg(String s) => _extractInstagramPermalink(s) != null;

  Future<void> _persist() async {
    await FirebaseFirestore.instance.collection('avatars').doc(widget.avatarId)
        .collection('social_accounts').doc('instagram')
        .set({
      'providerName': 'Instagram',
      'manualUrls': _urls.take(20).toList(),
      'connected': _urls.isNotEmpty,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    }, SetOptions(merge: true));
    await widget.onSaved();
  }

  Widget _buildTile(int index) {
    final url = _urls[index];
    _fetchThumb(url);
    final thumb = _thumbByUrl[url];
    final thumbBytes = _thumbBytesByUrl[url];
    return Stack(
      children: [
        SizedBox(
          width: 90,
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: (thumb == null && thumbBytes == null)
                  ? Container(color: Colors.white10, child: const Center(child: Icon(Icons.photo, color: Colors.white54)))
                  : (thumbBytes != null
                      ? Image.memory(thumbBytes, fit: BoxFit.cover)
                      : Image.network(
                      thumb!,
                      fit: BoxFit.cover,
                      headers: const {
                        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
                        'Referer': 'https://www.instagram.com/',
                        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
                      },
                    )),
            ),
          ),
        ),
        // Preview (Auge) unten links – gleich wie bei TikTok
        Positioned(
          left: 4,
          bottom: 4,
          child: InkWell(
            onTap: () => _openOEmbedPreview(context, provider: 'instagram', postUrl: url),
            child: Container(
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.remove_red_eye, size: 16, color: Colors.white70),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: InkWell(
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF1E1E1E),
                  title: const Text('Löschen?', style: TextStyle(color: Colors.white)),
                  content: const Text('Diesen Instagram‑Eintrag wirklich entfernen?', style: TextStyle(color: Colors.white70)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen')),
                  ],
                ),
              );
              if (confirm != true) return;
              _urls.removeAt(index);
              await _persist();
              setState(() {});
            },
            child: Container(
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.all(2),
              child: const Icon(Icons.delete, size: 16, color: Colors.redAccent),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _fetchThumb(String url) async {
    if (_thumbByUrl.containsKey(url)) return;
    try {
      // 0) Server-Proxy (robuster gegen IG-Blockaden)
      final cf = await http.get(
        Uri.parse('https://us-central1-sunriza26.cloudfunctions.net/instagramThumb?url=${Uri.encodeComponent(url)}'),
        headers: const {
          'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
          'Accept': 'application/json',
        },
      );
      if (cf.statusCode == 200) {
        final m = jsonDecode(cf.body) as Map<String, dynamic>;
        final t = (m['thumb'] as String?) ?? '';
        if (t.isNotEmpty) {
          try {
            final img = await http.get(Uri.parse(t), headers: const {
              'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
              'Referer': 'https://www.instagram.com/',
              'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
            });
            if (img.statusCode == 200 && img.bodyBytes.isNotEmpty) {
              setState(() { _thumbBytesByUrl[url] = img.bodyBytes; });
              return;
            } else {
              setState(() { _thumbByUrl[url] = t; });
              return;
            }
          } catch (_) {
            setState(() { _thumbByUrl[url] = t; });
            return;
          }
        }
      }
    } catch (_) {}
    try {
      // Versuche oEmbed ohne Token (kann je nach Region eingeschränkt sein)
      final resp = await http.get(
        Uri.parse('https://www.instagram.com/oembed/?url=${Uri.encodeComponent(url)}'),
        headers: const {
          'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
          'Accept': 'application/json',
          'Referer': 'https://www.instagram.com/',
        },
      );
      if (resp.statusCode == 200) {
        final m = jsonDecode(resp.body) as Map<String, dynamic>;
        final thumb = (m['thumbnail_url'] as String?) ?? '';
        if (thumb.isNotEmpty) {
          try {
            final img = await http.get(Uri.parse(thumb), headers: const {
              'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
              'Referer': 'https://www.instagram.com/',
              'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
            });
            if (img.statusCode == 200 && img.bodyBytes.isNotEmpty) {
              setState(() { _thumbBytesByUrl[url] = img.bodyBytes; });
            } else {
              setState(() { _thumbByUrl[url] = thumb; });
            }
          } catch (_) {
            setState(() { _thumbByUrl[url] = thumb; });
          }
        }
      }
    } catch (_) {}
    // Fallback: OG/Twitter-Meta scrapen, falls oEmbed kein Thumbnail liefert
    if (!_thumbByUrl.containsKey(url)) {
      try {
        final r = await http.get(
          Uri.parse(url),
          headers: const {
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
            'Accept': 'text/html',
            'Referer': 'https://www.instagram.com/',
          },
        );
        if (r.statusCode == 200) {
          final html = r.body;
          final regOg = RegExp(r'''<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']''', caseSensitive: false);
          final regTw = RegExp(r'''<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']+)["']''', caseSensitive: false);
          String img = regOg.firstMatch(html)?.group(1) ?? '';
          if (img.isEmpty) {
            img = regTw.firstMatch(html)?.group(1) ?? '';
          }
          if (img.isNotEmpty) {
            try {
              final rr = await http.get(Uri.parse(img), headers: const {
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
                'Referer': 'https://www.instagram.com/',
                'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
              });
              if (rr.statusCode == 200 && rr.bodyBytes.isNotEmpty) {
                setState(() { _thumbBytesByUrl[url] = rr.bodyBytes; });
              } else {
                setState(() { _thumbByUrl[url] = img; });
              }
            } catch (_) {
              setState(() { _thumbByUrl[url] = img; });
            }
          }
        }
      } catch (_) {}
    }
    // Zusätzlicher Fallback: öffentliche Embed-Seite laden und daraus OG/Twitter-Image extrahieren
    if (!_thumbByUrl.containsKey(url) && !_thumbBytesByUrl.containsKey(url)) {
      try {
        final embed = '${normalizeInstagramPermalink(url)}embed';
        final r = await http.get(
          Uri.parse(embed),
          headers: const {
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
            'Accept': 'text/html',
            'Referer': 'https://www.instagram.com/',
          },
        );
        if (r.statusCode == 200) {
          final html = r.body;
          final regOg = RegExp(r'''<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']''', caseSensitive: false);
          final regTw = RegExp(r'''<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']+)["']''', caseSensitive: false);
          String img = regOg.firstMatch(html)?.group(1) ?? '';
          if (img.isEmpty) {
            img = regTw.firstMatch(html)?.group(1) ?? '';
          }
          if (img.isNotEmpty) {
            try {
              final rr = await http.get(Uri.parse(img), headers: const {
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
                'Referer': 'https://www.instagram.com/',
                'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
              });
              if (rr.statusCode == 200 && rr.bodyBytes.isNotEmpty) {
                setState(() { _thumbBytesByUrl[url] = rr.bodyBytes; });
              } else {
                setState(() { _thumbByUrl[url] = img; });
              }
            } catch (_) {
              setState(() { _thumbByUrl[url] = img; });
            }
          }
        }
      } catch (_) {}
    }
  }
}

// Einheitliches Preview-Overlay für oEmbed-Provider (instagram/tiktok)
Future<void> _openOEmbedPreview(BuildContext context, {required String provider, required String postUrl}) async {
  Future<InAppWebViewInitialData> _buildData() async {
    // API-frei: reines Client-Embed über blockquote + embed.js
    String body;
    if (provider.toLowerCase() == 'instagram') {
      final permalink = normalizeInstagramPermalink(postUrl);
      final block = buildInstagramEmbedBlockquote(permalink);
      body = '$block<script async src="https://www.instagram.com/embed.js"></script>';
    } else {
      body = '<blockquote class="tiktok-embed" cite="$postUrl" style="max-width:100%;min-width:100%;"></blockquote>'
             '<script async src="https://www.tiktok.com/embed.js"></script>';
    }
    final doc = '''
<!doctype html>
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
    <style>
      html,body{height:100%;margin:0;background:#000;overflow-y:auto;overflow-x:hidden}
      .wrap{position:relative;width:100%;height:100%;display:flex;align-items:flex-start;justify-content:center}
      .inner{width:min(600px,100%);padding-top:8px}
      .close{
        position: fixed; top: 8px; right: 12px; width: 36px; height: 36px;
        border-radius: 18px; background: rgba(0,0,0,0.6); border: 1px solid rgba(255,255,255,0.2);
        display:flex; align-items:center; justify-content:center; color:#fff; font-size:20px; cursor:pointer; z-index:9999;
      }
    </style>
  </head>
  <body>
    <div class="wrap">
      <div class="close" onclick="window.flutter_inappwebview.callHandler('close')">✕</div>
      <div class="inner">$body</div>
    </div>
  </body>
</html>
''';
    return InAppWebViewInitialData(data: doc, mimeType: 'text/html', encoding: 'utf-8');
  }

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.black,
    builder: (ctx) {
      return SafeArea(
        child: FutureBuilder<InAppWebViewInitialData>(
          future: _buildData(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            return InAppWebView(
              initialData: snap.data,
              initialSettings: InAppWebViewSettings(
                transparentBackground: true,
                mediaPlaybackRequiresUserGesture: true,
              ),
              onWebViewCreated: (controller) {
                controller.addJavaScriptHandler(
                  handlerName: 'close',
                  callback: (_) {
                    Navigator.of(ctx).pop();
                    return null;
                  },
                );
              },
            );
          },
        ),
      );
    },
  );
}

/// Normalisiert Instagram-URLs zu einer sauberen Permalink-Form:
/// - unterstützt /reel/{id}/, /p/{id}/ und /tv/{id}/
/// - entfernt Query/Fragment, stellt den abschließenden Slash sicher
String normalizeInstagramPermalink(String rawUrl) {
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
    // Fallback: Query abschneiden, Slash sicherstellen
    final base = rawUrl.split('?').first.split('#').first;
    return base.endsWith('/') ? base : '$base/';
  } catch (_) {
    final base = rawUrl.split('?').first.split('#').first;
    return base.endsWith('/') ? base : '$base/';
  }
}

/// Baut nur den Blockquote-Teil für Instagram.
/// Beispielausgabe:
/// <blockquote class="instagram-media" data-instgrm-captioned
///   data-instgrm-permalink="https://www.instagram.com/reel/DOE1q9-CWr6/"
///   style="width:100%; max-width:540px; margin:0 auto;">
/// </blockquote>
String buildInstagramEmbedBlockquote(String permalink, {bool captioned = true}) {
  final p = normalizeInstagramPermalink(permalink);
  final capAttr = captioned ? ' data-instgrm-captioned' : '';
  return '<blockquote class="instagram-media"$capAttr data-instgrm-permalink="$p" '
      'style="width:100%; max-width:540px; margin:0 auto;"></blockquote>';
}

/// Extrahiert aus beliebigem Text (URL, Blockquote, HTML) die erste Instagram-Permalink-URL.
/// Unterstützt /reel/, /p/, /tv/
String? _extractInstagramPermalink(String input) {
  final text = input.trim();
  // 1) data-instgrm-permalink="...”
  final reAttr = RegExp(r'''data-instgrm-permalink=["\'](https?://(?:www\.|m\.)?instagram\.com/(?:reel|p|tv)/[^"']+)["']''', caseSensitive: false);
  final m1 = reAttr.firstMatch(text);
  if (m1 != null && m1.groupCount >= 1) {
    return normalizeInstagramPermalink(m1.group(1)!);
  }
  // 2) Plain URL im Text
  final reUrl = RegExp(r'''(https?://(?:www\.|m\.)?instagram\.com/(?:reel|p|tv)/[^\s"'<>\)]+)''', caseSensitive: false);
  final m2 = reUrl.firstMatch(text);
  if (m2 != null && m2.groupCount >= 1) {
    return normalizeInstagramPermalink(m2.group(1)!);
  }
  return null;
}

class _TikTokEditor extends StatefulWidget {
  final TextEditingController profileCtrl;
  final TextEditingController manualCtrl;
  final String avatarId;
  final Future<void> Function() onSaved;
  final bool connected;
  const _TikTokEditor({required this.profileCtrl, required this.manualCtrl, required this.avatarId, required this.connected, required this.onSaved});

  @override
  State<_TikTokEditor> createState() => _TikTokEditorState();
}

class _TikTokEditorState extends State<_TikTokEditor> {
  int _page = 0; // dynamisch nach Breite
  // Toggle/Updater entfernt: nur manuelle URLs
  static const String _ua = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
  bool _editingProfile = false;
  final TextEditingController _addUrlCtrl = TextEditingController();
  final Map<String, String> _thumbByUrl = <String, String>{};
  int? _dragFromIndex;

  @override
  void initState() {
    super.initState();
    // Sicherstellen, dass stale Proxy-Thumbs nicht weiterverwendet werden
    _thumbByUrl.clear();
  }

  @override
  void dispose() {
    _addUrlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manual = widget.manualCtrl.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final int perPage = _calcPerPage(context);
    final start = _page * perPage;
    final end = (start + perPage).clamp(0, manual.length);
    final slice = manual.sublist(start, end);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: Text('TikTok Setup', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            // Keine Zusatzaktionen mehr (Aktualisieren/Toggle/Plus entfernt)
          ],
        ),
        const SizedBox(height: 8),
        const SizedBox(height: 12),
        // Neuer URL-Input + Hook
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _addUrlCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Video-URL hinzufügen',
                  hintText: 'https://www.tiktok.com/@user/video/…',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Builder(builder: (_) {
              final bool _enabled = (_addUrlCtrl.text.contains('www.tiktok.com') && (_addUrlCtrl.text.contains('/video/') || _addUrlCtrl.text.contains('/photo/')));
              return IconButton(
              tooltip: 'Hinzufügen',
              icon: Icon(Icons.check, color: _enabled ? Colors.white : Colors.white24),
              onPressed: _enabled ? () async {
                final u = _addUrlCtrl.text.trim();
                if (!(u.contains('/video/') || u.contains('/photo/'))) { _toast(context, 'Bitte gültige TikTok URL (/video/ oder /photo/)'); return; }
                final list = widget.manualCtrl.text.split('\n').where((e) => e.trim().isNotEmpty).map((e) => e.trim()).toList();
                list.add(u);
                widget.manualCtrl.text = list.join('\n');
                _addUrlCtrl.clear();
                await FirebaseFirestore.instance.collection('avatars').doc(widget.avatarId)
                    .collection('social_accounts').doc('tiktok')
                    .set({
                      'manualUrls': list.take(20).toList(),
                      'connected': true,
                      'updatedAt': DateTime.now().millisecondsSinceEpoch
                    }, SetOptions(merge: true));
                _fetchThumb(u);
                // Auf letzte Seite springen, wenn Eintrag > perPage
                setState(() {
                  final int perPage = _calcPerPage(context);
                  _page = ((list.length - 1) / perPage).floor();
                });
              } : null,
            );}),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Benötigter Link: TikTok Post öffnen → rechts „Link kopieren“ → hier einfügen.',
          style: TextStyle(color: Colors.white54, fontSize: 10),
        ),
        const SizedBox(height: 12),
        // Grid mit 9:16 Thumbnails, Trash + Drag (dynamisch nach Breite, 2 Reihen)
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (int i = 0; i < slice.length; i++) _buildDraggableTile(manual, start + i),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _page > 0 ? () => setState(() => _page--) : null,
              child: const Text('Zurück'),
            ),
            Builder(builder: (_) {
              final int perPage = _calcPerPage(context);
              final total = ((manual.length + perPage - 1) / perPage).floor();
              return Text('${_page + 1} / $total', style: const TextStyle(color: Colors.white54, fontSize: 12));
            }),
            TextButton(
              onPressed: ((start + _calcPerPage(context)) < manual.length) ? () => setState(() => _page++) : null,
              child: const Text('Weiter'),
            ),
          ],
        ),
        // Keine globalen Speichern/Abbrechen Buttons mehr
      ],
    );
  }

  int _calcPerPage(BuildContext context) {
    // Verfügbare Breite minus Padding (ca. 32 px)
    final double width = MediaQuery.of(context).size.width - 32;
    const double tile = 90;
    const double spacing = 10;
    final int columns = max(1, ((width + spacing) / (tile + spacing)).floor());
    const int rows = 2; // Zwei Reihen sichtbar
    return columns * rows;
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.black87));
  }
  Future<void> _fetchThumb(String url) async {
    final existing = _thumbByUrl[url];
    if (existing != null && !existing.contains('cloudfunctions.net/thumbnailProxy')) {
      return;
    } else if (existing != null) {
      // Stale Proxy-Eintrag verwerfen und neu laden
      _thumbByUrl.remove(url);
    }
    try {
      final o = await http.get(Uri.parse('https://www.tiktok.com/oembed?url=${Uri.encodeComponent(url)}'),
          headers: {'User-Agent': _ua, 'Accept': 'application/json'});
      if (o.statusCode == 200) {
        final m = jsonDecode(o.body) as Map<String, dynamic>;
        final thumb = (m['thumbnail_url'] as String?) ?? '';
        if (thumb.isNotEmpty) {
          setState(() {
            _thumbByUrl[url] = thumb;
          });
        }
      } else {
        // Fallback: HTML scrapen und Bild aus Meta-Tags extrahieren (og:image / twitter:image)
        final r = await http.get(Uri.parse(url), headers: {'User-Agent': _ua, 'Accept': 'text/html'});
        if (r.statusCode == 200) {
          final html = r.body;
          final regOg = RegExp(r"""<meta[^>]+property=["'](?:og:image|og:image:url)["'][^>]+content=["']([^"']+)["']""", caseSensitive: false);
          final regTw = RegExp(r"""<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']+)["']""", caseSensitive: false);
          String img = regOg.firstMatch(html)?.group(1) ?? '';
          if (img.isEmpty) {
            img = regTw.firstMatch(html)?.group(1) ?? '';
          }
          if (img.isNotEmpty) {
            setState(() { _thumbByUrl[url] = img; });
          } else {
          }
        } else {
        }
      }
    } catch (_) {}
  }

  Widget _buildDraggableTile(List<String> urls, int index) {
    final url = urls[index];
    _fetchThumb(url);
    final thumb = _thumbByUrl[url];
    return Draggable<int>(
      data: index,
      onDragStarted: () => _dragFromIndex = index,
      onDragEnd: (_) => _dragFromIndex = null,
      feedback: Opacity(
        opacity: 0.8,
        child: SizedBox(
          width: 90,
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: Container(color: Colors.black54, child: const Icon(Icons.drag_indicator, color: Colors.white)),
          ),
        ),
      ),
      child: DragTarget<int>(
        onWillAccept: (from) => from != null && from != index,
        onAccept: (from) async {
          final list = urls;
          final item = list.removeAt(from);
          list.insert(index, item);
          widget.manualCtrl.text = list.join('\n');
          await FirebaseFirestore.instance.collection('avatars').doc(widget.avatarId)
              .collection('social_accounts').doc('tiktok')
              .set({
                'manualUrls': list.take(20).toList(),
                'connected': list.isNotEmpty,
                'updatedAt': DateTime.now().millisecondsSinceEpoch
              }, SetOptions(merge: true));
          setState(() {});
        },
        builder: (ctx, cand, rej) {
          return Stack(
            children: [
              SizedBox(
                width: 90,
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: thumb == null
                        ? Container(
                            color: Colors.white10,
                            child: const Center(
                              child: FaIcon(FontAwesomeIcons.tiktok, color: Colors.white54, size: 40),
                            ),
                          )
                        : Image.network(
                            thumb,
                            fit: BoxFit.cover,
                            headers: const {
                              'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
                              'Referer': 'https://www.tiktok.com/',
                              'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
                            },
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.white10,
                              child: const Center(
                                child: FaIcon(FontAwesomeIcons.tiktok, color: Colors.white54, size: 40),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              // Preview (Auge) unten links
              Positioned(
                left: 4,
                bottom: 4,
                child: InkWell(
                  onTap: () => _openPreview(url),
                  child: Container(
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(Icons.remove_red_eye, size: 16, color: Colors.white70),
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: InkWell(
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: const Color(0xFF1E1E1E),
                        title: const Text('Löschen?', style: TextStyle(color: Colors.white)),
                        content: const Text('Diesen TikTok‑Eintrag wirklich entfernen?', style: TextStyle(color: Colors.white70)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen')),
                        ],
                      ),
                    );
                    if (confirm != true) return;
                    final list = urls;
                    list.removeAt(index);
                    widget.manualCtrl.text = list.join('\n');
                    await FirebaseFirestore.instance.collection('avatars').doc(widget.avatarId)
                        .collection('social_accounts').doc('tiktok')
                        .set({
                          'manualUrls': list.take(20).toList(),
                          'connected': list.isNotEmpty,
                          'updatedAt': DateTime.now().millisecondsSinceEpoch
                        }, SetOptions(merge: true));
                    setState(() {});
                  },
                  child: Container(
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.all(2),
                    child: const Icon(Icons.delete, size: 16, color: Colors.redAccent),
                  ),
                ),
              ),
              Positioned(
                bottom: 4,
                right: 4,
                child: InkWell(
                  onTap: _openReorderDialog,
                  child: Container(
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.all(2),
                    child: const Icon(Icons.drag_indicator, size: 16, color: Colors.white70),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openPreview(String postUrl) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () async {
                    try {
                      await _previewController?.loadUrl(urlRequest: URLRequest(url: WebUri('about:blank')));
                    } catch (_) {}
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
              ),
              Expanded(
                child: FutureBuilder<InAppWebViewInitialData>(
                  future: _buildEmbedData(postUrl),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return Center(
                      child: AspectRatio(
                        aspectRatio: 9 / 16,
                        child: InAppWebView(
                          initialData: snap.data,
                          initialSettings: InAppWebViewSettings(
                            transparentBackground: true,
                            mediaPlaybackRequiresUserGesture: true,
                            disableContextMenu: true,
                            supportZoom: false,
                          ),
                          onWebViewCreated: (c) => _previewController = c,
                          onConsoleMessage: (controller, consoleMessage) {
                            // Console-Logs unterdrücken
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  InAppWebViewController? _previewController;
  Future<InAppWebViewInitialData> _buildEmbedData(String postUrl) async {
    String body = '';
    try {
      final resp = await http.get(Uri.parse('https://www.tiktok.com/oembed?url=${Uri.encodeComponent(postUrl)}'));
      if (resp.statusCode == 200) {
        final m = jsonDecode(resp.body) as Map<String, dynamic>;
        final html = (m['html'] as String?) ?? '';
        body = html;
      }
    } catch (_) {}
    if (body.isEmpty) {
      body = '<blockquote class="tiktok-embed" cite="$postUrl" style="max-width:100%;min-width:100%;"></blockquote><script async src="https://www.tiktok.com/embed.js"></script>';
    } else if (!body.contains('embed.js')) {
      body = '$body<script async src="https://www.tiktok.com/embed.js"></script>';
    }
    final doc = '''
<!doctype html>
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
    <style>html,body{height:100%;margin:0;background:#000;display:flex;align-items:center;justify-content:center} .wrap{width:100%}</style>
  </head>
  <body>
    <div class="wrap">$body</div>
  </body>
</html>
''';
    return InAppWebViewInitialData(data: doc, mimeType: 'text/html', encoding: 'utf-8');
  }
  Future<void> _openReorderDialog() async {
    final list = widget.manualCtrl.text.split('\n').where((e) => e.trim().isNotEmpty).map((e) => e.trim()).toList();
    final controller = ScrollController();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Reihenfolge ändern', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 400,
          height: 360,
          child: ReorderableListView.builder(
            scrollController: controller,
            itemCount: list.length,
            onReorder: (oldIndex, newIndex) {
              final from = oldIndex;
              var to = newIndex;
              if (to > from) to -= 1;
              final item = list.removeAt(from);
              list.insert(to, item);
            },
            itemBuilder: (ctx, i) {
              final u = list[i];
              return ListTile(
                key: ValueKey('re-$i'),
                title: Text(u, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
                trailing: const Icon(Icons.drag_handle, color: Colors.white54),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(context, list), child: const Text('Übernehmen')),
        ],
      ),
    );
    if (result != null) {
      widget.manualCtrl.text = result.join('\n');
      await FirebaseFirestore.instance.collection('avatars').doc(widget.avatarId)
          .collection('social_accounts').doc('tiktok')
          .set({
            'manualUrls': result.take(20).toList(),
            'connected': result.isNotEmpty,
            'updatedAt': DateTime.now().millisecondsSinceEpoch
          }, SetOptions(merge: true));
      setState(() {});
    }
  }
  Widget _miniToggle(bool value) {
    return Container(
      width: 48,
      height: 28,
      decoration: BoxDecoration(
        color: value ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            gradient: value
                ? const LinearGradient(
                    colors: [AppColors.magenta, AppColors.lightBlue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: value ? null : Colors.white.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  static String _detectProvider(String url) {
    final u = url.toLowerCase();
    if (u.contains('instagram.com')) return 'Instagram';
    if (u.contains('facebook.com')) return 'Facebook';
    if (u.contains('tiktok.com')) return 'TikTok';
    if (u.contains('x.com') || u.contains('twitter.com')) return 'X';
    if (u.contains('linkedin.com')) return 'LinkedIn';
    return 'Website';
  }

  Widget _iconForProvider(String provider) {
    switch (provider.toLowerCase()) {
      case 'instagram':
        return const FaIcon(FontAwesomeIcons.instagram, color: Color(0xFFE4405F), size: 22);
      case 'facebook':
        return const FaIcon(FontAwesomeIcons.facebook, color: Color(0xFF1877F2), size: 22);
      case 'x':
        return const FaIcon(FontAwesomeIcons.xTwitter, color: Colors.white, size: 22);
      case 'tiktok':
        return const FaIcon(FontAwesomeIcons.tiktok, color: Colors.white, size: 22);
      case 'linkedin':
        return const FaIcon(FontAwesomeIcons.linkedin, color: Color(0xFF0A66C2), size: 22);
      default:
        return const FaIcon(FontAwesomeIcons.globe, color: Colors.white, size: 22);
    }
  }

  Future<String> _encrypt(String plain) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
    final keyBytes = Uint8List.fromList(_deriveKey(uid));
    final key = enc.Key(keyBytes);
    // AES-CBC: 16 Byte IV
    final iv16 = enc.IV(Uint8List.fromList(_randomBytes(16)));
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(plain, iv: iv16);
    // Speichere iv:cipher als base64: iv|cipher
    return '${base64Encode(iv16.bytes)}:${encrypted.base64}';
  }

  Future<String> _decrypt(String data) async {
    try {
      final parts = data.split(':');
      if (parts.length != 2) return '';
      final ivBytes = base64Decode(parts[0]);
      final cipherB64 = parts[1];
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
      final key = enc.Key(Uint8List.fromList(_deriveKey(uid)));
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final decrypted = encrypter.decrypt(enc.Encrypted.fromBase64(cipherB64), iv: enc.IV(ivBytes));
      return decrypted;
    } catch (_) {
      return '';
    }
  }

  List<int> _deriveKey(String uid) {
    // Simple Ableitung: uid Hash zu 32 Bytes auffüllen/trimmen (clientseitig; ausreichend für obfuskierten Speicher)
    final b = utf8.encode(uid);
    final out = List<int>.filled(32, 0);
    for (int i = 0; i < 32; i++) {
      out[i] = b[i % b.length] ^ (i * 31);
    }
    return out;
  }

  List<int> _randomBytes(int n) {
    final rnd = Random.secure();
    return List<int>.generate(n, (_) => rnd.nextInt(256));
  }
}


