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
        const pinecone = new pinecone_service_1.PineconeService();
        const documentId = `${user_id}_${avatar_id}_${Date.now()}`;
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
        // Store in Pinecone
        await pinecone.storeDocument(documentId, full_text, metadata);
        res.status(200).json({
            namespace: `${user_id}_${avatar_id}`,
            inserted: 1,
            index_name: 'sunriza26-avatar-data',
            model: 'text-embedding-3-small',
        });
    }
    catch (error) {
        console.error('Memory insert error:', error);
        res.status(500).json({ error: (error === null || error === void 0 ? void 0 : error.message) || 'Memory insert failed' });
    }
});
//# sourceMappingURL=memoryApi.js.map