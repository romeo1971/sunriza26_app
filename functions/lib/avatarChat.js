"use strict";
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
Object.defineProperty(exports, "__esModule", { value: true });
exports.avatarChat = void 0;
const https_1 = require("firebase-functions/v2/https");
const rag_service_1 = require("./rag_service");
const admin = __importStar(require("firebase-admin"));
// Admin init (idempotent)
if (!admin.apps.length) {
    try {
        admin.initializeApp();
    }
    catch (_) { }
}
exports.avatarChat = (0, https_1.onRequest)({
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
        const { message, avatarId, userId, voiceId, room } = (req.body || {});
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
        const rag = new rag_service_1.RAGService();
        const response = await rag.generateAvatarResponse({
            query: message,
            userId,
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
                };
                // Fire-and-forget, aber Fehler loggen
                globalThis.fetch(speakUrl, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(payload),
                }).catch(() => { });
                speakTriggered = true;
            }
        }
        catch (_) { }
        res.status(200).json({
            answer: response.response,
            sources: response.sources,
            confidence: response.confidence,
            avatarId,
            voiceId: voiceId || null,
            room: room || null,
            speakTriggered,
        });
    }
    catch (e) {
        // eslint-disable-next-line no-console
        console.error('avatarChat error:', e);
        res.status(500).json({ error: 'Chat-Verarbeitung fehlgeschlagen', details: (e === null || e === void 0 ? void 0 : e.message) || String(e) });
    }
});
//# sourceMappingURL=avatarChat.js.map