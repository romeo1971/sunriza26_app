#!/bin/bash

# BitHuman Backend Start-Script
# Startet das offizielle BitHuman Backend

echo "🚀 Starte BitHuman Backend..."

# Virtual Environment aktivieren
source venv/bin/activate

# Backend starten
cd backend
python bithuman_service.py
