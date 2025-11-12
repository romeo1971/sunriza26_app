import 'dart:io';
import 'package:sunriza26/widgets/legal/privacy.dart';
import 'package:sunriza26/widgets/legal/terms.dart';
import 'package:sunriza26/widgets/legal/imprint.dart';

String _template(String title, String body) => '''
<!doctype html>
<html lang="de">
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$title – hauau</title>
  <body style="font-family:sans-serif;max-width:800px;margin:40px auto;padding:0 16px;line-height:1.6;background:#000;color:#fff">
    <h1>$title</h1>
    <pre style="white-space:pre-wrap;font:inherit">$body</pre>
  </body>
</html>
''';

Future<void> main() async {
  final projectRoot = Directory.current.path;
  final webDir = Directory('$projectRoot/web');
  if (!webDir.existsSync()) webDir.createSync(recursive: true);

  File('${webDir.path}/privacy.html').writeAsStringSync(_template(PrivacyWidget.title, PrivacyWidget.body));
  File('${webDir.path}/terms.html').writeAsStringSync(_template(TermsWidget.title, TermsWidget.body));
  File('${webDir.path}/imprint.html').writeAsStringSync(_template(ImprintWidget.title, ImprintWidget.body));
  // Optional deutsche Alias-Datei
  File('${webDir.path}/impressum.html').writeAsStringSync(_template(ImprintWidget.title, ImprintWidget.body));

  // ignore: avoid_print
  print('✅ Legal HTML generiert in web/: privacy.html, terms.html, imprint.html, impressum.html');
}


