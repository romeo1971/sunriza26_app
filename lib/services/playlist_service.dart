import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/playlist_models.dart';

class PlaylistService {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String avatarId) =>
      _fs.collection('avatars').doc(avatarId).collection('playlists');

  Future<List<Playlist>> list(String avatarId) async {
    final qs = await _col(
      avatarId,
    ).orderBy('createdAt', descending: true).get();
    return qs.docs.map((d) => Playlist.fromMap(d.data())).toList();
  }

  Future<Playlist> create(
    String avatarId, {
    required String name,
    int showAfterSec = 0,
  }) async {
    final id = _col(avatarId).doc().id;
    final now = DateTime.now().millisecondsSinceEpoch;
    final p = Playlist(
      id: id,
      avatarId: avatarId,
      name: name,
      showAfterSec: showAfterSec,
      createdAt: now,
      updatedAt: now,
    );
    await _col(avatarId).doc(id).set(p.toMap());
    return p;
  }

  Future<void> update(Playlist p) async {
    await _col(p.avatarId).doc(p.id).set({
      ...p.toMap(),
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    }, SetOptions(merge: true));
  }

  // Hilfsfunktion: Prüfen, ob Playlist heute aktiv ist
  bool isActiveToday(Playlist p, DateTime now) {
    if (p.specialDates.isNotEmpty) {
      final today = _fmt(now);
      if (p.specialDates.contains(today)) return true;
    }
    if (p.repeat == 'daily') return true;
    if (p.repeat == 'weekly') {
      final isoDow = (now.weekday); // 1=Mon .. 7=So
      return (p.weeklyDay != null && p.weeklyDay == isoDow);
    }
    if (p.repeat == 'monthly') {
      final dom = now.day;
      return (p.monthlyDay != null && p.monthlyDay == dom);
    }
    return p.repeat == 'none';
  }

  String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  Future<void> delete(String avatarId, String id) async {
    await _col(avatarId).doc(id).delete();
  }

  // Items
  CollectionReference<Map<String, dynamic>> _itemsCol(
    String avatarId,
    String playlistId,
  ) => _fs
      .collection('avatars')
      .doc(avatarId)
      .collection('playlists')
      .doc(playlistId)
      .collection('items');

  Future<List<PlaylistItem>> listItems(
    String avatarId,
    String playlistId,
  ) async {
    final qs = await _itemsCol(avatarId, playlistId).orderBy('order').get();
    return qs.docs.map((d) => PlaylistItem.fromMap(d.data())).toList();
  }

  Future<void> addItem(
    String avatarId,
    String playlistId,
    String mediaId, {
    required int order,
  }) async {
    final id = _itemsCol(avatarId, playlistId).doc().id;
    final item = PlaylistItem(
      id: id,
      playlistId: playlistId,
      avatarId: avatarId,
      mediaId: mediaId,
      order: order,
    );
    await _itemsCol(avatarId, playlistId).doc(id).set(item.toMap());
  }

  Future<void> setOrder(
    String avatarId,
    String playlistId,
    List<PlaylistItem> items,
  ) async {
    final batch = _fs.batch();
    for (int i = 0; i < items.length; i++) {
      final ref = _itemsCol(avatarId, playlistId).doc(items[i].id);
      batch.set(ref, {
        ...items[i].toMap(),
        'order': i,
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }
}
