#!/usr/bin/env bash
set -euo pipefail

out_dir="brain/ops"
out_file="$out_dir/stack_versions_last.txt"
mkdir -p "$out_dir"

ts() { date +"%Y-%m-%d %H:%M:%S"; }
say() { printf "%s %s\n" "[$(ts)]" "$*" | tee -a "$out_file"; }
hdr() { echo "\n==== $* ====\n" | tee -a "$out_file"; }

echo "# Stack Versions (latest run: $(ts))" > "$out_file"

hdr "Host"
uname -a | tee -a "$out_file" || true

chk() {
  local name="$1"; shift
  local cmd=("$@")
  if command -v "${cmd[0]}" >/dev/null 2>&1; then
    say "$name: $(${cmd[@]} 2>&1 | head -n 2 | tr -d '\r')"
  else
    say "$name: NOT INSTALLED"
  fi
}

hdr "Flutter/Dart"
chk "flutter --version" flutter --version
chk "dart --version" dart --version
say "flutter doctor -v:" && (flutter doctor -v 2>&1 | tee -a "$out_file" || true)
say "flutter pub outdated (app):" && (flutter pub outdated --no-transitive 2>&1 | tee -a "$out_file" || true)

hdr "Android/Java/Gradle"
chk "java -version" java -version
chk "gradle -v" gradle -v
chk "adb version" adb version
chk "sdkmanager --version" sdkmanager --version

hdr "Apple Toolchain"
chk "xcodebuild -version" xcodebuild -version
chk "swift --version" swift --version
chk "pod --version" pod --version
chk "ruby --version" ruby --version

hdr "Node.js / NPM / Yarn"
chk "node -v" node -v
chk "npm -v" npm -v
chk "yarn -v" yarn -v

hdr "Firebase/CLI"
chk "firebase --version" firebase --version
chk "gcloud --version" gcloud --version

hdr "Functions workspace"
if [ -d "functions" ]; then
  (cd functions && (npm outdated 2>&1 | tee -a "../$out_file" || true))
else
  say "functions/: not present"
fi

say "Done. Report saved to $out_file"

