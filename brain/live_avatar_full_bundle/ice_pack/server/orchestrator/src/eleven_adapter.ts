import WebSocket from "ws";
import type { TimestampEvent } from "./types";

/**
 * startElevenStream
 * Connects to ElevenLabs streaming endpoint (pseudo URL) and emits audio chunks + timestamp events.
 * Replace URL/headers with your key and chosen voice model.
 */
export function startElevenStream(opts: {
  voice_id: string;
  onAudio: (pcm: Buffer) => void;
  onTimestamp: (ts: TimestampEvent) => void;
}) {
  return new Promise<WebSocket>((resolve, reject) => {
    const url = `wss://api.elevenlabs.io/v1/text-to-speech/${opts.voice_id}/stream`;
    const ws = new WebSocket(url, {
      headers: { "xi-api-key": process.env.ELEVEN_API_KEY || "" },
    });
    ws.on("open", () => resolve(ws));
    ws.on("message", (data) => {
      try {
        const msg = JSON.parse(data.toString());
        if (msg.type === "audio_chunk") {
          // PCM / Opus data (depending on endpoint) – forward to WebRTC track
          opts.onAudio(Buffer.from(msg.data, "base64"));
        } else if (msg.type === "timestamp") {
          // Example structure; adapt to actual payload (phoneme/word timings)
          const ts: TimestampEvent = {
            t_ms: msg.t_ms,
            phoneme: msg.phoneme || null,
            word: msg.word || null,
            pitch: msg.pitch ?? 0,
            energy: msg.energy ?? 0,
          };
          opts.onTimestamp(ts);
        }
      } catch {}
    });
    ws.on("error", reject);
  });
}
