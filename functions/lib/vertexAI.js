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
// import { TTSResponse } from './textToSpeech';
const buffer_1 = require("buffer");
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
        const modelId = config.vertexAiModelId || 'gemini-pro-vision';
        const model = vertexAI.getGenerativeModel({
            model: modelId,
        });
        console.log(`Verwende Modell: ${modelId}`);
        console.log(`Referenzvideo: ${request.referenceVideoUrl}`);
        // PCM (LINEAR16) in WAV verpacken (24kHz, Mono), damit Vertex 'audio/wav' korrekt versteht
        const wavBuffer = pcmToWav(request.audioBuffer, request.audioConfig.sampleRateHertz || 24000, 1, 16);
        const audioBase64 = wavBuffer.toString('base64');
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
                const videoBuffer = buffer_1.Buffer.from(videoData, 'base64');
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
// Hilfsfunktion: PCM (LINEAR16) → WAV mit Header
function pcmToWav(pcm, sampleRate, channels, bitDepth) {
    const byteRate = (sampleRate * channels * bitDepth) / 8;
    const blockAlign = (channels * bitDepth) / 8;
    const wavHeader = buffer_1.Buffer.alloc(44);
    wavHeader.write('RIFF', 0); // ChunkID
    wavHeader.writeUInt32LE(36 + pcm.length, 4); // ChunkSize
    wavHeader.write('WAVE', 8); // Format
    wavHeader.write('fmt ', 12); // Subchunk1ID
    wavHeader.writeUInt32LE(16, 16); // Subchunk1Size (PCM)
    wavHeader.writeUInt16LE(1, 20); // AudioFormat (PCM=1)
    wavHeader.writeUInt16LE(channels, 22); // NumChannels
    wavHeader.writeUInt32LE(sampleRate, 24); // SampleRate
    wavHeader.writeUInt32LE(byteRate, 28); // ByteRate
    wavHeader.writeUInt16LE(blockAlign, 32); // BlockAlign
    wavHeader.writeUInt16LE(bitDepth, 34); // BitsPerSample
    wavHeader.write('data', 36); // Subchunk2ID
    wavHeader.writeUInt32LE(pcm.length, 40); // Subchunk2Size
    return buffer_1.Buffer.concat([wavHeader, pcm]);
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