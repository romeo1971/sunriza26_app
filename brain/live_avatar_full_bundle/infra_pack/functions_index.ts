import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { AccessToken } from "livekit-server-sdk";
import fetch from "node-fetch";

admin.initializeApp();

const LIVEKIT_URL = functions.config().livekit.url as string;
const LIVEKIT_KEY = functions.config().livekit.key as string;
const LIVEKIT_SECRET = functions.config().livekit.secret as string;
const ELEVEN_KEY = functions.config().eleven.api_key as string;

// Helper: mint a subscriber token for a room
function mintToken(roomName: string, identity: string, name?: string) {
  const at = new AccessToken(LIVEKIT_KEY, LIVEKIT_SECRET, { identity, name });
  at.addGrant({ roomJoin: true, room: roomName, canPublish: false, canSubscribe: true, canPublishData: true });
  return at.toJwt();
}

export const sessionLive = functions.https.onRequest(async (req, res) => {
  const { avatar_id, voice_id } = req.body as { avatar_id: string; voice_id: string };
  const roomName = "room_" + avatar_id;
  const identity = "viewer_" + Date.now();
  const token = mintToken(roomName, identity, "viewer");

  // TODO: start ElevenLabs streaming + push timestamps to DataChannel via server-side participant (separate worker)
  res.json({
    session_id: identity,
    webrtc: { url: LIVEKIT_URL, token },
    labels: { viseme: "viseme", prosody: "prosody" }
  });
});

export const speak = functions.https.onRequest(async (req, res) => {
  const { text, voice_id } = req.body as { text: string; voice_id: string };
  // TODO: call ElevenLabs "text-to-speech/stream" websocket from a worker process,
  // forward audio to LiveKit server-side participant, emit timestamps as DataChannel messages.
  res.json({ ok: true });
});

export const stop = functions.https.onRequest(async (_req, res) => {
  // TODO: send barge-in stop to ElevenLabs worker
  res.json({ ok: true });
});
