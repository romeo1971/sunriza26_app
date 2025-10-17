// HTTP Server mit WebSocket Upgrade für Modal.com
import { createServer } from "http";
import { WebSocketServer, WebSocket } from "ws";
import { startElevenStream } from "./eleven_adapter.js";
import dotenv from "dotenv";

dotenv.config();

const PORT = parseInt(process.env.PORT || '3001', 10);

// HTTP Server für Modal
const server = createServer((req, res) => {
  // Health check
  if (req.url === '/health') {
    res.writeHead(200);
    res.end('OK');
  } else {
    res.writeHead(200);
    res.end('Lipsync Orchestrator');
  }
});

// WebSocket Server auf gleichem Port
const wss = new WebSocketServer({ server });

wss.on("connection", (clientWs: WebSocket) => {
  console.log("🎤 Lipsync client connected");
  let elevenWs: WebSocket | null = null;
  let idleTimer: NodeJS.Timeout | null = null;

  const resetIdle = () => {
    if (idleTimer) clearTimeout(idleTimer);
    idleTimer = setTimeout(() => {
      try { clientWs.send(JSON.stringify({ type: "done" })); } catch {}
      try { elevenWs?.close(); } catch {}
      try { clientWs.close(); } catch {}
    }, 15000);
  };

  clientWs.on("message", async (data) => {
    try {
      const msg = JSON.parse(data.toString());
      console.log("📨 Client msg:", JSON.stringify(msg));

      if (msg.type === "speak") {
        const voiceId = msg.voice_id;
        const text = msg.text;
        const apiKey = process.env.ELEVENLABS_API_KEY;

        console.log("🗣️ SPEAK:", { voiceId, text: text?.substring(0, 50) });

        if (!apiKey) {
          clientWs.send(JSON.stringify({ type: "error", message: "ELEVENLABS_API_KEY missing" }));
          return;
        }

        // Alte ElevenLabs-WS schließen (spart $)
        if (elevenWs) {
          try { elevenWs.close(); } catch {}
        }

        elevenWs = await startElevenStream({
          voice_id: voiceId,
          apiKey,
          text,
          onAudio: (pcm) => {
            resetIdle();
            try {
              clientWs.send(
                JSON.stringify({
                  type: "audio",
                  data: pcm.toString("base64"),
                  format: "mp3_44100_128",
                })
              );
            } catch {}
          },
          onTimestamp: (ts) => {
            resetIdle();
            const viseme = mapPhonemeToViseme(ts.phoneme ?? null);
            try {
              clientWs.send(
                JSON.stringify({
                  type: "viseme",
                  value: viseme,
                  pts_ms: ts.t_ms,
                  duration_ms: 100,
                })
              );
            } catch {}
          },
          onDone: () => {
            try {
              clientWs.send(JSON.stringify({ type: "done" }));
            } catch {}
          },
        });
      }

      if (msg.type === "stop") {
        elevenWs?.close();
        try { clientWs.send(JSON.stringify({ type: "done" })); } catch {}
        clientWs.close();
      }
    } catch (e) {
      console.error("❌ Lipsync handler error:", e);
    }
  });

  clientWs.on("close", () => {
    console.log("🔌 Lipsync client disconnected");
    elevenWs?.close();
    if (idleTimer) clearTimeout(idleTimer);
  });
});

function mapPhonemeToViseme(phoneme: string | null): string {
  if (!phoneme || phoneme === " ") return "Rest";

  const char = phoneme.toLowerCase();

  // Character → Viseme Mapping (ElevenLabs sendet chars, nicht phonemes!)
  const map: Record<string, string> = {
    // Vokale
    a: "AI",
    e: "E",
    i: "AI",
    o: "O",
    u: "U",
    ä: "E",
    ö: "O",
    ü: "U",
    // Konsonanten
    m: "MBP",
    b: "MBP",
    p: "MBP",
    f: "FV",
    v: "FV",
    w: "FV",
    l: "L",
    r: "R",
    s: "CH",
    z: "CH",
    sch: "CH",
    ch: "CH",
    j: "CH",
    g: "CH",
    k: "CH",
    t: "TH",
    d: "TH",
    n: "TH",
    h: "Rest",
    // Satzzeichen
    ".": "Rest",
    ",": "Rest",
    "!": "Rest",
    "?": "Rest",
  };

  return map[char] || "Rest";
}

server.listen(PORT, () => {
  console.log(`🚀 Lipsync Orchestrator läuft auf Port ${PORT}`);
});
