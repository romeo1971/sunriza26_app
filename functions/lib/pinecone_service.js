"use strict";
/// Pinecone Service für RAG-System
/// Stand: 04.09.2025 - Vektordatenbank für KI-Avatar Training
Object.defineProperty(exports, "__esModule", { value: true });
exports.PineconeService = void 0;
const pinecone_1 = require("@pinecone-database/pinecone");
class PineconeService {
    constructor() {
        // Pinecone initialisieren
        this.pinecone = new pinecone_1.Pinecone({
            apiKey: process.env.PINECONE_API_KEY.trim(),
        });
        // PYTHON-KOMPATIBILITÄT: Nutze gleichen Index wie Python-Backend
        this.indexName = process.env.PINECONE_INDEX || 'avatars-index';
        this.embeddingDim = Number(process.env.EMB_DIM || 1536);
    }
    /// Initialisiert den Pinecone Index
    async initializeIndex() {
        var _a;
        try {
            const indexes = await this.pinecone.listIndexes();
            const indexExists = (_a = indexes.indexes) === null || _a === void 0 ? void 0 : _a.some((index) => index.name === this.indexName);
            if (!indexExists) {
                console.log(`Creating Pinecone index: ${this.indexName}`);
                await this.pinecone.createIndex({
                    name: this.indexName,
                    dimension: 1536, // OpenAI text-embedding-3-small dimension
                    metric: 'cosine',
                    spec: {
                        serverless: {
                            cloud: 'aws',
                            region: 'us-east-1',
                        },
                    },
                });
                // Warten bis Index bereit ist
                await this.waitForIndexReady(this.indexName);
            }
            console.log(`Pinecone index ${this.indexName} is ready`);
        }
        catch (error) {
            console.error('Error initializing Pinecone index:', error);
            throw error;
        }
    }
    /// Wartet bis ein Index bereit ist
    async waitForIndexReady(indexName) {
        const maxRetries = 30;
        let retries = 0;
        while (retries < maxRetries) {
            try {
                const index = this.pinecone.index(indexName);
                const stats = await index.describeIndexStats();
                if (stats.totalRecordCount !== undefined) {
                    console.log('Pinecone index is ready');
                    return;
                }
            }
            catch (error) {
                console.log(`Waiting for index to be ready... (${retries + 1}/${maxRetries})`);
            }
            retries++;
            await new Promise(resolve => setTimeout(resolve, 2000));
        }
        throw new Error('Pinecone index did not become ready in time');
    }
    /// Generiert Embeddings für Text
    async generateTextEmbedding(text) {
        var _a, _b, _c;
        try {
            const apiKey = (_a = process.env.MISTRAL_API_KEY) === null || _a === void 0 ? void 0 : _a.trim();
            const model = process.env.MISTRAL_EMBED_MODEL || 'mistral-embed';
            if (!apiKey) {
                throw new Error('MISTRAL_API_KEY ist nicht gesetzt');
            }
            const r = await globalThis.fetch('https://api.mistral.ai/v1/embeddings', {
                method: 'POST',
                headers: {
                    Authorization: `Bearer ${apiKey}`,
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    model,
                    input: text,
                }),
            });
            if (!r.ok) {
                const body = await r.text();
                throw new Error(`Mistral embeddings failed: ${body}`);
            }
            const j = await r.json();
            let vec = ((_c = (_b = j.data) === null || _b === void 0 ? void 0 : _b[0]) === null || _c === void 0 ? void 0 : _c.embedding) || [];
            // Auf Index-Dimension bringen (Padding/Truncation), damit bestehende
            // Pinecone-Indizes mit 1536 Dimension weiterverwendet werden können.
            if (vec.length !== this.embeddingDim) {
                if (vec.length > this.embeddingDim) {
                    vec = vec.slice(0, this.embeddingDim);
                }
                else {
                    vec = [
                        ...vec,
                        ...new Array(this.embeddingDim - vec.length).fill(0),
                    ];
                }
            }
            return vec;
        }
        catch (error) {
            console.error('Error generating text embedding:', error);
            throw error;
        }
    }
    /// Generiert Embeddings für Bild (über Beschreibung)
    async generateImageEmbedding(imageDescription) {
        // Für Bilder verwenden wir die Beschreibung als Text-Embedding
        return this.generateTextEmbedding(imageDescription);
    }
    /// Generiert Embeddings für Video (über Beschreibung)
    async generateVideoEmbedding(videoDescription) {
        // Für Videos verwenden wir die Beschreibung als Text-Embedding
        return this.generateTextEmbedding(videoDescription);
    }
    /// Speichert Dokument im Pinecone Index
    async storeDocument(documentId, content, metadata) {
        try {
            await this.initializeIndex();
            const index = this.pinecone.index(this.indexName);
            // Embedding generieren basierend auf Content-Typ
            let embedding;
            if (metadata.type === 'text') {
                embedding = await this.generateTextEmbedding(content);
            }
            else if (metadata.type === 'image') {
                embedding = await this.generateImageEmbedding(content);
            }
            else if (metadata.type === 'video') {
                embedding = await this.generateVideoEmbedding(content);
            }
            else {
                // Für Audio verwenden wir den Text-Content
                embedding = await this.generateTextEmbedding(content);
            }
            // Vektor in Pinecone speichern
            await index.upsert([
                {
                    id: documentId,
                    values: embedding,
                    metadata: metadata,
                },
            ]);
            console.log(`Document ${documentId} stored in Pinecone`);
        }
        catch (error) {
            console.error('Error storing document in Pinecone:', error);
            throw error;
        }
    }
    /// Sucht ähnliche Dokumente (user-spezifisch, avatars-index)
    async searchSimilarDocuments(query, userId, topK = 5, filter, avatarId) {
        var _a;
        try {
            await this.initializeIndex();
            const index = this.pinecone.index(this.indexName);
            // Query-Embedding generieren
            const queryEmbedding = await this.generateTextEmbedding(query);
            // KOMPATIBILITÄT: Nutze Python-Backend-Logik (namespace statt Filter)
            const namespace = avatarId ? `${userId}_${avatarId}` : userId;
            // Ähnliche Vektoren suchen (namespace statt Filter → Python-Kompatibilität)
            const searchResponse = await index.namespace(namespace).query({
                vector: queryEmbedding,
                topK,
                includeMetadata: true,
            });
            // Ergebnisse in DocumentVector-Format konvertieren
            const results = ((_a = searchResponse.matches) === null || _a === void 0 ? void 0 : _a.map(match => ({
                id: match.id,
                values: match.values || [],
                metadata: match.metadata,
            }))) || [];
            return results;
        }
        catch (error) {
            console.error('Error searching similar documents:', error);
            return [];
        }
    }
    /// Sucht ähnliche Dokumente (global, bestehender Pinecone-Index)
    async searchSimilarDocumentsGlobal(query, topK = 5) {
        var _a, _b;
        try {
            const globalIndexName = process.env.PINECONE_GLOBAL_INDEX || 'sunriza26-avatar-data';
            // Prüfe, ob Index existiert – wenn nicht, still überspringen (kein Auto-Create)
            const indexes = await this.pinecone.listIndexes();
            const indexExists = (_a = indexes.indexes) === null || _a === void 0 ? void 0 : _a.some((index) => index.name === globalIndexName);
            if (!indexExists) {
                console.log(`Global index ${globalIndexName} does not exist, skipping global search`);
                return [];
            }
            const index = this.pinecone.index(globalIndexName);
            // Query-Embedding generieren
            const queryEmbedding = await this.generateTextEmbedding(query);
            // Ähnliche Vektoren suchen (namespace 'global')
            const searchResponse = await index.namespace('global').query({
                vector: queryEmbedding,
                topK,
                includeMetadata: true,
            });
            // Ergebnisse in DocumentVector-Format konvertieren
            const results = ((_b = searchResponse.matches) === null || _b === void 0 ? void 0 : _b.map(match => ({
                id: match.id,
                values: match.values || [],
                metadata: match.metadata,
            }))) || [];
            return results;
        }
        catch (error) {
            console.error('Error searching global documents:', error);
            return [];
        }
    }
    /// Löscht Dokument aus Pinecone
    async deleteDocument(documentId) {
        try {
            await this.initializeIndex();
            const index = this.pinecone.index(this.indexName);
            await index.deleteOne(documentId);
            console.log(`Document ${documentId} deleted from Pinecone`);
        }
        catch (error) {
            console.error('Error deleting document from Pinecone:', error);
            throw error;
        }
    }
    /// Löscht alle Dokumente eines Users
    async deleteUserDocuments(userId) {
        try {
            await this.initializeIndex();
            const index = this.pinecone.index(this.indexName);
            await index.deleteMany({
                userId: { $eq: userId },
            });
            console.log(`All documents for user ${userId} deleted from Pinecone`);
        }
        catch (error) {
            console.error('Error deleting user documents from Pinecone:', error);
            throw error;
        }
    }
    /// Generiert Kontext für KI-Avatar basierend auf Query
    async generateAvatarContext(query, userId, maxContextLength = 2000) {
        try {
            // Ähnliche Dokumente suchen
            const similarDocs = await this.searchSimilarDocuments(query, userId, 10);
            if (similarDocs.length === 0) {
                return 'Keine relevanten Informationen gefunden.';
            }
            // Kontext aus ähnlichen Dokumenten zusammenstellen
            let context = '';
            let currentLength = 0;
            for (const doc of similarDocs) {
                const docContent = this.extractContentFromMetadata(doc.metadata);
                const docText = `[${doc.metadata.type.toUpperCase()}] ${docContent}\n\n`;
                if (currentLength + docText.length <= maxContextLength) {
                    context += docText;
                    currentLength += docText.length;
                }
                else {
                    break;
                }
            }
            return context.trim();
        }
        catch (error) {
            console.error('Error generating avatar context:', error);
            return 'Fehler beim Generieren des Kontexts.';
        }
    }
    /// Extrahiert Content aus Metadaten
    extractContentFromMetadata(metadata) {
        if (metadata.description) {
            return metadata.description;
        }
        // Fallback basierend auf Typ
        switch (metadata.type) {
            case 'text':
                return `Textdokument: ${metadata.originalFileName}`;
            case 'image':
                return `Bild: ${metadata.originalFileName}`;
            case 'video':
                return `Video: ${metadata.originalFileName}`;
            case 'audio':
                return `Audio: ${metadata.originalFileName}`;
            default:
                return `Dokument: ${metadata.originalFileName}`;
        }
    }
    /// Index-Statistiken abrufen
    async getIndexStats() {
        try {
            await this.initializeIndex();
            const index = this.pinecone.index(this.indexName);
            const stats = await index.describeIndexStats();
            return stats;
        }
        catch (error) {
            console.error('Error getting index stats:', error);
            throw error;
        }
    }
}
exports.PineconeService = PineconeService;
//# sourceMappingURL=pinecone_service.js.map