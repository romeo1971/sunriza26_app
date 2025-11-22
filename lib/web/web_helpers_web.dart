import 'package:flutter/widgets.dart';
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui;

String? getSessionStorage(String key) {
  try {
    return html.window.sessionStorage[key];
  } catch (e) {
    // Fallback bei Browser-Einschränkungen (Private Mode, etc.)
    return null;
  }
}
void setSessionStorage(String key, String value) {
  try {
    html.window.sessionStorage[key] = value;
  } catch (_) {
    // Ignore
  }
}
void removeSessionStorage(String key) {
  try {
    html.window.sessionStorage.remove(key);
  } catch (_) {
    // Ignore
  }
}

Future<void> openNewTab(String url) async {
  try { html.window.open(url, '_blank'); } catch (_) {}
}

Future<void> navigateTo(String url) async {
  try { html.window.location.href = url; } catch (_) {}
}

Future<void> downloadUrlCompat(String url, {String? filename}) async {
  try {
    final req = await html.HttpRequest.request(
      url,
      method: 'GET',
      responseType: 'blob',
      requestHeaders: {'Accept': 'application/octet-stream'},
    );
    final blob = req.response as html.Blob;
    final objUrl = html.Url.createObjectUrlFromBlob(blob);
    final a = html.AnchorElement(href: objUrl)
      ..download = filename ?? 'download';
    html.document.body?.append(a);
    a.click();
    a.remove();
    html.Url.revokeObjectUrl(objUrl);
    return;
  } catch (_) {}

  try {
    final a = html.AnchorElement(href: url)
      ..target = '_blank'
      ..rel = 'noopener'
      ..download = filename ?? '';
    html.document.body?.append(a);
    a.click();
    a.remove();
  } catch (_) {
    try { html.window.location.href = url; } catch (_) {}
  }
}

Stream<html.MessageEvent> windowMessages() => html.window.onMessage;

void registerViewFactory(String viewType, dynamic Function(int) factory) {
  // ignore: undefined_prefixed_name
  ui.platformViewRegistry.registerViewFactory(viewType, factory);
}

dynamic createIFrame(String src) {
  final iframe = html.IFrameElement()
    ..src = src
    ..style.border = 'none'
    ..style.width = '100%'
    ..style.height = '100%';
  return iframe;
}

Widget buildIframeView(String viewType) => HtmlElementView(viewType: viewType);

bool get isWeb => true;


