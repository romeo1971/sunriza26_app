import { onRequest } from 'firebase-functions/v2/https';
import { RAGService } from './rag_service';
import * as admin from 'firebase-admin';

// Admin init (idempotent)
if (!admin.apps.length) {
  try {
    admin.initializeApp();
  } catch (_) {}
}

export const avatarChat = onRequest({ 
  region: 'us-central1', 
  cors: true,
  invoker: 'public',
  secrets: ['OPENAI_API_KEY', 'PINECONE_API_KEY', 'GOOGLE_CSE_API_KEY', 'GOOGLE_CSE_CX']
}, async (req, res) => {
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  try {
    const { message, avatarId, userId, voiceId, room } = (req.body || {}) as {
      message?: string;
      avatarId?: string;
      userId?: string;
      voiceId?: string;
      room?: string;
    };

    if (!message || !avatarId || !userId) {
      res.status(400).json({ error: 'message, avatarId und userId erforderlich' });
      return;
    }

    // Persistiere Chat serverseitig in Firestore
    const db = admin.firestore();
    const chatId = `${userId}_${avatarId}`;
    const now = Date.now();
    const chatRef = db.collection('avatarUserChats').doc(chatId);
    const messagesRef = chatRef.collection('messages');

    // Chat-Metadaten updaten
    await chatRef.set({ userId, avatarId, updatedAt: now }, { merge: true });

    // User-Nachricht speichern
    await messagesRef.add({
      sender: 'user',
      content: message,
      text: message, // Backwards-Compat
      timestamp: now,
    });

    const rag = new RAGService();
    const response = await rag.generateAvatarResponse({
      query: message,
      userId,
      avatarId,
    });

    // Avatar-Antwort speichern
    const answerText = response.response;
    await messagesRef.add({
      sender: 'avatar',
      content: answerText,
      text: answerText, // Backwards-Compat
      timestamp: Date.now(),
      confidence: response.confidence,
      sources: response.sources,
    });

    // Orchestrator-Hook (serverseitiges Lipsync): nur wenn voiceId & room vorhanden
    let speakTriggered = false;
    try {
      if (voiceId && typeof room === 'string' && room.trim().length > 0) {
        const base = (process.env.ORCHESTRATOR_HTTP_BASE || 'https://romeo1971--lipsync-orchestrator-asgi.modal.run/')
          .toString()
          .replace(/\/$/, '');
        const speakUrl = `${base}/speak`;
        const payload = {
          text: answerText,
          room: room.trim(),
          voice_id: voiceId,
        } as any;
        // Fire-and-forget, aber Fehler loggen
        (globalThis as any).fetch(speakUrl as any, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' } as any,
          body: JSON.stringify(payload),
        } as any).catch(() => {});
        speakTriggered = true;
      }
    } catch (_) {}

    res.status(200).json({
      answer: response.response,
      sources: response.sources,
      confidence: response.confidence,
      avatarId,
      voiceId: voiceId || null,
      room: room || null,
      speakTriggered,
    });
  } catch (e: any) {
    // eslint-disable-next-line no-console
    console.error('avatarChat error:', e);
    res.status(500).json({ error: 'Chat-Verarbeitung fehlgeschlagen', details: e?.message || String(e) });
  }
});
