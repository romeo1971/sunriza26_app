#!/usr/bin/env python3
"""
Lädt ALLE LivePortrait Debug-Dateien von Firebase Storage in brain/hilfeLP/ runter.
"""
import firebase_admin
from firebase_admin import credentials, storage
import os
import sys

def main():
    avatar_id = sys.argv[1] if len(sys.argv) > 1 else 'OBIEVfYOXT3BoDAJfUSv'
    
    # Firebase initialisieren
    cred_path = '/Users/hhsw/Desktop/sunriza/sunriza26/service-account-key.json'
    if not firebase_admin._apps:
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred, {
            'storageBucket': 'sunriza26.firebasestorage.app'
        })
    
    bucket = storage.bucket()
    
    # Erstelle lokalen Ordner
    local_dir = f'/Users/hhsw/Desktop/sunriza/sunriza26/brain/hilfeLP/{avatar_id}'
    os.makedirs(local_dir, exist_ok=True)
    
    print(f"📥 Lade Debug-Dateien für Avatar {avatar_id}...")
    print(f"📁 Ziel: {local_dir}")
    
    # Liste alle Blobs in brain/hilfeLP/{avatar_id}/
    prefix = f'brain/hilfeLP/{avatar_id}/'
    blobs = bucket.list_blobs(prefix=prefix)
    
    count = 0
    for blob in blobs:
        filename = blob.name.split('/')[-1]
        local_path = os.path.join(local_dir, filename)
        
        print(f"  📥 {filename} ({blob.size / 1024 / 1024:.2f} MB)...")
        blob.download_to_filename(local_path)
        count += 1
    
    if count == 0:
        print(f"❌ Keine Dateien gefunden in {prefix}")
        print(f"   Generiere zuerst Dynamics für Avatar {avatar_id}!")
    else:
        print(f"\n✅ {count} Dateien heruntergeladen nach:")
        print(f"   {local_dir}")

if __name__ == '__main__':
    main()

