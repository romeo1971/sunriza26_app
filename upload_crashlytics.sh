#!/bin/bash
set -e

# === Konfiguration ===
FIREBASE_APP_ID="1:590744030274:ios:3312f6bd8cd558f03b31db"

# 1️⃣ Finde das neueste Xcode-Archiv
ARCHIVE_DIR="$HOME/Library/Developer/Xcode/Archives"
LATEST_ARCHIVE=$(ls -td "$ARCHIVE_DIR"/*/*.xcarchive 2>/dev/null | head -n1)

if [ -z "$LATEST_ARCHIVE" ]; then
    echo "⚠️ Kein Archiv gefunden in $ARCHIVE_DIR"
    exit 1
fi

echo "✅ Neuestes Archiv gefunden: $LATEST_ARCHIVE"

# 2️⃣ Prüfe, ob Runner.app.dSYM existiert
DSYM="$LATEST_ARCHIVE/dSYMs/Runner.app.dSYM"
if [ ! -d "$DSYM" ]; then
    echo "⚠️ Runner.app.dSYM nicht gefunden in $DSYM"
    echo "Bitte sicherstellen, dass du ein Archiv mit dSYM erzeugt hast."
    exit 1
fi

echo "✅ Runner.app.dSYM gefunden: $DSYM"

# 3️⃣ Crashlytics Upload
if ! command -v firebase &> /dev/null; then
    echo "⚠️ Firebase CLI nicht gefunden. Bitte installieren."
    exit 1
fi

echo "⏳ Lade Symbole zu Firebase Crashlytics hoch..."
firebase crashlytics:symbols:upload --app "$FIREBASE_APP_ID" "$DSYM"

echo "✅ Upload abgeschlossen."
