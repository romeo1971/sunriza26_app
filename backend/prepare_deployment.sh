#!/bin/bash
# Prepare Render.com Deployment Check

echo "🚀 Sunriza Backend - Render.com Deployment Check"
echo "================================================"
echo ""

# Farben
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR=$(dirname "$(realpath "$0")")
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")

# Check 1: Dockerfile vorhanden
echo "📦 Check 1: Dockerfile..."
if [ -f "$SCRIPT_DIR/Dockerfile" ]; then
    echo -e "${GREEN}✅ Dockerfile gefunden${NC}"
else
    echo -e "${RED}❌ Dockerfile fehlt!${NC}"
    exit 1
fi

# Check 2: render.yaml vorhanden
echo "📦 Check 2: render.yaml..."
if [ -f "$SCRIPT_DIR/render.yaml" ]; then
    echo -e "${GREEN}✅ render.yaml gefunden${NC}"
else
    echo -e "${RED}❌ render.yaml fehlt!${NC}"
    exit 1
fi

# Check 3: requirements.txt vorhanden
echo "📦 Check 3: requirements.txt..."
if [ -f "$SCRIPT_DIR/requirements.txt" ]; then
    echo -e "${GREEN}✅ requirements.txt gefunden${NC}"
else
    echo -e "${RED}❌ requirements.txt fehlt!${NC}"
    exit 1
fi

# Check 4: service-account-key.json vorhanden
echo "🔑 Check 4: service-account-key.json..."
if [ -f "$PROJECT_ROOT/service-account-key.json" ]; then
    echo -e "${GREEN}✅ service-account-key.json gefunden${NC}"
    echo -e "${YELLOW}   ⚠️  WICHTIG: Diese Datei muss manuell als Secret File in Render hochgeladen werden!${NC}"
else
    echo -e "${RED}❌ service-account-key.json fehlt!${NC}"
    echo "   Pfad: $PROJECT_ROOT/service-account-key.json"
    exit 1
fi

# Check 5: Git Repository
echo "🔧 Check 5: Git Repository..."
cd "$PROJECT_ROOT"
if git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Git Repository gefunden${NC}"
    
    # Check Git Remote
    if git remote get-url origin > /dev/null 2>&1; then
        REMOTE_URL=$(git remote get-url origin)
        echo -e "${GREEN}✅ Git Remote konfiguriert${NC}"
        echo "   Remote: $REMOTE_URL"
    else
        echo -e "${YELLOW}⚠️  Git Remote nicht konfiguriert${NC}"
        echo "   Führe aus: git remote add origin <your-github-url>"
    fi
else
    echo -e "${RED}❌ Kein Git Repository!${NC}"
    echo "   Führe aus: git init"
    exit 1
fi

# Check 6: Untracked files
echo "📝 Check 6: Untracked files..."
UNTRACKED=$(git ls-files --others --exclude-standard backend/ | wc -l)
if [ "$UNTRACKED" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  $UNTRACKED untracked files in backend/${NC}"
    echo "   Füge sie hinzu: git add backend/"
else
    echo -e "${GREEN}✅ Alle Backend-Files tracked${NC}"
fi

# Check 7: Uncommitted changes
echo "📝 Check 7: Uncommitted changes..."
if git diff --quiet backend/; then
    echo -e "${GREEN}✅ Keine uncommitted changes${NC}"
else
    echo -e "${YELLOW}⚠️  Uncommitted changes vorhanden${NC}"
    echo "   Commit sie: git commit -m 'Prepare Render deployment'"
fi

echo ""
echo "================================================"
echo ""

# Summary
echo "📋 ZUSAMMENFASSUNG:"
echo ""
echo "✅ Alle notwendigen Files vorhanden"
echo ""
echo "🎯 NÄCHSTE SCHRITTE:"
echo ""
echo "1. Code committen und pushen:"
echo "   cd $PROJECT_ROOT"
echo "   git add backend/"
echo "   git commit -m 'Add Render.com deployment'"
echo "   git push origin main"
echo ""
echo "2. Render.com Dashboard öffnen:"
echo "   https://dashboard.render.com"
echo ""
echo "3. New Blueprint oder Web Service erstellen"
echo ""
echo "4. service-account-key.json als Secret File hochladen!"
echo ""
echo "5. Deployment Guide lesen:"
echo "   cat $SCRIPT_DIR/RENDER_DEPLOYMENT.md"
echo ""
echo "🚀 Viel Erfolg!"

