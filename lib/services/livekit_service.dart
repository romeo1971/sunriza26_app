import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// LiveKit‑Service mit Feature‑Gate.
/// Wenn LIVEKIT_ENABLED != '1', verhalten sich join/leave no‑op (wie Stub).
class LiveKitService {
  static final LiveKitService _instance = LiveKitService._internal();
  factory LiveKitService() => _instance;
  LiveKitService._internal();

  final ValueNotifier<bool> connected = ValueNotifier<bool>(false);
  // Verbindungsstatus für UI (idle/connecting/connected/reconnecting/disconnected/ended)
  final ValueNotifier<String> connectionStatus = ValueNotifier<String>('idle');
  final StreamController<lk.RoomEvent> _events = StreamController.broadcast();

  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  String? _roomName;
  bool _manualStop = false;
  int _reconnectAttempts = 0;

  // Beobachtbarer Remote-Video-Track (für Rendering)
  final ValueNotifier<lk.VideoTrack?> remoteVideo =
      ValueNotifier<lk.VideoTrack?>(null);

  bool get isConnected => connected.value;
  String? get roomName => _roomName;
  Stream<lk.RoomEvent> get events => _events.stream;

  bool get _enabled => (dotenv.env['LIVEKIT_ENABLED'] ?? '').trim() == '1';
  String get _lkUrl => (dotenv.env['LIVEKIT_URL'] ?? '').trim();

  /// Join LiveKit‑Room. Erfordert LIVEKIT_ENABLED=1 und gültige URL/TOKEN.
  /// Bei deaktiviertem Flag verhält sich die Methode wie der frühere Stub
  /// (setzt nur den lokalen Status), damit die App stabil bleibt.
  Future<bool> join({
    required String room,
    required String token,
    String? urlOverride,
  }) async {
    _manualStop = false;
    connectionStatus.value = 'connecting';
    _roomName = room;

    if (!_enabled) {
      connected.value = true; // Stub‑Verhalten
      connectionStatus.value = 'connected';
      return true;
    }
    final String serverUrl =
        (urlOverride != null && urlOverride.trim().isNotEmpty)
        ? urlOverride.trim()
        : _lkUrl;
    if (serverUrl.isEmpty || token.trim().isEmpty) {
      return false;
    }

    // vorhandene Session schließen
    if (_room != null) {
      await leave();
    }

    final lk.Room roomObj = lk.Room(roomOptions: const lk.RoomOptions());
    // Listener erstellen und Events relayn + Tracks beobachten
    final lis = roomObj.createListener();
    lis.on<lk.RoomEvent>((e) => _events.add(e));
    lis.on<lk.TrackSubscribedEvent>((e) {
      final t = e.track;
      if (t is lk.RemoteVideoTrack) {
        remoteVideo.value = t;
      }
    });
    lis.on<lk.TrackUnsubscribedEvent>((e) {
      if (remoteVideo.value == e.track) {
        remoteVideo.value = null;
      }
    });
    lis.on<lk.ParticipantDisconnectedEvent>((e) {
      // Wenn der Publisher geht, Video-Track zurücksetzen
      remoteVideo.value = null;
    });
    lis.on<lk.RoomDisconnectedEvent>((e) async {
      connected.value = false;
      if (_manualStop) {
        connectionStatus.value = 'ended';
        return;
      }
      connectionStatus.value = 'reconnecting';
      if (_reconnectAttempts >= 3) {
        connectionStatus.value = 'disconnected';
        return;
      }
      _reconnectAttempts += 1;
      final delayMs = 500 * (1 << (_reconnectAttempts - 1));
      // Neuer Verbindungsaufbau mit gespeicherter URL/Token
      Future(() async {
        await Future.delayed(Duration(milliseconds: delayMs));
        if (_manualStop) return;
        final url = (dotenv.env['LIVEKIT_URL'] ?? '').trim();
        final token = (dotenv.env['LIVEKIT_LAST_TOKEN'] ?? '').trim();
        if (url.isEmpty || token.isEmpty) {
          connectionStatus.value = 'disconnected';
          return;
        }
        try {
          final lk.Room nr = lk.Room(roomOptions: const lk.RoomOptions());
          final lis2 = nr.createListener();
          lis2.on<lk.RoomEvent>((e) => _events.add(e));
          lis2.on<lk.TrackSubscribedEvent>((e) {
            final t = e.track;
            if (t is lk.RemoteVideoTrack) {
              remoteVideo.value = t;
            }
          });
          lis2.on<lk.TrackUnsubscribedEvent>((e) {
            if (remoteVideo.value == e.track) {
              remoteVideo.value = null;
            }
          });
          lis2.on<lk.ParticipantDisconnectedEvent>((e) {
            remoteVideo.value = null;
          });
          _listener = lis2;
          await nr.connect(url, token);
          _room = nr;
          connected.value = true;
          connectionStatus.value = 'connected';
          _reconnectAttempts = 0;
        } catch (_) {}
      });
    });

    try {
      await roomObj.connect(serverUrl, token);
      _room = roomObj;
      _listener = lis;
      connected.value = true;
      connectionStatus.value = 'connected';
      _reconnectAttempts = 0;
      return true;
    } catch (_) {
      try {
        await roomObj.dispose();
      } catch (_) {}
      _room = null;
      _listener = null;
      connected.value = false;
      connectionStatus.value = 'disconnected';
      return false;
    }
  }

  /// Leave/Dispose der aktuellen Session (no‑op bei deaktiviertem Flag).
  Future<void> leave() async {
    final lk.Room? r = _room;
    _manualStop = true;
    _room = null;
    _roomName = null;
    connected.value = false;
    connectionStatus.value = 'ended';
    remoteVideo.value = null;

    if (!_enabled) return; // Stub‑Verhalten

    try {
      await _listener?.dispose();
    } catch (_) {}
    _listener = null;

    if (r != null) {
      try {
        await r.disconnect();
      } catch (_) {}
      try {
        await r.dispose();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await leave();
    await _events.close();
    connected.dispose();
    remoteVideo.dispose();
  }
}
