import WebSocket from "ws";
import type { TimestampEvent } from "./types.js";

/**
 * ElevenLabs WebSocket Text-to-Speech with Input Streaming
 * Official Protocol: https://elevenlabs.io/docs/websockets
 */
export function startElevenStream(opts: {
  voice_id: string;
  apiKey: string;
  text: string;
  onAudio: (pcm: Buffer) => void;
  onTimestamp: (ts: TimestampEvent) => void;
  onDone: () => void;
}) {
  return new Promise<WebSocket>((resolve, reject) => {
    const base = process.env.ELEVENLABS_BASE || "api.elevenlabs.io";
    const model = process.env.ELEVENLABS_MODEL_ID || "eleven_turbo_v2";
    
    // Official endpoint + Header xi-api-key (REQUIRED!)
    const url = `wss://${base}/v1/text-to-speech/${opts.voice_id}/stream-input?model_id=${model}&output_format=mp3_44100_128`;
    
    console.log(`🔗 Connecting to ElevenLabs: ${url}`);
    
    const ws = new WebSocket(url, {
      headers: { "xi-api-key": opts.apiKey }
    });

    ws.on("open", () => {
      console.log("✅ ElevenLabs connected");
      
      // Init-Frame (optional settings)
      const initMessage = {
        text: " ",
        voice_settings: {
          stability: 0.5,
          similarity_boost: 0.8,
          speed: 1,
        },
      };
      
      console.log("📤 Sending INIT");
      ws.send(JSON.stringify(initMessage));
      
      // TEXT SENDEN
      console.log("📤 Sending text:", opts.text);
      ws.send(JSON.stringify({ text: opts.text }));
      
      // EOS
      console.log("📤 Sending EOS");
      ws.send(JSON.stringify({ text: "" }));
      
      resolve(ws);
    });

    ws.on("message", (data) => {
      try {
        const msg = JSON.parse(data.toString());
        
        console.log("📩 ElevenLabs msg:", JSON.stringify(msg).substring(0, 200));
        
        // Audio chunk (base64 PCM 16kHz mono)
        if (msg.audio) {
          console.log("🔊 Audio chunk:", msg.audio.length, "chars");
          const audioBuffer = Buffer.from(msg.audio, "base64");
          opts.onAudio(audioBuffer);
        }
        
        // Alignment data (character timestamps)
        if (msg.alignment) {
          console.log("📝 Alignment:", JSON.stringify(msg.alignment));
          const chars = msg.alignment.chars || [];
          const charStartTimesMs = msg.alignment.charStartTimesMs || [];
          const charDurationsMs = msg.alignment.charDurationsMs || [];
          
          for (let i = 0; i < chars.length; i++) {
            opts.onTimestamp({
              t_ms: charStartTimesMs[i] || 0,
              phoneme: chars[i], // Character als Phoneme (wird zu Viseme gemappt)
              word: null,
              pitch: 0,
              energy: 0,
            });
          }
        }
        
        // Stream complete
        if (msg.isFinal) {
          console.log("✅ Stream complete");
          opts.onDone();
        }
        
        // Errors
        if (msg.error) {
          console.error("❌ ElevenLabs error:", msg.error);
        }
      } catch (e) {
        console.error("❌ Parse error:", e);
      }
    });

    ws.on("error", (err) => {
      console.error("❌ ElevenLabs WS error:", err);
      reject(err);
    });

    ws.on("close", (code, reason) => {
      const reasonStr = reason.toString();
      console.log(`🔌 ElevenLabs closed: ${code} ${reasonStr}`);
    });
  });
}
