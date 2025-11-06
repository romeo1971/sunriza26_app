import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

String? getSessionStorage(String key) => null;
void removeSessionStorage(String key) {}

Future<void> openNewTab(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

Future<void> navigateTo(String url) async {
  await openNewTab(url);
}

Future<void> downloadUrlCompat(String url, {String? filename}) async {
  await openNewTab(url);
}

Stream<dynamic> windowMessages() => const Stream.empty();

void registerViewFactory(String viewType, dynamic Function(int) factory) {}

dynamic createIFrame(String src) => null;

Widget buildIframeView(String viewType) => const SizedBox.shrink();

bool get isWeb => false;


