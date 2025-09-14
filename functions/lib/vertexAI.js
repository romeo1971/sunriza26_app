"use strict";
/**
 * Google Cloud Vertex AI Integration für Live-Video-Lippensynchronisation
 * Stand: 04.09.2025 - Mit neuesten Generative AI Modellen für Video
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateLipsyncVideo = generateLipsyncVideo;
exports.validateVideoRequest = validateVideoRequest;
const vertexai_1 = require("@google-cloud/vertexai");
const config_1 = require("./config");
/**
 * Generiert Live-Video mit Lippen-Synchronisation über Vertex AI
 * Verwendet die neuesten Generative AI Modelle für Video-to-Video-Synthesis
 */
async function generateLipsyncVideo(request) {
    const config = await (0, config_1.getConfig)();
    try {
        console.log('Initialisiere Vertex AI für Video-Generierung...');
        // Vertex AI Client initialisieren
        const vertexAI = new vertexai_1.VertexAI({
            project: config.projectId,
            location: config.location,
        });
        // Modell für Video-Generierung auswählen
        // Stand 04.09.2025: Imagen Video Generator oder ähnliche Modelle
        const model = vertexAI.getGenerativeModel({
            model: config.vertexAiModelId,
        });
        console.log(`Verwende Modell: ${config.vertexAiModelId}`);
        console.log(`Referenzvideo: ${request.referenceVideoUrl}`);
        // Audio in Base64 für Vertex AI konvertieren
        const audioBase64 = request.audioBuffer.toString('base64');
        // Prompt für Video-Generierung erstellen
        const prompt = createVideoGenerationPrompt(request.text, request.referenceVideoUrl);
        // Generative AI Request für Video-Lippensynchronisation
        const generativeRequest = {
            contents: [
                {
                    role: 'user',
                    parts: [
                        {
                            text: prompt,
                        },
                        {
                            inlineData: {
                                mimeType: 'audio/wav',
                                data: audioBase64,
                            },
                        },
                    ],
                },
            ],
            generationConfig: {
                temperature: 0.7,
                topK: 40,
                topP: 0.95,
                maxOutputTokens: 8192,
            },
        };
        console.log('Starte Video-Generierung mit Vertex AI...');
        // Streaming Response von Vertex AI
        const result = await model.generateContentStream(generativeRequest);
        // Stream für Live-Übertragung vorbereiten
        const videoStream = new (require('stream').Readable)({
            read() {
                // Stream wird von Vertex AI gefüllt
            }
        });
        // Vertex AI Response verarbeiten und in Stream umleiten
        ;
        result.stream.on('data', (chunk) => {
            var _a, _b, _c, _d, _e;
            if ((_e = (_d = (_c = (_b = (_a = chunk.candidates) === null || _a === void 0 ? void 0 : _a[0]) === null || _b === void 0 ? void 0 : _b.content) === null || _c === void 0 ? void 0 : _c.parts) === null || _d === void 0 ? void 0 : _d[0]) === null || _e === void 0 ? void 0 : _e.inlineData) {
                const videoData = chunk.candidates[0].content.parts[0].inlineData.data;
                const videoBuffer = Buffer.from(videoData, 'base64');
                videoStream.push(videoBuffer);
            }
        });
        ;
        result.stream.on('end', () => {
            videoStream.push(null); // Stream beenden
        });
        ;
        result.stream.on('error', (error) => {
            console.error('Vertex AI Stream Fehler:', error);
            videoStream.destroy(error);
        });
        return {
            videoStream,
            contentType: 'video/mp4',
            metadata: {
                duration: estimateVideoDuration(request.audioBuffer.length, request.audioConfig.sampleRateHertz),
                resolution: '1920x1080',
                format: 'mp4',
            },
        };
    }
    catch (error) {
        console.error('Fehler bei Vertex AI Video-Generierung:', error);
        throw new Error(`Vertex AI Fehler: ${error instanceof Error ? error.message : 'Unbekannter Fehler'}`);
    }
}
/**
 * Erstellt optimierten Prompt für Video-Lippensynchronisation
 */
function createVideoGenerationPrompt(text, referenceVideoUrl) {
    return `
    Erstelle ein Video mit perfekter Lippen-Synchronisation basierend auf:
    
    REFERENZVIDEO: ${referenceVideoUrl}
    AUDIO: Das bereitgestellte Audio (LINEAR16, 24kHz)
    TEXT: "${text}"
    
    ANFORDERUNGEN:
    1. Synchronisiere die Lippenbewegungen im Referenzvideo exakt mit dem neuen Audio
    2. Behalte alle anderen visuellen Elemente (Hintergrund, Beleuchtung, etc.) bei
    3. Stelle sicher, dass die Lippenbewegungen natürlich und realistisch aussehen
    4. Das Video soll in Echtzeit generiert werden (Streaming-optimiert)
    5. Verwende hohe Qualität (1920x1080, 30fps)
    
    TECHNISCHE SPEZIFIKATIONEN:
    - Format: MP4
    - Codec: H.264
    - Bitrate: 5-10 Mbps
    - Optimiert für Live-Streaming
    
    Gib das Video als kontinuierlichen Stream zurück, beginnend mit dem ersten Frame.
  `.trim();
}
/**
 * Schätzt Video-Dauer basierend auf Audio-Länge
 */
function estimateVideoDuration(audioBufferLength, sampleRate) {
    // Berechnung: Buffer-Länge / (Sample-Rate * Bytes pro Sample * Kanäle)
    const bytesPerSample = 2; // 16-bit = 2 Bytes
    const channels = 1; // Mono
    const durationSeconds = audioBufferLength / (sampleRate * bytesPerSample * channels);
    return Math.ceil(durationSeconds);
}
/**
 * Validiert Video-Generierungs-Request
 */
function validateVideoRequest(request) {
    if (!request.audioBuffer || request.audioBuffer.length === 0) {
        return {
            isValid: false,
            message: 'Audio-Buffer ist leer'
        };
    }
    if (!request.referenceVideoUrl || !request.referenceVideoUrl.startsWith('gs://')) {
        return {
            isValid: false,
            message: 'Ungültige Referenzvideo-URL'
        };
    }
    if (!request.text || request.text.trim().length === 0) {
        return {
            isValid: false,
            message: 'Text ist leer'
        };
    }
    return { isValid: true };
}
//# sourceMappingURL=vertexAI.js.map