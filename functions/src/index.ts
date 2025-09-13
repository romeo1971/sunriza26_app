/**
 * Haupt-Cloud Function für Live AI-Assistenten
 * Stand: 04.09.2025 - Mit geklonter Stimme und Echtzeit-Video-Lippensynchronisation
 */

import 'dotenv/config';
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as cors from 'cors';
import { generateSpeech } from './textToSpeech';
import { generateLipsyncVideo, validateVideoRequest } from './vertexAI';
import { getConfig } from './config';
import { RAGService } from './rag_service';
import { PineconeService, DocumentMetadata } from './pinecone_service';

// Firebase Admin initialisieren
admin.initializeApp();

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
          } else {
            res.end();
          }
        });

        // Client-Disconnect Handling
        req.on('close', () => {
          console.log('Client hat Verbindung getrennt');
          videoResponse.videoStream.destroy();
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

        const ttsResponse = await generateSpeech({
          text: text,
          languageCode: 'de-DE',
        });

        res.setHeader('Content-Type', 'audio/wav');
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

/**
 * RAG-System: Verarbeitet hochgeladene Dokumente
 */
export const processDocument = functions
  .region('us-central1')
  .runWith({
    timeoutSeconds: 300,
    memory: '1GB',
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
