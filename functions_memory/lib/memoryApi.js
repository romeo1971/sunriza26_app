"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.avatarMemoryInsertV2 = void 0;
const https_1 = require("firebase-functions/v2/https");
const node_fetch_1 = __importDefault(require("node-fetch"));
// Chunking-Funktion (portiert aus Python-Backend)
function chunkText(text, targetTokens = 900, overlap = 100, minChunkTokens = 630) {
    text = (text || '').trim();
    if (!text)
        return [];
    // Naive Split (~4 Zeichen pro Token)
    const approxChars = Math.max(targetTokens * 4, 2000);
    const chunks = [];
    let start = 0;
    let idx = 0;
    while (start < text.length) {
        const end = Math.min(text.length, start + approxChars);
        const chunk = text.substring(start, end);
        chunks.push({ index: idx, text: chunk });
        start = end - Math.min(overlap * 4, end);
        idx++;
    }
    // Merge zu kleine letzte Chunks
    const approxTokens = (s) => Math.max(1, Math.floor(s.length / 4));
    while (chunks.length >= 2 && approxTokens(chunks[chunks.length - 1].text) < minChunkTokens) {
        const prev = chunks[chunks.length - 2].text;
        const last = chunks[chunks.length - 1].text;
        chunks[chunks.length - 2].text = (prev + '\n\n' + last).trim();
        chunks.pop();
    }
    // Reindex
    chunks.forEach((c, i) => (c.index = i));
    return chunks;
}
exports.avatarMemoryInsertV2 = (0, https_1.onRequest)({
    region: 'us-central1',
    cors: true,
    invoker: 'public',
    secrets: ['OPENAI_API_KEY', 'PINECONE_API_KEY'],
    timeoutSeconds: 540,
    memory: '4GiB',
    concurrency: 1,
    minInstances: 0,
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
        const { user_id, avatar_id, full_text, source, file_name, target_tokens = 900, overlap = 100, min_chunk_tokens = 630, } = req.body || {};
        if (!user_id || !avatar_id || !full_text) {
            res.status(400).json({ error: 'user_id, avatar_id und full_text erforderlich' });
            return;
        }
        // Input-Größen-Limit (verhindert OOM)
        const MAX_INPUT_SIZE = 5000000; // 5MB Text
        if (full_text.length > MAX_INPUT_SIZE) {
            res.status(400).json({
                error: `Text zu groß: ${full_text.length} chars (max: ${MAX_INPUT_SIZE})`,
                suggestion: 'Bitte in kleinere Teile aufteilen'
            });
            return;
        }
        // Chunking
        const chunks = chunkText(full_text, target_tokens, overlap, min_chunk_tokens);
        if (chunks.length === 0) {
            res.status(400).json({ error: 'full_text ist leer' });
            return;
        }
        // Secrets
        const OPENAI_API_KEY = (process.env.OPENAI_API_KEY || '').trim();
        const PINECONE_API_KEY = (process.env.PINECONE_API_KEY || '').trim();
        if (!OPENAI_API_KEY || !PINECONE_API_KEY) {
            res.status(500).json({ error: 'Server secrets missing' });
            return;
        }
        const indexName = process.env.PINECONE_GLOBAL_INDEX || 'sunriza26-avatar-data';
        const namespace = `${user_id}_${avatar_id}`;
        // Pinecone Host abrufen (einmalig)
        const hostResp = await (0, node_fetch_1.default)(`https://api.pinecone.io/indexes/${indexName}`, {
            method: 'GET',
            headers: { 'Api-Key': PINECONE_API_KEY },
        });
        if (!hostResp.ok) {
            const body = await hostResp.text();
            res.status(hostResp.status).json({ error: `Pinecone host lookup failed: ${body}` });
            return;
        }
        const hostJson = await hostResp.json();
        const host = hostJson === null || hostJson === void 0 ? void 0 : hostJson.host;
        if (!host) {
            res.status(500).json({ error: 'Pinecone host missing' });
            return;
        }
        // ========== BATCH PROCESSING (verhindert Memory-Spikes) ==========
        // WICHTIG: Klein halten wegen JSON.stringify() Memory-Overhead in Node.js!
        const BATCH_SIZE = 10; // Max 10 Chunks pro Batch (JSON.stringify safe)
        const docId = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
        const createdAt = Date.now();
        let totalInserted = 0;
        for (let i = 0; i < chunks.length; i += BATCH_SIZE) {
            const batchChunks = chunks.slice(i, i + BATCH_SIZE);
            const batchTexts = batchChunks.map(c => c.text);
            // 1) Embeddings für diesen Batch
            const embResp = await (0, node_fetch_1.default)('https://api.openai.com/v1/embeddings', {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${OPENAI_API_KEY}`,
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ model: 'text-embedding-3-small', input: batchTexts }),
            });
            if (!embResp.ok) {
                const body = await embResp.text();
                res.status(embResp.status).json({
                    error: `OpenAI embeddings failed at batch ${i}: ${body}`
                });
                return;
            }
            const embJson = await embResp.json();
            const batchEmbeddings = (embJson.data || []).map((d) => d.embedding);
            // 2) Vektoren für diesen Batch vorbereiten
            const batchVectors = batchChunks.map((chunk, idx) => {
                const meta = {
                    user_id,
                    avatar_id,
                    chunk_index: chunk.index,
                    doc_id: docId,
                    created_at: createdAt,
                    source: source || 'app',
                    text: chunk.text,
                };
                if (file_name)
                    meta.file_name = file_name;
                return {
                    id: `${avatar_id}-${docId}-${chunk.index}`,
                    values: batchEmbeddings[idx],
                    metadata: meta,
                };
            });
            // 3) Batch in Pinecone upserten
            const upsertResp = await (0, node_fetch_1.default)(`https://${host}/vectors/upsert`, {
                method: 'POST',
                headers: {
                    'Api-Key': PINECONE_API_KEY,
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ namespace, vectors: batchVectors }),
            });
            if (!upsertResp.ok) {
                const body = await upsertResp.text();
                res.status(upsertResp.status).json({
                    error: `Pinecone upsert failed at batch ${i}: ${body}`
                });
                return;
            }
            totalInserted += batchVectors.length;
            // Memory-Freigabe: Explizit null setzen (hilft GC)
            batchTexts = null;
            batchEmbeddings = null;
            batchVectors = null;
        }
        res.status(200).json({
            namespace,
            inserted: totalInserted,
            chunks: chunks.length,
            batches: Math.ceil(chunks.length / BATCH_SIZE),
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