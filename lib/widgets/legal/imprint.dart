import 'package:flutter/material.dart';

class ImprintWidget extends StatelessWidget {
  static const String title = 'Impressum';
  static const String body = '''
Impressum – HAU·AU

frentle GmbH
Musterstraße 12
12345 Musterstadt, Deutschland

Vertreten durch:
Max Mustermann, Geschäftsführer

Kontakt:
Telefon: +49 123 456789
E-Mail: support@hauau.de

Handelsregister: Amtsgericht Musterstadt, HRB 123456
Umsatzsteuer-ID: DE123456789

Verantwortlich für den Inhalt nach § 55 Abs. 2 RStV:
Max Mustermann, Musterstraße 12, 12345 Musterstadt

Stand: November 2025
''';

  const ImprintWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text(title),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          body,
          style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5),
        ),
      ),
    );
  }
}


