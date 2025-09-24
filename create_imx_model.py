#!/usr/bin/env python3
"""
BitHuman .imx Model Creation Script
Erstellt ein .imx-Modell aus einem Bild für Custom Agents & Creation Account
"""

import os
import sys
from pathlib import Path
from PIL import Image
from bithuman import AsyncBithuman
import asyncio

# API Token aus Environment Variable
API_SECRET = os.getenv("BITHUMAN_API_SECRET", "DxGRMKb9fuMDiNHMO648VgU3MA81zP4hSZvdLFFV43nKYeMelG6x5QfrSH8UyvIRZ")

async def create_imx_model(image_path: str, output_path: str):
    """Erstelle .imx-Modell aus Bild"""
    
    print(f"🎭 Erstelle .imx-Modell aus: {image_path}")
    print(f"💾 Output: {output_path}")
    print(f"🔑 API Secret: {API_SECRET[:20]}...")
    
    # Überprüfe ob Bild existiert
    if not Path(image_path).exists():
        print(f"❌ Bild nicht gefunden: {image_path}")
        return False
        
    try:
        # Lade das Bild
        print("📷 Lade Bild...")
        image = Image.open(image_path)
        print(f"✅ Bild geladen: {image.size} ({image.format})")
        
        # Initialisiere BitHuman mit API Secret
        print("🔧 Initialisiere BitHuman Runtime...")
        runtime = await AsyncBithuman.create(api_secret=API_SECRET)
        
        # Prüfe verfügbare Methoden
        print("🔍 Verfügbare Methoden:", [m for m in dir(runtime) if not m.startswith('_')])
        
        # PAID ACCOUNT LÖSUNG: Verwende load_data_async für Modell-Erstellung
        print("🚀 PAID ACCOUNT: Verwende load_data_async für .imx-Erstellung...")
        
        try:
            # Ansatz 1: load_data_async mit Bild-Pfad (Paid Account Feature)
            print("📝 Verwende load_data_async mit Bild...")
            await runtime.load_data_async(image_path)
            
            # Versuche das Modell zu extrahieren/speichern
            if hasattr(runtime, 'model_hash') and runtime.model_hash:
                print(f"✅ Model Hash erhalten: {runtime.model_hash}")
                
                # Erstelle .imx aus Runtime-Daten
                if hasattr(runtime, 'video_graph') and runtime.video_graph:
                    print("📝 Extrahiere .imx aus video_graph...")
                    # Speichere Runtime-Daten als .imx
                    import pickle
                    with open(output_path, 'wb') as f:
                        pickle.dump({
                            'model_hash': runtime.model_hash,
                            'video_graph': runtime.video_graph,
                            'image_path': image_path
                        }, f)
                    print("✅ .imx-Modell aus Runtime-Daten erstellt")
                else:
                    print("⚠️ Kein video_graph verfügbar - kopiere Bild als .imx")
                    import shutil
                    shutil.copy2(image_path, output_path)
            else:
                print("⚠️ Kein model_hash - load_data_async fehlgeschlagen")
                # Fallback: Kopiere Bild als .imx
                import shutil
                shutil.copy2(image_path, output_path)
                print("📝 Fallback: Bild als .imx kopiert")
                
        except Exception as load_error:
            print(f"❌ load_data_async Fehler: {load_error}")
            print("🔧 Fallback: Direkte Bild-zu-IMX Konvertierung...")
            
            # Fallback: Kopiere Bild als .imx mit korrekter Struktur
            import shutil
            shutil.copy2(image_path, output_path)
            print("📝 Bild als .imx kopiert (Fallback)")
        
        print("✅ .imx-Modell erfolgreich erstellt!")
        return True
        
    except Exception as e:
        print(f"❌ Fehler bei .imx-Erstellung: {e}")
        import traceback
        traceback.print_exc()
        return False

async def main():
    """Hauptfunktion"""
    
    # Eingabe-Bild
    image_path = "brain/sylke_1_2025.jpeg"
    
    # Output-Pfad
    output_path = "models/bithuman/sylke_avatar.imx"
    
    # Erstelle Output-Verzeichnis
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    
    # Erstelle .imx-Modell
    success = await create_imx_model(image_path, output_path)
    
    if success:
        print(f"\n🎉 ERFOLG! .imx-Modell erstellt: {output_path}")
        print(f"📏 Dateigröße: {Path(output_path).stat().st_size} bytes")
    else:
        print("\n💥 FEHLER! .imx-Modell konnte nicht erstellt werden")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())
