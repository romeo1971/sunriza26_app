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
  .runWith({ secrets: ['ELEVEN_API_KEY','ELEVEN_VOICE_ID','ELEVEN_TTS_MODEL'] })
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
        const elevenKey = process.env.ELEVEN_API_KEY;
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
