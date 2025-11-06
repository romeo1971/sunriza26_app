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
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateMissingVideoThumbs = exports.trimVideo = exports.extractVideoFrameAtPosition = exports.backfillVideoDocuments = exports.backfillOriginalFileNames = exports.onTimelineAssetDelete = exports.onMediaDeleteCleanup = exports.validateRAGSystem = exports.generateAvatarResponse = exports.processDocument = exports.talkingHeadCallback = exports.talkingHeadStatus = exports.createTalkingHeadJob = exports.llm = exports.restoreAvatarCovers = exports.fixVideoAspectRatios = exports.onMediaCreateSetDocumentThumb = exports.onMediaCreateSetVideoThumb = exports.onMediaCreateSetImageThumb = exports.onMediaCreateSetAudioThumb = exports.onMediaCreateSetAvatarImage = exports.onMediaObjectDelete = exports.backfillAudioWaveforms = exports.scheduledBackfillAudioThumbs = exports.backfillAudioThumbsAllAvatars = exports.scheduledBackfillThumbs = exports.backfillThumbsAllAvatars = exports.cleanAllAvatarsNow = exports.scheduledStorageClean = exports.cleanStorageAndFixDocThumbs = exports.tts = exports.testTTS = exports.healthCheck = exports.generateLiveVideo = exports.handleMediaPurchaseWebhook = exports.mediaCheckoutWebhook = exports.createMediaCheckoutSession = exports.copyMediaToMoments = void 0;
require("dotenv/config");
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const cors_1 = __importDefault(require("cors"));
const textToSpeech_1 = require("./textToSpeech");
const vertexAI_1 = require("./vertexAI");
const config_1 = require("./config");
const rag_service_1 = require("./rag_service");
const node_fetch_1 = __importDefault(require("node-fetch"));
// import OpenAI from 'openai'; // Nicht benötigt, nutzen native fetch
const stream_1 = require("stream");
const ffmpeg_static_1 = __importDefault(require("ffmpeg-static"));
const fluent_ffmpeg_1 = __importDefault(require("fluent-ffmpeg"));
const fs = __importStar(require("fs"));
const os = __importStar(require("os"));
const path = __importStar(require("path"));
const sharp_1 = __importDefault(require("sharp"));
const functionsStorage = __importStar(require("firebase-functions/v2/storage"));
const https_1 = require("firebase-functions/v2/https");
// Exports
__exportStar(require("./avatarChat"), exports);
__exportStar(require("./memoryApi"), exports);
__exportStar(require("./stripeCheckout"), exports);
__exportStar(require("./invoiceGenerator"), exports);
__exportStar(require("./mediaCheckout"), exports);
__exportStar(require("./stripeConnect"), exports);
__exportStar(require("./paymentMethods"), exports);
// Explizite Re-Exports für mediaCheckout
var mediaCheckout_1 = require("./mediaCheckout");
Object.defineProperty(exports, "copyMediaToMoments", { enumerable: true, get: function () { return mediaCheckout_1.copyMediaToMoments; } });
Object.defineProperty(exports, "createMediaCheckoutSession", { enumerable: true, get: function () { return mediaCheckout_1.createMediaCheckoutSession; } });
Object.defineProperty(exports, "mediaCheckoutWebhook", { enumerable: true, get: function () { return mediaCheckout_1.mediaCheckoutWebhook; } });
Object.defineProperty(exports, "handleMediaPurchaseWebhook", { enumerable: true, get: function () { return mediaCheckout_1.handleMediaPurchaseWebhook; } });
// Admin init (falls notwendig)
if (!admin.apps.length) {
    try {
        admin.initializeApp();
    }
    catch (_) { }
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
// Spiegelung: invoiceAnchors → Transaktion (verhindert UI‑Flackern und doppelte Reads)
// Entfernt: Spiegelung aus einer separaten Collection. Anchordaten liegen direkt unter
// users/{userId}/transactions/{txId}.invoiceAnchors
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
        var _a;
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
            const elevenKey = (_a = process.env.ELEVENLABS_API_KEY) === null || _a === void 0 ? void 0 : _a.trim();
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
                        catch (_b) { }
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
 * Storage-Cleaner: Löscht verwaiste Dateien und setzt fehlende thumbUrl für Dokumente
 * Aufruf: https://<region>-<project>.cloudfunctions.net/cleanStorageAndFixDocThumbs?avatarId=AVATAR_ID
 */
async function runCleanerForAvatar(avatarId) {
    var _a, _b, _c, _d;
    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    const mediaSnap = await getAllMediaDocs(avatarId);
    const referencedPaths = new Set();
    const mediaDocs = [];
    const extractPath = (url) => {
        if (!url)
            return null;
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
        }
        catch (_) { }
        return null;
    };
    mediaSnap.forEach((data) => {
        mediaDocs.push({ id: data.id, type: data.type, url: data.url, thumbUrl: data.thumbUrl });
        const p1 = extractPath(data.url);
        const p2 = extractPath(data.thumbUrl);
        if (p1)
            referencedPaths.add(p1);
        if (p2)
            referencedPaths.add(p2);
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
        if (name.endsWith('/'))
            continue;
        if (!allowed.some((p) => name.startsWith(p)))
            continue; // skip non-media folders (e.g. playlists)
        if (!referencedPaths.has(name)) {
            try {
                await f.delete();
                deleted++;
            }
            catch (e) {
                console.warn('Delete failed for', name, e);
            }
        }
    }
    // Fix missing document thumbs from existing files
    let fixedThumbs = 0;
    for (const m of mediaDocs) {
        if (m.type !== 'document' || (m.thumbUrl && m.thumbUrl.length > 0))
            continue;
        const thumbPrefix = `${base}documents/thumbs/${m.id}`;
        const [tfs] = await bucket.getFiles({ prefix: thumbPrefix });
        if (tfs && tfs.length > 0) {
            let latest = tfs[0];
            for (const f of tfs) {
                const a = new Date(((_a = latest.metadata) === null || _a === void 0 ? void 0 : _a.updated) || ((_b = latest.metadata) === null || _b === void 0 ? void 0 : _b.timeCreated) || 0).getTime();
                const b = new Date(((_c = f.metadata) === null || _c === void 0 ? void 0 : _c.updated) || ((_d = f.metadata) === null || _d === void 0 ? void 0 : _d.timeCreated) || 0).getTime();
                if (b > a)
                    latest = f;
            }
            try {
                const [url] = await latest.getSignedUrl({ action: 'read', expires: Date.now() + 365 * 24 * 3600 * 1000 });
                await db
                    .collection('avatars').doc(avatarId)
                    .collection(getCollectionName(m.type)).doc(m.id)
                    .update({ thumbUrl: url, aspectRatio: 9 / 16 });
                fixedThumbs++;
            }
            catch (e) {
                console.warn('Set thumb failed for', m.id, e);
            }
        }
    }
    return { deletedFiles: deleted, fixedDocumentThumbs: fixedThumbs, mediaCount: mediaDocs.length };
}
exports.cleanStorageAndFixDocThumbs = functions
    .region('us-central1')
    .runWith({ timeoutSeconds: 540, memory: '1GB' })
    .https.onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
        try {
            const avatarId = (req.query.avatarId || '').trim();
            if (!avatarId) {
                res.status(400).json({ error: 'avatarId fehlt' });
                return;
            }
            const out = await runCleanerForAvatar(avatarId);
            res.status(200).json(out);
        }
        catch (e) {
            console.error('Cleaner error:', e);
            res.status(500).json({ error: (e === null || e === void 0 ? void 0 : e.message) || 'unknown' });
        }
    });
});
// Scheduled daily cleanup for all avatars
exports.scheduledStorageClean = functions
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
        }
        catch (e) {
            console.warn('scheduled clean failed for', doc.id, e);
        }
    }
});
// Manual trigger for all avatars (one-off)
exports.cleanAllAvatarsNow = functions
    .region('us-central1')
    .runWith({ timeoutSeconds: 540, memory: '1GB' })
    .https.onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
        try {
            const db = admin.firestore();
            const avatars = await db.collection('avatars').select('id').get();
            const results = [];
            for (const doc of avatars.docs) {
                const r = await runCleanerForAvatar(doc.id);
                results.push({ avatarId: doc.id, ...r });
            }
            res.status(200).json({ results });
        }
        catch (e) {
            res.status(500).json({ error: (e === null || e === void 0 ? void 0 : e.message) || 'unknown' });
        }
    });
});
// Backfill: setze fehlende thumbUrl für Bilder/Videos (auf Original-URL) und für Dokumente aus Storage-Thumbs
async function runBackfillThumbsForAvatar(avatarId) {
    var _a, _b, _c, _d;
    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    const allMedia = await getAllMediaDocs(avatarId);
    let updated = 0;
    for (const m of allMedia) {
        if (!m)
            continue;
        if ((!m.thumbUrl || m.thumbUrl.length === 0)) {
            const docRef = db.collection('avatars').doc(avatarId).collection(getCollectionName(m.type)).doc(m.id);
            if (m.type === 'image' || m.type === 'video') {
                if (typeof m.url === 'string' && m.url.length > 0) {
                    await docRef.update({ thumbUrl: m.url });
                    updated++;
                }
            }
            else if (m.type === 'document') {
                const prefix = `avatars/${avatarId}/documents/thumbs/${m.id}`;
                const [tfs] = await bucket.getFiles({ prefix });
                if (tfs && tfs.length > 0) {
                    let latest = tfs[0];
                    for (const f of tfs) {
                        const a = new Date(((_a = latest.metadata) === null || _a === void 0 ? void 0 : _a.updated) || ((_b = latest.metadata) === null || _b === void 0 ? void 0 : _b.timeCreated) || 0).getTime();
                        const b = new Date(((_c = f.metadata) === null || _c === void 0 ? void 0 : _c.updated) || ((_d = f.metadata) === null || _d === void 0 ? void 0 : _d.timeCreated) || 0).getTime();
                        if (b > a)
                            latest = f;
                    }
                    const [url] = await latest.getSignedUrl({ action: 'read', expires: Date.now() + 365 * 24 * 3600 * 1000 });
                    await docRef.update({ thumbUrl: url });
                    updated++;
                }
            }
        }
    }
    return { updatedThumbs: updated, mediaCount: allMedia.length };
}
exports.backfillThumbsAllAvatars = functions
    .region('us-central1')
    .runWith({ timeoutSeconds: 540, memory: '1GB' })
    .https.onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
        try {
            const db = admin.firestore();
            const avatars = await db.collection('avatars').select('id').get();
            const results = [];
            for (const doc of avatars.docs) {
                const r = await runBackfillThumbsForAvatar(doc.id);
                results.push({ avatarId: doc.id, ...r });
            }
            res.status(200).json({ results });
        }
        catch (e) {
            res.status(500).json({ error: (e === null || e === void 0 ? void 0 : e.message) || 'unknown' });
        }
    });
});
exports.scheduledBackfillThumbs = functions
    .region('us-central1')
    .pubsub.schedule('15 4 * * 0') // wöchentlich So 04:15 UTC
    .timeZone('Etc/UTC')
    .onRun(async () => {
    const db = admin.firestore();
    const avatars = await db.collection('avatars').select('id').get();
    for (const doc of avatars.docs) {
        try {
            await runBackfillThumbsForAvatar(doc.id);
        }
        catch (_a) { }
    }
});
// Backfill: setzt fehlende Audio-Thumbs (Platzhalter: nutzt Audio-URL als thumbUrl)
async function runBackfillAudioThumbsForAvatar(avatarId) {
    const db = admin.firestore();
    const snap = await db.collection('avatars').doc(avatarId).collection('audios').get();
    let updated = 0;
    for (const d of snap.docs) {
        const m = d.data();
        const has = typeof m.thumbUrl === 'string' && m.thumbUrl.length > 0;
        if (!has && typeof m.url === 'string' && m.url.length > 0) {
            await d.ref.set({ thumbUrl: m.url, aspectRatio: 16 / 9 }, { merge: true });
            updated++;
        }
    }
    return { updatedAudioThumbs: updated, audioCount: snap.size };
}
exports.backfillAudioThumbsAllAvatars = functions
    .region('us-central1')
    .runWith({ timeoutSeconds: 540, memory: '1GB' })
    .https.onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
        try {
            const db = admin.firestore();
            const avatars = await db.collection('avatars').select('id').get();
            const results = [];
            for (const doc of avatars.docs) {
                const r = await runBackfillAudioThumbsForAvatar(doc.id);
                results.push({ avatarId: doc.id, ...r });
            }
            res.status(200).json({ results });
        }
        catch (e) {
            res.status(500).json({ error: (e === null || e === void 0 ? void 0 : e.message) || 'unknown' });
        }
    });
});
exports.scheduledBackfillAudioThumbs = functions
    .region('us-central1')
    .pubsub.schedule('45 4 * * 0') // wöchentlich So 04:45 UTC
    .timeZone('Etc/UTC')
    .onRun(async () => {
    const db = admin.firestore();
    const avatars = await db.collection('avatars').select('id').get();
    for (const doc of avatars.docs) {
        try {
            await runBackfillAudioThumbsForAvatar(doc.id);
        }
        catch (_a) { }
    }
});
// Erzeuge und setze echte Audio-Waveform-PNG als thumbUrl
async function createWaveThumb(avatarId, mediaId, audioUrl) {
    if (ffmpeg_static_1.default)
        fluent_ffmpeg_1.default.setFfmpegPath(ffmpeg_static_1.default);
    const tmpDir = os.tmpdir();
    const random = Math.random().toString(36).substring(7);
    const src = path.join(tmpDir, `${mediaId}_${random}.audio`);
    const out = path.join(tmpDir, `${mediaId}_${random}.png`);
    const res = await node_fetch_1.default(audioUrl);
    if (!res.ok)
        throw new Error(`download audio failed ${res.status}`);
    const buf = Buffer.from(await res.arrayBuffer());
    fs.writeFileSync(src, buf);
    await new Promise((resolve, reject) => {
        fluent_ffmpeg_1.default(src)
            .complexFilter(['showwavespic=s=800x180:colors=0xFFFFFF'])
            .frames(1)
            .on('end', () => resolve())
            .on('error', (e) => reject(e))
            .save(out);
    });
    const bucket = admin.storage().bucket();
    const dest = `avatars/${avatarId}/audio/thumbs/${mediaId}.png`;
    await bucket.upload(out, {
        destination: dest,
        contentType: 'image/png',
        metadata: { cacheControl: 'public,max-age=31536000,immutable' },
    });
    const [signed] = await bucket.file(dest).getSignedUrl({ action: 'read', expires: Date.now() + 365 * 24 * 3600 * 1000 });
    try {
        fs.unlinkSync(src);
    }
    catch (_a) { }
    try {
        fs.unlinkSync(out);
    }
    catch (_b) { }
    await admin.firestore().collection('avatars').doc(avatarId)
        .collection('audios').doc(mediaId)
        .set({ thumbUrl: signed, aspectRatio: 800 / 180 }, { merge: true });
    return signed;
}
exports.backfillAudioWaveforms = functions
    .region('us-central1')
    .runWith({ timeoutSeconds: 540, memory: '2GB' })
    .https.onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
        try {
            const avatarId = (req.query.avatarId || '').trim();
            if (!avatarId) {
                res.status(400).json({ error: 'avatarId fehlt' });
                return;
            }
            const db = admin.firestore();
            const qs = await db.collection('avatars').doc(avatarId).collection('audios').get();
            let created = 0;
            for (const d of qs.docs) {
                const m = d.data();
                if (!m || !m.url)
                    continue;
                const has = typeof m.thumbUrl === 'string' && m.thumbUrl.length > 0;
                if (has)
                    continue;
                try {
                    await createWaveThumb(avatarId, d.id, m.url);
                    created++;
                }
                catch (e) {
                    console.warn('waveform fail', d.id, e);
                }
            }
            res.status(200).json({ avatarId, created, total: qs.size });
        }
        catch (e) {
            res.status(500).json({ error: (e === null || e === void 0 ? void 0 : e.message) || 'unknown' });
        }
    });
});
// Video: Thumb aus erstem Frame generieren, wenn nicht vorhanden
async function createVideoThumbFromFirstFrame(avatarId, mediaId, videoUrl) {
    var _a, _b;
    if (ffmpeg_static_1.default)
        fluent_ffmpeg_1.default.setFfmpegPath(ffmpeg_static_1.default);
    const tmpDir = os.tmpdir();
    const random = Math.random().toString(36).substring(7);
    const src = path.join(tmpDir, `${mediaId}_${random}.mp4`);
    // Download Video (kurz, reicht für Frame)
    const res = await node_fetch_1.default(videoUrl);
    if (!res.ok)
        throw new Error(`download video failed ${res.status}`);
    const buf = Buffer.from(await res.arrayBuffer());
    fs.writeFileSync(src, buf);
    // Extrahiere Video-Dimensionen mit FFprobe
    let aspectRatio = 16 / 9; // Fallback
    try {
        const metadata = await new Promise((resolve, reject) => {
            fluent_ffmpeg_1.default.ffprobe(src, (err, data) => {
                if (err)
                    reject(err);
                else
                    resolve(data);
            });
        });
        const videoStream = (_a = metadata === null || metadata === void 0 ? void 0 : metadata.streams) === null || _a === void 0 ? void 0 : _a.find((s) => s.codec_type === 'video');
        if ((videoStream === null || videoStream === void 0 ? void 0 : videoStream.width) && (videoStream === null || videoStream === void 0 ? void 0 : videoStream.height)) {
            aspectRatio = videoStream.width / videoStream.height;
            console.log(`Video dimensions: ${videoStream.width}x${videoStream.height}, aspectRatio: ${aspectRatio}`);
        }
    }
    catch (e) {
        console.warn('Failed to extract video dimensions, using fallback 16/9', e);
    }
    // Vereinfachte Logik: Extrahiere Frame bei 2s (überspringt meist schwarze Intros)
    const framePath = path.join(tmpDir, `${mediaId}_${random}_thumb.jpg`);
    console.log('📹 Extrahiere Video-Thumbnail bei 2s...');
    try {
        await new Promise((resolve, reject) => {
            fluent_ffmpeg_1.default(src)
                .on('end', () => {
                console.log('✅ Frame erfolgreich extrahiert');
                resolve();
            })
                .on('error', (e) => {
                console.error('❌ FFmpeg Fehler:', e);
                reject(e);
            })
                .screenshots({
                count: 1,
                timemarks: ['2'], // 2 Sekunden = überspringt meist schwarze Intros
                filename: path.basename(framePath),
                folder: tmpDir,
            });
        });
    }
    catch (e) {
        // Fallback: Versuche bei 0.5s
        console.warn('⚠️ Frame bei 2s fehlgeschlagen, versuche 0.5s...', e);
        await new Promise((resolve, reject) => {
            fluent_ffmpeg_1.default(src)
                .on('end', () => resolve())
                .on('error', (e) => reject(e))
                .screenshots({
                count: 1,
                timemarks: ['0.5'],
                filename: path.basename(framePath),
                folder: tmpDir,
            });
        });
    }
    const selectedFrame = framePath;
    const bucket = admin.storage().bucket();
    const dest = `avatars/${avatarId}/videos/thumbs/${mediaId}_${Date.now()}.jpg`;
    await bucket.upload(selectedFrame, {
        destination: dest,
        contentType: 'image/jpeg',
        metadata: { cacheControl: 'public,max-age=31536000,immutable' },
    });
    const [signed] = await bucket.file(dest).getSignedUrl({ action: 'read', expires: Date.now() + 365 * 24 * 3600 * 1000 });
    console.log(`✅ Video-Thumbnail erstellt: ${dest}`);
    // Cleanup
    try {
        fs.unlinkSync(src);
    }
    catch (_c) { }
    try {
        fs.unlinkSync(selectedFrame);
    }
    catch (_d) { }
    // AspectRatio NUR setzen, wenn sie noch nicht existiert (verhindert Überschreiben der korrekten App-Werte)
    const docSnap = await admin.firestore().collection('avatars').doc(avatarId)
        .collection('videos').doc(mediaId).get();
    const existingAspectRatio = (_b = docSnap.data()) === null || _b === void 0 ? void 0 : _b.aspectRatio;
    if (existingAspectRatio) {
        // App hat bereits korrekte aspectRatio gesetzt → nur thumbUrl aktualisieren
        await docSnap.ref.set({ thumbUrl: signed }, { merge: true });
    }
    else {
        // Keine aspectRatio vorhanden → setze FFprobe-Wert als Fallback
        await docSnap.ref.set({ thumbUrl: signed, aspectRatio }, { merge: true });
    }
    return signed;
}
// DEPRECATED: Alte Storage-Triggers entfernt (ersetzt durch Firestore-Triggers)
// Grund: Doppelte Thumb-Generierung vermeiden
// Helper für Storage-Pfad-Parsing
function parseAvatarPath(objectName) {
    if (!objectName)
        return null;
    const parts = objectName.split('/');
    if (parts.length < 4)
        return null;
    if (parts[0] !== 'avatars')
        return null;
    const avatarId = parts[1];
    const kind = parts[2];
    const inThumbs = parts.length >= 4 && parts[3] === 'thumbs';
    return { avatarId, kind, inThumbs, fileName: parts[parts.length - 1], objectName };
}
// Storage-Delete: zugehörige Thumbs löschen
exports.onMediaObjectDelete = functionsStorage.onObjectDeleted({ region: 'europe-west9' }, async (event) => {
    try {
        const obj = parseAvatarPath(event.data.name);
        if (!obj)
            return;
        if (obj.inThumbs)
            return; // Thumb gelöscht → keine Aktion
        const bucket = admin.storage().bucket(event.data.bucket);
        const base = obj.fileName.replace(/\.[^.]+$/, '');
        const prefix = `avatars/${obj.avatarId}/${obj.kind}/thumbs/${base}_`;
        const [files] = await bucket.getFiles({ prefix });
        await Promise.all(files.map(f => f.delete().catch(() => { })));
        if (obj.kind === 'images' && obj.fileName === 'heroImage.jpg') {
            try {
                const avatarRef = admin.firestore().collection('avatars').doc(obj.avatarId);
                await avatarRef.update({ avatarImageUrl: admin.firestore.FieldValue.delete() });
            }
            catch (_a) { }
        }
    }
    catch (e) {
        console.warn('onMediaObjectDelete error', e);
    }
});
// Video: Vorhandenes Poster/Platzhalterbild in Storage kopieren und als Thumb setzen
async function copyExistingVideoThumbToStorage(avatarId, mediaId, imageUrl) {
    const res = await node_fetch_1.default(imageUrl);
    if (!res.ok)
        throw new Error(`download image failed ${res.status}`);
    const buf = Buffer.from(await res.arrayBuffer());
    const bucket = admin.storage().bucket();
    const dest = `avatars/${avatarId}/videos/thumbs/${mediaId}_${Date.now()}.jpg`;
    await bucket.file(dest).save(buf, { contentType: 'image/jpeg', metadata: { cacheControl: 'public,max-age=31536000,immutable' } });
    const [signed] = await bucket.file(dest).getSignedUrl({ action: 'read', expires: Date.now() + 365 * 24 * 3600 * 1000 });
    await admin.firestore().collection('avatars').doc(avatarId)
        .collection('videos').doc(mediaId)
        .set({ thumbUrl: signed }, { merge: true });
    return signed;
}
// Firestore Trigger: Wenn erstes Bild hochgeladen wird, setze es als avatarImageUrl
// Helper: prüft ob Collection eine Media-Collection ist
function isMediaCollection(collectionId) {
    return ['images', 'videos', 'documents', 'audios'].includes(collectionId);
}
// Helper: sammelt alle Media-Docs aus allen Media-Collections
async function getAllMediaDocs(avatarId) {
    const db = admin.firestore();
    const all = [];
    for (const col of ['images', 'videos', 'documents', 'audios']) {
        const snap = await db.collection('avatars').doc(avatarId).collection(col).get();
        all.push(...snap.docs.map((d) => ({ id: d.id, ...d.data() })));
    }
    return all;
}
// Helper: Collection-Namen aus Media-Type
function getCollectionName(type) {
    if (type === 'image')
        return 'images';
    if (type === 'video')
        return 'videos';
    if (type === 'document')
        return 'documents';
    if (type === 'audio')
        return 'audios';
    if (type === 'voiceClone')
        return 'voiceClone';
    return 'images'; // fallback
}
exports.onMediaCreateSetAvatarImage = functions
    .region('us-central1')
    .firestore.document('avatars/{avatarId}/{collectionId}/{mediaId}')
    .onCreate(async (snap, ctx) => {
    var _a;
    try {
        const collectionId = ctx.params.collectionId;
        if (!isMediaCollection(collectionId))
            return;
        const data = snap.data();
        const avatarId = ctx.params.avatarId;
        if (!data || data.type !== 'image')
            return;
        const db = admin.firestore();
        const avatarRef = db.collection('avatars').doc(avatarId);
        const avatar = await avatarRef.get();
        const currentUrl = (_a = avatar.data()) === null || _a === void 0 ? void 0 : _a.avatarImageUrl;
        if (currentUrl && currentUrl.trim().length > 0)
            return; // bereits gesetzt
        // Prüfe, ob dies das einzige Bild ist
        const imgs = await avatarRef.collection('images').limit(2).get();
        if (imgs.size === 1 && imgs.docs[0].id === snap.id) {
            const url = data.url;
            if (url && url.length > 0) {
                await avatarRef.update({ avatarImageUrl: url, updatedAt: Date.now() });
            }
        }
    }
    catch (e) {
        console.warn('onMediaCreateSetAvatarImage error', e);
    }
});
// Firestore Trigger: Bei Audio-Upload fehlende thumbUrl sofort setzen (Platzhalter: url)
exports.onMediaCreateSetAudioThumb = functions
    .region('us-central1')
    .runWith({ memory: '1GB', timeoutSeconds: 120 })
    .firestore.document('avatars/{avatarId}/{collectionId}/{mediaId}')
    .onCreate(async (snap, ctx) => {
    try {
        const collectionId = ctx.params.collectionId;
        if (!isMediaCollection(collectionId))
            return;
        const data = snap.data();
        if (!data || data.type !== 'audio')
            return;
        const url = data.url;
        if (!url || url.length === 0)
            return;
        console.log(`Audio thumb generation START for ${snap.id}`);
        // Erzeuge echte Waveform sofort
        try {
            await createWaveThumb(ctx.params.avatarId, snap.id, url);
            console.log(`Audio thumb generation SUCCESS for ${snap.id}`);
        }
        catch (e) {
            console.error(`Audio thumb generation FAILED for ${snap.id}:`, e);
            // Fallback: setze zumindest die Audio-URL als Thumb
            await snap.ref.set({ thumbUrl: url, aspectRatio: 16 / 9 }, { merge: true });
        }
    }
    catch (e) {
        console.error('onMediaCreateSetAudioThumb error', e);
    }
});
// Firestore Trigger: Bei Image-Upload erstelle Thumb (9:16 oder 16:9 zugeschnitten)
exports.onMediaCreateSetImageThumb = functions
    .region('us-central1')
    .firestore.document('avatars/{avatarId}/{collectionId}/{mediaId}')
    .onCreate(async (snap, ctx) => {
    try {
        const collectionId = ctx.params.collectionId;
        if (!isMediaCollection(collectionId))
            return;
        const data = snap.data();
        if (!data || data.type !== 'image')
            return;
        if (data.thumbUrl)
            return;
        const avatarId = ctx.params.avatarId;
        const mediaId = ctx.params.mediaId;
        const url = data.url;
        if (!url)
            return;
        // Lade Bytes: unterstütze sowohl https Download-URLs als auch gs:// Pfade
        let buf = null;
        try {
            if (url.startsWith('gs://')) {
                const u = url.replace('gs://', '');
                const i = u.indexOf('/');
                const pathOnly = i >= 0 ? u.substring(i + 1) : '';
                const [bytes] = await admin.storage().bucket().file(pathOnly).download();
                buf = Buffer.from(bytes);
            }
            else {
                const res = await node_fetch_1.default(url);
                if (res.ok)
                    buf = Buffer.from(await res.arrayBuffer());
            }
        }
        catch (e) {
            console.warn('image fetch failed', e);
        }
        if (!buf)
            return;
        const meta = await (0, sharp_1.default)(buf).metadata();
        const ar = (meta.width || 1) / (meta.height || 1);
        const portrait = ar < 1.0;
        const targetAR = portrait ? 9 / 16 : 16 / 9;
        // zentriertes Crop auf targetAR
        let width = meta.width || 0;
        let height = meta.height || 0;
        if (width <= 0 || height <= 0)
            return;
        let cropW = width;
        let cropH = Math.round(width / targetAR);
        if (cropH > height) {
            cropH = height;
            cropW = Math.round(cropH * targetAR);
        }
        const left = Math.max(0, Math.floor((width - cropW) / 2));
        const top = Math.max(0, Math.floor((height - cropH) / 2));
        const outBuf = await (0, sharp_1.default)(buf)
            .extract({ left, top, width: cropW, height: cropH })
            .resize(720)
            .jpeg({ quality: 80 })
            .toBuffer();
        const bucket = admin.storage().bucket();
        const dest = `avatars/${avatarId}/images/thumbs/${mediaId}_${Date.now()}.jpg`;
        await bucket.file(dest).save(outBuf, { contentType: 'image/jpeg', metadata: { cacheControl: 'public,max-age=31536000,immutable' } });
        const [signed] = await bucket.file(dest).getSignedUrl({ action: 'read', expires: Date.now() + 365 * 24 * 3600 * 1000 });
        await snap.ref.set({ thumbUrl: signed, aspectRatio: targetAR }, { merge: true });
    }
    catch (e) {
        console.warn('onMediaCreateSetImageThumb error', e);
    }
});
// Firestore Trigger: Bei Video-Upload versuche vorhandenes Storage-Thumb zu setzen
exports.onMediaCreateSetVideoThumb = functions
    .region('us-central1')
    .firestore.document('avatars/{avatarId}/{collectionId}/{mediaId}')
    .onCreate(async (snap, ctx) => {
    try {
        const collectionId = ctx.params.collectionId;
        if (!isMediaCollection(collectionId))
            return;
        const data = snap.data();
        if (!data || data.type !== 'video')
            return;
        const avatarId = ctx.params.avatarId;
        const mediaId = ctx.params.mediaId;
        const bucket = admin.storage().bucket();
        const prefix = `avatars/${avatarId}/videos/thumbs/${mediaId}`;
        const [items] = await bucket.getFiles({ prefix });
        if (items.length > 0) {
            const f = items[0];
            const [signed] = await f.getSignedUrl({ action: 'read', expires: Date.now() + 365 * 24 * 3600 * 1000 });
            await snap.ref.set({ thumbUrl: signed }, { merge: true });
            return;
        }
        // Wenn bereits ein externes Poster/Platzhalterbild existiert → in Storage übernehmen
        if (typeof data.thumbUrl === 'string' && data.thumbUrl.length > 0) {
            try {
                await copyExistingVideoThumbToStorage(avatarId, mediaId, data.thumbUrl);
                return;
            }
            catch (e) {
                console.warn('copyExistingVideoThumbToStorage failed, fallback to frame grab', e);
            }
        }
        // Falls kein Storage-Thumb existiert: generiere aus erstem Frame
        if (typeof data.url === 'string' && data.url.length > 0) {
            await createVideoThumbFromFirstFrame(avatarId, mediaId, data.url);
        }
    }
    catch (e) {
        console.warn('onMediaCreateSetVideoThumb error', e);
    }
});
// Firestore Trigger: Bei Document-Upload erstelle Platzhalter-Thumb (wird später vom Client überschrieben)
exports.onMediaCreateSetDocumentThumb = functions
    .region('us-central1')
    .firestore.document('avatars/{avatarId}/{collectionId}/{mediaId}')
    .onCreate(async (snap, ctx) => {
    try {
        const collectionId = ctx.params.collectionId;
        if (!isMediaCollection(collectionId))
            return;
        const data = snap.data();
        if (!data || data.type !== 'document')
            return;
        if (data.thumbUrl)
            return; // bereits gesetzt
        // NEU: Für neue Dokumente NICHTS tun - User croppt manuell!
        // Cloud Function soll NICHT automatisch alte Thumbnails suchen und setzen.
        console.log(`⏳ Document thumb will be generated by client after manual crop`);
    }
    catch (e) {
        console.warn('onMediaCreateSetDocumentThumb error', e);
    }
});
// Backfill: Korrigiere aspectRatio für alle Videos basierend auf echten Dimensionen
exports.fixVideoAspectRatios = functions
    .region('us-central1')
    .runWith({ timeoutSeconds: 540, memory: '2GB' })
    .https.onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
        var _a;
        try {
            if (ffmpeg_static_1.default)
                fluent_ffmpeg_1.default.setFfmpegPath(ffmpeg_static_1.default);
            const db = admin.firestore();
            const avatars = await db.collection('avatars').get();
            const results = [];
            for (const avatarDoc of avatars.docs) {
                const avatarId = avatarDoc.id;
                const mediaSnap = await db.collection('avatars').doc(avatarId)
                    .collection('videos')
                    .get();
                for (const mediaDoc of mediaSnap.docs) {
                    const data = mediaDoc.data();
                    const mediaId = mediaDoc.id;
                    const videoUrl = data.url;
                    if (!videoUrl) {
                        results.push({ avatarId, mediaId, status: 'no_url' });
                        continue;
                    }
                    try {
                        // Download Video temporär
                        const tmpDir = os.tmpdir();
                        const src = path.join(tmpDir, `${mediaId}_fix.mp4`);
                        const res = await node_fetch_1.default(videoUrl);
                        if (!res.ok) {
                            results.push({ avatarId, mediaId, status: 'download_failed' });
                            continue;
                        }
                        const buf = Buffer.from(await res.arrayBuffer());
                        fs.writeFileSync(src, buf);
                        // Extrahiere Video-Dimensionen
                        const metadata = await new Promise((resolve, reject) => {
                            fluent_ffmpeg_1.default.ffprobe(src, (err, data) => {
                                if (err)
                                    reject(err);
                                else
                                    resolve(data);
                            });
                        });
                        const videoStream = (_a = metadata === null || metadata === void 0 ? void 0 : metadata.streams) === null || _a === void 0 ? void 0 : _a.find((s) => s.codec_type === 'video');
                        if ((videoStream === null || videoStream === void 0 ? void 0 : videoStream.width) && (videoStream === null || videoStream === void 0 ? void 0 : videoStream.height)) {
                            const aspectRatio = videoStream.width / videoStream.height;
                            const oldAR = data.aspectRatio;
                            // Update in Firestore
                            await mediaDoc.ref.update({ aspectRatio });
                            // Cleanup
                            try {
                                fs.unlinkSync(src);
                            }
                            catch (_b) { }
                            results.push({
                                avatarId,
                                mediaId,
                                status: 'updated',
                                oldAspectRatio: oldAR,
                                newAspectRatio: aspectRatio,
                                dimensions: `${videoStream.width}x${videoStream.height}`,
                            });
                            console.log(`✅ Fixed ${avatarId}/${mediaId}: ${oldAR} → ${aspectRatio}`);
                        }
                        else {
                            try {
                                fs.unlinkSync(src);
                            }
                            catch (_c) { }
                            results.push({ avatarId, mediaId, status: 'no_dimensions' });
                        }
                    }
                    catch (e) {
                        results.push({ avatarId, mediaId, status: 'error', error: e.message });
                    }
                }
            }
            res.status(200).json({ success: true, results, total: results.length });
        }
        catch (e) {
            res.status(500).json({ error: e.message });
        }
    });
});
// Restore/Set avatar cover images if missing or broken
exports.restoreAvatarCovers = functions
    .region('us-central1')
    .runWith({ timeoutSeconds: 540, memory: '1GB' })
    .https.onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
        var _a, _b, _c, _d, _e;
        try {
            const db = admin.firestore();
            const bucket = admin.storage().bucket();
            const avatars = await db.collection('avatars').get();
            const out = [];
            for (const doc of avatars.docs) {
                const data = doc.data();
                let needsFix = false;
                const url = data.avatarImageUrl;
                if (!url || url.trim().length === 0)
                    needsFix = true;
                else {
                    try {
                        const r = await node_fetch_1.default(url, { method: 'HEAD' });
                        if (!r.ok)
                            needsFix = true;
                    }
                    catch (_f) {
                        needsFix = true;
                    }
                }
                if (!needsFix) {
                    out.push({ id: doc.id, status: 'ok' });
                    continue;
                }
                // 1) Versuche neuestes Bild unter avatars/<id>/images/
                const prefix = `avatars/${doc.id}/images/`;
                const [files] = await bucket.getFiles({ prefix });
                let chosen = null;
                for (const f of files) {
                    if (f.name.endsWith('/'))
                        continue;
                    if (f.name.includes('/thumbs/'))
                        continue;
                    if (!chosen) {
                        chosen = f;
                        continue;
                    }
                    const a = new Date(((_a = chosen.metadata) === null || _a === void 0 ? void 0 : _a.updated) || ((_b = chosen.metadata) === null || _b === void 0 ? void 0 : _b.timeCreated) || 0).getTime();
                    const b = new Date(((_c = f.metadata) === null || _c === void 0 ? void 0 : _c.updated) || ((_d = f.metadata) === null || _d === void 0 ? void 0 : _d.timeCreated) || 0).getTime();
                    if (b > a)
                        chosen = f;
                }
                // 2) Falls nichts gefunden, nimm erstes Bild aus images collection
                if (!chosen) {
                    const ms = await db.collection('avatars').doc(doc.id).collection('images').limit(1).get();
                    const m = (_e = ms.docs[0]) === null || _e === void 0 ? void 0 : _e.data();
                    if (m === null || m === void 0 ? void 0 : m.url) {
                        await doc.ref.update({ avatarImageUrl: m.url, updatedAt: Date.now() });
                        out.push({ id: doc.id, status: 'setFromMediaUrl' });
                        continue;
                    }
                }
                if (chosen) {
                    try {
                        const [signed] = await chosen.getSignedUrl({ action: 'read', expires: Date.now() + 365 * 24 * 3600 * 1000 });
                        await doc.ref.update({ avatarImageUrl: signed, updatedAt: Date.now() });
                        out.push({ id: doc.id, status: 'setFromStorage', file: chosen.name });
                    }
                    catch (e) {
                        out.push({ id: doc.id, status: 'failedSet', error: e === null || e === void 0 ? void 0 : e.message });
                    }
                }
                else {
                    out.push({ id: doc.id, status: 'noImageFound' });
                }
            }
            res.status(200).json({ results: out });
        }
        catch (e) {
            res.status(500).json({ error: (e === null || e === void 0 ? void 0 : e.message) || 'unknown' });
        }
    });
});
/**
 * LLM Router: OpenAI primär (gpt-4o-mini), Gemini Fallback
 * Body: { messages: [{role:'system'|'user'|'assistant', content:string}], maxTokens?, temperature? }
 */
exports.llm = (0, https_1.onRequest)({
    region: 'us-central1',
    cors: true,
    invoker: 'public',
    secrets: ['OPENAI_API_KEY']
}, async (req, res) => {
    var _a, _b, _c, _d;
    if (req.method === 'OPTIONS') {
        res.status(204).send('');
        return;
    }
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
        const openaiKey = (_a = process.env.OPENAI_API_KEY) === null || _a === void 0 ? void 0 : _a.trim();
        if (!openaiKey) {
            res.status(500).json({ error: 'OPENAI_API_KEY fehlt' });
            return;
        }
        // Native fetch statt OpenAI SDK
        const response = await (0, node_fetch_1.default)('https://api.openai.com/v1/chat/completions', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${openaiKey}`,
            },
            body: JSON.stringify({
                model: 'gpt-4o-mini',
                messages: messages.map((m) => ({ role: m.role, content: m.content })),
                max_tokens: maxTokens || 300,
                temperature: temperature !== null && temperature !== void 0 ? temperature : 0.6,
            }),
        });
        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(`OpenAI API Error: ${response.status} ${errorText}`);
        }
        const data = await response.json();
        const answer = (((_d = (_c = (_b = data === null || data === void 0 ? void 0 : data.choices) === null || _b === void 0 ? void 0 : _b[0]) === null || _c === void 0 ? void 0 : _c.message) === null || _d === void 0 ? void 0 : _d.content) || '').trim();
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
    .firestore.document('avatars/{avatarId}/{collectionId}/{mediaId}')
    .onDelete(async (snap, context) => {
    const collectionId = context.params.collectionId;
    if (!isMediaCollection(collectionId))
        return;
    const { avatarId, mediaId } = context.params;
    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    // 0) Originaldatei im Storage löschen, sofern URL bekannt
    try {
        const data = snap.data();
        const extractPath = (url) => {
            if (!url)
                return null;
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
            }
            catch (_a) { }
            return null;
        };
        const originalPath = extractPath(data === null || data === void 0 ? void 0 : data.url);
        if (originalPath) {
            try {
                await bucket.file(originalPath).delete();
            }
            catch (e) {
                console.warn('original delete warn:', originalPath, e);
            }
        }
    }
    catch (e) {
        console.warn('original delete parse warn:', e);
    }
    // 1) Storage-Thumbs & Hero löschen (alle bekannten Pfade mit Prefix)
    const prefixes = [
        `avatars/${avatarId}/documents/thumbs/${mediaId}_`,
        `avatars/${avatarId}/images/thumbs/${mediaId}_`,
        `avatars/${avatarId}/videos/thumbs/${mediaId}_`,
        `avatars/${avatarId}/audio/thumbs/${mediaId}`, // Audio: ohne Underscore!
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
        // Hero-Image ggf. löschen
        try {
            const hero = `avatars/${avatarId}/images/heroImage.jpg`;
            const [exists] = await bucket.file(hero).exists();
            if (exists) {
                // nur löschen, wenn dieses Media die Quelle des Hero war
                const data = snap.data();
                if ((data === null || data === void 0 ? void 0 : data.url) && typeof data.url === 'string') {
                    const avatarRef = db.collection('avatars').doc(avatarId);
                    const avatarSnap = await avatarRef.get();
                    const avatar = avatarSnap.data();
                    if ((avatar === null || avatar === void 0 ? void 0 : avatar.avatarImageUrl) && avatar.avatarImageUrl.includes('heroImage.jpg')) {
                        await bucket.file(hero).delete();
                        await avatarRef.update({ avatarImageUrl: admin.firestore.FieldValue.delete() });
                    }
                }
            }
        }
        catch (e) {
            console.warn('hero delete warn', e);
        }
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
/**
 * Backfill originalFileName für existierende Medien
 * Extrahiert den Dateinamen aus der URL und setzt ihn in Firestore
 */
exports.backfillOriginalFileNames = functions
    .region('us-central1')
    .runWith({ timeoutSeconds: 540, memory: '2GB' })
    .https.onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
        try {
            const db = admin.firestore();
            const avatars = await db.collection('avatars').get();
            const results = [];
            let updated = 0;
            let skipped = 0;
            for (const avatarDoc of avatars.docs) {
                const avatarId = avatarDoc.id;
                const allMedia = await getAllMediaDocs(avatarId);
                for (const data of allMedia) {
                    const mediaId = data.id;
                    // Skip wenn originalFileName bereits vorhanden
                    if (data.originalFileName && data.originalFileName.trim() !== '') {
                        skipped++;
                        continue;
                    }
                    // Extrahiere Dateinamen aus URL
                    try {
                        const url = data.url;
                        if (!url) {
                            results.push({ avatarId, mediaId, status: 'no_url' });
                            continue;
                        }
                        // Parse URL und extrahiere NUR den Dateinamen (ohne Pfad)
                        const urlObj = new URL(url);
                        const pathname = urlObj.pathname;
                        const segments = pathname.split('/');
                        let filename = segments[segments.length - 1];
                        // Entferne Query-Parameter
                        const queryIndex = filename.indexOf('?');
                        if (queryIndex >= 0) {
                            filename = filename.substring(0, queryIndex);
                        }
                        // Decode URL-Encoding
                        filename = decodeURIComponent(filename);
                        // Entferne alles VOR dem letzten Slash (falls noch Pfad drin ist)
                        const lastSlash = filename.lastIndexOf('/');
                        if (lastSlash >= 0) {
                            filename = filename.substring(lastSlash + 1);
                        }
                        // Update in Firestore
                        const docRef = db.collection('avatars').doc(avatarId).collection(getCollectionName(data.type)).doc(mediaId);
                        await docRef.update({ originalFileName: filename });
                        updated++;
                        results.push({
                            avatarId,
                            mediaId,
                            type: data.type,
                            status: 'updated',
                            originalFileName: filename,
                        });
                    }
                    catch (e) {
                        results.push({
                            avatarId,
                            mediaId,
                            status: 'error',
                            error: e.message
                        });
                    }
                }
            }
            res.status(200).json({
                success: true,
                updated,
                skipped,
                total: updated + skipped,
                results: results.slice(0, 100), // Nur erste 100 für Ausgabe
            });
        }
        catch (e) {
            res.status(500).json({ error: e.message });
        }
    });
});
// HTTP Function: Backfill fehlender Firestore-Einträge für Videos in Storage
exports.backfillVideoDocuments = functions
    .runWith({ timeoutSeconds: 540, memory: '1GB' })
    .https.onRequest(async (req, res) => {
    const corsHandler = (0, cors_1.default)({ origin: true });
    corsHandler(req, res, async () => {
        try {
            const db = admin.firestore();
            const bucket = admin.storage().bucket();
            const results = [];
            let created = 0;
            let skipped = 0;
            // Hole alle Avatare
            const avatarsSnapshot = await db.collection('avatars').get();
            for (const avatarDoc of avatarsSnapshot.docs) {
                const avatarId = avatarDoc.id;
                console.log(`📹 Prüfe Avatar: ${avatarId}`);
                // Liste alle Videos in Storage für diesen Avatar
                const [files] = await bucket.getFiles({
                    prefix: `avatars/${avatarId}/videos/`,
                });
                const videoFiles = files.filter((f) => !f.name.includes('/thumbs/') &&
                    (f.name.endsWith('.mp4') || f.name.endsWith('.mov') || f.name.endsWith('.webm')));
                console.log(`📹 Gefundene Videos in Storage: ${videoFiles.length}`);
                for (const file of videoFiles) {
                    try {
                        const url = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(file.name)}?alt=media`;
                        // Extrahiere mediaId aus Dateiname (Format: {timestamp}_{originalName}.mp4)
                        const filename = path.basename(file.name);
                        const parts = filename.split('_');
                        const mediaId = parts[0]; // Timestamp als ID
                        // Prüfe, ob Firestore-Doc bereits existiert
                        const docRef = db.collection('avatars').doc(avatarId).collection('videos').doc(mediaId);
                        const docSnap = await docRef.get();
                        if (docSnap.exists) {
                            console.log(`⏭️  Video-Doc existiert bereits: ${mediaId}`);
                            skipped++;
                            continue;
                        }
                        // Erstelle Firestore-Dokument
                        const originalFileName = filename.substring(filename.indexOf('_') + 1); // Alles nach erstem _
                        const createdAt = parseInt(mediaId, 10);
                        const videoDoc = {
                            id: mediaId,
                            avatarId,
                            type: 'video',
                            url,
                            createdAt: isNaN(createdAt) ? Date.now() : createdAt,
                            originalFileName,
                            tags: ['video'],
                        };
                        await docRef.set(videoDoc);
                        console.log(`✅ Video-Doc erstellt: ${mediaId}`);
                        created++;
                        results.push({
                            avatarId,
                            mediaId,
                            url,
                            originalFileName,
                            status: 'created',
                        });
                    }
                    catch (e) {
                        console.error(`❌ Fehler bei Video ${file.name}: ${e.message}`);
                        results.push({
                            avatarId,
                            file: file.name,
                            status: 'error',
                            error: e.message,
                        });
                    }
                }
            }
            res.status(200).json({
                success: true,
                created,
                skipped,
                total: created + skipped,
                results: results.slice(0, 100),
            });
        }
        catch (e) {
            console.error(`❌ Backfill-Fehler: ${e.message}`);
            res.status(500).json({ error: e.message });
        }
    });
});
// HTTP Function: Extrahiere Frame an bestimmter Position für Video-Thumbnail
exports.extractVideoFrameAtPosition = functions
    .runWith({ timeoutSeconds: 180, memory: '2GB' })
    .https.onRequest(async (req, res) => {
    const corsHandler = (0, cors_1.default)({ origin: true });
    corsHandler(req, res, async () => {
        try {
            const { avatarId, mediaId, videoUrl, timeInSeconds } = req.body;
            if (!avatarId || !mediaId || !videoUrl || timeInSeconds === undefined) {
                res.status(400).json({
                    error: 'Missing required parameters: avatarId, mediaId, videoUrl, timeInSeconds'
                });
                return;
            }
            console.log(`🎬 Extrahiere Frame für Video ${mediaId} bei ${timeInSeconds}s`);
            // Download Video
            if (ffmpeg_static_1.default)
                fluent_ffmpeg_1.default.setFfmpegPath(ffmpeg_static_1.default);
            const tmpDir = os.tmpdir();
            const random = Math.random().toString(36).substring(7);
            const src = path.join(tmpDir, `${mediaId}_${random}.mp4`);
            const framePath = path.join(tmpDir, `${mediaId}_${random}_custom.jpg`);
            const videoRes = await node_fetch_1.default(videoUrl);
            if (!videoRes.ok) {
                throw new Error(`Video download failed: ${videoRes.status}`);
            }
            const buf = Buffer.from(await videoRes.arrayBuffer());
            fs.writeFileSync(src, buf);
            // Extrahiere Frame an gewünschter Position
            await new Promise((resolve, reject) => {
                fluent_ffmpeg_1.default(src)
                    .on('end', () => {
                    console.log(`✅ Frame extrahiert bei ${timeInSeconds}s`);
                    resolve();
                })
                    .on('error', (e) => {
                    console.error(`❌ FFmpeg Fehler:`, e);
                    reject(e);
                })
                    .screenshots({
                    count: 1,
                    timemarks: [timeInSeconds.toString()],
                    filename: path.basename(framePath),
                    folder: tmpDir,
                });
            });
            // Upload zu Storage
            const bucket = admin.storage().bucket();
            const dest = `avatars/${avatarId}/videos/thumbs/${mediaId}_custom_${Date.now()}.jpg`;
            await bucket.upload(framePath, {
                destination: dest,
                contentType: 'image/jpeg',
                metadata: { cacheControl: 'public,max-age=31536000,immutable' },
            });
            const [signed] = await bucket.file(dest).getSignedUrl({
                action: 'read',
                expires: Date.now() + 365 * 24 * 3600 * 1000
            });
            console.log(`✅ Custom Thumbnail erstellt: ${dest}`);
            // Update Firestore
            await admin.firestore()
                .collection('avatars').doc(avatarId)
                .collection('videos').doc(mediaId)
                .update({ thumbUrl: signed });
            // Cleanup
            try {
                fs.unlinkSync(src);
            }
            catch (_a) { }
            try {
                fs.unlinkSync(framePath);
            }
            catch (_b) { }
            res.status(200).json({
                success: true,
                thumbUrl: signed,
                message: `Thumbnail erstellt bei ${timeInSeconds}s`,
            });
        }
        catch (e) {
            console.error(`❌ Frame-Extraktion Fehler:`, e);
            res.status(500).json({ error: e.message });
        }
    });
});
// HTTP Function: Video-Trimming
exports.trimVideo = functions
    .runWith({ timeoutSeconds: 180, memory: '2GB' })
    .https.onRequest(async (req, res) => {
    const corsHandler = (0, cors_1.default)({ origin: true });
    corsHandler(req, res, async () => {
        try {
            const { video_url, start_time, end_time } = req.body;
            if (!video_url || start_time === undefined || end_time === undefined) {
                res.status(400).json({
                    error: 'Missing required parameters: video_url, start_time, end_time'
                });
                return;
            }
            console.log(`✂️ Trimme Video: ${start_time}s bis ${end_time}s`);
            // Download Video
            if (ffmpeg_static_1.default)
                fluent_ffmpeg_1.default.setFfmpegPath(ffmpeg_static_1.default);
            const tmpDir = os.tmpdir();
            const random = Math.random().toString(36).substring(7);
            const src = path.join(tmpDir, `input_${random}.mp4`);
            const output = path.join(tmpDir, `trimmed_${random}.mp4`);
            const videoRes = await node_fetch_1.default(video_url);
            if (!videoRes.ok) {
                throw new Error(`Video download failed: ${videoRes.status}`);
            }
            const buf = Buffer.from(await videoRes.arrayBuffer());
            fs.writeFileSync(src, buf);
            // Video mit ffmpeg trimmen (SCHNELL: Stream Copy ohne Re-Encoding!)
            const duration = end_time - start_time;
            await new Promise((resolve, reject) => {
                fluent_ffmpeg_1.default(src)
                    .on('end', () => {
                    console.log(`✅ Video getrimmt: ${duration}s`);
                    resolve();
                })
                    .on('error', (e) => {
                    console.error(`❌ FFmpeg Fehler:`, e);
                    reject(e);
                })
                    .seekInput(start_time)
                    .duration(duration)
                    .videoCodec('copy') // STREAM COPY = SUPER SCHNELL!
                    .audioCodec('copy') // STREAM COPY = SUPER SCHNELL!
                    .output(output)
                    .run();
            });
            // Getrimmtes Video zurückgeben
            const trimmedBuffer = fs.readFileSync(output);
            // Cleanup
            try {
                fs.unlinkSync(src);
            }
            catch (_a) { }
            try {
                fs.unlinkSync(output);
            }
            catch (_b) { }
            res.status(200)
                .set('Content-Type', 'video/mp4')
                .set('Content-Disposition', 'attachment; filename="trimmed_video.mp4"')
                .send(trimmedBuffer);
        }
        catch (e) {
            console.error(`❌ Video-Trimming Fehler:`, e);
            res.status(500).json({ error: e.message });
        }
    });
});
// HTTP Function: Generiere Thumbnails für alle Videos ohne thumbUrl
exports.generateMissingVideoThumbs = functions
    .runWith({ timeoutSeconds: 540, memory: '2GB' })
    .https.onRequest(async (req, res) => {
    const corsHandler = (0, cors_1.default)({ origin: true });
    corsHandler(req, res, async () => {
        try {
            const db = admin.firestore();
            const results = [];
            let processed = 0;
            // Hole alle Avatare
            const avatarsSnapshot = await db.collection('avatars').get();
            for (const avatarDoc of avatarsSnapshot.docs) {
                const avatarId = avatarDoc.id;
                console.log(`🎬 Prüfe Avatar: ${avatarId}`);
                // Hole alle Videos ohne thumbUrl
                const videosSnapshot = await db.collection('avatars')
                    .doc(avatarId)
                    .collection('videos')
                    .get();
                for (const videoDoc of videosSnapshot.docs) {
                    const data = videoDoc.data();
                    const mediaId = videoDoc.id;
                    // Prüfe ob thumbUrl fehlt
                    if (!data.thumbUrl && data.url) {
                        console.log(`🎬 Generiere Thumbnail für Video: ${mediaId}`);
                        try {
                            await createVideoThumbFromFirstFrame(avatarId, mediaId, data.url);
                            processed++;
                            results.push({
                                avatarId,
                                mediaId,
                                status: 'success',
                            });
                            console.log(`✅ Thumbnail generiert für: ${mediaId}`);
                        }
                        catch (e) {
                            console.error(`❌ Fehler bei Thumbnail-Generierung für ${mediaId}:`, e);
                            results.push({
                                avatarId,
                                mediaId,
                                status: 'error',
                                error: e.message,
                            });
                        }
                    }
                }
            }
            res.status(200).json({
                success: true,
                processed,
                results: results.slice(0, 100),
            });
        }
        catch (e) {
            console.error(`❌ Generate-Thumbnails-Fehler: ${e.message}`);
            res.status(500).json({ error: e.message });
        }
    });
});
//# sourceMappingURL=index.js.map