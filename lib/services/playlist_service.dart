import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../models/playlist_models.dart';

class PlaylistService {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String avatarId) =>
      _fs.collection('avatars').doc(avatarId).collection('playlists');

  Future<Playlist?> getOne(String avatarId, String playlistId) async {
    final d = await _col(avatarId).doc(playlistId).get();
    if (!d.exists) return null;
    try {
      final data = d.data();
      if (data == null) return null;
      final sanitized = _sanitizePlaylistMap(
        Map<String, dynamic>.from(data),
        expectedAvatarId: avatarId,
        docId: d.id,
        fixes: <String>[],
      );
      // timelineSplitRatio beibehalten, falls im Original vorhanden
      if (data.containsKey('timelineSplitRatio')) {
        sanitized['timelineSplitRatio'] = data['timelineSplitRatio'];
      }
      return Playlist.fromMap(sanitized);
    } catch (_) {
      return null;
    }
  }

  Future<List<Playlist>> list(String avatarId) async {
    QuerySnapshot<Map<String, dynamic>> qs;
    try {
      qs = await _col(avatarId)
          .orderBy('createdAt', descending: true)
          .limit(200) // defensive: keine unendliche Liste in den Speicher laden
          .get()
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Fallback: ohne Sortierung laden (z. B. wenn Feldtypen inkonsistent sind)
      qs = await _col(
        avatarId,
      ).limit(200).get().timeout(const Duration(seconds: 8));
    }

    final List<Playlist> out = [];
    for (final d in qs.docs) {
      try {
        final data = d.data();
        // Sanitize pro Dokument, um inkonsistente Typen zu vermeiden
        final sanitized = _sanitizePlaylistMap(
          Map<String, dynamic>.from(data),
          expectedAvatarId: avatarId,
          docId: d.id,
          fixes: <String>[],
        );
        out.add(Playlist.fromMap(sanitized));
      } catch (_) {
        // Ungültiges Dokument überspringen
        continue;
      }
    }
    return out;
  }

  // Diagnose: Playlists validieren (liefert Liste von {id, problems})
  Future<List<Map<String, dynamic>>> validate(String avatarId) async {
    final qs = await _col(avatarId)
        .orderBy('createdAt', descending: true)
        .limit(500)
        .get()
        .timeout(const Duration(seconds: 8));
    final List<Map<String, dynamic>> issues = [];
    for (final d in qs.docs) {
      try {
        final data = d.data();
        final problems = _validatePlaylistMap(data, expectedAvatarId: avatarId);
        if (problems.isNotEmpty) {
          issues.add({'id': data['id'] ?? d.id, 'problems': problems});
        }
      } catch (e) {
        issues.add({
          'id': d.id,
          'problems': ['Exception: $e'],
        });
      }
    }
    return issues;
  }

  List<String> _validatePlaylistMap(
    Map<String, dynamic> m, {
    required String expectedAvatarId,
  }) {
    final List<String> problems = [];
    String? asString(dynamic v) => v is String ? v : null;
    int? asInt(dynamic v) {
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    final id = asString(m['id']);
    final avatarId = asString(m['avatarId']);
    final name = asString(m['name']);
    if (id == null || id.isEmpty) problems.add('id fehlt/leer');
    if (avatarId == null || avatarId.isEmpty) {
      problems.add('avatarId fehlt/leer');
    } else if (expectedAvatarId.isNotEmpty && avatarId != expectedAvatarId) {
      problems.add('avatarId ungleich erwartetem Avatar');
    }
    if (name == null || name.trim().isEmpty) problems.add('name fehlt/leer');

    final ws = m['weeklySchedules'];
    if (ws != null && ws is List) {
      for (int i = 0; i < ws.length; i++) {
        final e = ws[i];
        if (e is! Map) {
          problems.add('weekly[$i] kein Objekt');
          continue;
        }
        final weekday = asInt(e['weekday']);
        if (weekday == null || weekday < 1 || weekday > 7) {
          problems.add('weekly[$i].weekday ungültig: $weekday');
        }
        final ts = e['timeSlots'];
        if (ts is List) {
          for (int j = 0; j < ts.length; j++) {
            final idx = asInt(ts[j]);
            if (idx == null || idx < 0 || idx >= TimeSlot.values.length) {
              problems.add('weekly[$i].timeSlots[$j] ungültig: $idx');
            }
          }
        } else if (ts != null) {
          problems.add('weekly[$i].timeSlots kein Array');
        }
      }
    } else if (ws != null) {
      problems.add('weeklySchedules kein Array');
    }

    final ss = m['specialSchedules'];
    if (ss != null && ss is List) {
      for (int i = 0; i < ss.length; i++) {
        final e = ss[i];
        if (e is! Map) {
          problems.add('special[$i] kein Objekt');
          continue;
        }
        final start = asInt(e['startDate']);
        final end = asInt(e['endDate']);
        if (start == null || start <= 0) {
          problems.add('special[$i].startDate ungültig: $start');
        }
        if (end == null || end <= 0) {
          problems.add('special[$i].endDate ungültig: $end');
        }
        if (start != null && end != null && end < start) {
          problems.add('special[$i].endDate < startDate');
        }
        final ts = e['timeSlots'];
        if (ts is List) {
          for (int j = 0; j < ts.length; j++) {
            final idx = asInt(ts[j]);
            if (idx == null || idx < 0 || idx >= TimeSlot.values.length) {
              problems.add('special[$i].timeSlots[$j] ungültig: $idx');
            }
          }
        } else if (ts != null) {
          problems.add('special[$i].timeSlots kein Array');
        }
      }
    } else if (ss != null) {
      problems.add('specialSchedules kein Array');
    }

    final sm = asString(m['scheduleMode']);
    if (sm != null && sm != 'weekly' && sm != 'special') {
      problems.add('scheduleMode ungültig: $sm');
    }

    final tg = m['targeting'];
    if (tg != null && tg is! Map) {
      problems.add('targeting kein Objekt');
    }

    return problems;
  }

  Future<Map<String, dynamic>> repair(String avatarId, String docId) async {
    final ref = _col(avatarId).doc(docId);
    final snap = await ref.get();
    if (!snap.exists) return {'status': 'missing', 'docId': docId};
    final data = snap.data();
    if (data is! Map<String, dynamic>) {
      await ref.delete();
      return {'status': 'deleted', 'docId': docId, 'reason': 'no object'};
    }

    final fixes = <String>[];
    Map<String, dynamic> sanitized = _sanitizePlaylistMap(
      Map<String, dynamic>.from(data),
      expectedAvatarId: avatarId,
      docId: docId,
      fixes: fixes,
    );

    if ((sanitized['id'] as String?)?.isEmpty ?? true) {
      await ref.delete();
      return {'status': 'deleted', 'docId': docId, 'reason': 'empty id'};
    }

    await ref.set(sanitized, SetOptions(merge: false));
    return {'status': 'fixed', 'docId': docId, 'fixes': fixes};
  }

  Map<String, dynamic> _sanitizePlaylistMap(
    Map<String, dynamic> m, {
    required String expectedAvatarId,
    required String docId,
    required List<String> fixes,
  }) {
    int nowMs() => DateTime.now().millisecondsSinceEpoch;
    int parseInt(dynamic v, {int def = 0}) {
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? def;
      return def;
    }

    String? asString(dynamic v) => v is String ? v : null;

    final out = <String, dynamic>{};
    out['id'] = asString(m['id']) ?? docId;
    if (out['id'] != m['id']) fixes.add('id gesetzt (${out['id']})');

    out['avatarId'] = asString(m['avatarId']) ?? expectedAvatarId;
    if (out['avatarId'] != m['avatarId']) fixes.add('avatarId korrigiert');
    if (out['avatarId'] != expectedAvatarId) {
      out['avatarId'] = expectedAvatarId;
      fixes.add('avatarId auf Avatar angepasst');
    }

    final name = asString(m['name']);
    out['name'] = (name == null || name.trim().isEmpty)
        ? 'Untitled ${docId.substring(0, 6)}'
        : name;
    if (out['name'] != m['name']) fixes.add('name korrigiert');

    out['showAfterSec'] = parseInt(m['showAfterSec'], def: 0);

    final highlightTag = asString(m['highlightTag']);
    if (highlightTag != null && highlightTag.isNotEmpty) {
      out['highlightTag'] = highlightTag;
    }

    final coverImageUrl = asString(m['coverImageUrl']);
    if (coverImageUrl != null && coverImageUrl.isNotEmpty) {
      out['coverImageUrl'] = coverImageUrl;
    }

    final List<Map<String, dynamic>> weekly = [];
    final ws = m['weeklySchedules'];
    if (ws is List) {
      for (final e in ws) {
        if (e is Map) {
          int wd = parseInt(e['weekday'], def: 1);
          if (wd < 1 || wd > 7) {
            wd = 1;
            fixes.add('weekday korrigiert');
          }
          final ts = <int>[];
          final rawTs = e['timeSlots'];
          if (rawTs is List) {
            for (final v in rawTs) {
              final idx = parseInt(v, def: -1);
              if (idx >= 0 &&
                  idx < TimeSlot.values.length &&
                  !ts.contains(idx)) {
                ts.add(idx);
              }
            }
          }
          weekly.add({'weekday': wd, 'timeSlots': ts});
        }
      }
    }
    out['weeklySchedules'] = weekly;

    final List<Map<String, dynamic>> specials = [];
    final ss = m['specialSchedules'];
    if (ss is List) {
      for (final e in ss) {
        if (e is Map) {
          int start = parseInt(e['startDate'], def: 0);
          int end = parseInt(e['endDate'], def: 0);
          if (start > 0 && end > 0 && end < start) {
            final tmp = start;
            start = end;
            end = tmp;
            fixes.add('special: start/end vertauscht korrigiert');
          }
          if (start <= 0 || end <= 0) {
            fixes.add('special mit ungültigem Datum entfernt');
            continue;
          }
          final ts = <int>[];
          final rawTs = e['timeSlots'];
          if (rawTs is List) {
            for (final v in rawTs) {
              final idx = parseInt(v, def: -1);
              if (idx >= 0 &&
                  idx < TimeSlot.values.length &&
                  !ts.contains(idx)) {
                ts.add(idx);
              }
            }
          }
          specials.add({'startDate': start, 'endDate': end, 'timeSlots': ts});
        }
      }
    }
    out['specialSchedules'] = specials;

    final tg = m['targeting'];
    if (tg is Map) {
      out['targeting'] = Map<String, dynamic>.from(tg);
    }

    final pr = m['priority'];
    final prInt = (pr is num)
        ? pr.toInt()
        : (pr is String ? int.tryParse(pr) : null);
    if (prInt != null) out['priority'] = prInt;

    final sm = asString(m['scheduleMode']);
    if (sm == 'weekly' || sm == 'special') out['scheduleMode'] = sm;

    out['createdAt'] = parseInt(m['createdAt'], def: nowMs());
    out['updatedAt'] = nowMs();
    return out;
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
    // Vor dem Schreiben sanitizen, damit Felder (v. a. createdAt, timeSlots)
    // in konsistenten Typen landen und nachfolgende Queries stabil sind.
    final raw = p.toMap();
    final sanitized = _sanitizePlaylistMap(
      Map<String, dynamic>.from(raw),
      expectedAvatarId: p.avatarId,
      docId: p.id,
      fixes: <String>[],
    );
    sanitized['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    // Vollständiges Überschreiben: verhindert, dass Alt-Felder mit falschen Typen
    // im Dokument verbleiben und spätere Reads/Queries stören.
    await _col(p.avatarId).doc(p.id).set(sanitized, SetOptions(merge: false));
  }

  Future<void> setTimelineSplitRatio(
    String avatarId,
    String playlistId,
    double ratio,
  ) async {
    final r = ratio.clamp(0.1, 0.9);
    await _col(avatarId).doc(playlistId).set({
      'timelineSplitRatio': (r as num).toDouble(),
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

    // 2. Prüfe wöchentlichen Scheduler
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

  // --- Timeline Assets / Items ---
  CollectionReference<Map<String, dynamic>> _assetsCol(
    String avatarId,
    String playlistId,
  ) => _fs
      .collection('avatars')
      .doc(avatarId)
      .collection('playlists')
      .doc(playlistId)
      .collection('timelineAssets');

  CollectionReference<Map<String, dynamic>> _tItemsCol(
    String avatarId,
    String playlistId,
  ) => _fs
      .collection('avatars')
      .doc(avatarId)
      .collection('playlists')
      .doc(playlistId)
      .collection('timelineItems');

  Future<List<Map<String, dynamic>>> listAssets(
    String avatarId,
    String playlistId,
  ) async {
    final qs = await _assetsCol(avatarId, playlistId).get();
    return qs.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> setAssets(
    String avatarId,
    String playlistId,
    List<Map<String, dynamic>> assets,
  ) async {
    // Ersetzt alle Assets durch übergebene Liste
    final existing = await _assetsCol(avatarId, playlistId).get();
    final batch = _fs.batch();
    for (final d in existing.docs) {
      batch.delete(d.reference);
    }
    for (final a in assets) {
      final id =
          a['id'] as String? ?? _assetsCol(avatarId, playlistId).doc().id;
      batch.set(_assetsCol(avatarId, playlistId).doc(id), a);
    }
    await batch.commit();
  }

  Future<List<Map<String, dynamic>>> listTimelineItems(
    String avatarId,
    String playlistId,
  ) async {
    final qs = await _tItemsCol(avatarId, playlistId).orderBy('order').get();
    return qs.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> writeTimelineItems(
    String avatarId,
    String playlistId,
    List<Map<String, dynamic>> items,
  ) async {
    // Ersetzt alle Items mit neuer geordneter Liste
    final existing = await _tItemsCol(avatarId, playlistId).get();
    final batch = _fs.batch();
    for (final d in existing.docs) {
      batch.delete(d.reference);
    }
    for (int i = 0; i < items.length; i++) {
      final it = {...items[i]};
      it['order'] = i;
      final id =
          it['id'] as String? ?? _tItemsCol(avatarId, playlistId).doc().id;
      batch.set(
        _tItemsCol(avatarId, playlistId).doc(id),
        it,
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> deleteTimelineItemsByAsset(
    String avatarId,
    String playlistId,
    String assetId,
  ) async {
    final qs = await _tItemsCol(
      avatarId,
      playlistId,
    ).where('assetId', isEqualTo: assetId).get();
    if (qs.docs.isEmpty) return;
    final batch = _fs.batch();
    for (final d in qs.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  // Prüft und bereinigt Inkonsistenzen:
  // 1) timelineItems ohne existierendes timelineAsset
  // 2) timelineAssets deren mediaId nicht mehr unter avatars/{avatarId}/media existiert
  // Löscht in Batches und gibt Counters zurück
  Future<Map<String, int>> pruneTimelineData(
    String avatarId,
    String playlistId,
  ) async {
    final mediaCol = _fs
        .collection('avatars')
        .doc(avatarId)
        .collection('media');
    final mediaQs = await mediaCol.get();
    final Set<String> mediaIds = mediaQs.docs.map((d) => d.id).toSet();

    final assetsRef = _assetsCol(avatarId, playlistId);
    final itemsRef = _tItemsCol(avatarId, playlistId);

    final assetsQs = await assetsRef.get();
    final itemsQs = await itemsRef.get();

    final Set<String> assetDocIds = assetsQs.docs.map((d) => d.id).toSet();

    final List<QueryDocumentSnapshot<Map<String, dynamic>>> itemsToDelete = [];
    for (final it in itemsQs.docs) {
      final aid = (it.data()['assetId'] as String?) ?? '';
      if (aid.isEmpty || !assetDocIds.contains(aid)) {
        itemsToDelete.add(it);
      }
    }

    final List<QueryDocumentSnapshot<Map<String, dynamic>>> assetsToDelete = [];
    for (final a in assetsQs.docs) {
      final mid = (a.data()['mediaId'] as String?) ?? a.id;
      if (!mediaIds.contains(mid)) {
        assetsToDelete.add(a);
      }
    }

    int deletedItems = 0;
    int deletedAssets = 0;

    if (itemsToDelete.isNotEmpty || assetsToDelete.isNotEmpty) {
      final batch = _fs.batch();
      for (final it in itemsToDelete) {
        batch.delete(it.reference);
        deletedItems++;
      }
      for (final a in assetsToDelete) {
        // Lösche auch alle Items, die auf dieses Asset referenzieren
        final itQs = await itemsRef.where('assetId', isEqualTo: a.id).get();
        for (final it in itQs.docs) {
          batch.delete(it.reference);
          deletedItems++;
        }
        batch.delete(a.reference);
        deletedAssets++;
      }
      await batch.commit();
    }

    return {'deletedItems': deletedItems, 'deletedAssets': deletedAssets};
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
    QuerySnapshot<Map<String, dynamic>> qs;
    try {
      qs = await _itemsCol(avatarId, playlistId).orderBy('order').get();
    } catch (_) {
      // Fallback: unsortiert laden, falls Feldtypen inkonsistent sind
      qs = await _itemsCol(avatarId, playlistId).get();
    }
    final List<PlaylistItem> out = [];
    for (final d in qs.docs) {
      try {
        final m = d.data();
        // Sanitize minimale Felder
        final orderVal = (m['order'] is num)
            ? (m['order'] as num).toInt()
            : (m['order'] is String
                  ? int.tryParse(m['order'] as String) ?? 0
                  : 0);
        out.add(
          PlaylistItem(
            id: (m['id'] as String?) ?? d.id,
            playlistId: (m['playlistId'] as String?) ?? playlistId,
            avatarId: (m['avatarId'] as String?) ?? avatarId,
            mediaId: (m['mediaId'] as String?) ?? '',
            order: orderVal,
          ),
        );
      } catch (_) {
        continue;
      }
    }
    // Stabil sortieren, falls Fallback ohne orderBy war
    out.sort((a, b) => a.order.compareTo(b.order));
    return out;
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
