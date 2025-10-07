/**
 * Haupt-Cloud Function für Live AI-Assistenten
 * Stand: 04.09.2025 - Mit geklonter Stimme und Echtzeit-Video-Lippensynchronisation
 */

import 'dotenv/config';
import * as functions from 'firebase-functions';
// admin ist bereits oben initialisiert
import cors from 'cors';
import { generateSpeech } from './textToSpeech';
import { generateLipsyncVideo, validateVideoRequest } from './vertexAI';
import { getConfig } from './config';
import { RAGService } from './rag_service';
// Entfernt: Unbenutzte Importe aus pinecone_service
import fetch from 'node-fetch';
import OpenAI from 'openai';
import * as admin from 'firebase-admin';
import { PassThrough } from 'stream';
import ffmpegPath from 'ffmpeg-static';
import ffmpeg from 'fluent-ffmpeg';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import sharp from 'sharp';
import * as functionsStorage from 'firebase-functions/v2/storage';

// Stripe Checkout für Credits
export * from './stripeCheckout';

// eRechnung Generator
export * from './invoiceGenerator';

// Media-Kauf (Credits oder Stripe)
export * from './mediaCheckout';

// Stripe Connect (Seller Marketplace)
export * from './stripeConnect';

// Payment Methods Management (Karten speichern)
export * from './paymentMethods';

// Firebase Admin initialisieren: lokal mit expliziten Credentials, in Cloud mit Default
if (process.env.GOOGLE_APPLICATION_CREDENTIALS || process.env.FIREBASE_CLIENT_EMAIL) {
  // Lokale Entwicklung: nutze Service-Account aus .env oder Datei
  const projectId = process.env.FIREBASE_PROJECT_ID || process.env.GOOGLE_CLOUD_PROJECT_ID;
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
  const privateKey = process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n');

  if (clientEmail && privateKey) {
    admin.initializeApp({
      credential: admin.credential.cert({
        projectId: projectId,
        clientEmail: clientEmail,
        privateKey: privateKey,
      }),
      projectId: projectId,
    });
  } else {
    // Fallback auf Datei, wenn gesetzt
    if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
      admin.initializeApp({
        credential: admin.credential.applicationDefault(),
        projectId: projectId,
      });
    } else {
      admin.initializeApp();
    }
  }
} else {
  // In Cloud Functions: Default Credentials
  admin.initializeApp();
}

// CORS für Cross-Origin Requests
const corsHandler = cors({ origin: true });


/**
 * Haupt-Cloud Function für Live-Video-Generierung
 * HTTP-Trigger für optimale Streaming-Kontrolle
 */
export const generateLiveVideo = functions
  .region('us-central1')
  .runWith({
    timeoutSeconds: 540, // 9 Minuten für komplexe Video-Generierung
    memory: '2GB', // Mehr RAM für Vertex AI
    secrets: [],
  })
  .https
  .onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
      try {
        console.log('=== Live Video Generation Request ===');
        console.log('Method:', req.method);
        console.log('Headers:', req.headers);
        
        // Nur POST Requests erlauben
        if (req.method !== 'POST') {
          res.status(405).json({ error: 'Nur POST Requests erlaubt' });
          return;
        }

        const { text } = req.body || {};
        
        if (!text || typeof text !== 'string') {
          res.status(400).json({ error: 'Text ist erforderlich' });
          return;
        }

        console.log(`Verarbeite Text: "${text.substring(0, 100)}..."`);

        // Konfiguration laden
        const config = await getConfig();
        console.log('Konfiguration geladen:', {
          projectId: config.projectId,
          location: config.location,
          customVoiceName: config.customVoiceName,
        });

        // Schritt 1: Text-to-Speech mit Custom Voice
        console.log('Schritt 1: Generiere Audio mit Custom Voice...');
        const ttsResponse = await generateSpeech({
          text: text,
          languageCode: 'de-DE',
          ssmlGender: 'NEUTRAL',
        });

        console.log(`Audio generiert: ${ttsResponse.audioContent.length} Bytes`);

        // Vertex AI Pfad für Video-Generierung
        console.log('Starte Vertex AI Video-Generierung...');
        // Schritt 2: Video-Lippensynchronisation mit Vertex AI
        console.log('Schritt 2: Starte Video-Lippensynchronisation...');
        const videoRequest = {
          audioBuffer: ttsResponse.audioContent,
          referenceVideoUrl: config.referenceVideoUrl,
          text: text,
          audioConfig: ttsResponse.audioConfig,
        };

        // Request validieren
        const validation = validateVideoRequest(videoRequest);
        if (!validation.isValid) {
          res.status(400).json({ error: validation.message });
          return;
        }

        const videoResponse = await generateLipsyncVideo(videoRequest);

        // Schritt 3: Live-Streaming an Client
        console.log('Schritt 3: Starte Live-Streaming...');
        
        // HTTP Headers für Video-Streaming setzen
        res.setHeader('Content-Type', videoResponse.contentType);
        res.setHeader('Cache-Control', 'no-cache');
        res.setHeader('Connection', 'keep-alive');
        res.setHeader('Transfer-Encoding', 'chunked');
        res.setHeader('X-Video-Metadata', JSON.stringify(videoResponse.metadata));
        
        // Status 200 für Streaming-Start
        res.status(200);

        // Debug: in GCS mitloggen und gleichzeitig an Client streamen
        const bucket2 = admin.storage().bucket();
        const debugPath = `debug/lipsync_${Date.now()}.mp4`;
        let signedUrl: string | null = null;
        const pass = new PassThrough();
        const gcsWrite = bucket2.file(debugPath).createWriteStream({ contentType: 'video/mp4' });
        pass.pipe(gcsWrite);
        gcsWrite.on('finish', async () => {
          try {
            const [url] = await bucket2.file(debugPath).getSignedUrl({ action: 'read', expires: Date.now() + 7*24*3600*1000 });
            signedUrl = url;
            console.log('Lipsync saved to:', url);
          } catch (e) {
            console.warn('Signed URL error:', e);
          }
        });

        // Video-Stream an Client weiterleiten und in pass schreiben
        videoResponse.videoStream.on('data', (chunk: any) => {
          res.write(chunk);
          pass.write(chunk);
        });

        videoResponse.videoStream.on('end', () => {
          pass.end();
          if (signedUrl) {
            try { res.setHeader('X-Video-URL', signedUrl); } catch {}
          }
          console.log('Video-Stream beendet', signedUrl ? `URL: ${signedUrl}` : '');
          res.end();
        });

        videoResponse.videoStream.on('error', (error: any) => {
          console.error('Stream-Fehler:', error);
          if (!res.headersSent) {
            res.status(500).json({ error: 'Stream-Fehler aufgetreten' });
          } else {
            res.end();
          }
        });

        // Client-Disconnect Handling
        req.on('close', () => {
          console.log('Client hat Verbindung getrennt');
          if ((videoResponse.videoStream as any).destroy) {
            (videoResponse.videoStream as any).destroy();
          }
        });

      } catch (error) {
        console.error('Fehler in generateLiveVideo:', error);
        
        if (!res.headersSent) {
          res.status(500).json({ 
            error: 'Interner Server-Fehler',
            details: error instanceof Error ? error.message : 'Unbekannter Fehler'
          });
        }
      }
    });
  });

/**
 * Health Check Endpoint
 */
export const healthCheck = functions
  .region('us-central1')
  .https
  .onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
      try {
        const config = await getConfig();
        
        res.status(200).json({
          status: 'healthy',
          timestamp: new Date().toISOString(),
          config: {
            projectId: config.projectId,
            location: config.location,
            hasCustomVoice: config.customVoiceName !== 'default-voice',
            hasReferenceVideo: config.referenceVideoUrl.includes('gs://'),
          },
        });
      } catch (error) {
        res.status(500).json({
          status: 'unhealthy',
          error: error instanceof Error ? error.message : 'Unbekannter Fehler',
        });
      }
    });
  });

/**
 * Test Endpoint für TTS (ohne Video)
 */
export const testTTS = functions
  .region('us-central1')
  .runWith({ secrets: ['ELEVENLABS_API_KEY','ELEVEN_VOICE_ID','ELEVEN_TTS_MODEL'] })
  .https
  .onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
      try {
        if (req.method !== 'POST') {
          res.status(405).json({ error: 'Nur POST Requests erlaubt' });
          return;
        }

        const { text, voiceId, modelId, stability, similarity } = req.body || {};
        
        if (!text) {
          res.status(400).json({ error: 'Text ist erforderlich' });
          return;
        }

        // 1) ElevenLabs bevorzugen, falls Key vorhanden
        const elevenKey = process.env.ELEVENLABS_API_KEY;
        if (elevenKey) {
          try {
            const effectiveVoiceId = (typeof voiceId === 'string' && voiceId.trim().length > 0)
              ? voiceId.trim()
              : (process.env.ELEVEN_VOICE_ID || '21m00Tcm4TlvDq8ikWAM');
            const effectiveModelId = (typeof modelId === 'string' && modelId.trim().length > 0)
              ? modelId.trim()
              : (process.env.ELEVEN_TTS_MODEL || 'eleven_multilingual_v2');
            const effStability = Number.isFinite(parseFloat(stability))
              ? parseFloat(stability)
              : parseFloat(process.env.ELEVEN_STABILITY || '0.5');
            const effSimilarity = Number.isFinite(parseFloat(similarity))
              ? parseFloat(similarity)
              : parseFloat(process.env.ELEVEN_SIMILARITY || '0.75');
            const r: any = await (globalThis as any).fetch(`https://api.elevenlabs.io/v1/text-to-speech/${effectiveVoiceId}` as any, {
              method: 'POST',
              headers: {
                'xi-api-key': elevenKey,
                'Content-Type': 'application/json',
                'Accept': 'audio/mpeg',
              } as any,
              body: JSON.stringify({
                text,
                model_id: effectiveModelId,
                voice_settings: { stability: effStability, similarity_boost: effSimilarity },
              }),
            } as any);
            if ((r as any).ok) {
              const ab = await (r as any).arrayBuffer();
              const buf = Buffer.from(ab);
              res.setHeader('Content-Type', 'audio/mpeg');
              res.setHeader('Content-Length', buf.length.toString());
              res.send(buf);
              return;
            } else {
              // Fehlerdetails ausgeben, damit wir wissen, warum ElevenLabs nicht liefert
              let errText = '';
              try {
                errText = await (r as any).text();
              } catch {}
              console.warn(`ElevenLabs antwortete mit Status ${r.status}: ${r.statusText} | ${errText?.slice(0,400)}`);
              throw new Error(`ElevenLabs HTTP ${r.status}`);
            }
          } catch (e) {
            console.warn('ElevenLabs TTS fehlgeschlagen, fallback auf Google TTS:', e);
          }
        }

        // 2) Fallback: Google TTS
        const ttsResponse = await generateSpeech({ text, languageCode: 'de-DE' });
        res.setHeader('Content-Type', 'audio/mpeg');
        res.setHeader('Content-Length', ttsResponse.audioContent.length.toString());
        res.send(ttsResponse.audioContent);

      } catch (error) {
        console.error('TTS Test Fehler:', error);
        res.status(500).json({ 
          error: 'TTS Fehler',
          details: error instanceof Error ? error.message : 'Unbekannter Fehler'
        });
      }
    });
  });

// Produktiver Alias: gleicher Handler wie testTTS, aber unter dem Namen "tts"
export const tts = testTTS;

/**
 * Storage-Cleaner: Löscht verwaiste Dateien und setzt fehlende thumbUrl für Dokumente
 * Aufruf: https://<region>-<project>.cloudfunctions.net/cleanStorageAndFixDocThumbs?avatarId=AVATAR_ID
 */
async function runCleanerForAvatar(avatarId: string) {
  const db = admin.firestore();
  const bucket = admin.storage().bucket();

  const mediaSnap = await db
    .collection('avatars')
    .doc(avatarId)
    .collection('media')
    .get();

  const referencedPaths = new Set<string>();
  const mediaDocs: Array<{ id: string; type: string; url?: string; thumbUrl?: string }> = [];

  const extractPath = (url?: string): string | null => {
    if (!url) return null;
    try {
      if (url.startsWith('gs://')) {
        const u = url.replace('gs://', '');
        const i = u.indexOf('/');
        return i >= 0 ? u.substring(i + 1) : null;
      }
      const u = new URL(url);
      if (u.hostname.includes('firebasestorage.googleapis.com')) {
        const m = u.pathname.match(/\/o\/(.+)$/);
        if (m && m[1]) {
          const p = m[1].split('?')[0];
          return decodeURIComponent(p);
        }
      }
    } catch (_) {}
    return null;
  };

  mediaSnap.forEach((d) => {
    const data = d.data() as any;
    mediaDocs.push({ id: d.id, type: data.type, url: data.url, thumbUrl: data.thumbUrl });
    const p1 = extractPath(data.url);
    const p2 = extractPath(data.thumbUrl);
    if (p1) referencedPaths.add(p1);
    if (p2) referencedPaths.add(p2);
  });

  // Delete only in allowed media folders
  const base = `avatars/${avatarId}/`;
  // SICHER: Lösche nur Thumbs – Originale nie automatisch löschen
  const allowed = [
    `${base}images/thumbs/`,
    `${base}videos/thumbs/`,
    `${base}documents/thumbs/`,
    `${base}audio/thumbs/`,
  ];

  const [files] = await bucket.getFiles({ prefix: base });
  let deleted = 0;
  for (const f of files) {
    const name = f.name;
    if (name.endsWith('/')) continue;
    if (!allowed.some((p) => name.startsWith(p))) continue; // skip non-media folders (e.g. playlists)
    if (!referencedPaths.has(name)) {
      try {
        await f.delete();
        deleted++;
      } catch (e) {
        console.warn('Delete failed for', name, e);
      }
    }
  }

  // Fix missing document thumbs from existing files
  let fixedThumbs = 0;
  for (const m of mediaDocs) {
    if (m.type !== 'document' || (m.thumbUrl && m.thumbUrl.length > 0)) continue;
    const thumbPrefix = `${base}documents/thumbs/${m.id}`;
    const [tfs] = await bucket.getFiles({ prefix: thumbPrefix });
    if (tfs && tfs.length > 0) {
      let latest = tfs[0];
      for (const f of tfs) {
        const a = new Date(latest.metadata?.updated || latest.metadata?.timeCreated || 0).getTime();
        const b = new Date(f.metadata?.updated || f.metadata?.timeCreated || 0).getTime();
        if (b > a) latest = f;
      }
      try {
        const [url] = await latest.getSignedUrl({ action: 'read', expires: Date.now() + 365*24*3600*1000 });
        await db
          .collection('avatars').doc(avatarId)
          .collection('media').doc(m.id)
          .update({ thumbUrl: url, aspectRatio: 9/16 });
        fixedThumbs++;
      } catch (e) {
        console.warn('Set thumb failed for', m.id, e);
      }
    }
  }

  return { deletedFiles: deleted, fixedDocumentThumbs: fixedThumbs, mediaCount: mediaDocs.length };
}

export const cleanStorageAndFixDocThumbs = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 540, memory: '1GB' })
  .https.onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
      try {
        const avatarId = (req.query.avatarId as string || '').trim();
        if (!avatarId) {
          res.status(400).json({ error: 'avatarId fehlt' });
          return;
        }
        const out = await runCleanerForAvatar(avatarId);
        res.status(200).json(out);
      } catch (e) {
        console.error('Cleaner error:', e);
        res.status(500).json({ error: (e as any)?.message || 'unknown' });
      }
    });
  });

// Scheduled daily cleanup for all avatars
export const scheduledStorageClean = functions
  .region('us-central1')
  .pubsub.schedule('30 3 * * 0') // wöchentlich So 03:30 UTC
  .timeZone('Etc/UTC')
  .onRun(async () => {
    const db = admin.firestore();
    const avatars = await db.collection('avatars').select('id').get();
    for (const doc of avatars.docs) {
      try {
        await runCleanerForAvatar(doc.id);
        // Re-run prune on playlists referencing this avatar
        // reserved: playlist-level maintenance can be added here if needed
      } catch (e) {
        console.warn('scheduled clean failed for', doc.id, e);
      }
    }
  });

// Manual trigger for all avatars (one-off)
export const cleanAllAvatarsNow = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 540, memory: '1GB' })
  .https.onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
      try {
        const db = admin.firestore();
        const avatars = await db.collection('avatars').select('id').get();
        const results: any[] = [];
        for (const doc of avatars.docs) {
          const r = await runCleanerForAvatar(doc.id);
          results.push({ avatarId: doc.id, ...r });
        }
        res.status(200).json({ results });
      } catch (e) {
        res.status(500).json({ error: (e as any)?.message || 'unknown' });
      }
    });
  });

// Backfill: setze fehlende thumbUrl für Bilder/Videos (auf Original-URL) und für Dokumente aus Storage-Thumbs
async function runBackfillThumbsForAvatar(avatarId: string) {
  const db = admin.firestore();
  const bucket = admin.storage().bucket();
  const snap = await db.collection('avatars').doc(avatarId).collection('media').get();
  let updated = 0;
  for (const d of snap.docs) {
    const m = d.data() as any;
    if (!m) continue;
    if ((!m.thumbUrl || m.thumbUrl.length === 0)) {
      if (m.type === 'image' || m.type === 'video') {
        if (typeof m.url === 'string' && m.url.length > 0) {
          await d.ref.update({ thumbUrl: m.url });
          updated++;
        }
      } else if (m.type === 'document') {
        const prefix = `avatars/${avatarId}/documents/thumbs/${d.id}`;
        const [tfs] = await bucket.getFiles({ prefix });
        if (tfs && tfs.length > 0) {
          let latest = tfs[0];
          for (const f of tfs) {
            const a = new Date(latest.metadata?.updated || latest.metadata?.timeCreated || 0).getTime();
            const b = new Date(f.metadata?.updated || f.metadata?.timeCreated || 0).getTime();
            if (b > a) latest = f;
          }
          const [url] = await latest.getSignedUrl({ action: 'read', expires: Date.now() + 365*24*3600*1000 });
          await d.ref.update({ thumbUrl: url });
          updated++;
        }
      }
    }
  }
  return { updatedThumbs: updated, mediaCount: snap.size };
}

export const backfillThumbsAllAvatars = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 540, memory: '1GB' })
  .https.onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
      try {
        const db = admin.firestore();
        const avatars = await db.collection('avatars').select('id').get();
        const results: any[] = [];
        for (const doc of avatars.docs) {
          const r = await runBackfillThumbsForAvatar(doc.id);
          results.push({ avatarId: doc.id, ...r });
        }
        res.status(200).json({ results });
      } catch (e) {
        res.status(500).json({ error: (e as any)?.message || 'unknown' });
      }
    });
  });

export const scheduledBackfillThumbs = functions
  .region('us-central1')
  .pubsub.schedule('15 4 * * 0') // wöchentlich So 04:15 UTC
  .timeZone('Etc/UTC')
  .onRun(async () => {
    const db = admin.firestore();
    const avatars = await db.collection('avatars').select('id').get();
    for (const doc of avatars.docs) {
      try { await runBackfillThumbsForAvatar(doc.id); } catch {}
    }
  });

// Backfill: setzt fehlende Audio-Thumbs (Platzhalter: nutzt Audio-URL als thumbUrl)
async function runBackfillAudioThumbsForAvatar(avatarId: string) {
  const db = admin.firestore();
  const snap = await db.collection('avatars').doc(avatarId).collection('media')
    .where('type','==','audio').get();
  let updated = 0;
  for (const d of snap.docs) {
    const m = d.data() as any;
    const has = typeof m.thumbUrl === 'string' && m.thumbUrl.length > 0;
    if (!has && typeof m.url === 'string' && m.url.length > 0) {
      await d.ref.set({ thumbUrl: m.url, aspectRatio: 16/9 }, { merge: true });
      updated++;
    }
  }
  return { updatedAudioThumbs: updated, audioCount: snap.size };
}

export const backfillAudioThumbsAllAvatars = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 540, memory: '1GB' })
  .https.onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
      try {
        const db = admin.firestore();
        const avatars = await db.collection('avatars').select('id').get();
        const results: any[] = [];
        for (const doc of avatars.docs) {
          const r = await runBackfillAudioThumbsForAvatar(doc.id);
          results.push({ avatarId: doc.id, ...r });
        }
        res.status(200).json({ results });
      } catch (e) {
        res.status(500).json({ error: (e as any)?.message || 'unknown' });
      }
    });
  });

export const scheduledBackfillAudioThumbs = functions
  .region('us-central1')
  .pubsub.schedule('45 4 * * 0') // wöchentlich So 04:45 UTC
  .timeZone('Etc/UTC')
  .onRun(async () => {
    const db = admin.firestore();
    const avatars = await db.collection('avatars').select('id').get();
    for (const doc of avatars.docs) {
      try { await runBackfillAudioThumbsForAvatar(doc.id); } catch {}
    }
  });

// Erzeuge und setze echte Audio-Waveform-PNG als thumbUrl
async function createWaveThumb(avatarId: string, mediaId: string, audioUrl: string) {
  if (ffmpegPath) (ffmpeg as any).setFfmpegPath(ffmpegPath);
  const tmpDir = os.tmpdir();
  const src = path.join(tmpDir, `${mediaId}.audio`);
  const out = path.join(tmpDir, `${mediaId}.png`);
  const res = await (fetch as any)(audioUrl);
  if (!(res as any).ok) throw new Error(`download audio failed ${res.status}`);
  const buf = Buffer.from(await (res as any).arrayBuffer());
  fs.writeFileSync(src, buf);
  await new Promise<void>((resolve, reject) => {
    (ffmpeg as any)(src)
      .complexFilter(['showwavespic=s=800x180:colors=0xFFFFFF'])
      .frames(1)
      .on('end', () => resolve())
      .on('error', (e: any) => reject(e))
      .save(out);
  });
  const bucket = admin.storage().bucket();
  const dest = `avatars/${avatarId}/audio/thumbs/${mediaId}.png`;
  await bucket.upload(out, {
    destination: dest,
    contentType: 'image/png',
    metadata: { cacheControl: 'public,max-age=31536000,immutable' },
  });
  const [signed] = await bucket.file(dest).getSignedUrl({ action: 'read', expires: Date.now() + 365*24*3600*1000 });
  try { fs.unlinkSync(src); } catch {}
  try { fs.unlinkSync(out); } catch {}
  await admin.firestore().collection('avatars').doc(avatarId)
    .collection('media').doc(mediaId)
    .set({ thumbUrl: signed, aspectRatio: 800/180 }, { merge: true });
  return signed;
}

export const backfillAudioWaveforms = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 540, memory: '2GB' })
  .https.onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
      try {
        const avatarId = (req.query.avatarId as string || '').trim();
        if (!avatarId) { res.status(400).json({ error: 'avatarId fehlt' }); return; }
        const db = admin.firestore();
        const qs = await db.collection('avatars').doc(avatarId).collection('media')
          .where('type','==','audio').get();
        let created = 0;
        for (const d of qs.docs) {
          const m = d.data() as any;
          if (!m || !m.url) continue;
          const has = typeof m.thumbUrl === 'string' && m.thumbUrl.length > 0;
          if (has) continue;
          try { await createWaveThumb(avatarId, d.id, m.url); created++; } catch (e) { console.warn('waveform fail', d.id, e); }
        }
        res.status(200).json({ avatarId, created, total: qs.size });
      } catch (e) {
        res.status(500).json({ error: (e as any)?.message || 'unknown' });
      }
    });
  });

// Video: Thumb aus erstem Frame generieren, wenn nicht vorhanden
async function createVideoThumbFromFirstFrame(avatarId: string, mediaId: string, videoUrl: string) {
  if (ffmpegPath) (ffmpeg as any).setFfmpegPath(ffmpegPath);
  const tmpDir = os.tmpdir();
  const src = path.join(tmpDir, `${mediaId}.mp4`);
  const out = path.join(tmpDir, `${mediaId}.jpg`);
  // Download Video (kurz, reicht für Frame)
  const res = await (fetch as any)(videoUrl);
  if (!(res as any).ok) throw new Error(`download video failed ${(res as any).status}`);
  const buf = Buffer.from(await (res as any).arrayBuffer());
  fs.writeFileSync(src, buf);
  
  // Extrahiere Video-Dimensionen mit FFprobe
  let aspectRatio = 16/9; // Fallback
  try {
    const metadata: any = await new Promise((resolve, reject) => {
      (ffmpeg as any).ffprobe(src, (err: any, data: any) => {
        if (err) reject(err);
        else resolve(data);
      });
    });
    const videoStream = metadata?.streams?.find((s: any) => s.codec_type === 'video');
    if (videoStream?.width && videoStream?.height) {
      aspectRatio = videoStream.width / videoStream.height;
      console.log(`Video dimensions: ${videoStream.width}x${videoStream.height}, aspectRatio: ${aspectRatio}`);
    }
  } catch (e) {
    console.warn('Failed to extract video dimensions, using fallback 16/9', e);
  }
  
  await new Promise<void>((resolve, reject) => {
    (ffmpeg as any)(src)
      .on('end', () => resolve())
      .on('error', (e: any) => reject(e))
      .screenshots({
        count: 1,
        timemarks: ['0.5'],
        filename: path.basename(out),
        folder: tmpDir,
      });
  });
  const bucket = admin.storage().bucket();
  const dest = `avatars/${avatarId}/videos/thumbs/${mediaId}_${Date.now()}.jpg`;
  await bucket.upload(out, {
    destination: dest,
    contentType: 'image/jpeg',
    metadata: { cacheControl: 'public,max-age=31536000,immutable' },
  });
  const [signed] = await bucket.file(dest).getSignedUrl({ action: 'read', expires: Date.now() + 365*24*3600*1000 });
  try { fs.unlinkSync(src); } catch {}
  try { fs.unlinkSync(out); } catch {}
  await admin.firestore().collection('avatars').doc(avatarId)
    .collection('media').doc(mediaId)
    .set({ thumbUrl: signed, aspectRatio }, { merge: true });
  return signed;
}

// STORAGE TRIGGERS: Thumbs für Details-Screen Uploads (direkter Storage-Upload)
function parseAvatarPath(objectName: string | undefined) {
  if (!objectName) return null;
  // erwartet: avatars/<avatarId>/(images|videos)/...
  const parts = objectName.split('/');
  if (parts.length < 4) return null;
  if (parts[0] !== 'avatars') return null;
  const avatarId = parts[1];
  const kind = parts[2];
  const inThumbs = parts.length >= 4 && parts[3] === 'thumbs';
  return { avatarId, kind, inThumbs, fileName: parts[parts.length - 1], objectName };
}

export const onImageObjectFinalize = functionsStorage.onObjectFinalized({ region: 'europe-west9' }, async (event) => {
  try {
    const obj = parseAvatarPath(event.data.name);
    if (!obj) return;
    if (obj.kind !== 'images') return;
    if (obj.inThumbs) return; // keine Thumbs für Thumbs
    const bucket = admin.storage().bucket(event.data.bucket);
    const [bytes] = await bucket.file(obj.objectName!).download();
    // Crop auf 9:16/16:9 wie in Galerie
    const meta = await sharp(bytes).metadata();
    const ar = (meta.width || 1) / (meta.height || 1);
    const targetAR = ar < 1.0 ? 9/16 : 16/9;
    let width = meta.width || 0;
    let height = meta.height || 0;
    if (width <= 0 || height <= 0) return;
    let cropW = width;
    let cropH = Math.round(width / targetAR);
    if (cropH > height) { cropH = height; cropW = Math.round(cropH * targetAR); }
    const left = Math.max(0, Math.floor((width - cropW) / 2));
    const top = Math.max(0, Math.floor((height - cropH) / 2));
    const out = await sharp(bytes).extract({ left, top, width: cropW, height: cropH }).resize(720).jpeg({ quality: 80 }).toBuffer();
    const base = obj.fileName.replace(/\.[^.]+$/, '');
    const dest = `avatars/${obj.avatarId}/images/thumbs/${base}_thumb.jpg`;
    await bucket.file(dest).save(out, { contentType: 'image/jpeg', metadata: { cacheControl: 'public,max-age=31536000,immutable' }});
  } catch (e) {
    console.warn('onImageObjectFinalize error', e);
  }
});

export const onVideoObjectFinalize = functionsStorage.onObjectFinalized({ region: 'europe-west9' }, async (event) => {
  try {
    const obj = parseAvatarPath(event.data.name);
    if (!obj) return;
    if (obj.kind !== 'videos') return;
    if (obj.inThumbs) return;
    const bucket = admin.storage().bucket(event.data.bucket);
    const tmpDir = os.tmpdir();
    const src = path.join(tmpDir, `${Date.now()}_${obj.fileName}`);
    const out = path.join(tmpDir, `${Date.now()}_${obj.fileName}.jpg`);
    await bucket.file(obj.objectName!).download({ destination: src });
    if (ffmpegPath) (ffmpeg as any).setFfmpegPath(ffmpegPath);
    await new Promise<void>((resolve, reject) => {
      (ffmpeg as any)(src)
        .on('end', () => resolve())
        .on('error', (e: any) => reject(e))
        .screenshots({ count: 1, timemarks: ['0.5'], filename: path.basename(out), folder: tmpDir });
    });
    const base = obj.fileName.replace(/\.[^.]+$/, '');
    const dest = `avatars/${obj.avatarId}/videos/thumbs/${base}_thumb.jpg`;
    await bucket.upload(out, { destination: dest, contentType: 'image/jpeg', metadata: { cacheControl: 'public,max-age=31536000,immutable' }});
    try { fs.unlinkSync(src); } catch {}
    try { fs.unlinkSync(out); } catch {}
  } catch (e) {
    console.warn('onVideoObjectFinalize error', e);
  }
});

// Storage-Delete: zugehörige Thumbs löschen
export const onMediaObjectDelete = functionsStorage.onObjectDeleted({ region: 'europe-west9' }, async (event) => {
  try {
    const obj = parseAvatarPath(event.data.name);
    if (!obj) return;
    if (obj.inThumbs) return; // Thumb gelöscht → keine Aktion
    const bucket = admin.storage().bucket(event.data.bucket);
    const base = obj.fileName.replace(/\.[^.]+$/, '');
    const prefix = `avatars/${obj.avatarId}/${obj.kind}/thumbs/${base}_`;
    const [files] = await bucket.getFiles({ prefix });
    await Promise.all(files.map(f => f.delete().catch(() => {})));
    if (obj.kind === 'images' && obj.fileName === 'heroImage.jpg') {
      try {
        const avatarRef = admin.firestore().collection('avatars').doc(obj.avatarId);
        await avatarRef.update({ avatarImageUrl: admin.firestore.FieldValue.delete() });
      } catch {}
    }
  } catch (e) {
    console.warn('onMediaObjectDelete error', e);
  }
});
// Video: Vorhandenes Poster/Platzhalterbild in Storage kopieren und als Thumb setzen
async function copyExistingVideoThumbToStorage(avatarId: string, mediaId: string, imageUrl: string) {
  const res = await (fetch as any)(imageUrl);
  if (!(res as any).ok) throw new Error(`download image failed ${(res as any).status}`);
  const buf = Buffer.from(await (res as any).arrayBuffer());
  const bucket = admin.storage().bucket();
  const dest = `avatars/${avatarId}/videos/thumbs/${mediaId}_${Date.now()}.jpg`;
  await bucket.file(dest).save(buf, { contentType: 'image/jpeg', metadata: { cacheControl: 'public,max-age=31536000,immutable' }});
  const [signed] = await bucket.file(dest).getSignedUrl({ action: 'read', expires: Date.now() + 365*24*3600*1000 });
  await admin.firestore().collection('avatars').doc(avatarId)
    .collection('media').doc(mediaId)
    .set({ thumbUrl: signed }, { merge: true });
  return signed;
}

// Firestore Trigger: Wenn erstes Bild hochgeladen wird, setze es als avatarImageUrl
export const onMediaCreateSetAvatarImage = functions
  .region('us-central1')
  .firestore.document('avatars/{avatarId}/media/{mediaId}')
  .onCreate(async (snap, ctx) => {
    try {
      const data = snap.data() as any;
      const avatarId = ctx.params.avatarId as string;
      if (!data || data.type !== 'image') return;
      const db = admin.firestore();
      const avatarRef = db.collection('avatars').doc(avatarId);
      const avatar = await avatarRef.get();
      const currentUrl = (avatar.data() as any)?.avatarImageUrl as string | undefined;
      if (currentUrl && currentUrl.trim().length > 0) return; // bereits gesetzt
      // Prüfe, ob dies das einzige Bild ist
      const imgs = await avatarRef.collection('media').where('type','==','image').limit(2).get();
      if (imgs.size === 1 && imgs.docs[0].id === snap.id) {
        const url = data.url as string | undefined;
        if (url && url.length > 0) {
          await avatarRef.update({ avatarImageUrl: url, updatedAt: Date.now() });
        }
      }
    } catch (e) {
      console.warn('onMediaCreateSetAvatarImage error', e);
    }
  });

// Firestore Trigger: Bei Audio-Upload fehlende thumbUrl sofort setzen (Platzhalter: url)
export const onMediaCreateSetAudioThumb = functions
  .region('us-central1')
  .firestore.document('avatars/{avatarId}/media/{mediaId}')
  .onCreate(async (snap, ctx) => {
    try {
      const data = snap.data() as any;
      if (!data || data.type !== 'audio') return;
      const url = data.url as string | undefined;
      if (!url || url.length === 0) return;
      // Erzeuge echte Waveform sofort
      try {
        await createWaveThumb(ctx.params.avatarId as string, snap.id, url);
      } catch (e) {
        // Fallback: setze zumindest die Audio-URL als Thumb
        await snap.ref.set({ thumbUrl: url, aspectRatio: 16/9 }, { merge: true });
      }
    } catch (e) {
      console.warn('onMediaCreateSetAudioThumb error', e);
    }
  });

// Firestore Trigger: Bei Image-Upload erstelle Thumb (9:16 oder 16:9 zugeschnitten)
export const onMediaCreateSetImageThumb = functions
  .region('us-central1')
  .firestore.document('avatars/{avatarId}/media/{mediaId}')
  .onCreate(async (snap, ctx) => {
    try {
      const data = snap.data() as any;
      if (!data || data.type !== 'image') return;
      if (data.thumbUrl) return;
      const avatarId = ctx.params.avatarId as string;
      const mediaId = ctx.params.mediaId as string;
      const url = data.url as string | undefined;
      if (!url) return;
      // Lade Bytes: unterstütze sowohl https Download-URLs als auch gs:// Pfade
      let buf: Buffer | null = null;
      try {
        if (url.startsWith('gs://')) {
          const u = url.replace('gs://', '');
          const i = u.indexOf('/');
          const pathOnly = i >= 0 ? u.substring(i + 1) : '';
          const [bytes] = await admin.storage().bucket().file(pathOnly).download();
          buf = Buffer.from(bytes);
        } else {
          const res = await (fetch as any)(url);
          if ((res as any).ok) buf = Buffer.from(await (res as any).arrayBuffer());
        }
      } catch (e) {
        console.warn('image fetch failed', e);
      }
      if (!buf) return;
      const meta = await sharp(buf).metadata();
      const ar = (meta.width || 1) / (meta.height || 1);
      const portrait = ar < 1.0;
      const targetAR = portrait ? 9/16 : 16/9;
      // zentriertes Crop auf targetAR
      let width = meta.width || 0;
      let height = meta.height || 0;
      if (width <= 0 || height <= 0) return;
      let cropW = width;
      let cropH = Math.round(width / targetAR);
      if (cropH > height) {
        cropH = height;
        cropW = Math.round(cropH * targetAR);
      }
      const left = Math.max(0, Math.floor((width - cropW) / 2));
      const top = Math.max(0, Math.floor((height - cropH) / 2));
      const outBuf = await sharp(buf)
        .extract({ left, top, width: cropW, height: cropH })
        .resize(720)
        .jpeg({ quality: 80 })
        .toBuffer();
      const bucket = admin.storage().bucket();
      const dest = `avatars/${avatarId}/images/thumbs/${mediaId}_${Date.now()}.jpg`;
      await bucket.file(dest).save(outBuf, { contentType: 'image/jpeg', metadata: { cacheControl: 'public,max-age=31536000,immutable' }});
      const [signed] = await bucket.file(dest).getSignedUrl({ action: 'read', expires: Date.now() + 365*24*3600*1000 });
      await snap.ref.set({ thumbUrl: signed, aspectRatio: targetAR }, { merge: true });
    } catch (e) {
      console.warn('onMediaCreateSetImageThumb error', e);
    }
  });

// Firestore Trigger: Bei Video-Upload versuche vorhandenes Storage-Thumb zu setzen
export const onMediaCreateSetVideoThumb = functions
  .region('us-central1')
  .firestore.document('avatars/{avatarId}/media/{mediaId}')
  .onCreate(async (snap, ctx) => {
    try {
      const data = snap.data() as any;
      if (!data || data.type !== 'video') return;
      const avatarId = ctx.params.avatarId as string;
      const mediaId = ctx.params.mediaId as string;
      const bucket = admin.storage().bucket();
      const prefix = `avatars/${avatarId}/videos/thumbs/${mediaId}`;
      const [items] = await bucket.getFiles({ prefix });
      if (items.length > 0) {
        const f = items[0];
        const [signed] = await f.getSignedUrl({ action: 'read', expires: Date.now() + 365*24*3600*1000 });
        await snap.ref.set({ thumbUrl: signed }, { merge: true });
        return;
      }
      // Wenn bereits ein externes Poster/Platzhalterbild existiert → in Storage übernehmen
      if (typeof data.thumbUrl === 'string' && data.thumbUrl.length > 0) {
        try {
          await copyExistingVideoThumbToStorage(avatarId, mediaId, data.thumbUrl as string);
          return;
        } catch (e) {
          console.warn('copyExistingVideoThumbToStorage failed, fallback to frame grab', e);
        }
      }
      // Falls kein Storage-Thumb existiert: generiere aus erstem Frame
      if (typeof data.url === 'string' && data.url.length > 0) {
        await createVideoThumbFromFirstFrame(avatarId, mediaId, data.url);
      }
    } catch (e) {
      console.warn('onMediaCreateSetVideoThumb error', e);
    }
  });
// Backfill: Korrigiere aspectRatio für alle Videos basierend auf echten Dimensionen
export const fixVideoAspectRatios = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 540, memory: '2GB' })
  .https.onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
      try {
        if (ffmpegPath) (ffmpeg as any).setFfmpegPath(ffmpegPath);
        const db = admin.firestore();
        const avatars = await db.collection('avatars').get();
        const results: any[] = [];
        
        for (const avatarDoc of avatars.docs) {
          const avatarId = avatarDoc.id;
          const mediaSnap = await db.collection('avatars').doc(avatarId)
            .collection('media')
            .where('type', '==', 'video')
            .get();
          
          for (const mediaDoc of mediaSnap.docs) {
            const data = mediaDoc.data() as any;
            const mediaId = mediaDoc.id;
            const videoUrl = data.url as string;
            
            if (!videoUrl) {
              results.push({ avatarId, mediaId, status: 'no_url' });
              continue;
            }
            
            try {
              // Download Video temporär
              const tmpDir = os.tmpdir();
              const src = path.join(tmpDir, `${mediaId}_fix.mp4`);
              const res = await (fetch as any)(videoUrl);
              if (!(res as any).ok) {
                results.push({ avatarId, mediaId, status: 'download_failed' });
                continue;
              }
              const buf = Buffer.from(await (res as any).arrayBuffer());
              fs.writeFileSync(src, buf);
              
              // Extrahiere Video-Dimensionen
              const metadata: any = await new Promise((resolve, reject) => {
                (ffmpeg as any).ffprobe(src, (err: any, data: any) => {
                  if (err) reject(err);
                  else resolve(data);
                });
              });
              
              const videoStream = metadata?.streams?.find((s: any) => s.codec_type === 'video');
              if (videoStream?.width && videoStream?.height) {
                const aspectRatio = videoStream.width / videoStream.height;
                const oldAR = data.aspectRatio;
                
                // Update in Firestore
                await mediaDoc.ref.update({ aspectRatio });
                
                // Cleanup
                try { fs.unlinkSync(src); } catch {}
                
                results.push({
                  avatarId,
                  mediaId,
                  status: 'updated',
                  oldAspectRatio: oldAR,
                  newAspectRatio: aspectRatio,
                  dimensions: `${videoStream.width}x${videoStream.height}`,
                });
                console.log(`✅ Fixed ${avatarId}/${mediaId}: ${oldAR} → ${aspectRatio}`);
              } else {
                try { fs.unlinkSync(src); } catch {}
                results.push({ avatarId, mediaId, status: 'no_dimensions' });
              }
            } catch (e: any) {
              results.push({ avatarId, mediaId, status: 'error', error: e.message });
            }
          }
        }
        
        res.status(200).json({ success: true, results, total: results.length });
      } catch (e: any) {
        res.status(500).json({ error: e.message });
      }
    });
  });

// Restore/Set avatar cover images if missing or broken
export const restoreAvatarCovers = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 540, memory: '1GB' })
  .https.onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
      try {
        const db = admin.firestore();
        const bucket = admin.storage().bucket();
        const avatars = await db.collection('avatars').get();
        const out: any[] = [];
        for (const doc of avatars.docs) {
          const data = doc.data() as any;
          let needsFix = false;
          const url = data.avatarImageUrl as string | undefined;
          if (!url || url.trim().length === 0) needsFix = true;
          else {
            try {
              const r = await (fetch as any)(url, { method: 'HEAD' });
              if (!(r as any).ok) needsFix = true;
            } catch {
              needsFix = true;
            }
          }

          if (!needsFix) { out.push({ id: doc.id, status: 'ok' }); continue; }

          // 1) Versuche neuestes Bild unter avatars/<id>/images/
          const prefix = `avatars/${doc.id}/images/`;
          const [files] = await bucket.getFiles({ prefix });
          let chosen: any = null;
          for (const f of files) {
            if (f.name.endsWith('/')) continue;
            if (f.name.includes('/thumbs/')) continue;
            if (!chosen) { chosen = f; continue; }
            const a = new Date(chosen.metadata?.updated || chosen.metadata?.timeCreated || 0).getTime();
            const b = new Date(f.metadata?.updated || f.metadata?.timeCreated || 0).getTime();
            if (b > a) chosen = f;
          }
          // 2) Falls nichts gefunden, nimm erstes Bild aus media collection
          if (!chosen) {
            const ms = await db.collection('avatars').doc(doc.id).collection('media').where('type','==','image').limit(1).get();
            const m = ms.docs[0]?.data() as any;
            if (m?.url) {
              await doc.ref.update({ avatarImageUrl: m.url, updatedAt: Date.now() });
              out.push({ id: doc.id, status: 'setFromMediaUrl' });
              continue;
            }
          }
          if (chosen) {
            try {
              const [signed] = await chosen.getSignedUrl({ action: 'read', expires: Date.now() + 365*24*3600*1000 });
              await doc.ref.update({ avatarImageUrl: signed, updatedAt: Date.now() });
              out.push({ id: doc.id, status: 'setFromStorage', file: chosen.name });
            } catch (e) {
              out.push({ id: doc.id, status: 'failedSet', error: (e as any)?.message });
            }
          } else {
            out.push({ id: doc.id, status: 'noImageFound' });
          }
        }
        res.status(200).json({ results: out });
      } catch (e) {
        res.status(500).json({ error: (e as any)?.message || 'unknown' });
      }
    });
  });

/**
 * LLM Router: OpenAI primär (gpt-4o-mini), Gemini Fallback
 * Body: { messages: [{role:'system'|'user'|'assistant', content:string}], maxTokens?, temperature? }
 */
export const llm = functions
  .region('us-central1')
  .runWith({ secrets: ['OPENAI_API_KEY', 'GEMINI_API_KEY'] })
  .https.onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
      try {
        if (req.method !== 'POST') {
          res.status(405).json({ error: 'Nur POST Requests erlaubt' });
          return;
        }
        const { messages, maxTokens, temperature } = req.body || {};
        if (!Array.isArray(messages) || messages.length === 0) {
          res.status(400).json({ error: 'messages[] ist erforderlich' });
          return;
        }
        // OpenAI primär
        const openaiKey = process.env.OPENAI_API_KEY;
        const geminiKey = process.env.GEMINI_API_KEY;
        const joined = messages
          .map((m: any) => `${m.role || 'user'}: ${m.content || ''}`)
          .join('\n');

        const tryOpenAI = async () => {
          if (!openaiKey) throw new Error('OPENAI_API_KEY fehlt');
          const client = new OpenAI({ apiKey: openaiKey });
          const resp = await client.chat.completions.create({
            model: 'gpt-4o-mini',
            messages: messages.map((m: any) => ({ role: m.role, content: m.content })),
            max_tokens: maxTokens || 300,
            temperature: temperature ?? 0.6,
          });
          const text = resp.choices?.[0]?.message?.content || '';
          return text.trim();
        };

        const tryGemini = async () => {
          if (!geminiKey) throw new Error('GEMINI_API_KEY fehlt');
          const url = `https://generativelanguage.googleapis.com/v1/models/gemini-1.5-flash:generateContent?key=${geminiKey}`;
          const body = {
            contents: [
              {
                parts: [{ text: joined }],
              },
            ],
            generationConfig: {
              temperature: temperature ?? 0.6,
              maxOutputTokens: maxTokens || 300,
            },
          } as any;
          const r = await (fetch as any)(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
          });
          if (!(r as any).ok) throw new Error(`Gemini HTTP ${(r as any).status}`);
          const j = await (r as any).json();
          const text = j?.candidates?.[0]?.content?.parts?.[0]?.text || '';
          return (text as string).trim();
        };

        let answer = '';
        try {
          answer = await tryOpenAI();
        } catch (e) {
          console.warn('OpenAI Fehler, fallback auf Gemini:', e);
          answer = await tryGemini();
        }
        res.status(200).json({ answer });
      } catch (error) {
        console.error('LLM Router Fehler:', error);
        res.status(500).json({
          error: 'LLM Fehler',
          details: error instanceof Error ? error.message : 'Unbekannter Fehler',
        });
      }
    });
  });

/**
 * Talking-Head: Jobs anlegen / Status / Callback
 * Firestore: collection 'renderJobs/{jobId}'
 */
export const createTalkingHeadJob = functions
  .region('us-central1')
  .https.onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
      try {
        if (req.method !== 'POST') {
          res.status(405).json({ error: 'Nur POST Requests erlaubt' });
          return;
        }
        const { imageUrl, audioUrl, preset, userId, avatarId } = req.body || {};
        if (!imageUrl || !audioUrl) {
          res.status(400).json({ error: 'imageUrl und audioUrl sind erforderlich' });
          return;
        }
        const db = admin.firestore();
        const doc = db.collection('renderJobs').doc();
        const jobId = doc.id;
        const job = {
          jobId,
          userId: userId || null,
          avatarId: avatarId || null,
          type: 'talking_head',
          status: 'queued',
          progress: 0,
          input: { imageUrl, audioUrl, preset: preset || '1080p30' },
          outputUrl: null,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        } as any;
        await doc.set(job);

        // Job wird direkt in Firestore gespeichert

        res.status(200).json({ jobId });
      } catch (error) {
        console.error('createTalkingHeadJob Fehler:', error);
        res.status(500).json({ error: 'Job-Erstellung fehlgeschlagen' });
      }
    });
  });

export const talkingHeadStatus = functions
  .region('us-central1')
  .https.onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
      try {
        const jobId = (req.query.jobId as string) || (req.body && req.body.jobId);
        if (!jobId) { res.status(400).json({ error: 'jobId fehlt' }); return; }
        const db = admin.firestore();
        const snap = await db.collection('renderJobs').doc(jobId).get();
        if (!snap.exists) { res.status(404).json({ error: 'Job nicht gefunden' }); return; }
        res.status(200).json(snap.data());
      } catch (e) {
        res.status(500).json({ error: 'Status-Fehler' });
      }
    });
  });

export const talkingHeadCallback = functions
  .region('us-central1')
  .https.onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
      try {
        if (req.method !== 'POST') { res.status(405).json({ error: 'Nur POST' }); return; }
        const { jobId, status, progress, outputUrl, error } = req.body || {};
        if (!jobId) { res.status(400).json({ error: 'jobId fehlt' }); return; }
        const db = admin.firestore();
        const ref = db.collection('renderJobs').doc(jobId);
        const update: any = { updatedAt: admin.firestore.FieldValue.serverTimestamp() };
        if (status) update.status = status;
        if (typeof progress === 'number') update.progress = progress;
        if (outputUrl) update.outputUrl = outputUrl;
        if (error) update.error = error;
        await ref.set(update, { merge: true });
        res.status(200).json({ ok: true });
      } catch (e) {
        console.error('Callback Fehler:', e);
        res.status(500).json({ error: 'Callback-Fehler' });
      }
    });
  });

/**
 * RAG-System: Verarbeitet hochgeladene Dokumente
 */
export const processDocument = functions
  .region('us-central1')
  .runWith({
    timeoutSeconds: 300,
    memory: '1GB',
    secrets: ['PINECONE_API_KEY','OPENAI_API_KEY'],
  })
  .https
  .onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
      try {
        if (req.method !== 'POST') {
          res.status(405).json({ error: 'Nur POST Requests erlaubt' });
          return;
        }

        const { userId, documentId, content, metadata } = req.body;
        
        if (!userId || !documentId || !content || !metadata) {
          res.status(400).json({ error: 'userId, documentId, content und metadata sind erforderlich' });
          return;
        }

        const ragService = new RAGService();
        await ragService.processUploadedDocument(userId, documentId, content, metadata);

        res.status(200).json({
          success: true,
          message: 'Dokument erfolgreich verarbeitet',
          documentId,
        });

      } catch (error) {
        console.error('Document processing error:', error);
        res.status(500).json({ 
          error: 'Dokument-Verarbeitung fehlgeschlagen',
          details: error instanceof Error ? error.message : 'Unbekannter Fehler'
        });
      }
    });
  });

/**
 * RAG-System: Generiert KI-Avatar Antwort
 */
export const generateAvatarResponse = functions
  .region('us-central1')
  .runWith({
    timeoutSeconds: 300,
    memory: '1GB',
    secrets: ['PINECONE_API_KEY','OPENAI_API_KEY','GOOGLE_CSE_API_KEY','GOOGLE_CSE_CX'],
  })
  .https
  .onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
      try {
        if (req.method !== 'POST') {
          res.status(405).json({ error: 'Nur POST Requests erlaubt' });
          return;
        }

        const { userId, query, context, maxTokens, temperature } = req.body;
        
        if (!userId || !query) {
          res.status(400).json({ error: 'userId und query sind erforderlich' });
          return;
        }

        const ragService = new RAGService();
        const response = await ragService.generateAvatarResponse({
          userId,
          query,
          context,
          maxTokens,
          temperature,
        });

        res.status(200).json(response);

      } catch (error) {
        console.error('Avatar response generation error:', error);
        res.status(500).json({ 
          error: 'Avatar-Antwort-Generierung fehlgeschlagen',
          details: error instanceof Error ? error.message : 'Unbekannter Fehler'
        });
      }
    });
  });

/**
 * RAG-System: Validiert System-Status
 */
export const validateRAGSystem = functions
  .region('us-central1')
  .runWith({
    timeoutSeconds: 60,
    memory: '512MB',
    secrets: ['PINECONE_API_KEY','OPENAI_API_KEY'],
  })
  .https
  .onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
      try {
        const ragService = new RAGService();
        const isValid = await ragService.validateRAGSystem();

        res.status(200).json({
          success: true,
          ragSystemValid: isValid,
          timestamp: new Date().toISOString(),
        });

      } catch (error) {
        console.error('RAG system validation error:', error);
        res.status(500).json({ 
          error: 'RAG-System-Validierung fehlgeschlagen',
          details: error instanceof Error ? error.message : 'Unbekannter Fehler'
        });
      }
    });
  });

 /**
  * Kaskadierendes Aufräumen bei Medien-Löschung
  * - Löscht zugehörige Storage-Thumbs (documents/images/videos/audio)
  * - Entfernt referenzierende timelineAssets und deren timelineItems in allen Playlists
  */
export const onMediaDeleteCleanup = functions
   .region('us-central1')
  .firestore.document('avatars/{avatarId}/media/{mediaId}')
  .onDelete(async (snap, context) => {
    const { avatarId, mediaId } = context.params as { avatarId: string; mediaId: string };
     const db = admin.firestore();
     const bucket = admin.storage().bucket();
 
    // 0) Originaldatei im Storage löschen, sofern URL bekannt
    try {
      const data = snap.data() as any;
      const extractPath = (url?: string): string | null => {
        if (!url) return null;
        try {
          if (url.startsWith('gs://')) {
            const u = url.replace('gs://', '');
            const i = u.indexOf('/');
            return i >= 0 ? u.substring(i + 1) : null;
          }
          const u = new URL(url);
          if (u.hostname.includes('firebasestorage.googleapis.com')) {
            const m = u.pathname.match(/\/o\/(.+)$/);
            if (m && m[1]) {
              const p = m[1].split('?')[0];
              return decodeURIComponent(p);
            }
          }
        } catch {}
        return null;
      };
      const originalPath = extractPath(data?.url);
      if (originalPath) {
        try { await bucket.file(originalPath).delete(); } catch (e) { console.warn('original delete warn:', originalPath, e); }
      }
    } catch (e) {
      console.warn('original delete parse warn:', e);
    }

    // 1) Storage-Thumbs & Hero löschen (alle bekannten Pfade mit Prefix)
     const prefixes = [
       `avatars/${avatarId}/documents/thumbs/${mediaId}_`,
       `avatars/${avatarId}/images/thumbs/${mediaId}_`,
       `avatars/${avatarId}/videos/thumbs/${mediaId}_`,
       `avatars/${avatarId}/audio/thumbs/${mediaId}_`,
     ];
     try {
       await Promise.all(
         prefixes.map(async (prefix) => {
           const [files] = await bucket.getFiles({ prefix });
           if (!files || files.length === 0) return;
           await Promise.all(
             files.map(async (f) => {
               try { await f.delete(); } catch (e) { console.warn('Thumb delete warn:', f.name, e); }
             }),
           );
         }),
       );
      // Hero-Image ggf. löschen
      try {
        const hero = `avatars/${avatarId}/images/heroImage.jpg`;
        const [exists] = await bucket.file(hero).exists();
        if (exists) {
          // nur löschen, wenn dieses Media die Quelle des Hero war
          const data = snap.data() as any;
          if (data?.url && typeof data.url === 'string') {
            const avatarRef = db.collection('avatars').doc(avatarId);
            const avatarSnap = await avatarRef.get();
            const avatar = avatarSnap.data() as any;
            if (avatar?.avatarImageUrl && avatar.avatarImageUrl.includes('heroImage.jpg')) {
              await bucket.file(hero).delete();
              await avatarRef.update({ avatarImageUrl: admin.firestore.FieldValue.delete() });
            }
          }
        }
      } catch (e) { console.warn('hero delete warn', e); }
     } catch (e) {
       console.warn('Thumb cleanup warn:', e);
     }
 
     // 2) timelineAssets+timelineItems löschen, die dieses mediaId referenzieren
     try {
       const playlistsSnap = await db.collection('avatars').doc(avatarId).collection('playlists').get();
       for (const p of playlistsSnap.docs) {
         const assetsRef = p.ref.collection('timelineAssets');
         const assetsSnap = await assetsRef.where('mediaId', '==', mediaId).get();
         if (assetsSnap.empty) continue;
 
         for (const a of assetsSnap.docs) {
           // Alle Items, die auf dieses Asset zeigen, entfernen
           const itemsRef = p.ref.collection('timelineItems');
           const itemsSnap = await itemsRef.where('assetId', '==', a.id).get();
           const batch = db.batch();
           itemsSnap.forEach((it) => batch.delete(it.ref));
           batch.delete(a.ref);
           await batch.commit();
         }
       }
     } catch (e) {
       console.error('timeline cleanup error:', e);
     }
   });
 
 /**
  * Kaskadierendes Aufräumen beim Löschen eines timelineAssets:
  * - Löscht alle timelineItems, die auf das Asset verweisen
  */
 export const onTimelineAssetDelete = functions
   .region('us-central1')
   .firestore.document('avatars/{avatarId}/playlists/{playlistId}/timelineAssets/{assetId}')
   .onDelete(async (_snap, context) => {
     const { avatarId, playlistId, assetId } = context.params as { avatarId: string; playlistId: string; assetId: string };
     try {
       const db = admin.firestore();
       const itemsRef = db
         .collection('avatars').doc(avatarId)
         .collection('playlists').doc(playlistId)
         .collection('timelineItems');
       const itemsSnap = await itemsRef.where('assetId', '==', assetId).get();
       if (itemsSnap.empty) return;
       const batch = db.batch();
       itemsSnap.forEach((d) => batch.delete(d.ref));
       await batch.commit();
     } catch (e) {
       console.error('onTimelineAssetDelete cleanup error:', e);
     }
   });
