// scripts/createIngress.mjs – saubere Version (einmaliger Import, korrekte Signatur)
import { IngressClient, IngressInput } from 'livekit-server-sdk';

const host   = process.env.LIVEKIT_URL;           // z.B. https://...livekit.cloud
const apiKey = process.env.LIVEKIT_API_KEY;
const secret = process.env.LIVEKIT_API_SECRET;

if (!host || !apiKey || !secret) {
  console.error('LIVEKIT_URL / LIVEKIT_API_KEY / LIVEKIT_API_SECRET fehlen');
  process.exit(1);
}

// sehr simples Arg-Parsing: --room, --name, --identity (Format --flag=value)
const args = Object.fromEntries(
  process.argv.slice(2)
    .map(s => s.split('='))
    .map(([k, v]) => [k.replace(/^--/, ''), v ?? true])
);

const room     = args.room || process.env.LK_ROOM || 'mt-test';
const name     = args.name || 'musetalk';
const identity = args.identity || 'musetalk-publisher';

try {
  const client = new IngressClient(host, apiKey, secret);

  // RTMP Ingress anlegen (neue SDK-Signatur: (inputType, options))
  const info = await client.createIngress(IngressInput.RTMP_INPUT, {
    roomName: room,
    participantIdentity: identity,
    participantName: name,
    name,
    enableTranscoding: true,
  });

  console.log('Ingress erstellt ✅');
  console.log('RTMP URL :', info.url);
  console.log('StreamKey:', info.streamKey);
  console.log('Publish  :', `${info.url}/${info.streamKey}`);
} catch (e) {
  console.error('Ingress-Erstellung fehlgeschlagen:', e?.message || e);
  process.exit(1);
}


