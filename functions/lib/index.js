"use strict";
/**
 * Haupt-Cloud Function für Live AI-Assistenten
 * Stand: 04.09.2025 - Mit geklonter Stimme und Echtzeit-Video-Lippensynchronisation
 */
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __exportStar = (this && this.__exportStar) || function(m, exports) {
    for (var p in m) if (p !== "default" && !Object.prototype.hasOwnProperty.call(exports, p)) __createBinding(exports, m, p);
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
var _a;
Object.defineProperty(exports, "__esModule", { value: true });
exports.onTimelineAssetDelete = exports.onMediaDeleteCleanup = exports.validateRAGSystem = exports.generateAvatarResponse = exports.processDocument = exports.talkingHeadCallback = exports.talkingHeadStatus = exports.createTalkingHeadJob = exports.llm = exports.tts = exports.testTTS = exports.healthCheck = exports.generateLiveVideo = void 0;
require("dotenv/config");
const functions = __importStar(require("firebase-functions"));
// admin ist bereits oben initialisiert
const cors_1 = __importDefault(require("cors"));
const textToSpeech_1 = require("./textToSpeech");
const vertexAI_1 = require("./vertexAI");
const config_1 = require("./config");
const rag_service_1 = require("./rag_service");
// Entfernt: Unbenutzte Importe aus pinecone_service
const node_fetch_1 = __importDefault(require("node-fetch"));
const openai_1 = __importDefault(require("openai"));
const admin = __importStar(require("firebase-admin"));
const stream_1 = require("stream");
// Stripe Checkout für Credits
__exportStar(require("./stripeCheckout"), exports);
// eRechnung Generator
__exportStar(require("./invoiceGenerator"), exports);
// Media-Kauf (Credits oder Stripe)
__exportStar(require("./mediaCheckout"), exports);
// Stripe Connect (Seller Marketplace)
__exportStar(require("./stripeConnect"), exports);
// Payment Methods Management (Karten speichern)
__exportStar(require("./paymentMethods"), exports);
// Firebase Admin initialisieren: lokal mit expliziten Credentials, in Cloud mit Default
if (process.env.GOOGLE_APPLICATION_CREDENTIALS || process.env.FIREBASE_CLIENT_EMAIL) {
    // Lokale Entwicklung: nutze Service-Account aus .env oder Datei
    const projectId = process.env.FIREBASE_PROJECT_ID || process.env.GOOGLE_CLOUD_PROJECT_ID;
    const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
    const privateKey = (_a = process.env.FIREBASE_PRIVATE_KEY) === null || _a === void 0 ? void 0 : _a.replace(/\\n/g, '\n');
    if (clientEmail && privateKey) {
        admin.initializeApp({
            credential: admin.credential.cert({
                projectId: projectId,
                clientEmail: clientEmail,
                privateKey: privateKey,
            }),
            projectId: projectId,
        });
    }
    else {
        // Fallback auf Datei, wenn gesetzt
        if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
            admin.initializeApp({
                credential: admin.credential.applicationDefault(),
                projectId: projectId,
            });
        }
        else {
            admin.initializeApp();
        }
    }
}
else {
    // In Cloud Functions: Default Credentials
    admin.initializeApp();
}
// CORS für Cross-Origin Requests
const corsHandler = (0, cors_1.default)({ origin: true });
/**
 * Haupt-Cloud Function für Live-Video-Generierung
 * HTTP-Trigger für optimale Streaming-Kontrolle
 */
exports.generateLiveVideo = functions
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
            const config = await (0, config_1.getConfig)();
            console.log('Konfiguration geladen:', {
                projectId: config.projectId,
                location: config.location,
                customVoiceName: config.customVoiceName,
            });
            // Schritt 1: Text-to-Speech mit Custom Voice
            console.log('Schritt 1: Generiere Audio mit Custom Voice...');
            const ttsResponse = await (0, textToSpeech_1.generateSpeech)({
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
            const validation = (0, vertexAI_1.validateVideoRequest)(videoRequest);
            if (!validation.isValid) {
                res.status(400).json({ error: validation.message });
                return;
            }
            const videoResponse = await (0, vertexAI_1.generateLipsyncVideo)(videoRequest);
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
            let signedUrl = null;
            const pass = new stream_1.PassThrough();
            const gcsWrite = bucket2.file(debugPath).createWriteStream({ contentType: 'video/mp4' });
            pass.pipe(gcsWrite);
            gcsWrite.on('finish', async () => {
                try {
                    const [url] = await bucket2.file(debugPath).getSignedUrl({ action: 'read', expires: Date.now() + 7 * 24 * 3600 * 1000 });
                    signedUrl = url;
                    console.log('Lipsync saved to:', url);
                }
                catch (e) {
                    console.warn('Signed URL error:', e);
                }
            });
            // Video-Stream an Client weiterleiten und in pass schreiben
            videoResponse.videoStream.on('data', (chunk) => {
                res.write(chunk);
                pass.write(chunk);
            });
            videoResponse.videoStream.on('end', () => {
                pass.end();
                if (signedUrl) {
                    try {
                        res.setHeader('X-Video-URL', signedUrl);
                    }
                    catch (_a) { }
                }
                console.log('Video-Stream beendet', signedUrl ? `URL: ${signedUrl}` : '');
                res.end();
            });
            videoResponse.videoStream.on('error', (error) => {
                console.error('Stream-Fehler:', error);
                if (!res.headersSent) {
                    res.status(500).json({ error: 'Stream-Fehler aufgetreten' });
                }
                else {
                    res.end();
                }
            });
            // Client-Disconnect Handling
            req.on('close', () => {
                console.log('Client hat Verbindung getrennt');
                if (videoResponse.videoStream.destroy) {
                    videoResponse.videoStream.destroy();
                }
            });
        }
        catch (error) {
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
exports.healthCheck = functions
    .region('us-central1')
    .https
    .onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
        try {
            const config = await (0, config_1.getConfig)();
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
        }
        catch (error) {
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
exports.testTTS = functions
    .region('us-central1')
    .runWith({ secrets: ['ELEVENLABS_API_KEY', 'ELEVEN_VOICE_ID', 'ELEVEN_TTS_MODEL'] })
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
                    const r = await globalThis.fetch(`https://api.elevenlabs.io/v1/text-to-speech/${effectiveVoiceId}`, {
                        method: 'POST',
                        headers: {
                            'xi-api-key': elevenKey,
                            'Content-Type': 'application/json',
                            'Accept': 'audio/mpeg',
                        },
                        body: JSON.stringify({
                            text,
                            model_id: effectiveModelId,
                            voice_settings: { stability: effStability, similarity_boost: effSimilarity },
                        }),
                    });
                    if (r.ok) {
                        const ab = await r.arrayBuffer();
                        const buf = Buffer.from(ab);
                        res.setHeader('Content-Type', 'audio/mpeg');
                        res.setHeader('Content-Length', buf.length.toString());
                        res.send(buf);
                        return;
                    }
                    else {
                        // Fehlerdetails ausgeben, damit wir wissen, warum ElevenLabs nicht liefert
                        let errText = '';
                        try {
                            errText = await r.text();
                        }
                        catch (_a) { }
                        console.warn(`ElevenLabs antwortete mit Status ${r.status}: ${r.statusText} | ${errText === null || errText === void 0 ? void 0 : errText.slice(0, 400)}`);
                        throw new Error(`ElevenLabs HTTP ${r.status}`);
                    }
                }
                catch (e) {
                    console.warn('ElevenLabs TTS fehlgeschlagen, fallback auf Google TTS:', e);
                }
            }
            // 2) Fallback: Google TTS
            const ttsResponse = await (0, textToSpeech_1.generateSpeech)({ text, languageCode: 'de-DE' });
            res.setHeader('Content-Type', 'audio/mpeg');
            res.setHeader('Content-Length', ttsResponse.audioContent.length.toString());
            res.send(ttsResponse.audioContent);
        }
        catch (error) {
            console.error('TTS Test Fehler:', error);
            res.status(500).json({
                error: 'TTS Fehler',
                details: error instanceof Error ? error.message : 'Unbekannter Fehler'
            });
        }
    });
});
// Produktiver Alias: gleicher Handler wie testTTS, aber unter dem Namen "tts"
exports.tts = exports.testTTS;
/**
 * LLM Router: OpenAI primär (gpt-4o-mini), Gemini Fallback
 * Body: { messages: [{role:'system'|'user'|'assistant', content:string}], maxTokens?, temperature? }
 */
exports.llm = functions
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
                .map((m) => `${m.role || 'user'}: ${m.content || ''}`)
                .join('\n');
            const tryOpenAI = async () => {
                var _a, _b, _c;
                if (!openaiKey)
                    throw new Error('OPENAI_API_KEY fehlt');
                const client = new openai_1.default({ apiKey: openaiKey });
                const resp = await client.chat.completions.create({
                    model: 'gpt-4o-mini',
                    messages: messages.map((m) => ({ role: m.role, content: m.content })),
                    max_tokens: maxTokens || 300,
                    temperature: temperature !== null && temperature !== void 0 ? temperature : 0.6,
                });
                const text = ((_c = (_b = (_a = resp.choices) === null || _a === void 0 ? void 0 : _a[0]) === null || _b === void 0 ? void 0 : _b.message) === null || _c === void 0 ? void 0 : _c.content) || '';
                return text.trim();
            };
            const tryGemini = async () => {
                var _a, _b, _c, _d, _e;
                if (!geminiKey)
                    throw new Error('GEMINI_API_KEY fehlt');
                const url = `https://generativelanguage.googleapis.com/v1/models/gemini-1.5-flash:generateContent?key=${geminiKey}`;
                const body = {
                    contents: [
                        {
                            parts: [{ text: joined }],
                        },
                    ],
                    generationConfig: {
                        temperature: temperature !== null && temperature !== void 0 ? temperature : 0.6,
                        maxOutputTokens: maxTokens || 300,
                    },
                };
                const r = await node_fetch_1.default(url, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(body),
                });
                if (!r.ok)
                    throw new Error(`Gemini HTTP ${r.status}`);
                const j = await r.json();
                const text = ((_e = (_d = (_c = (_b = (_a = j === null || j === void 0 ? void 0 : j.candidates) === null || _a === void 0 ? void 0 : _a[0]) === null || _b === void 0 ? void 0 : _b.content) === null || _c === void 0 ? void 0 : _c.parts) === null || _d === void 0 ? void 0 : _d[0]) === null || _e === void 0 ? void 0 : _e.text) || '';
                return text.trim();
            };
            let answer = '';
            try {
                answer = await tryOpenAI();
            }
            catch (e) {
                console.warn('OpenAI Fehler, fallback auf Gemini:', e);
                answer = await tryGemini();
            }
            res.status(200).json({ answer });
        }
        catch (error) {
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
exports.createTalkingHeadJob = functions
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
            };
            await doc.set(job);
            // Job wird direkt in Firestore gespeichert
            res.status(200).json({ jobId });
        }
        catch (error) {
            console.error('createTalkingHeadJob Fehler:', error);
            res.status(500).json({ error: 'Job-Erstellung fehlgeschlagen' });
        }
    });
});
exports.talkingHeadStatus = functions
    .region('us-central1')
    .https.onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
        try {
            const jobId = req.query.jobId || (req.body && req.body.jobId);
            if (!jobId) {
                res.status(400).json({ error: 'jobId fehlt' });
                return;
            }
            const db = admin.firestore();
            const snap = await db.collection('renderJobs').doc(jobId).get();
            if (!snap.exists) {
                res.status(404).json({ error: 'Job nicht gefunden' });
                return;
            }
            res.status(200).json(snap.data());
        }
        catch (e) {
            res.status(500).json({ error: 'Status-Fehler' });
        }
    });
});
exports.talkingHeadCallback = functions
    .region('us-central1')
    .https.onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
        try {
            if (req.method !== 'POST') {
                res.status(405).json({ error: 'Nur POST' });
                return;
            }
            const { jobId, status, progress, outputUrl, error } = req.body || {};
            if (!jobId) {
                res.status(400).json({ error: 'jobId fehlt' });
                return;
            }
            const db = admin.firestore();
            const ref = db.collection('renderJobs').doc(jobId);
            const update = { updatedAt: admin.firestore.FieldValue.serverTimestamp() };
            if (status)
                update.status = status;
            if (typeof progress === 'number')
                update.progress = progress;
            if (outputUrl)
                update.outputUrl = outputUrl;
            if (error)
                update.error = error;
            await ref.set(update, { merge: true });
            res.status(200).json({ ok: true });
        }
        catch (e) {
            console.error('Callback Fehler:', e);
            res.status(500).json({ error: 'Callback-Fehler' });
        }
    });
});
/**
 * RAG-System: Verarbeitet hochgeladene Dokumente
 */
exports.processDocument = functions
    .region('us-central1')
    .runWith({
    timeoutSeconds: 300,
    memory: '1GB',
    secrets: ['PINECONE_API_KEY', 'OPENAI_API_KEY'],
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
            const ragService = new rag_service_1.RAGService();
            await ragService.processUploadedDocument(userId, documentId, content, metadata);
            res.status(200).json({
                success: true,
                message: 'Dokument erfolgreich verarbeitet',
                documentId,
            });
        }
        catch (error) {
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
exports.generateAvatarResponse = functions
    .region('us-central1')
    .runWith({
    timeoutSeconds: 300,
    memory: '1GB',
    secrets: ['PINECONE_API_KEY', 'OPENAI_API_KEY', 'GOOGLE_CSE_API_KEY', 'GOOGLE_CSE_CX'],
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
            const ragService = new rag_service_1.RAGService();
            const response = await ragService.generateAvatarResponse({
                userId,
                query,
                context,
                maxTokens,
                temperature,
            });
            res.status(200).json(response);
        }
        catch (error) {
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
exports.validateRAGSystem = functions
    .region('us-central1')
    .runWith({
    timeoutSeconds: 60,
    memory: '512MB',
    secrets: ['PINECONE_API_KEY', 'OPENAI_API_KEY'],
})
    .https
    .onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
        try {
            const ragService = new rag_service_1.RAGService();
            const isValid = await ragService.validateRAGSystem();
            res.status(200).json({
                success: true,
                ragSystemValid: isValid,
                timestamp: new Date().toISOString(),
            });
        }
        catch (error) {
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
exports.onMediaDeleteCleanup = functions
    .region('us-central1')
    .firestore.document('avatars/{avatarId}/media/{mediaId}')
    .onDelete(async (_snap, context) => {
    const { avatarId, mediaId } = context.params;
    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    // 1) Storage-Thumbs löschen (alle bekannten Pfade mit Prefix)
    const prefixes = [
        `avatars/${avatarId}/documents/thumbs/${mediaId}_`,
        `avatars/${avatarId}/images/thumbs/${mediaId}_`,
        `avatars/${avatarId}/videos/thumbs/${mediaId}_`,
        `avatars/${avatarId}/audio/thumbs/${mediaId}_`,
    ];
    try {
        await Promise.all(prefixes.map(async (prefix) => {
            const [files] = await bucket.getFiles({ prefix });
            if (!files || files.length === 0)
                return;
            await Promise.all(files.map(async (f) => {
                try {
                    await f.delete();
                }
                catch (e) {
                    console.warn('Thumb delete warn:', f.name, e);
                }
            }));
        }));
    }
    catch (e) {
        console.warn('Thumb cleanup warn:', e);
    }
    // 2) timelineAssets+timelineItems löschen, die dieses mediaId referenzieren
    try {
        const playlistsSnap = await db.collection('avatars').doc(avatarId).collection('playlists').get();
        for (const p of playlistsSnap.docs) {
            const assetsRef = p.ref.collection('timelineAssets');
            const assetsSnap = await assetsRef.where('mediaId', '==', mediaId).get();
            if (assetsSnap.empty)
                continue;
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
    }
    catch (e) {
        console.error('timeline cleanup error:', e);
    }
});
/**
 * Kaskadierendes Aufräumen beim Löschen eines timelineAssets:
 * - Löscht alle timelineItems, die auf das Asset verweisen
 */
exports.onTimelineAssetDelete = functions
    .region('us-central1')
    .firestore.document('avatars/{avatarId}/playlists/{playlistId}/timelineAssets/{assetId}')
    .onDelete(async (_snap, context) => {
    const { avatarId, playlistId, assetId } = context.params;
    try {
        const db = admin.firestore();
        const itemsRef = db
            .collection('avatars').doc(avatarId)
            .collection('playlists').doc(playlistId)
            .collection('timelineItems');
        const itemsSnap = await itemsRef.where('assetId', '==', assetId).get();
        if (itemsSnap.empty)
            return;
        const batch = db.batch();
        itemsSnap.forEach((d) => batch.delete(d.ref));
        await batch.commit();
    }
    catch (e) {
        console.error('onTimelineAssetDelete cleanup error:', e);
    }
});
//# sourceMappingURL=index.js.map