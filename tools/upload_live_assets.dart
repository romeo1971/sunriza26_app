#!/usr/bin/env dart

/// Upload Live Avatar Assets zu Firebase Storage
/// Usage: dart run tools/upload_live_assets.dart <avatarId> <assets_dir>
/// Example: dart run tools/upload_live_assets.dart schatzy_id ./avatars/schatzy

import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    print(
      'Usage: dart run tools/upload_live_assets.dart <avatarId> <assets_dir>',
    );
    exit(1);
  }

  final avatarId = args[0];
  final assetsDir = args[1];

  print('🚀 Uploading Live Avatar Assets...');
  print('   Avatar ID: $avatarId');
  print('   Assets Dir: $assetsDir');

  // Firebase initialisieren
  await Firebase.initializeApp();

  final storage = FirebaseStorage.instance;
  final firestore = FirebaseFirestore.instance;

  // Files
  final idleFile = File('$assetsDir/idle.mp4');
  final atlasFile = File('$assetsDir/atlas.png');
  final maskFile = File('$assetsDir/mask.png');
  final atlasJsonFile = File('$assetsDir/atlas.json');
  final roiJsonFile = File('$assetsDir/roi.json');

  if (!idleFile.existsSync()) {
    print('❌ Fehler: idle.mp4 nicht gefunden in $assetsDir');
    exit(1);
  }

  try {
    // Upload zu Firebase Storage
    print('📤 Uploading idle.mp4...');
    final idleRef = storage.ref('avatars/$avatarId/idle.mp4');
    await idleRef.putFile(idleFile);
    final idleUrl = await idleRef.getDownloadURL();

    print('📤 Uploading atlas.png...');
    final atlasRef = storage.ref('avatars/$avatarId/atlas.png');
    await atlasRef.putFile(atlasFile);
    final atlasUrl = await atlasRef.getDownloadURL();

    print('📤 Uploading mask.png...');
    final maskRef = storage.ref('avatars/$avatarId/mask.png');
    await maskRef.putFile(maskFile);
    final maskUrl = await maskRef.getDownloadURL();

    print('📤 Reading JSON files...');
    final atlasJson = await atlasJsonFile.readAsString();
    final roiJson = await roiJsonFile.readAsString();

    // Update Firestore
    print('💾 Updating Firestore...');
    await firestore.collection('avatars').doc(avatarId).update({
      'liveAssets': {
        'idleUrl': idleUrl,
        'atlasUrl': atlasUrl,
        'maskUrl': maskUrl,
        'atlasJson': atlasJson,
        'roiJson': roiJson,
        'uploadedAt': FieldValue.serverTimestamp(),
      },
    });

    print('✅ Upload erfolgreich!');
    print('   idle.mp4: $idleUrl');
    print('   atlas.png: $atlasUrl');
    print('   mask.png: $maskUrl');
  } catch (e) {
    print('❌ Fehler beim Upload: $e');
    exit(1);
  }
}
