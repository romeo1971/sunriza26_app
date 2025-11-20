import 'package:flutter/material.dart';

class TermsWidget extends StatelessWidget {
  static const String title = 'AGB';
  static const String body = '''
Nutzungsbedingungen – HAUAU

frentle GmbH · Kontakt: support@hauau.de

1. Geltungsbereich
Diese Nutzungsbedingungen regeln die Nutzung der App HAUAU und der zugehörigen Webdienste. Mit der Registrierung stimmst du diesen Bedingungen zu.

2. Registrierung und Konto
Für die Nutzung benötigst du ein Nutzerkonto. Du bist verpflichtet, richtige Angaben zu machen und deine Zugangsdaten sicher zu verwahren.

3. Inhalte und Avatare
Nutzer:innen können Avatare erstellen und Medien hochladen. Du versicherst, dass du die Rechte an den hochgeladenen Inhalten besitzt oder die Erlaubnis der betroffenen Personen hast.
- Keine rechtswidrigen Inhalte (Pornografie, Hass, Urheberrechtsverletzungen)
- Avatare realer Personen nur mit Einwilligung; für Verstorbene ist Befugnis (z. B. Erbe) erforderlich
- Wir behalten uns vor, Inhalte zu entfernen oder Konten zu sperren

4. Kauf und Verkauf von Medien
Verkäufe erfolgen über Stripe Connect. Der Verkauf von Medien durch Nutzer:innen ist erlaubt; frentle GmbH fungiert als Plattformbetreiber.

5. Geistiges Eigentum
Die Nutzenden behalten die Rechte an ihren Inhalten. Durch das Hochladen räumst du HAUAU eine nicht-exklusive Lizenz zur Anzeige und Distribution innerhalb der Plattform ein.

6. Haftung
frentle GmbH haftet nur bei Vorsatz oder grober Fahrlässigkeit. Für Nutzerinhalte übernimmt frentle GmbH keine Haftung.

7. Kündigung und Sperrung
Wir können Konten bei Verstößen sperren. Nutzer:innen können ihre Konten jederzeit löschen; dies löscht alle zugehörigen Inhalte.

8. Änderungen der Bedingungen
Wir können diese Bedingungen anpassen; Änderungen werden auf dieser Seite veröffentlicht. Bei wesentlichen Änderungen informieren wir die Nutzer:innen.

Stand: November 2025
''';

  const TermsWidget({super.key});

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


