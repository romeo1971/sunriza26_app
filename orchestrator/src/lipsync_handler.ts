import { WebSocketServer, WebSocket } from "ws";
import { startElevenStream } from "./eleven_adapter.js";

const PORT = 3001;
const wss = new WebSocketServer({ port: PORT });

wss.on("connection", (clientWs: WebSocket) => {
  console.log("🎤 Lipsync client connected");
  let elevenWs: WebSocket | null = null;

  clientWs.on("message", async (data) => {
    try {
      const msg = JSON.parse(data.toString());

      if (msg.type === "speak") {
        const voiceId = msg.voice_id;
        const text = msg.text;
        const apiKey = process.env.ELEVENLABS_API_KEY;

        if (!apiKey) {
          clientWs.send(JSON.stringify({ type: "error", message: "ELEVENLABS_API_KEY missing" }));
          return;
        }

        elevenWs = await startElevenStream({
          voice_id: voiceId,
          apiKey,
          onAudio: (pcm) => {
            clientWs.send(
              JSON.stringify({
                type: "audio",
                data: pcm.toString("base64"),
                format: "pcm_16000",
              })
            );
          },
          onTimestamp: (ts) => {
            const viseme = mapPhonemeToViseme(ts.phoneme);
            clientWs.send(
              JSON.stringify({
                type: "viseme",
                value: viseme,
                pts_ms: ts.t_ms,
                duration_ms: 100,
              })
            );
          },
        });

        elevenWs.send(
          JSON.stringify({
            text,
            voice_settings: { stability: 0.5, similarity_boost: 0.75 },
          })
        );
      }

      if (msg.type === "stop") {
        elevenWs?.close();
      }
    } catch (e) {
      console.error("❌ Lipsync handler error:", e);
    }
  });

  clientWs.on("close", () => {
    console.log("🔌 Lipsync client disconnected");
    elevenWs?.close();
  });
});

function mapPhonemeToViseme(phoneme: string | null): string {
  if (!phoneme) return "Rest";

  const map: Record<string, string> = {
    ə: "E",
    ɚ: "E",
    ɝ: "E",
    ɛ: "E",
    e: "E",
    i: "AI",
    ɪ: "AI",
    iː: "AI",
    u: "U",
    ʊ: "U",
    uː: "U",
    o: "O",
    ɔ: "O",
    oː: "O",
    ɑ: "AI",
    aː: "AI",
    æ: "AI",
    m: "MBP",
    b: "MBP",
    p: "MBP",
    f: "FV",
    v: "FV",
    l: "L",
    w: "WQ",
    r: "R",
    θ: "TH",
    ð: "TH",
    ʃ: "CH",
    ʒ: "CH",
    tʃ: "CH",
    dʒ: "CH",
  };

  return map[phoneme] || "Rest";
}

console.log(`🚀 Lipsync Orchestrator läuft auf Port ${PORT}`);

