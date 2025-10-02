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
      debugPrint('📤 uploadImage START: ${imageFile.path}');

      final user = _auth.currentUser;
      if (user == null) {
        debugPrint('❌ uploadImage FEHLER: Benutzer nicht angemeldet');
        throw Exception('Benutzer nicht angemeldet');
      }
      debugPrint('✅ User authenticated: ${user.uid}');

      // Prüfe ob Datei existiert
      if (!await imageFile.exists()) {
        debugPrint(
          '❌ uploadImage FEHLER: Datei existiert nicht: ${imageFile.path}',
        );
        throw Exception('Bild-Datei nicht gefunden');
      }
      final fileSize = await imageFile.length();
      debugPrint('✅ Bild-Datei gefunden: ${fileSize / 1024} KB');

      final fileName = path.basename(imageFile.path);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      // WARNUNG: Fallback-Pfad ohne avatarId - nur für Legacy-Zwecke
      final filePath =
          customPath ??
          'users/${user.uid}/uploads/images/${timestamp}_$fileName';
      debugPrint('📁 Upload-Pfad: $filePath');

      final ref = _storage.ref().child(filePath);
      debugPrint('⏳ Starte Firebase Upload...');
      final uploadTask = ref.putFile(imageFile);

      // Progress Monitoring
      uploadTask.snapshotEvents.listen((snapshot) {
        final progress = (snapshot.bytesTransferred / snapshot.totalBytes * 100)
            .toStringAsFixed(1);
        debugPrint('📊 Upload-Fortschritt: $progress%');
      });

      final snapshot = await uploadTask;
      debugPrint('✅ Upload abgeschlossen, hole Download-URL...');

      final downloadUrl = await snapshot.ref.getDownloadURL();
      debugPrint('✅ uploadImage OK → $downloadUrl');
      return downloadUrl;
    } catch (e, stack) {
      debugPrint('❌ FEHLER beim Upload des Bildes: $e');
      debugPrint('Stack: $stack');
      return null;
    }
  }

  static String pathFromUrl(String url) {
    try {
      final ref = _storage.refFromURL(url);
      return ref.fullPath;
    } catch (_) {
      return '';
    }
  }

  /// Upload ein Video zu Firebase Storage
  static Future<String?> uploadVideo(
    File videoFile, {
    String? customPath,
  }) async {
    try {
      debugPrint('📤 uploadVideo START: ${videoFile.path}');

      final user = _auth.currentUser;
      if (user == null) {
        debugPrint('❌ uploadVideo FEHLER: Benutzer nicht angemeldet');
        throw Exception('Benutzer nicht angemeldet');
      }
      debugPrint('✅ User authenticated: ${user.uid}');

      // Prüfe ob Datei existiert
      if (!await videoFile.exists()) {
        debugPrint(
          '❌ uploadVideo FEHLER: Datei existiert nicht: ${videoFile.path}',
        );
        throw Exception('Video-Datei nicht gefunden');
      }
      final fileSize = await videoFile.length();
      debugPrint('✅ Video-Datei gefunden: ${fileSize / 1024 / 1024} MB');

      final fileName = path.basename(videoFile.path);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      // WARNUNG: Fallback-Pfad ohne avatarId - nur für Legacy-Zwecke
      final filePath =
          customPath ??
          'users/${user.uid}/uploads/videos/${timestamp}_$fileName';
      debugPrint('📁 Upload-Pfad: $filePath');

      final ref = _storage.ref().child(filePath);
      // Content-Type setzen, wichtig für mp4-Abspielbarkeit
      final String ext = path.extension(videoFile.path).toLowerCase();
      String contentType = 'video/mp4';
      if (ext == '.mov') contentType = 'video/quicktime';
      if (ext == '.m4v') contentType = 'video/x-m4v';
      debugPrint('📹 Content-Type: $contentType (Extension: $ext)');

      debugPrint('⏳ Starte Firebase Upload...');
      final uploadTask = ref.putFile(
        videoFile,
        SettableMetadata(contentType: contentType),
      );

      // Progress Monitoring
      uploadTask.snapshotEvents.listen((snapshot) {
        final progress = (snapshot.bytesTransferred / snapshot.totalBytes * 100)
            .toStringAsFixed(1);
        debugPrint('📊 Upload-Fortschritt: $progress%');
      });

      final snapshot = await uploadTask;
      debugPrint('✅ Upload abgeschlossen, hole Download-URL...');

      final downloadUrl = await snapshot.ref.getDownloadURL();
      debugPrint('✅ uploadVideo OK → $downloadUrl');
      return downloadUrl;
    } catch (e, stack) {
      debugPrint('❌ FEHLER beim Upload des Videos: $e');
      debugPrint('Stack: $stack');
      return null;
    }
  }

  /// Upload eine Audiodatei zu Firebase Storage
  static Future<String?> uploadAudio(
    File audioFile, {
    String? customPath,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Benutzer nicht angemeldet');

      final fileName = path.basename(audioFile.path);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      // WARNUNG: Fallback-Pfad ohne avatarId - nur für Legacy-Zwecke
      final filePath =
          customPath ??
          'users/${user.uid}/uploads/audio/${timestamp}_$fileName';

      // Content-Type anhand der Dateiendung setzen
      final ext = path.extension(audioFile.path).toLowerCase();
      String contentType = 'audio/mpeg';
      if (ext == '.m4a') contentType = 'audio/mp4';
      if (ext == '.wav') contentType = 'audio/wav';
      if (ext == '.aac') contentType = 'audio/aac';
      if (ext == '.ogg') contentType = 'audio/ogg';

      final ref = _storage.ref().child(filePath);
      final uploadTask = ref.putFile(
        audioFile,
        SettableMetadata(contentType: contentType),
      );

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      debugPrint('uploadAudio OK → $downloadUrl');
      return downloadUrl;
    } catch (e) {
      debugPrint('Fehler beim Upload der Audiodatei: $e');
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
      // WARNUNG: Fallback-Pfad ohne avatarId - nur für Legacy-Zwecke
      final filePath =
          customPath ??
          'users/${user.uid}/uploads/texts/${timestamp}_$fileName';

      final ref = _storage.ref().child(filePath);
      final uploadTask = ref.putFile(
        textFile,
        SettableMetadata(contentType: 'text/plain'),
      );

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      debugPrint('uploadTextFile OK → $downloadUrl');
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
    debugPrint('uploadMultipleImages count=${downloadUrls.length}');
    return downloadUrls;
  }

  /// Upload mehrere Bilder unter einem Avatar-Pfad
  static Future<List<String>> uploadAvatarImages(
    List<File> imageFiles,
    String avatarId,
  ) async {
    final List<String> downloadUrls = [];
    final user = _auth.currentUser;
    if (user == null) return downloadUrls;
    for (int i = 0; i < imageFiles.length; i++) {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = 'avatars/$avatarId/images/${ts}_$i.jpg';
      final url = await uploadImage(imageFiles[i], customPath: path);
      if (url != null) downloadUrls.add(url);
    }
    debugPrint('uploadAvatarImages count=${downloadUrls.length}');
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
    debugPrint('uploadMultipleVideos count=${downloadUrls.length}');
    return downloadUrls;
  }

  /// Upload mehrere Videos unter einem Avatar-Pfad
  static Future<List<String>> uploadAvatarVideos(
    List<File> videoFiles,
    String avatarId,
  ) async {
    final List<String> downloadUrls = [];
    final user = _auth.currentUser;
    if (user == null) return downloadUrls;
    for (int i = 0; i < videoFiles.length; i++) {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = 'avatars/$avatarId/videos/${ts}_$i.mp4';
      final url = await uploadVideo(videoFiles[i], customPath: path);
      if (url != null) downloadUrls.add(url);
    }
    debugPrint('uploadAvatarVideos count=${downloadUrls.length}');
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
    debugPrint('uploadMultipleTextFiles count=${downloadUrls.length}');
    return downloadUrls;
  }

  /// Upload mehrere Textdateien unter einem Avatar-Pfad
  static Future<List<String>> uploadAvatarTextFiles(
    List<File> textFiles,
    String avatarId,
  ) async {
    final List<String> downloadUrls = [];
    final user = _auth.currentUser;
    if (user == null) return downloadUrls;
    for (int i = 0; i < textFiles.length; i++) {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = 'avatars/$avatarId/texts/${ts}_$i.txt';
      final url = await uploadTextFile(textFiles[i], customPath: path);
      if (url != null) downloadUrls.add(url);
    }
    debugPrint('uploadAvatarTextFiles count=${downloadUrls.length}');
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
  static Future<bool> deleteAvatarFiles(String avatarId) async {
    try {
      final ref = _storage.ref().child('avatars/$avatarId');
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
  static Future<List<Reference>> getAvatarFiles(String avatarId) async {
    try {
      final ref = _storage.ref().child('avatars/$avatarId');
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
      // WARNUNG: Fallback-Pfad ohne avatarId - nur für Legacy-Zwecke
      final filePath =
          customPath ??
          'users/${user.uid}/uploads/$fileType/${timestamp}_$fileName';

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
