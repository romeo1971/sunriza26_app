import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/media_models.dart';

class MediaService {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  // Neue Struktur: {type}/{mediaId} (ohne media/ prefix)
  CollectionReference<Map<String, dynamic>> _col(
    String avatarId,
    AvatarMediaType type,
  ) {
    final typeFolder = _typeFolder(type);
    return _fs.collection('avatars').doc(avatarId).collection(typeFolder);
  }

  String _typeFolder(AvatarMediaType type) {
    switch (type) {
      case AvatarMediaType.image:
        return 'images';
      case AvatarMediaType.video:
        return 'videos';
      case AvatarMediaType.document:
        return 'documents';
      case AvatarMediaType.audio:
        return 'audios';
    }
  }

  Future<List<AvatarMedia>> list(String avatarId) async {
    final List<AvatarMedia> all = [];
    // Alle Typen durchlaufen
    for (final type in AvatarMediaType.values) {
      // Robust: ohne orderBy abfragen (einige ältere Docs könnten createdAt fehlen)
      final qs = await _col(avatarId, type).get();
      all.addAll(
        qs.docs.map((d) => AvatarMedia.fromMap({'id': d.id, ...d.data()})),
      );
    }
    // Nach createdAt sortieren
    all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return all;
  }

  Future<void> add(String avatarId, AvatarMedia m) async {
    await _col(avatarId, m.type).doc(m.id).set(m.toMap());
  }

  Future<void> delete(String avatarId, String id, AvatarMediaType type) async {
    await _col(avatarId, type).doc(id).delete();
  }

  Future<void> update(
    String avatarId,
    String id,
    AvatarMediaType type, {
    String? url,
    double? aspectRatio,
    List<String>? tags,
  }) async {
    final Map<String, dynamic> updates = {};
    if (url != null) updates['url'] = url;
    if (aspectRatio != null) updates['aspectRatio'] = aspectRatio;
    if (tags != null) updates['tags'] = tags;
    if (updates.isNotEmpty) {
      await _col(avatarId, type).doc(id).update(updates);
    }
  }
}
