import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path/path.dart' as path;

class FirebaseStorageService {
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Upload ein Bild zu Firebase Storage
  static Future<String?> uploadImage(
    File imageFile, {
    String? customPath,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Benutzer nicht angemeldet');

      final fileName = path.basename(imageFile.path);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath =
          customPath ?? 'avatars/${user.uid}/images/${timestamp}_$fileName';

      final ref = _storage.ref().child(filePath);
      final uploadTask = ref.putFile(imageFile);

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      debugPrint('Fehler beim Upload des Bildes: $e');
      return null;
    }
  }

  /// Upload ein Video zu Firebase Storage
  static Future<String?> uploadVideo(
    File videoFile, {
    String? customPath,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Benutzer nicht angemeldet');

      final fileName = path.basename(videoFile.path);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath =
          customPath ?? 'avatars/${user.uid}/videos/${timestamp}_$fileName';

      final ref = _storage.ref().child(filePath);
      final uploadTask = ref.putFile(videoFile);

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      debugPrint('Fehler beim Upload des Videos: $e');
      return null;
    }
  }

  /// Upload eine Textdatei zu Firebase Storage
  static Future<String?> uploadTextFile(
    File textFile, {
    String? customPath,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Benutzer nicht angemeldet');

      final fileName = path.basename(textFile.path);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath =
          customPath ?? 'avatars/${user.uid}/texts/${timestamp}_$fileName';

      final ref = _storage.ref().child(filePath);
      final uploadTask = ref.putFile(textFile);

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      debugPrint('Fehler beim Upload der Textdatei: $e');
      return null;
    }
  }

  /// Upload mehrere Bilder gleichzeitig
  static Future<List<String>> uploadMultipleImages(
    List<File> imageFiles,
  ) async {
    final List<String> downloadUrls = [];

    for (final imageFile in imageFiles) {
      final url = await uploadImage(imageFile);
      if (url != null) {
        downloadUrls.add(url);
      }
    }

    return downloadUrls;
  }

  /// Upload mehrere Videos gleichzeitig
  static Future<List<String>> uploadMultipleVideos(
    List<File> videoFiles,
  ) async {
    final List<String> downloadUrls = [];

    for (final videoFile in videoFiles) {
      final url = await uploadVideo(videoFile);
      if (url != null) {
        downloadUrls.add(url);
      }
    }

    return downloadUrls;
  }

  /// Upload mehrere Textdateien gleichzeitig
  static Future<List<String>> uploadMultipleTextFiles(
    List<File> textFiles,
  ) async {
    final List<String> downloadUrls = [];

    for (final textFile in textFiles) {
      final url = await uploadTextFile(textFile);
      if (url != null) {
        downloadUrls.add(url);
      }
    }

    return downloadUrls;
  }

  /// Lösche eine Datei aus Firebase Storage
  static Future<bool> deleteFile(String downloadUrl) async {
    try {
      final ref = _storage.refFromURL(downloadUrl);
      await ref.delete();
      return true;
    } catch (e) {
      debugPrint('Fehler beim Löschen der Datei: $e');
      return false;
    }
  }

  /// Lösche alle Dateien eines Avatars
  static Future<bool> deleteAvatarFiles(String userId) async {
    try {
      final ref = _storage.ref().child('avatars/$userId');
      final listResult = await ref.listAll();

      for (final item in listResult.items) {
        await item.delete();
      }

      // Lösche auch alle Unterordner
      for (final folder in listResult.prefixes) {
        final folderListResult = await folder.listAll();
        for (final item in folderListResult.items) {
          await item.delete();
        }
      }

      return true;
    } catch (e) {
      debugPrint('Fehler beim Löschen der Avatar-Dateien: $e');
      return false;
    }
  }

  /// Erhalte alle Dateien eines Avatars
  static Future<List<Reference>> getAvatarFiles(String userId) async {
    try {
      final ref = _storage.ref().child('avatars/$userId');
      final listResult = await ref.listAll();

      final List<Reference> allFiles = [];
      allFiles.addAll(listResult.items);

      // Füge Dateien aus Unterordnern hinzu
      for (final folder in listResult.prefixes) {
        final folderListResult = await folder.listAll();
        allFiles.addAll(folderListResult.items);
      }

      return allFiles;
    } catch (e) {
      debugPrint('Fehler beim Abrufen der Avatar-Dateien: $e');
      return [];
    }
  }

  /// Upload mit Fortschrittsanzeige
  static Future<String?> uploadWithProgress(
    File file,
    String fileType, {
    String? customPath,
    Function(double)? onProgress,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Benutzer nicht angemeldet');

      final fileName = path.basename(file.path);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath =
          customPath ?? 'avatars/${user.uid}/$fileType/${timestamp}_$fileName';

      final ref = _storage.ref().child(filePath);
      final uploadTask = ref.putFile(file);

      // Fortschritt überwachen
      uploadTask.snapshotEvents.listen((snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        onProgress?.call(progress);
      });

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      debugPrint('Fehler beim Upload mit Fortschritt: $e');
      return null;
    }
  }
}
