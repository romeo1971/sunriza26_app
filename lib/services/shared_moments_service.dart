import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/shared_moment.dart';

class SharedMomentsService {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> _col(
    String userId,
    String avatarId,
  ) => _fs
      .collection('users')
      .doc(userId)
      .collection('avatars')
      .doc(avatarId)
      .collection('sharedMoments');

  Future<void> store(String avatarId, String mediaId, String decision) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final id = _col(uid, avatarId).doc().id;
    final m = SharedMoment(
      id: id,
      userId: uid,
      avatarId: avatarId,
      mediaId: mediaId,
      decision: decision,
      decidedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _col(uid, avatarId).doc(id).set(m.toMap());
  }

  Future<Map<String, String>> latestDecisions(String avatarId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return {};
    final qs = await _col(
      uid,
      avatarId,
    ).orderBy('decidedAt', descending: true).get();
    final Map<String, String> mediaDecision = {};
    for (final d in qs.docs) {
      final data = d.data();
      final mid = (data['mediaId'] as String?) ?? '';
      if (mid.isEmpty) continue;
      if (!mediaDecision.containsKey(mid)) {
        mediaDecision[mid] = (data['decision'] as String?) ?? 'shown';
      }
    }
    return mediaDecision;
  }

  Future<List<SharedMoment>> list(String avatarId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return [];
    final qs = await _col(
      uid,
      avatarId,
    ).orderBy('decidedAt', descending: true).limit(500).get();
    return qs.docs.map((d) => SharedMoment.fromMap(d.data())).toList();
  }
}
