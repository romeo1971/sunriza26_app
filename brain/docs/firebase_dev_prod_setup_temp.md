TEMPORÄR – kann gelöscht werden, sobald Dev/Prod sauber laufen.

# Firebase Dev/Prod Setup (Hauau/Sunriza)

## 1. Firebase-Projekte (Vorschlag)

- **Prod-Projekt**: `hauau-prod`
  - Firestore: echte User, echte Credits, echte Payments.
  - Auth, Storage, Functions: nur Live-Daten.
- **Dev-Projekt**: `hauau-dev`
  - Firestore: Test-User, Test-Credits, Test-Payments.
  - Auth, Storage, Functions: zum Entwickeln / Testen.

Richtlinie: **niemals** direkt gegen `hauau-prod` entwickeln oder testen – nur über bewusst gebaute Prod-Builds.

## 2. Firebase-Konfiguration im Flutter-Code

Aktueller Stand:
- `lib/main.dart` nutzt:
  - `firebase_options.dart` (aktuelles Single-Projekt)
  - `.env` über `dotenv.load(fileName: '.env');`

Ziel:
- **Gemeinsamer Bootstrap** in `main.dart`, der `envFileName` + `firebaseOptions` entgegennimmt.
- Zwei schlanke Entry-Points:
  - `lib/main_dev.dart` → `.env.dev` + `firebase_options_dev.dart` + Projekt `hauau-dev`
  - `lib/main_prod.dart` → `.env.prod` + `firebase_options.dart` (Prod) + Projekt `hauau-prod`

Wichtig: **nur ein Code-Repository**, keine zwei getrennten Codes.

## 3. Code-Struktur (soll-Zustand)

In `lib/main.dart`:
- Neue Funktion:
  - `Future<void> bootstrapApp({required String envFileName, required FirebaseOptions firebaseOptions})`
    - lädt `.env` über `envFileName`
    - initialisiert Firebase mit `firebaseOptions`
    - macht alle weiteren Setups (Firestore Settings, BitHuman, GoogleSignIn, Sprache, runApp, etc.)
- `main()` ruft:
  - `bootstrapApp(envFileName: '.env', firebaseOptions: DefaultFirebaseOptions.currentPlatform);`
  - → bestehendes Verhalten bleibt Prod‑kompatibel.

Neue Dateien:
- `lib/main_dev.dart`
  - importiert `bootstrapApp` aus `main.dart`
  - importiert `firebase_options_dev.dart`
  - `main()` ruft:
    - `bootstrapApp(envFileName: '.env.dev', firebaseOptions: DefaultFirebaseOptionsDev.currentPlatform);`
- `lib/main_prod.dart`
  - importiert `bootstrapApp` aus `main.dart`
  - importiert `firebase_options.dart`
  - `main()` ruft:
    - `bootstrapApp(envFileName: '.env.prod', firebaseOptions: DefaultFirebaseOptions.currentPlatform);`

Dev-Firebase-Options:
- Datei `lib/firebase_options_dev.dart`
  - wird mit `flutterfire configure` für Projekt `hauau-dev` erzeugt.
  - vorerst liegt ein schlanker Stub im Repo, damit der Code kompiliert.

## 4. .env-Dateien

Im Projekt-Root:
- `.env.prod` → echte Keys (Stripe, Pinecone, ElevenLabs, etc.) für Prod.
- `.env.dev` → Dev-/Test-Keys (andere Projekte, Test-Stripe-Keys, etc.).

Richtlinie:
- **Niemals** Prod-Secrets in `.env.dev`.
- `.env` kann optional als Alias auf eine der beiden Umgebungen dienen, wird aber perspektivisch durch `.env.dev` / `.env.prod` ersetzt.

## 5. Lokaler Workflow

- **Dev-Modus (Standard-Entwicklung)**:
  - `flutter run -t lib/main_dev.dart`
  - oder `flutter build web -t lib/main_dev.dart --release`
  - Firebase-Projekt: `hauau-dev`
  - Daten: Test-User, Test-Credits, Test-Payments (Stripe Test-Keys).

- **Prod-Build (bewusster Schritt)**:
  - `flutter build web -t lib/main_prod.dart --release`
  - `firebase deploy --only hosting --project=hauau-prod`
  - Firebase-Projekt: `hauau-prod`
  - Daten: echte User & Payments.

## 6. Hosting / Domains

Empfehlung:
- `www.hauau.de` → Firebase Hosting in `hauau-prod` (Zero‑Downtime Deploys, Preview Channels).
- `dev.hauau.de` oder `stage.hauau.de` → Hosting in `hauau-dev`.

Deployment-Flow:
1. Änderungen lokal gegen `main_dev.dart` + `hauau-dev` testen.
2. Wenn alles passt:
   - Prod-Build mit `main_prod.dart` erstellen.
   - auf `hauau-prod` deploen.

Strato:
- Perspektivisch durch Firebase Hosting ablösen (kein manuelles FTP-Löschen mehr).


