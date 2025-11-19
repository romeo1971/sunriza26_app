#!/usr/bin/env python3
"""
Upload Live Avatar Assets to Firebase Storage
Uploads idle.mp4, atlas.png, atlas.json, mask.png, roi.json for a specific avatar
"""

import sys
import os
from pathlib import Path
from datetime import datetime
import firebase_admin
from firebase_admin import credentials, storage, firestore

# Service Account Key
SERVICE_ACCOUNT_KEY = Path(__file__).parent.parent / "service-account-key.json"

def init_firebase():
    """Initialize Firebase Admin SDK"""
    if not firebase_admin._apps:
        cred = credentials.Certificate(str(SERVICE_ACCOUNT_KEY))
        firebase_admin.initialize_app(cred, {
            'storageBucket': 'hauau-prod.firebasestorage.app'
        })
    return storage.bucket(), firestore.client()

def upload_file(bucket, local_path: str, storage_path: str) -> str:
    """Upload a file to Firebase Storage and return the download URL"""
    blob = bucket.blob(storage_path)
    blob.upload_from_filename(local_path)
    
    # Make publicly readable
    blob.make_public()
    
    return blob.public_url

def upload_live_avatar_assets(avatar_id: str, assets_dir: str):
    """
    Upload all live avatar assets for a specific avatar
    
    Args:
        avatar_id: Firestore avatar document ID
        assets_dir: Directory containing the assets (idle.mp4, atlas.png, etc.)
    """
    bucket, db = init_firebase()
    
    assets_dir = Path(assets_dir)
    if not assets_dir.exists():
        print(f"❌ Assets directory not found: {assets_dir}")
        sys.exit(1)
    
    # Define files to upload
    files = {
        'idle.mp4': 'idleVideoUrl',
        'atlas.png': 'atlasUrl',
        'atlas.json': 'atlasJsonUrl',
        'mask.png': 'maskUrl',
        'roi.json': 'roiJsonUrl'
    }
    
    print(f"📦 Uploading live avatar assets for avatar: {avatar_id}")
    
    live_avatar_data = {
        'generatedAt': datetime.utcnow(),
        'status': 'generating'
    }
    
    # Upload each file
    for filename, field_name in files.items():
        local_path = assets_dir / filename
        
        if not local_path.exists():
            print(f"⚠️  Skipping {filename} (not found)")
            continue
        
        storage_path = f"avatars/{avatar_id}/live_avatar/{filename}"
        
        print(f"📤 Uploading {filename}...")
        try:
            url = upload_file(bucket, str(local_path), storage_path)
            live_avatar_data[field_name] = url
            print(f"✅ {filename} → {url}")
        except Exception as e:
            print(f"❌ Failed to upload {filename}: {e}")
            live_avatar_data['status'] = 'failed'
            live_avatar_data['error'] = str(e)
    
    # Update status to ready if all uploads succeeded
    if live_avatar_data.get('status') != 'failed':
        live_avatar_data['status'] = 'ready'
    
    # Update Firestore document
    print(f"\n💾 Updating Firestore document...")
    try:
        avatar_ref = db.collection('avatars').document(avatar_id)
        avatar_ref.update({
            'liveAvatar': live_avatar_data
        })
        print(f"✅ Firestore updated successfully!")
    except Exception as e:
        print(f"❌ Failed to update Firestore: {e}")
        sys.exit(1)
    
    print(f"\n🎉 Live avatar assets uploaded and configured!")
    return live_avatar_data

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: python upload_live_avatar_assets.py <avatar_id> <assets_directory>")
        print("\nExample:")
        print("  python upload_live_avatar_assets.py OBIEVfYOXT3BoDAJfUSv assets/avatars/schatzy/")
        sys.exit(1)
    
    avatar_id = sys.argv[1]
    assets_dir = sys.argv[2]
    
    upload_live_avatar_assets(avatar_id, assets_dir)

