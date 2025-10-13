import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';
import 'package:sunriza26/widgets/avatar_overlay.dart';

Future<Room> joinLiveKit(
  String apiBase,
  String avatarId,
  String voiceId,
  mixer,
  prosodyState,
) async {
  final resp = await http.post(
    Uri.parse('$apiBase/session-live'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'avatar_id': avatarId, 'voice_id': voiceId}),
  );
  final data = jsonDecode(resp.body);
  final room = Room();

  // Setup listener before connecting
  final listener = room.createListener();
  listener.on<DataReceivedEvent>((event) {
    final msg = utf8.decode(event.data);
    if (event.topic == 'viseme') onVisemeMessage(msg, mixer);
    if (event.topic == 'prosody') onProsodyMessage(msg, prosodyState);
  });

  await room.connect(data['webrtc']['url'], data['webrtc']['token']);
  return room;
}
