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
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
var _a;
Object.defineProperty(exports, "__esModule", { value: true });
exports.validateRAGSystem = exports.generateAvatarResponse = exports.processDocument = exports.tts = exports.testTTS = exports.healthCheck = exports.generateLiveVideo = void 0;
require("dotenv/config");
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
const cors_1 = __importDefault(require("cors"));
const textToSpeech_1 = require("./textToSpeech");
const vertexAI_1 = require("./vertexAI");
const config_1 = require("./config");
const rag_service_1 = require("./rag_service");
// Entfernt: Unbenutzte Importe aus pinecone_service
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
            const { text } = req.body;
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
            // Video-Stream an Client weiterleiten
            videoResponse.videoStream.on('data', (chunk) => {
                res.write(chunk);
            });
            videoResponse.videoStream.on('end', () => {
                console.log('Video-Stream beendet');
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
    .runWith({ secrets: ['ELEVEN_API_KEY', 'ELEVEN_VOICE_ID', 'ELEVEN_TTS_MODEL'] })
    .https
    .onRequest(async (req, res) => {
    return corsHandler(req, res, async () => {
        try {
            if (req.method !== 'POST') {
                res.status(405).json({ error: 'Nur POST Requests erlaubt' });
                return;
            }
            const { text } = req.body;
            if (!text) {
                res.status(400).json({ error: 'Text ist erforderlich' });
                return;
            }
            // 1) ElevenLabs bevorzugen, falls Key vorhanden
            const elevenKey = process.env.ELEVEN_API_KEY;
            if (elevenKey) {
                try {
                    const voiceId = process.env.ELEVEN_VOICE_ID || '21m00Tcm4TlvDq8ikWAM';
                    const modelId = process.env.ELEVEN_TTS_MODEL || 'eleven_multilingual_v2';
                    const stability = parseFloat(process.env.ELEVEN_STABILITY || '0.5');
                    const similarity = parseFloat(process.env.ELEVEN_SIMILARITY || '0.75');
                    const r = await globalThis.fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`, {
                        method: 'POST',
                        headers: {
                            'xi-api-key': elevenKey,
                            'Content-Type': 'application/json',
                            'Accept': 'audio/mpeg',
                        },
                        body: JSON.stringify({
                            text,
                            model_id: modelId,
                            voice_settings: { stability, similarity_boost: similarity },
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
//# sourceMappingURL=index.js.map