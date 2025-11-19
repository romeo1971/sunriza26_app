#!/usr/bin/env python3
import firebase_admin
from firebase_admin import credentials, firestore

cred_path = '/Users/hhsw/Desktop/hauau/hauau/service-account-key.json'
if not firebase_admin._apps:
    cred = credentials.Certificate(cred_path)
    firebase_admin.initialize_app(cred)

db = firestore.client()
avatars = db.collection('avatars').limit(10).stream()

print("🔍 Avatare in Firebase:")
for doc in avatars:
    data = doc.to_dict()
    first = data.get('firstName', 'N/A')
    last = data.get('lastName', 'N/A')
    print(f"  - {first} {last} (ID: {doc.id})")

