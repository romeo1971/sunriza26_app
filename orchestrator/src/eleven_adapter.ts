import WebSocket from "ws";
import type { TimestampEvent } from "./types.js";

/**
 * startElevenStream
 * Connects to ElevenLabs streaming endpoint and emits audio chunks + timestamp events.
 */
export function startElevenStream(opts: {
  voice_id: string;
  apiKey: string;
  onAudio: (pcm: Buffer) => void;
  onTimestamp: (ts: TimestampEvent) => void;
}) {
  return new Promise<WebSocket>((resolve, reject) => {
    const url = `wss://api.elevenlabs.io/v1/text-to-speech/${opts.voice_id}/stream`;
    const ws = new WebSocket(url, {
      headers: { "xi-api-key": opts.apiKey },
    });
    ws.on("open", () => {
      console.log("✅ ElevenLabs WebSocket connected");
      resolve(ws);
    });
    ws.on("message", (data) => {
      try {
        const msg = JSON.parse(data.toString());
        if (msg.type === "audio_chunk") {
          // PCM / Opus data (depending on endpoint) – forward to WebRTC track
          opts.onAudio(Buffer.from(msg.data, "base64"));
        } else if (msg.type === "timestamp") {
          // Example structure; adapt to actual payload (phoneme/word timings)
          const ts: TimestampEvent = {
            t_ms: msg.t_ms || Date.now(),
            phoneme: msg.phoneme || null,
            word: msg.word || null,
            pitch: msg.pitch ?? 0,
            energy: msg.energy ?? 0,
          };
          opts.onTimestamp(ts);
        }
      } catch (e) {
        console.error("❌ ElevenLabs message parse error:", e);
      }
    });
    ws.on("error", (err) => {
      console.error("❌ ElevenLabs WebSocket error:", err);
      reject(err);
    });
    ws.on("close", () => {
      console.log("🔌 ElevenLabs WebSocket closed");
    });
  });
}

