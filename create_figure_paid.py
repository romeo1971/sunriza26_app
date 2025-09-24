#!/usr/bin/env python3
"""
BitHuman Figure Creation für Paid Account (Custom Agents & Creation)
"""

import os
import requests
import json
from pathlib import Path

# API Secret
API_SECRET = "DxGRMKb9fuMDiNHMO648VgU3MA81zP4hSZvdLFFV43nKYeMelG6x5QfrSH8UyvIRZ"

def create_figure_paid_account(image_path: str):
    """Erstelle Figure über Paid Account API"""
    
    print(f"🎭 Erstelle Figure für Paid Account aus: {image_path}")
    print(f"🔑 API Secret: {API_SECRET[:20]}...")
    
    # Mögliche Paid Account Endpunkte
    paid_endpoints = [
        "https://api.bithuman.ai/v1/custom/figures",
        "https://api.bithuman.ai/v1/premium/figures", 
        "https://api.bithuman.ai/v1/paid/figures",
        "https://custom.api.bithuman.ai/v1/figures",
        "https://premium.api.bithuman.ai/v1/figures",
        "https://auth.api.bithuman.ai/v1/custom/figures",
        "https://auth.api.bithuman.ai/v1/premium/figures",
        # LiveKit Integration Endpunkte
        "https://api.bithuman.ai/v1/livekit/figures",
        "https://livekit.api.bithuman.ai/v1/figures",
    ]
    
    headers = {
        "Authorization": f"Bearer {API_SECRET}",
        "api-secret": API_SECRET,  # Fallback Header
        "X-API-Key": API_SECRET,   # Alternative Header
    }
    
    # Bild laden
    with open(image_path, 'rb') as f:
        image_data = f.read()
    
    for endpoint in paid_endpoints:
        print(f"\n📡 Teste Paid Account Endpunkt: {endpoint}")
        
        try:
            # Verschiedene Payload-Formate testen
            payloads = [
                # Multipart Form Data mit "image"
                {
                    "files": {"image": (Path(image_path).name, image_data, "image/jpeg")},
                    "data": {"type": "custom_agent", "quality": "high"}
                },
                # Multipart Form Data mit "file"
                {
                    "files": {"file": (Path(image_path).name, image_data, "image/jpeg")},
                    "data": {"type": "custom_agent", "quality": "high"}
                },
                # Einfache Form Data ohne extra data
                {
                    "files": {"image": (Path(image_path).name, image_data, "image/jpeg")}
                }
            ]
            
            for i, payload in enumerate(payloads, 1):
                print(f"   🔄 Payload-Format {i}...")
                
                if "files" in payload:
                    response = requests.post(
                        endpoint, 
                        headers=headers,
                        files=payload["files"],
                        data=payload.get("data", {})
                    )
                else:
                    response = requests.post(
                        endpoint,
                        headers=headers,
                        json=payload["json"]
                    )
                
                print(f"   📋 Status: {response.status_code}")
                
                if response.status_code == 200:
                    print("   ✅ ERFOLG!")
                    result = response.json()
                    print(f"   📄 Response: {json.dumps(result, indent=2)}")
                    return result
                elif response.status_code == 401:
                    print("   ❌ 401 UNAUTHORIZED - API Key Problem")
                elif response.status_code == 404:
                    print("   ❌ 404 NOT FOUND - Endpunkt existiert nicht")
                elif response.status_code == 522:
                    print("   ❌ 522 CONNECTION TIMEOUT - Server Problem")
                else:
                    print(f"   ❌ {response.status_code} - {response.text[:200]}...")
                    
        except Exception as e:
            print(f"   💥 Fehler: {e}")
    
    print("\n🚫 Alle Paid Account Endpunkte fehlgeschlagen")
    return None

def main():
    """Hauptfunktion"""
    
    image_path = "brain/sylke_1_2025.jpeg"
    
    if not Path(image_path).exists():
        print(f"❌ Bild nicht gefunden: {image_path}")
        return
    
    result = create_figure_paid_account(image_path)
    
    if result:
        print(f"\n🎉 Figure erfolgreich erstellt!")
        
        # Extrahiere wichtige Daten
        if "figure_id" in result:
            print(f"📋 Figure ID: {result['figure_id']}")
        if "model_url" in result:
            print(f"🔗 Model URL: {result['model_url']}")
        if "imx_url" in result:
            print(f"🔗 IMX URL: {result['imx_url']}")
        if "runtime_model_hash" in result:
            print(f"🔐 Runtime Model Hash: {result['runtime_model_hash']}")
            
    else:
        print(f"\n💥 Figure-Erstellung fehlgeschlagen")

if __name__ == "__main__":
    main()
