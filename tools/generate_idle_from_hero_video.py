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
    driver_path_orig = '/tmp/schatzy_hero_video.mp4'
    driver_path = '/tmp/schatzy_hero_video_seamless.mp4'
    
    try:
        response = requests.get(hero_video_url, stream=True, timeout=60)
        response.raise_for_status()
        
        with open(driver_path_orig, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
        
        print(f"✅ Video gespeichert: {driver_path_orig}")
        
        # TRIM auf 10 Sekunden - NUR VORWÄRTS (kein Ping-Pong!)
        print("✂️ Trimme Video auf 10 Sekunden (nur vorwärts)...")
        driver_path = '/tmp/schatzy_hero_video_trimmed.mp4'
        trim_cmd = [
            'ffmpeg', '-i', driver_path_orig,
            '-ss', '0', '-t', '10',  # 10 Sekunden
            '-c:v', 'copy', '-y', driver_path
        ]
        subprocess.run(trim_cmd, capture_output=True, check=True)
        print(f"✅ Trimmed video (10s, nur vorwärts): {driver_path}")
        
    except Exception as e:
        print(f"❌ ERROR beim Download/Seamless: {e}")
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
        '--driving_multiplier', '0.41',  # 41% Intensität - ausgewogen!
        '--flag-normalize-lip',  # ✅ Neutralisiert Lächeln im Ruhezustand
        '--animation-region', 'all',  # Alle Regionen (Expression + Pose)
        '--flag-pasteback',  # ✅ Paste-back in Original-Space (mit Körper!)
        '--source-max-dim', '1600',  # ✅ Maximale Dimension auf 1600
        '--scale', '1.7',  # ✅ MEHR Animation (Schultern, Haare, Hals!)
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
    
    # Zu H.264 konvertieren + Crossfade für seamless loop
    print("\n🔄 Konvertiere zu H.264 + Crossfade für seamless loop...")
    temp_output = '/tmp/idle_temp.mp4'
    final_output = '/Users/hhsw/Desktop/sunriza/sunriza26/assets/avatars/schatzy/idle.mp4'
    
    # Schritt 1: H.264 Konvertierung (OHNE AUDIO!)
    ffmpeg_cmd = [
        'ffmpeg',
        '-i', lp_output,
        '-an',  # ✅ KEIN AUDIO für Chat-Video!
        '-c:v', 'libx264',
        '-preset', 'slow',
        '-crf', '18',
        '-pix_fmt', 'yuv420p',
        '-y',
        temp_output
    ]
    result = subprocess.run(ffmpeg_cmd, capture_output=True, text=True)
    
    if result.returncode != 0:
        print(f"❌ FFmpeg H.264 fehlgeschlagen: {result.stderr}")
        sys.exit(1)
    
    # Schritt 2: Crossfade für seamless loop (1 Sekunde!)
    print("🔄 Füge Crossfade hinzu (1s für glatten Loop)...")
    # Get video duration
    duration_cmd = ['ffprobe', '-v', 'error', '-show_entries', 'format=duration', 
                    '-of', 'default=noprint_wrappers=1:nokey=1', temp_output]
    duration_result = subprocess.run(duration_cmd, capture_output=True, text=True)
    duration = float(duration_result.stdout.strip())
    offset = duration - 1.0  # 1 Sekunde Crossfade!
    
    crossfade_cmd = [
        'ffmpeg',
        '-i', temp_output,
        '-filter_complex',
        f'[0:v]split[main][dup];[dup]trim=start=0:duration=1.0,setpts=PTS-STARTPTS[start];[main][start]xfade=transition=fade:duration=1.0:offset={offset}',
        '-y',
        final_output
    ]
    
    result = subprocess.run(crossfade_cmd, capture_output=True, text=True)
    
    if result.returncode != 0:
        print(f"❌ FFmpeg fehlgeschlagen: {result.stderr}")
        sys.exit(1)
    
    print(f"\n✅✅✅ FERTIG! idle.mp4 erstellt mit DEINEM Hero-Video!")
    print(f"📁 {final_output}")
    
    # Auto-Upload zu Firebase Storage
    print("\n📤 Uploading zu Firebase Storage...")
    upload_script = os.path.join(os.path.dirname(__file__), 'upload_live_avatar_assets.py')
    assets_dir = os.path.dirname(final_output)
    
    upload_cmd = [
        'python',
        upload_script,
        avatar_id,
        assets_dir
    ]
    
    result = subprocess.run(upload_cmd, capture_output=False, text=True)
    
    if result.returncode == 0:
        print("\n🎉 FERTIG! Live Avatar Assets sind in Firebase!")
    else:
        print("\n⚠️  Upload fehlgeschlagen. Assets sind lokal gespeichert.")
    
    print("\n🎯 Starte jetzt Flutter und teste Schatzy Chat!")

if __name__ == '__main__':
    main()

