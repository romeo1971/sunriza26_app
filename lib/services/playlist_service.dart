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

  // Hilfsfunktion: Prüfen, ob Playlist jetzt aktiv ist
  bool isActiveNow(Playlist p, DateTime now) {
    final weekday = now.weekday; // 1=Mo .. 7=So
    final hour = now.hour;

    // Bestimme aktuelles Zeitfenster
    TimeSlot? currentSlot;
    if (hour >= 3 && hour < 6) {
      currentSlot = TimeSlot.earlyMorning;
    } else if (hour >= 6 && hour < 11)
      currentSlot = TimeSlot.morning;
    else if (hour >= 11 && hour < 14)
      currentSlot = TimeSlot.noon;
    else if (hour >= 14 && hour < 18)
      currentSlot = TimeSlot.afternoon;
    else if (hour >= 18 && hour < 23)
      currentSlot = TimeSlot.evening;
    else
      currentSlot = TimeSlot.night; // 23-3

    // 1. Prüfe Sondertermine (überschreiben weekly)
    final nowMs = now.millisecondsSinceEpoch;
    for (final special in p.specialSchedules) {
      if (nowMs >= special.startDate && nowMs <= special.endDate) {
        return special.timeSlots.contains(currentSlot);
      }
    }

    // 2. Prüfe wöchentlichen Zeitplan
    for (final weekly in p.weeklySchedules) {
      if (weekly.weekday == weekday && weekly.timeSlots.contains(currentSlot)) {
        return true;
      }
    }

    return false;
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

  Future<void> deleteItem(
    String avatarId,
    String playlistId,
    String itemId,
  ) async {
    await _itemsCol(avatarId, playlistId).doc(itemId).delete();
  }
}
