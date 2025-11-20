import 'package:flutter/material.dart';

class PrivacyWidget extends StatelessWidget {
  static const String title = 'Datenschutz';
  // Single Source of Truth: Inhalt hier pflegen (Markdown/Plaintext möglich)
  static const String body = '''
Datenschutz – HAUAU

frentle GmbH
Support / Datenschutz: privacy@hauau.de

1. Einleitung
Diese Datenschutzrichtlinie erklärt, welche personenbezogenen Daten die App HAUAU ("App") verarbeitet, zu welchem Zweck und auf welchen Rechtsgrundlagen. Sie gilt für alle Nutzer:innen der App und der zugehörigen Webdienste.

2. Verantwortlicher
frentle GmbH
[Adresse einsetzen]
E‑Mail: privacy@hauau.de

3. Welche Daten wir verarbeiten
- Vorname, Nachname, Nickname
- E‑Mail‑Adresse, Telefonnummer
- Geburtsdatum, (optional) Todesdatum
- Medieninhalte (Fotos, Videos, Audios, Dokumente), Profilbild
- Avatar‑Metadaten (Name, Beschreibung, KI‑Profile, Voice‑Clones)
- Abwicklungsdaten für Zahlungen via Stripe (werden von Stripe gespeichert)
- Technische Daten (z. B. anonymisierte Logs, Geräteinformationen zur Fehleranalyse)

4. Zweck der Verarbeitung
- Kontoerstellung und Authentifizierung
- Speicherung und Verwaltung eigener Inhalte (Medien, Avatare)
- Bereitstellung der App‑Funktionen (z. B. Chat, Verkauf von Medien)
- Kommunikation (Support, Passwortzurücksetzung)
- Abwicklung von Zahlungen über Stripe

5. Rechtsgrundlagen
- Art. 6 Abs. 1 lit. b DSGVO (Vertragserfüllung)
- Art. 6 Abs. 1 lit. a DSGVO (Einwilligung) – z. B. Voice‑Cloning oder Veröffentlichungen
- Art. 6 Abs. 1 lit. f DSGVO (berechtigtes Interesse) – z. B. Sicherheit, Betrugsprävention

6. Weitergabe an Dritte
- Stripe (Zahlungsabwicklung)
- Hosting‑/Cloud‑Provider (EU‑Regionen, z. B. Frankfurt) zur Speicherung von Inhalten
- Behörden auf Anfrage bei gesetzlichen Verpflichtungen

7. Speicherdauer
Daten werden solange gespeichert, wie dein Konto aktiv ist, bzw. solange gesetzliche Aufbewahrungspflichten bestehen. Auf Anforderung löschen oder anonymisieren wir Daten.

8. Rechte der Nutzer:innen
Auskunft, Berichtigung, Löschung, Einschränkung der Verarbeitung, Datenübertragbarkeit, Widerspruch. Kontakt: privacy@hauau.de

9. Hinweise zu Avataren und Voice‑Clones
- Der Ersteller bestätigt erforderliche Rechte/Einwilligungen (bei realen Personen oder als Erbe/Bevollmächtigter).
- Verstöße gegen Rechte Dritter können zur Sperrung/Löschung führen.
- Voice‑Cloning erfordert gesonderte Einwilligung; für Verstorbene gelten ggf. Erbenrechte.

10. Sicherheit
TLS/HTTPS, Zugriffsbeschränkungen, sichere Speicherung.

11. Änderungen
Änderungen werden auf dieser Seite veröffentlicht. Stand: November 2025.
''';

  const PrivacyWidget({super.key});

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


