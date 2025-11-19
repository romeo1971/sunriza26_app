# Terminal-Befehlsübersicht (Sunriza)

Pfad zum Repo (Flutter-App):

```
/Users/hhsw/Desktop/hauau/hauau
```

## Dev-CLI (empfohlen)
Kurzbefehle für häufige Tasks:

```
cd /Users/hhsw/Desktop/hauau/hauau
bash scripts/dev.sh help          # Hilfe/Übersicht
bash scripts/dev.sh stack         # Stack-Report -> brain/stack_versions_last.txt
bash scripts/dev.sh hooks         # Git pre-push Hook installieren
bash scripts/dev.sh get           # flutter pub get
bash scripts/dev.sh clean         # flutter clean
bash scripts/dev.sh outdated      # veraltete Pakete anzeigen
bash scripts/dev.sh run:macos     # App starten (macOS)
bash scripts/dev.sh run:ios       # App starten (iOS)
bash scripts/dev.sh build:ios     # iOS Release-Build
bash scripts/dev.sh build:apk     # Android Release-APK
bash scripts/dev.sh format        # dart format .
bash scripts/dev.sh test          # flutter test
```

## Makefile-Shortcuts

```
make check-stack           # wie scripts/check_stack_versions.sh
make install-git-hooks     # installiert pre-push Hook
```

## Einzelbefehle (Quick Reference)

- Flutter/Dart

```
flutter --version
flutter doctor -v
flutter pub get
flutter pub outdated --no-transitive
flutter run -d macos
flutter run -d ios
flutter build ios --release
flutter build apk --release
```

- Apple Toolchain

```
xcodebuild -version
swift --version
pod --version
```

- Android/Java/Gradle

```
java -version
gradle -v
adb version
sdkmanager --version
```

- Node / NPM / Yarn

```
node -v
npm -v
yarn -v
```

- Firebase/Google Cloud

```
firebase --version
gcloud --version
```

## Stack-Report (Automatisiert)

Erstellt/aktualisiert `brain/ops/stack_versions_last.txt`:

```
bash scripts/check_stack_versions.sh
```

Pre-Push Hook (automatische Aktualisierung vor jedem Push):

```
make install-git-hooks
```

Hinweis: Diese Datei ist bewusst im Ordner `brain/` verankert, damit sie bei jedem Kontextwechsel schnell auffindbar ist.

verhaltensregeln.md befolgen 1:1
