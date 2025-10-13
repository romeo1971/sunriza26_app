#!/usr/bin/env python3
"""
Holt das heroVideoUrl von Schatzy aus Firestore und generiert idle.mp4 mit LivePortrait.
"""
import firebase_admin
from firebase_admin import credentials, firestore
import subprocess
import sys
import os
import requests

def main():
    # Firebase initialisieren
    cred_path = '/Users/hhsw/Desktop/sunriza/sunriza26/service-account-key.json'
    if not firebase_admin._apps:
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred)
    
    db = firestore.client()
    
    # Schatzy finden (firstName ODER nickname)
    print("🔍 Suche Schatzy Avatar (firstName oder nickname)...")
    
    # Versuche zuerst firstName
    avatars = list(db.collection('avatars').where('firstName', '==', 'Schatzy').limit(1).stream())
    
    # Falls nicht gefunden, versuche nickname
    if not avatars:
        avatars = list(db.collection('avatars').where('nickname', '==', 'Schatzy').limit(1).stream())
    
    if not avatars:
        print("❌ ERROR: Schatzy nicht gefunden (weder firstName noch nickname)!")
        sys.exit(1)
    
    avatar_doc = avatars[0]
    
    data = avatar_doc.to_dict()
    training = data.get('training', {})
    hero_video_url = training.get('heroVideoUrl')
    
    if not hero_video_url:
        print("❌ ERROR: Kein heroVideoUrl bei Schatzy gefunden!")
        sys.exit(1)
    
    print(f"✅ Hero-Video URL: {hero_video_url}")
    
    # Video herunterladen
    print("📥 Lade Hero-Video herunter...")
    driver_path = '/tmp/schatzy_hero_video.mp4'
    
    try:
        response = requests.get(hero_video_url, stream=True, timeout=60)
        response.raise_for_status()
        
        with open(driver_path, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
        
        print(f"✅ Video gespeichert: {driver_path}")
    except Exception as e:
        print(f"❌ ERROR beim Download: {e}")
        sys.exit(1)
    
    # LivePortrait starten
    print("\n🎬 Starte LivePortrait mit DEINEM Hero-Video!")
    
    source_image = '/Users/hhsw/Desktop/sunriza/sunriza26/schatzy_hero.jpg'
    output_path = '/tmp/idle_from_hero.mp4'
    
    lp_cmd = [
        'python',
        '/Users/hhsw/Desktop/sunriza/LivePortrait/inference.py',
        '-s', source_image,
        '-d', driver_path,
        '-o', output_path,
        '--driving_multiplier', '0.40',  # 40% Intensität - FINALE VERSION!
        '--flag-normalize-lip',  # ✅ Neutralisiert Lächeln im Ruhezustand
        '--animation-region', 'all',  # Alle Regionen (Expression + Pose)
        '--flag-pasteback',  # ✅ Paste-back in Original-Space (mit Körper!)
        '--source-max-dim', '1600',  # ✅ Maximale Dimension auf 1600
    ]
    
    env = os.environ.copy()
    env['PYTORCH_ENABLE_MPS_FALLBACK'] = '1'
    
    result = subprocess.run(lp_cmd, env=env, capture_output=False, text=True)
    
    if result.returncode != 0:
        print(f"❌ LivePortrait fehlgeschlagen!")
        sys.exit(1)
    
    # Output-Pfad finden (LivePortrait erstellt Unterordner)
    lp_output = f"{output_path}/schatzy_hero--schatzy_hero_video.mp4"
    
    if not os.path.exists(lp_output):
        print(f"❌ Output nicht gefunden: {lp_output}")
        # Versuche alternatives Pattern
        import glob
        candidates = glob.glob(f"{output_path}/*.mp4")
        if candidates:
            lp_output = candidates[0]
            print(f"✅ Gefunden: {lp_output}")
        else:
            sys.exit(1)
    
    # Zu H.264 konvertieren (Original-Auflösung behalten - jetzt mit Körper!)
    print("\n🔄 Konvertiere zu H.264 (mit Körper, Original-Größe)...")
    final_output = '/Users/hhsw/Desktop/sunriza/sunriza26/assets/avatars/schatzy/idle.mp4'
    
    ffmpeg_cmd = [
        'ffmpeg',
        '-i', lp_output,
        '-c:v', 'libx264',
        '-preset', 'slow',
        '-crf', '18',  # Höchste Qualität
        '-pix_fmt', 'yuv420p',
        '-y',
        final_output
    ]
    
    result = subprocess.run(ffmpeg_cmd, capture_output=True, text=True)
    
    if result.returncode != 0:
        print(f"❌ FFmpeg fehlgeschlagen: {result.stderr}")
        sys.exit(1)
    
    print(f"\n✅✅✅ FERTIG! idle.mp4 erstellt mit DEINEM Hero-Video!")
    print(f"📁 {final_output}")
    print("\n🎯 Starte jetzt Flutter und teste Schatzy Chat!")

if __name__ == '__main__':
    main()

