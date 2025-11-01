import 'dart:io';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/avatar_data.dart';
import 'firebase_storage_service.dart';
import '../services/env_service.dart';

class AvatarService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _avatarsCollection =>
      _fs.collection('avatars');

  /// Erstelle einen neuen Avatar
  Future<AvatarData?> createAvatar({
    required String firstName,
    String? nickname,
    String? lastName,
    DateTime? birthDate,
    DateTime? deathDate,
    File? avatarImage,
    List<File>? images,
    List<File>? videos,
    List<File>? textFiles,
    List<String>? writtenTexts,
    bool isPublic = false,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Benutzer nicht angemeldet');

      final now = DateTime.now();
      final avatarId = _avatarsCollection.doc().id;

      // Avatar-Bild hochladen
      String? avatarImageUrl;
      if (avatarImage != null) {
        avatarImageUrl = await FirebaseStorageService.uploadImage(
          avatarImage,
          customPath:
              'avatars/$avatarId/avatar_${now.millisecondsSinceEpoch}.jpg',
        );
      }

      // Bilder hochladen
      List<String> imageUrls = [];
      if (images != null && images.isNotEmpty) {
        for (int i = 0; i < images.length; i++) {
          final url = await FirebaseStorageService.uploadImage(
            images[i],
            customPath:
                'avatars/$avatarId/images/${now.millisecondsSinceEpoch}_$i.jpg',
          );
          if (url != null) imageUrls.add(url);
        }
      }

      // Videos hochladen
      List<String> videoUrls = [];
      if (videos != null && videos.isNotEmpty) {
        for (int i = 0; i < videos.length; i++) {
          final url = await FirebaseStorageService.uploadVideo(
            videos[i],
            customPath:
                'avatars/$avatarId/videos/${now.millisecondsSinceEpoch}_$i.mp4',
          );
          if (url != null) videoUrls.add(url);
        }
      }

      // Textdateien hochladen
      List<String> textFileUrls = [];
      if (textFiles != null && textFiles.isNotEmpty) {
        for (int i = 0; i < textFiles.length; i++) {
          final url = await FirebaseStorageService.uploadTextFile(
            textFiles[i],
            customPath:
                'avatars/$avatarId/texts/${now.millisecondsSinceEpoch}_$i.txt',
          );
          if (url != null) textFileUrls.add(url);
        }
      }

      // Alter berechnen
      int? calculatedAge;
      if (birthDate != null) {
        if (deathDate != null) {
          calculatedAge = deathDate.difference(birthDate).inDays ~/ 365;
        } else {
          calculatedAge = now.difference(birthDate).inDays ~/ 365;
        }
      }

      final avatarData = AvatarData(
        id: avatarId,
        userId: user.uid,
        firstName: firstName,
        nickname: nickname,
        lastName: lastName,
        birthDate: birthDate,
        deathDate: deathDate,
        calculatedAge: calculatedAge,
        avatarImageUrl: avatarImageUrl,
        imageUrls: imageUrls,
        videoUrls: videoUrls,
        textFileUrls: textFileUrls,
        writtenTexts: writtenTexts ?? [],
        createdAt: now,
        updatedAt: now,
        training: {
          'status': 'pending',
          'startedAt': null,
          'finishedAt': null,
          'lastRunAt': null,
          'progress': 0.0,
          'totalDocuments':
              (writtenTexts?.length ?? 0) +
              imageUrls.length +
              videoUrls.length +
              textFileUrls.length,
          'totalFiles': {
            'texts': writtenTexts?.length ?? 0,
            'images': imageUrls.length,
            'videos': videoUrls.length,
            'others': textFileUrls.length,
          },
          'totalChunks': 0,
          'chunkSize': 0,
          'totalTokens': 0,
          'vector': null,
          'lastError': null,
          'jobId': null,
          'needsRetrain': false,
        },
      );

      final payload = avatarData.toMap();
      // Debug-Logging: zu speichernde Felder
      try {
        debugPrint(
          'Avatar create payload keys: '
          '${payload.keys.toList()}',
        );
        debugPrint('Avatar create payload: $payload');
      } catch (_) {}

      await _avatarsCollection.doc(avatarId).set(payload);
      return avatarData;
    } on FirebaseException catch (e) {
      // Zusätzliche Diagnoseausgabe
      debugPrint(
        'Firestore error on createAvatar: code=${e.code} message=${e.message}',
      );
      rethrow;
    } catch (e) {
      debugPrint('Fehler beim Erstellen des Avatars: $e');
      return null;
    }
  }

  /// Lade alle Avatare des aktuellen Users
  Future<List<AvatarData>> getUserAvatars() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return [];

      final querySnapshot = await _avatarsCollection
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => AvatarData.fromMap(doc.data()))
          .toList();
    } on FirebaseException {
      // Reiche spezifische Firestore-Fehler nach oben weiter (Index, Rules etc.)
      rethrow;
    } catch (e) {
      debugPrint('Fehler beim Laden der Avatare: $e');
      return [];
    }
  }

  /// Lade einen spezifischen Avatar
  Future<AvatarData?> getAvatar(String avatarId) async {
    try {
      final doc = await _avatarsCollection.doc(avatarId).get();
      if (!doc.exists) return null;
      return AvatarData.fromMap(doc.data()!);
    } catch (e) {
      debugPrint('Fehler beim Laden des Avatars: $e');
      return null;
    }
  }

  /// Aktualisiere einen Avatar
  Future<bool> updateAvatar(AvatarData avatar) async {
    try {
      final user = _auth.currentUser;
      if (user == null || avatar.userId != user.uid) return false;

      final updatedAvatar = avatar.copyWith(updatedAt: DateTime.now());
      final payload = updatedAvatar.toMap();

      // Wenn greetingText geleert wurde, Feld in Firestore entfernen → Standard greift
      try {
        if ((updatedAvatar.greetingText != null) &&
            updatedAvatar.greetingText!.trim().isEmpty) {
          payload['greetingText'] = FieldValue.delete();
        }
        // Falls das Hero-Image entfernt wurde, Feld löschen
        if (updatedAvatar.avatarImageUrl == null ||
            (updatedAvatar.avatarImageUrl?.isEmpty ?? true)) {
          payload['avatarImageUrl'] = FieldValue.delete();
        }
        // WICHTIG: heroVideoUrl NIEMALS implizit löschen.
        // Löschung darf nur explizit per update({'training.heroVideoUrl': FieldValue.delete()}) erfolgen.
      } catch (_) {}
      try {
        debugPrint('Avatar update payload keys: ${payload.keys.toList()}');
        debugPrint(
          'imageUrls: ${(payload['imageUrls'] as List?)?.length} - ${payload['imageUrls']}',
        );
        debugPrint(
          'videoUrls: ${(payload['videoUrls'] as List?)?.length} - ${payload['videoUrls']}',
        );
        debugPrint(
          'textFileUrls: ${(payload['textFileUrls'] as List?)?.length} - ${payload['textFileUrls']}',
        );
        debugPrint('training: ${payload['training']}');
        debugPrint('Full update payload: $payload');
      } catch (_) {}

      // Schutz: heroVideoUrl niemals unbeabsichtigt löschen
      try {
        final curSnap = await _avatarsCollection.doc(avatar.id).get();
        final cur = curSnap.data();
        if (cur != null) {
          final curTraining = cur['training'] as Map<String, dynamic>?;
          final curHero = curTraining != null
              ? (curTraining['heroVideoUrl'] as String?)
              : null;
          if (payload['training'] is Map &&
              curHero != null &&
              curHero.isNotEmpty) {
            final t = payload['training'] as Map<String, dynamic>;
            // Wenn kein neuer heroVideoUrl gesetzt wurde, bestehenden Wert beibehalten
            if (!t.containsKey('heroVideoUrl') || (t['heroVideoUrl'] == null)) {
              t['heroVideoUrl'] = curHero;
            }
          }
        }
      } catch (_) {}

      await _avatarsCollection
          .doc(avatar.id)
          .set(payload, SetOptions(merge: true));

      return true;
    } catch (e) {
      debugPrint('Fehler beim Aktualisieren des Avatars: $e');
      return false;
    }
  }

  /// Füge Medien zu einem Avatar hinzu
  Future<bool> addMediaToAvatar({
    required String avatarId,
    List<File>? images,
    List<File>? videos,
    List<File>? textFiles,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final avatar = await getAvatar(avatarId);
      if (avatar == null || avatar.userId != user.uid) return false;

      final now = DateTime.now();
      List<String> newImageUrls = List.from(avatar.imageUrls);
      List<String> newVideoUrls = List.from(avatar.videoUrls);
      List<String> newTextFileUrls = List.from(avatar.textFileUrls);

      // Neue Bilder hinzufügen
      if (images != null && images.isNotEmpty) {
        for (int i = 0; i < images.length; i++) {
          final url = await FirebaseStorageService.uploadImage(
            images[i],
            customPath:
                'avatars/$avatarId/images/${now.millisecondsSinceEpoch}_$i.jpg',
          );
          if (url != null) newImageUrls.add(url);
        }
      }

      // Neue Videos hinzufügen
      if (videos != null && videos.isNotEmpty) {
        for (int i = 0; i < videos.length; i++) {
          final url = await FirebaseStorageService.uploadVideo(
            videos[i],
            customPath:
                'avatars/$avatarId/videos/${now.millisecondsSinceEpoch}_$i.mp4',
          );
          if (url != null) newVideoUrls.add(url);
        }
      }

      // Neue Textdateien hinzufügen
      if (textFiles != null && textFiles.isNotEmpty) {
        for (int i = 0; i < textFiles.length; i++) {
          final url = await FirebaseStorageService.uploadTextFile(
            textFiles[i],
            customPath:
                'avatars/$avatarId/texts/${now.millisecondsSinceEpoch}_$i.txt',
          );
          if (url != null) newTextFileUrls.add(url);
        }
      }

      // Avatar aktualisieren
      final updatedAvatar = avatar.copyWith(
        imageUrls: newImageUrls,
        videoUrls: newVideoUrls,
        textFileUrls: newTextFileUrls,
        updatedAt: now,
      );

      return await updateAvatar(updatedAvatar);
    } catch (e) {
      debugPrint('Fehler beim Hinzufügen von Medien: $e');
      return false;
    }
  }

  /// Lösche einen Avatar und alle seine Dateien
  Future<bool> deleteAvatar(String avatarId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final avatar = await getAvatar(avatarId);
      if (avatar == null || avatar.userId != user.uid) return false;

      // 1) Dateien aus Storage entfernen
      await _deleteAvatarFiles(avatar);

      // 2) Verknüpfte Firestore-Daten entfernen (media_gallery, playlists, timeline)
      await _deleteAvatarFirestoreData(avatarId);

      // 3) Pinecone/Knowledge löschen (nicht-blockierend, best-effort)
      unawaited(_deletePineconeEntries(avatarId, user.uid));

      // 4) Avatar-Dokument löschen
      await _avatarsCollection.doc(avatarId).delete();
      return true;
    } catch (e) {
      debugPrint('Fehler beim Löschen des Avatars: $e');
      return false;
    }
  }

  /// Lösche alle Dateien eines Avatars
  Future<void> _deleteAvatarFiles(AvatarData avatar) async {
    try {
      // Lösche Avatar-Bild
      if (avatar.avatarImageUrl != null) {
        await FirebaseStorageService.deleteFile(avatar.avatarImageUrl!);
      }

      // Lösche alle Bilder
      for (final url in avatar.imageUrls) {
        await FirebaseStorageService.deleteFile(url);
      }

      // Lösche alle Videos
      for (final url in avatar.videoUrls) {
        await FirebaseStorageService.deleteFile(url);
      }

      // Lösche alle Textdateien
      for (final url in avatar.textFileUrls) {
        await FirebaseStorageService.deleteFile(url);
      }
    } catch (e) {
      debugPrint('Fehler beim Löschen der Avatar-Dateien: $e');
    }
  }

  /// Löscht alle Firestore-Daten unterhalb von avatars/{avatarId}
  Future<void> _deleteAvatarFirestoreData(String avatarId) async {
    try {
      final root = _avatarsCollection.doc(avatarId);

      // Medien-Kollektionen
      for (final col in const ['images', 'videos', 'audios', 'documents']) {
        final snap = await root.collection(col).get();
        for (final d in snap.docs) {
          await d.reference.delete();
        }
      }

      // Playlists inkl. timelineAssets + timelineItems
      final playlists = await root.collection('playlists').get();
      for (final p in playlists.docs) {
        final assets = await p.reference.collection('timelineAssets').get();
        for (final a in assets.docs) {
          await a.reference.delete();
        }
        final items = await p.reference.collection('timelineItems').get();
        for (final it in items.docs) {
          await it.reference.delete();
        }
        await p.reference.delete();
      }
    } catch (e) {
      debugPrint('Fehler beim Löschen der Firestore-Daten: $e');
    }
  }

  /// Löscht Pinecone/Knowledge-Einträge für diesen Avatar (Best Effort)
  Future<void> _deletePineconeEntries(String avatarId, String userId) async {
    try {
      final base = EnvService.pineconeApiBaseUrl();
      if (base.isEmpty) return;
      final uri = Uri.parse('$base/avatar/memory/delete/by-avatar');
      await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: '{"user_id":"$userId","avatar_id":"$avatarId"}',
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      // still weiter; UI nicht blockieren
      debugPrint('Fehler beim Löschen der Pinecone-Einträge: $e');
    }
  }

  /// Setze die letzte Nachricht für einen Avatar
  Future<bool> updateLastMessage(String avatarId, String message) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final now = DateTime.now();
      await _avatarsCollection.doc(avatarId).update({
        'lastMessage': message,
        'lastMessageTime': now.millisecondsSinceEpoch,
        'updatedAt': now.millisecondsSinceEpoch,
      });
      return true;
    } catch (e) {
      debugPrint('Fehler beim Aktualisieren der letzten Nachricht: $e');
      return false;
    }
  }

  /// Stream für Echtzeit-Updates der Avatare
  Stream<List<AvatarData>> getUserAvatarsStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _avatarsCollection
        .where('userId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AvatarData.fromMap(doc.data()))
              .toList(),
        );
  }
}
