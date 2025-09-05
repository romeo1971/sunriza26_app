/**
 * Google Cloud Text-to-Speech Integration
 * Stand: 04.09.2025 - Mit Custom Voice Support für geklonte Stimmen
 */

import { TextToSpeechClient } from '@google-cloud/text-to-speech';
import { getConfig } from './config';

export interface TTSRequest {
  text: string;
  languageCode?: string;
  ssmlGender?: 'NEUTRAL' | 'MALE' | 'FEMALE';
}

export interface TTSResponse {
  audioContent: Buffer;
  audioConfig: {
    audioEncoding: string;
    sampleRateHertz: number;
  };
}

/**
 * Generiert Audio aus Text mit Custom Voice Model
 * Optimiert für Live-Streaming und Vertex AI Integration
 */
export async function generateSpeech(request: TTSRequest): Promise<TTSResponse> {
  const config = await getConfig();
  const client = new TextToSpeechClient();

  try {
    console.log(`Generiere Speech für Text: "${request.text.substring(0, 50)}..."`);
    console.log(`Verwende Custom Voice: ${config.customVoiceName}`);

    const ttsRequest = {
      input: {
        text: request.text,
      },
      voice: {
        languageCode: request.languageCode || 'de-DE',
        name: config.customVoiceName,
        ssmlGender: request.ssmlGender || 'NEUTRAL',
      },
      audioConfig: {
        audioEncoding: 'LINEAR16' as const, // Optimal für Vertex AI Video-Generierung
        sampleRateHertz: 24000, // Hohe Qualität für bessere Lippen-Synchronisation
        speakingRate: 1.0,
        pitch: 0.0,
        volumeGainDb: 0.0,
      },
    };

    const [response] = await client.synthesizeSpeech(ttsRequest);
    
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

  } catch (error) {
    console.error('Fehler bei Text-to-Speech Generierung:', error);
    throw new Error(`TTS Fehler: ${error instanceof Error ? error.message : 'Unbekannter Fehler'}`);
  }
}

/**
 * Generiert SSML für erweiterte Sprachsteuerung
 * Nützlich für Pausen, Betonungen und natürlichere Sprache
 */
export function generateSSML(text: string, pauseMs: number = 500): string {
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
export function validateTextLength(text: string): { isValid: boolean; message?: string } {
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
