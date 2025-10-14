#!/usr/bin/env dart
// Upload Live Avatar Assets zu Firebase Storage
// Usage: dart run tools/upload_live_assets.dart <avatarId> <assets_dir>

import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    debugPrint(
      'Usage: dart run tools/upload_live_assets.dart <avatarId> <assets_dir>',
    );
    exit(1);
  }

  final avatarId = args[0];
  final assetsDir = args[1];

  debugPrint('🚀 Uploading Live Avatar Assets...');
  debugPrint('   Avatar ID: $avatarId');
  debugPrint('   Assets Dir: $assetsDir');

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
    debugPrint('❌ Fehler: idle.mp4 nicht gefunden in $assetsDir');
    exit(1);
  }

  try {
    // Upload zu Firebase Storage
    debugPrint('📤 Uploading idle.mp4...');
    final idleRef = storage.ref('avatars/$avatarId/idle.mp4');
    await idleRef.putFile(idleFile);
    final idleUrl = await idleRef.getDownloadURL();

    debugPrint('📤 Uploading atlas.png...');
    final atlasRef = storage.ref('avatars/$avatarId/atlas.png');
    await atlasRef.putFile(atlasFile);
    final atlasUrl = await atlasRef.getDownloadURL();

    debugPrint('📤 Uploading mask.png...');
    final maskRef = storage.ref('avatars/$avatarId/mask.png');
    await maskRef.putFile(maskFile);
    final maskUrl = await maskRef.getDownloadURL();

    debugPrint('📤 Reading JSON files...');
    final atlasJson = await atlasJsonFile.readAsString();
    final roiJson = await roiJsonFile.readAsString();

    // Update Firestore
    debugPrint('💾 Updating Firestore...');
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

    debugPrint('✅ Upload erfolgreich!');
    debugPrint('   idle.mp4: $idleUrl');
    debugPrint('   atlas.png: $atlasUrl');
    debugPrint('   mask.png: $maskUrl');
  } catch (e) {
    debugPrint('❌ Fehler beim Upload: $e');
    exit(1);
  }
}
