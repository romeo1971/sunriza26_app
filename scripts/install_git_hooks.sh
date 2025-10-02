#!/usr/bin/env bash
set -euo pipefail

HOOKS_DIR=".git/hooks"
mkdir -p "$HOOKS_DIR"

cat > "$HOOKS_DIR/pre-push" <<'EOF'
#!/usr/bin/env bash
# Pre-push: sammelt Stack-Versionen, damit Upgrades sichtbar bleiben
if [ -x scripts/check_stack_versions.sh ]; then
  bash scripts/check_stack_versions.sh >/dev/null 2>&1 || true
fi
exit 0
EOF

chmod +x "$HOOKS_DIR/pre-push"
echo "Installed pre-push hook."


