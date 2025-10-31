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
  
  // Voice Activity Detection: Audio Level State
  final ValueNotifier<bool> isSpeaking = ValueNotifier<bool>(false);
  final ValueNotifier<double> audioLevel = ValueNotifier<double>(0.0);
  Timer? _vadTimer;

  bool get isConnected => connected.value;
  String? get roomName => _roomName;
  Stream<lk.RoomEvent> get events => _events.stream;
  lk.Room? get room => _room; // Public access für Mikrofon-Toggle

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

    // Room mit AUDIO OPTIONS wie bithumanProd!
    final lk.Room roomObj = lk.Room(
      roomOptions: const lk.RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultAudioPublishOptions: lk.AudioPublishOptions(dtx: true),
        defaultVideoPublishOptions: lk.VideoPublishOptions(simulcast: true),
      ),
    );
    // Listener erstellen und Events relayn + Tracks beobachten
    final lis = roomObj.createListener();
    lis.on<lk.RoomEvent>((e) => _events.add(e));
    
    // DEBUG: Participant Connected
    lis.on<lk.ParticipantConnectedEvent>((e) {
      debugPrint('👤 PARTICIPANT CONNECTED: ${e.participant.identity}');
    });
    
    // DEBUG: Track Published
    lis.on<lk.TrackPublishedEvent>((e) {
      debugPrint('📹 TRACK PUBLISHED: ${e.publication.kind} from ${e.participant.identity}');
    });
    
    // DEBUG: Track Subscribed
    lis.on<lk.TrackSubscribedEvent>((e) {
      debugPrint('✅ TRACK SUBSCRIBED: ${e.track.kind} from ${e.participant.identity}');
      final t = e.track;
      if (t is lk.RemoteVideoTrack) {
        debugPrint('🎬 REMOTE VIDEO TRACK SET!');
        remoteVideo.value = t;
      }
    });
    
    lis.on<lk.TrackUnsubscribedEvent>((e) {
      debugPrint('❌ TRACK UNSUBSCRIBED: ${e.track.kind}');
      if (remoteVideo.value == e.track) {
        remoteVideo.value = null;
      }
    });
    
    lis.on<lk.ParticipantDisconnectedEvent>((e) {
      debugPrint('👋 PARTICIPANT DISCONNECTED: ${e.participant.identity}');
      // Wenn der Publisher geht, Video-Track zurücksetzen
      remoteVideo.value = null;
    });
    
    // Voice Activity Detection: DEAKTIVIERT - Manuelles Mikrofon nur
    // lis.on<lk.LocalTrackPublishedEvent>((e) {
    //   if (e.publication.kind == lk.TrackType.AUDIO) {
    //     _setupAudioLevelMonitoring(roomObj);
    //   }
    // });
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
          final lk.Room nr = lk.Room(
            roomOptions: const lk.RoomOptions(
              adaptiveStream: true,
              dynacast: true,
              defaultAudioPublishOptions: lk.AudioPublishOptions(dtx: true),
              defaultVideoPublishOptions: lk.VideoPublishOptions(simulcast: true),
            ),
          );
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
          
          // MIKROFON DEAKTIVIERT bei Reconnect - wird manuell aktiviert
          try {
            await nr.localParticipant?.setMicrophoneEnabled(false);
            debugPrint('🎤 Microphone DISABLED after reconnect (manual activation only)');
          } catch (_) {}

        } catch (_) {}
      });
    });

    try {
      debugPrint('🔌 LiveKit connecting to: $serverUrl (room: $room)');
      await roomObj.connect(
        serverUrl,
        token,
        connectOptions: const lk.ConnectOptions(autoSubscribe: true),
      );
      _room = roomObj;
      _listener = lis;
      connected.value = true;
      connectionStatus.value = 'connected';
      _reconnectAttempts = 0;
      
      // MIKROFON DEAKTIVIERT by default - wird manuell aktiviert beim Recording
      try {
        await roomObj.localParticipant?.setMicrophoneEnabled(false);
        debugPrint('🎤 Microphone DISABLED by default (manual activation only)');
      } catch (e) {
        debugPrint('⚠️ Could not disable microphone: $e');
      }
      
      debugPrint('✅ LiveKit CONNECTED to room: $room');
      return true;
    } catch (e) {
      debugPrint('❌ LiveKit connection FAILED: $e');
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

  // Voice Activity Detection DEAKTIVIERT - nur manuelles Mikrofon
  // 
  // /// Setup Audio Level Monitoring for Voice Activity Detection
  // void _setupAudioLevelMonitoring(lk.Room room) {
  //   _vadTimer?.cancel();
  //   
  //   // Monitor local participant audio level stream für Voice Activity Detection
  //   // VAD threshold: -40dB, silence timeout: 3s wie bithumanProd
  //   const vadThreshold = 0.01; // ~-40dB in linear scale (0.0-1.0)
  //   const silenceTimeout = Duration(seconds: 3);
  //   DateTime? lastSpeechTime;
  //   
  //   _vadTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
  //     final localParticipant = room.localParticipant;
  //     if (localParticipant == null) {
  //       isSpeaking.value = false;
  //       return;
  //     }
  //     
  //     // Check if microphone is enabled
  //     final isMicEnabled = localParticipant.isMicrophoneEnabled();
  //     if (!isMicEnabled) {
  //       isSpeaking.value = false;
  //       audioLevel.value = 0.0;
  //       return;
  //     }
  //     
  //     // Get audio level from participant (0.0-1.0)
  //     // LiveKit Participant hat audioLevel Property das automatisch gemessen wird
  //     final level = localParticipant.audioLevel;
  //     audioLevel.value = level;
  //     
  //     // Voice Activity Detection mit threshold
  //     if (level > vadThreshold) {
  //       isSpeaking.value = true;
  //       lastSpeechTime = DateTime.now();
  //     } else {
  //       // Silence timeout: wenn 3s keine Sprache -> isSpeaking = false
  //       if (lastSpeechTime != null) {
  //         final silenceDuration = DateTime.now().difference(lastSpeechTime!);
  //         if (silenceDuration > silenceTimeout) {
  //           isSpeaking.value = false;
  //         }
  //         // Während Silence Timeout noch speaking = true
  //       } else {
  //         isSpeaking.value = false;
  //       }
  //     }
  //   });
  // }

  Future<void> dispose() async {
    await leave();
    await _events.close();
    _vadTimer?.cancel();
    connected.dispose();
    remoteVideo.dispose();
    isSpeaking.dispose();
    audioLevel.dispose();
  }
}
