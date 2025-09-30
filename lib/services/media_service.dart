import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/media_models.dart';

class MediaService {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> _col(String avatarId) =>
      _fs.collection('avatars').doc(avatarId).collection('media');

  Future<List<AvatarMedia>> list(String avatarId) async {
    final qs = await _col(
      avatarId,
    ).orderBy('createdAt', descending: true).get();
    return qs.docs.map((d) => AvatarMedia.fromMap(d.data())).toList();
  }

  Future<void> add(String avatarId, AvatarMedia m) async {
    await _col(avatarId).doc(m.id).set(m.toMap());
  }

  Future<void> delete(String avatarId, String id) async {
    await _col(avatarId).doc(id).delete();
  }
}

