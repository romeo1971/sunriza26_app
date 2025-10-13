import express from "express";
import cors from "cors";
import { WebSocketServer } from "ws";
import { createServer } from "http";
import { startElevenStream } from "./eleven_adapter";
import { VisemeMapper } from "./viseme_mapper";
import type { VisemeEvent, ProsodyEvent, SessionInfo } from "./types";

/**
 * Orchestrator HTTP + WebSocket (DataChannel mirror for dev).
 * In Produktion sendest du viseme/prosody Events über den WebRTC DataChannel.
 * Hier zeigen wir beides: WS (zum Debuggen) + Hooks für WebRTC-SFU (Pseudo).
 */

const app = express();
app.use(cors());
app.use(express.json());

const httpServer = createServer(app);
const wss = new WebSocketServer({ server: httpServer, path: "/ws" });

// Broadcast helper (for debug WS clients)
function broadcast(obj: any) {
  const msg = JSON.stringify(obj);
  for (const client of wss.clients) {
    if (client.readyState === 1) client.send(msg);
  }
}

app.post("/avatarize-2d", async (req, res) => {
  // In Produktion: empfange multipart/form-data, rufe Python-CLI, hoste Assets
  // Hier stubben wir die Antwort
  const avatar_id = "demo-avatar";
  res.json({
    avatar_id,
    idle_url: `/static/${avatar_id}/idle.mp4`,
    atlas_url: `/static/${avatar_id}/atlas.png`,
    atlas_meta_url: `/static/${avatar_id}/atlas.json`,
    mask_url: `/static/${avatar_id}/mask.png`,
    roi: { x: 620, y: 830, w: 360, h: 220 },
  });
});

app.post("/voice-clone", async (req, res) => {
  // Proxy zu ElevenLabs Voice Clone API
  const voice_id = "eleven-voice-id-demo";
  res.json({ voice_id });
});

const sessions = new Map<string, SessionInfo>();

app.post("/session-live", async (req, res) => {
  const { avatar_id, voice_id } = req.body as { avatar_id: string; voice_id: string };
  const session_id = Math.random().toString(36).slice(2);
  // In Produktion: Erzeuge SFU-Raum + Token (LiveKit/Janus)
  // Start ElevenLabs streaming + mapper
  const mapper = new VisemeMapper();
  const stream = await startElevenStream({
    voice_id,
    onAudio: (chunk) => {
      // attach to WebRTC Audio Track (not shown here)
    },
    onTimestamp: (ts) => {
      const visemeEvt: VisemeEvent = mapper.consumeTimestamp(ts);
      if (visemeEvt) broadcast({ type: "viseme", ...visemeEvt });
      // Prosody (optional)
      const pros: ProsodyEvent = { t_ms: ts.t_ms, pitch: ts.pitch, energy: ts.energy, speaking: true };
      broadcast({ type: "prosody", ...pros });
    },
  });
  sessions.set(session_id, { id: session_id, voice_id, avatar_id });
  res.json({
    session_id,
    webrtc: { url: "wss://your-sfu.example.com", token: "jwt" },
    labels: { viseme: "viseme", prosody: "prosody" },
  });
});

app.post("/session-live/:id/speak", async (req, res) => {
  // Send text to ElevenLabs streaming TTS (adapter handles barge-in)
  res.json({ ok: true });
});

app.post("/session-live/:id/stop", async (req, res) => {
  // barge-in stop
  res.json({ ok: true });
});

httpServer.listen(8787, () => {
  console.log("Orchestrator on http://localhost:8787  (WS debug: /ws)");
});
