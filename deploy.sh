#!/bin/bash

# Sunriza26 Deployment Script
# Stand: 04.09.2025 - Für Live AI-Assistenten mit geklonter Stimme

set -e

echo "🚀 Sunriza26 Deployment gestartet..."

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funktionen
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Prüfe ob Firebase CLI installiert ist
if ! command -v firebase &> /dev/null; then
    print_error "Firebase CLI ist nicht installiert. Installiere es mit: npm install -g firebase-tools"
    exit 1
fi

# Prüfe ob Flutter installiert ist
if ! command -v flutter &> /dev/null; then
    print_error "Flutter ist nicht installiert. Installiere es von: https://flutter.dev"
    exit 1
fi

# Prüfe Firebase Login
print_status "Prüfe Firebase Login..."
if ! firebase projects:list &> /dev/null; then
    print_error "Nicht bei Firebase angemeldet. Führe 'firebase login' aus."
    exit 1
fi

# Prüfe ob Projekt korrekt konfiguriert ist
print_status "Prüfe Firebase Projekt-Konfiguration..."
PROJECT_ID=$(firebase use --project | grep -o 'tomorrow-3e1c8' || echo "")
if [ "$PROJECT_ID" != "tomorrow-3e1c8" ]; then
    print_warning "Projekt nicht korrekt konfiguriert. Setze Projekt..."
    firebase use tomorrow-3e1c8
fi

# 1. Cloud Functions deployen
print_status "Deploye Cloud Functions..."
cd functions

# Dependencies installieren
print_status "Installiere Node.js Dependencies..."
npm install

# TypeScript kompilieren
print_status "Kompiliere TypeScript..."
npm run build

# Functions deployen
print_status "Deploye Firebase Cloud Functions..."
firebase deploy --only functions

print_success "Cloud Functions erfolgreich deployed!"

# 2. Flutter App builden und deployen
cd ..
print_status "Baue Flutter Web App..."

# Dependencies installieren
flutter pub get

# Web App builden
flutter build web --release

print_success "Flutter Web App erfolgreich gebaut!"

# 3. Hosting deployen
print_status "Deploye Firebase Hosting..."
firebase deploy --only hosting

print_success "Firebase Hosting erfolgreich deployed!"

# 4. Health Check
print_status "Führe Health Check durch..."
sleep 5

HEALTH_URL="https://us-central1-tomorrow-3e1c8.cloudfunctions.net/healthCheck"
HEALTH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL" || echo "000")

if [ "$HEALTH_RESPONSE" = "200" ]; then
    print_success "Health Check erfolgreich! Services sind online."
else
    print_warning "Health Check fehlgeschlagen (HTTP $HEALTH_RESPONSE). Prüfe die Logs."
fi

# 5. Deployment-Info
print_success "🎉 Deployment abgeschlossen!"
echo ""
echo "📱 App-URLs:"
echo "   Web App: https://tomorrow-3e1c8.web.app"
echo "   Health Check: $HEALTH_URL"
echo ""
echo "🔧 Cloud Functions:"
echo "   generateLiveVideo: https://us-central1-tomorrow-3e1c8.cloudfunctions.net/generateLiveVideo"
echo "   testTTS: https://us-central1-tomorrow-3e1c8.cloudfunctions.net/testTTS"
echo ""
echo "📊 Monitoring:"
echo "   Firebase Console: https://console.firebase.google.com/project/tomorrow-3e1c8"
echo "   Google Cloud Console: https://console.cloud.google.com/home/dashboard?project=tomorrow-3e1c8"
echo ""
echo "📝 Nächste Schritte:"
echo "   1. Custom Voice Model in Google Cloud Console trainieren"
echo "   2. Referenzvideo in Firebase Cloud Storage hochladen"
echo "   3. Secrets in Firebase Secret Manager konfigurieren"
echo "   4. App testen und optimieren"
echo ""

print_success "Deployment-Skript erfolgreich abgeschlossen!"
