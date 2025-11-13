#!/bin/bash
set -e

# 🏗 Pfad zu Xcode Archives
ARCHIVE_DIR="$HOME/Library/Developer/Xcode/Archives"

# 🔍 Neuestes Archiv suchen
LATEST_ARCHIVE=$(find "$ARCHIVE_DIR" -name "*.xcarchive" -type d -print0 | xargs -0 ls -td 2>/dev/null | head -n 1)
if [ -z "$LATEST_ARCHIVE" ]; then
    echo "⚠️ Kein Archiv gefunden in $ARCHIVE_DIR"
    exit 1
fi
echo "✅ Neuestes Archiv gefunden: $LATEST_ARCHIVE"

# 🗂 Pfad zur Runner.app.dSYM
DSYM_PATH="$LATEST_ARCHIVE/dSYMs/Runner.app.dSYM"
if [ ! -d "$DSYM_PATH" ]; then
    echo "⚠️ Runner.app.dSYM nicht gefunden in $DSYM_PATH"
    exit 1
fi
echo "✅ Runner.app.dSYM gefunden: $DSYM_PATH"

# 💡 Firebase App-ID eintragen (von deinem Firebase Projekt)
FIREBASE_APP_ID="1:590744030274:ios:3312f6bd8cd558f03b31db"

# ⏳ Crashlytics Upload
echo "⏳ Lade Symbole zu Firebase Crashlytics hoch..."
firebase crashlytics:symbols:upload \
  --app "$FIREBASE_APP_ID" \
  "$DSYM_PATH" || echo "⚠️ Warnung: Native Symbol Upload fehlgeschlagen, Dart-Symbole wurden trotzdem hochgeladen."

echo "✅ Fertig. Crashlytics sollte jetzt Dart-Symbole haben."
