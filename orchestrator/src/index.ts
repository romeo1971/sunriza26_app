import express from "express";
import cors from "cors";
import { WebSocketServer, WebSocket as WS } from "ws";
import { createServer } from "http";
import { startElevenStream } from "./eleven_adapter.js";
import { VisemeMapper } from "./viseme_mapper.js";
import type { VisemeEvent, ProsodyEvent, SessionInfo } from "./types.js";
import { config } from "dotenv";

config(); // .env laden

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

// Clients tracking
const sessions = new Map<string, SessionInfo>();
const elevenStreams = new Map<string, WS>();

wss.on('connection', (ws) => {
  console.log('🔌 WebSocket client connected');
  ws.on('close', () => {
    console.log('🔌 WebSocket client disconnected');
  });
});

app.post("/avatarize-2d", async (req, res) => {
  // In Produktion: empfange multipart/form-data, rufe Python-CLI, hoste Assets
  // Hier stubben wir die Antwort
  const avatar_id = "schatzy";
  res.json({
    avatar_id,
    idle_url: `/static/${avatar_id}/idle.mp4`,
    atlas_url: `/static/${avatar_id}/atlas.png`,
    atlas_meta_url: `/static/${avatar_id}/atlas.json`,
    mask_url: `/static/${avatar_id}/mask.png`,
    roi: { x: 870, y: 1150, w: 480, h: 280 },
  });
});

app.post("/voice-clone", async (req, res) => {
  // Proxy zu ElevenLabs Voice Clone API
  const voice_id = process.env.ELEVENLABS_VOICE_ID || "demo-voice";
  res.json({ voice_id });
});

app.post("/session-live", async (req, res) => {
  const { avatar_id, voice_id } = req.body as { avatar_id: string; voice_id: string };
  const session_id = Math.random().toString(36).slice(2);
  
  console.log(`📡 Session erstellt: ${session_id}`);
  
  sessions.set(session_id, { id: session_id, voice_id, avatar_id });
  
  res.json({
    session_id,
    ws_url: `ws://localhost:8787/ws`,
    labels: { viseme: "viseme", prosody: "prosody" },
  });
});

app.post("/session-live/:id/speak", async (req, res) => {
  const { id } = req.params;
  const { text, barge_in } = req.body as { text: string; barge_in?: boolean };
  
  const session = sessions.get(id);
  if (!session) {
    return res.status(404).json({ error: "Session not found" });
  }
  
  console.log(`🗣️ Speak request: "${text.substring(0, 50)}..."`);
  
  try {
    const apiKey = process.env.ELEVENLABS_API_KEY;
    if (!apiKey) {
      console.error('❌ ELEVENLABS_API_KEY nicht in .env gefunden');
      return res.status(500).json({ error: "ElevenLabs API Key missing" });
    }
    
    // Start ElevenLabs streaming
    const mapper = new VisemeMapper();
    
    // Demo: Simuliere Viseme-Events (später echtes Streaming)
    // Für jetzt: Text durchgehen und Viseme simulieren
    simulateVisemes(text, mapper);
    
    res.json({ ok: true });
  } catch (e) {
    console.error('❌ Speak error:', e);
    res.status(500).json({ error: String(e) });
  }
});

// Simuliere Viseme-Events für Test (später durch echtes ElevenLabs Streaming ersetzen)
function simulateVisemes(text: string, mapper: VisemeMapper) {
  const words = text.split(' ');
  let t = 0;
  
  words.forEach((word, idx) => {
    setTimeout(() => {
      // Simuliere Phoneme für das Wort
      const phonemes = ["M", "B", "P", "AI", "O", "E"];
      const randomPhoneme = phonemes[Math.floor(Math.random() * phonemes.length)];
      
      const ts = {
        t_ms: Date.now() + t,
        phoneme: randomPhoneme,
        word: word,
        pitch: 200 + Math.random() * 50,
        energy: 0.5 + Math.random() * 0.3,
      };
      
      const visemeEvt = mapper.consumeTimestamp(ts);
      if (visemeEvt) {
        broadcast({ type: "viseme", ...visemeEvt });
      }
      
      const prosEvt: ProsodyEvent = {
        t_ms: ts.t_ms,
        pitch: ts.pitch,
        energy: ts.energy,
        speaking: true,
      };
      broadcast({ type: "prosody", ...prosEvt });
    }, t);
    
    t += 200 + Math.random() * 300; // 200-500ms pro Wort
  });
  
  // Ende-Event
  setTimeout(() => {
    broadcast({
      type: "prosody",
      t_ms: Date.now() + t,
      pitch: 0,
      energy: 0,
      speaking: false,
    });
  }, t + 500);
}

app.post("/session-live/:id/stop", async (req, res) => {
  const { id } = req.params;
  // barge-in stop
  console.log(`🛑 Stop request: ${id}`);
  res.json({ ok: true });
});

app.get("/health", (req, res) => {
  res.json({ status: "ok", service: "live-avatar-orchestrator" });
});

const PORT = process.env.ORCHESTRATOR_PORT || 8787;
httpServer.listen(PORT, () => {
  console.log(`🚀 Orchestrator läuft auf http://localhost:${PORT}`);
  console.log(`🔌 WebSocket Debug: ws://localhost:${PORT}/ws`);
});

