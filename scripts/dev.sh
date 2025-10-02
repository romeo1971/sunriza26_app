#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
  cat <<'EOF'
Sunriza Dev CLI

Usage:
  scripts/dev.sh <command>

Commands (häufig):
  help                     Zeigt diese Hilfe
  stack                    Versionen/Diagnose sammeln (-> brain/stack_versions_last.txt)
  hooks                    Git-Hooks installieren (pre-push sammelt Versionen)
  get                      flutter pub get
  clean                    flutter clean && rm -rf build/
  outdated                 flutter pub outdated --no-transitive

Start/Build:
  run:macos                flutter run -d macos
  run:ios                  flutter run -d ios
  build:ios                flutter build ios --release
  build:apk                flutter build apk --release

Qualität:
  format                   dart format .
  test                     flutter test

Beispiele:
  bash scripts/dev.sh stack
  bash scripts/dev.sh run:macos
EOF
}

cmd=${1:-help}
case "$cmd" in
  help|-h|--help)
    usage ;;
  stack)
    bash "$ROOT_DIR/scripts/check_stack_versions.sh" ;;
  hooks)
    bash "$ROOT_DIR/scripts/install_git_hooks.sh" ;;
  get)
    (cd "$ROOT_DIR" && flutter pub get) ;;
  clean)
    (cd "$ROOT_DIR" && flutter clean && rm -rf build/ || true) ;;
  outdated)
    (cd "$ROOT_DIR" && flutter pub outdated --no-transitive) ;;
  run:macos)
    (cd "$ROOT_DIR" && flutter run -d macos) ;;
  run:ios)
    (cd "$ROOT_DIR" && flutter run -d ios) ;;
  build:ios)
    (cd "$ROOT_DIR" && flutter build ios --release) ;;
  build:apk)
    (cd "$ROOT_DIR" && flutter build apk --release) ;;
  format)
    (cd "$ROOT_DIR" && dart format .) ;;
  test)
    (cd "$ROOT_DIR" && flutter test) ;;
  *)
    echo "Unbekannter Befehl: $cmd" >&2
    usage
    exit 2 ;;
esac


