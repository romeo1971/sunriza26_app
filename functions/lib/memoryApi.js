"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.avatarMemoryInsert = void 0;
const https_1 = require("firebase-functions/v2/https");
const pinecone_service_1 = require("./pinecone_service");
exports.avatarMemoryInsert = (0, https_1.onRequest)({
    region: 'us-central1',
    cors: true,
    invoker: 'public',
    secrets: ['OPENAI_API_KEY', 'PINECONE_API_KEY'],
    timeoutSeconds: 540,
    memory: '512MiB',
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
        const { user_id, avatar_id, full_text, source, file_name, } = req.body || {};
        if (!user_id || !avatar_id || !full_text) {
            res.status(400).json({ error: 'user_id, avatar_id und full_text erforderlich' });
            return;
        }
        // Per-Avatar Index ermitteln (wie Python-Backend)
        const mode = (process.env.PINECONE_INDEX_MODE || 'per_avatar').toLowerCase();
        const base = process.env.PINECONE_INDEX || 'avatars-index';
        let indexName;
        if (mode === 'per_avatar') {
            const san = (s) => (s || '').toLowerCase().replace(/[^a-z0-9-]/g, '-');
            indexName = `${base}-${san(user_id).slice(0, 24)}-${san(avatar_id).slice(0, 24)}`.slice(0, 45);
        }
        else {
            indexName = process.env.PINECONE_GLOBAL_INDEX || 'sunriza26-avatar-data';
        }
        const pinecone = new pinecone_service_1.PineconeService();
        const documentId = `${user_id}_${avatar_id}_${Date.now()}`;
        const namespace = `${user_id}_${avatar_id}`;
        const metadata = {
            type: 'text',
            userId: user_id,
            uploadDate: new Date().toISOString(),
            originalFileName: file_name || 'memory_insert',
            contentType: 'text/plain',
            size: full_text.length,
            description: source || 'app',
            tags: [avatar_id],
        };
        // Store in Pinecone mit per-avatar Index
        await pinecone.storeDocumentWithIndex(indexName, documentId, full_text, metadata, namespace);
        res.status(200).json({
            namespace: `${user_id}_${avatar_id}`,
            inserted: 1,
            index_name: indexName,
            model: 'text-embedding-3-small',
        });
    }
    catch (error) {
        console.error('Memory insert error:', error);
        res.status(500).json({ error: (error === null || error === void 0 ? void 0 : error.message) || 'Memory insert failed' });
    }
});
//# sourceMappingURL=memoryApi.js.map