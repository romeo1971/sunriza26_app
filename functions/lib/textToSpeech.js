"use strict";
/**
 * Google Cloud Text-to-Speech Integration
 * Stand: 04.09.2025 - Mit Custom Voice Support für geklonte Stimmen
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateSpeech = generateSpeech;
exports.generateSSML = generateSSML;
exports.validateTextLength = validateTextLength;
const text_to_speech_1 = require("@google-cloud/text-to-speech");
const config_1 = require("./config");
/**
 * Generiert Audio aus Text mit Custom Voice Model
 * Optimiert für Live-Streaming und Vertex AI Integration
 */
async function generateSpeech(request) {
    const config = await (0, config_1.getConfig)();
    const client = new text_to_speech_1.TextToSpeechClient();
    try {
        console.log(`Generiere Speech für Text: "${request.text.substring(0, 50)}..."`);
        console.log(`Verwende Custom Voice: ${config.customVoiceName}`);
        const buildReq = (useCustom) => ({
            input: { text: request.text },
            voice: useCustom
                ? {
                    languageCode: request.languageCode || 'de-DE',
                    name: config.customVoiceName,
                    ssmlGender: request.ssmlGender || 'NEUTRAL',
                }
                : {
                    languageCode: request.languageCode || 'de-DE',
                    ssmlGender: request.ssmlGender || 'NEUTRAL',
                },
            audioConfig: {
                // Für Lipsync/Vertex: LINEAR16 (PCM, 24 kHz)
                audioEncoding: 'LINEAR16',
                sampleRateHertz: 24000,
                speakingRate: 1.0,
                pitch: 0.0,
                volumeGainDb: 0.0,
            },
        });
        const tryCustom = !!config.customVoiceName && !config.customVoiceName.includes('default-voice');
        let response;
        try {
            [response] = await client.synthesizeSpeech(buildReq(tryCustom));
        }
        catch (e) {
            console.warn('Custom Voice fehlgeschlagen, fallback auf Standard-Voice:', e);
            [response] = await client.synthesizeSpeech(buildReq(false));
        }
        if (!response.audioContent) {
            throw new Error('Kein Audio-Content von Text-to-Speech API erhalten');
        }
        const audioBuffer = Buffer.from(response.audioContent);
        console.log(`Audio generiert: ${audioBuffer.length} Bytes`);
        return {
            audioContent: audioBuffer,
            audioConfig: {
                audioEncoding: 'LINEAR16',
                sampleRateHertz: 24000,
            },
        };
    }
    catch (error) {
        console.error('Fehler bei Text-to-Speech Generierung:', error);
        throw new Error(`TTS Fehler: ${error instanceof Error ? error.message : 'Unbekannter Fehler'}`);
    }
}
/**
 * Generiert SSML für erweiterte Sprachsteuerung
 * Nützlich für Pausen, Betonungen und natürlichere Sprache
 */
function generateSSML(text, pauseMs = 500) {
    return `
    <speak>
      <prosody rate="1.0" pitch="0.0">
        ${text}
      </prosody>
      <break time="${pauseMs}ms"/>
    </speak>
  `.trim();
}
/**
 * Validiert Text-Länge für optimale Performance
 */
function validateTextLength(text) {
    const maxLength = 5000; // Google TTS Limit
    if (text.length > maxLength) {
        return {
            isValid: false,
            message: `Text zu lang. Maximum: ${maxLength} Zeichen, aktuell: ${text.length}`
        };
    }
    if (text.trim().length === 0) {
        return {
            isValid: false,
            message: 'Text darf nicht leer sein'
        };
    }
    return { isValid: true };
}
//# sourceMappingURL=textToSpeech.js.map