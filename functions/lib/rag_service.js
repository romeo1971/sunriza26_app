"use strict";
/// RAG Service für KI-Avatar Training
/// Stand: 04.09.2025 - Retrieval-Augmented Generation mit Pinecone
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
exports.RAGService = void 0;
const pinecone_service_1 = require("./pinecone_service");
class RAGService {
    constructor() {
        this.pineconeService = new pinecone_service_1.PineconeService();
    }
    /// Verarbeitet hochgeladenes Dokument für RAG-System
    async processUploadedDocument(userId, documentId, content, metadata) {
        try {
            console.log(`Processing document ${documentId} for user ${userId}`);
            // Dokument in Pinecone speichern
            await this.pineconeService.storeDocument(documentId, content, metadata);
            console.log(`Document ${documentId} successfully processed for RAG system`);
        }
        catch (error) {
            console.error('Error processing uploaded document:', error);
            throw error;
        }
    }
    /// Generiert KI-Avatar Antwort basierend auf RAG
    async generateAvatarResponse(request) {
        var _a;
        try {
            console.log(`Generating avatar response for user ${request.userId}`);
            // Kontext aus ähnlichen Dokumenten generieren (global + user-spezifisch)
            const maxCtx = 2000;
            const globalDocs = await this.pineconeService.searchSimilarDocuments(request.query, 'global', 6);
            const userDocs = await this.pineconeService.searchSimilarDocuments(request.query, request.userId, 6);
            const assembleContext = (docs) => {
                var _a, _b, _c;
                let ctx = '';
                let len = 0;
                for (const doc of docs) {
                    const docContent = ((_a = doc.metadata) === null || _a === void 0 ? void 0 : _a.description) ||
                        ((_b = doc.metadata) === null || _b === void 0 ? void 0 : _b.originalFileName) || 'Eintrag';
                    const line = `[${(((_c = doc.metadata) === null || _c === void 0 ? void 0 : _c.type) || 'text').toString().toUpperCase()}] ${docContent}\n\n`;
                    if (len + line.length <= maxCtx) {
                        ctx += line;
                        len += line.length;
                    }
                    else {
                        break;
                    }
                }
                return ctx;
            };
            const context = (assembleContext(globalDocs) + assembleContext(userDocs)).trim() || 'Keine relevanten Informationen gefunden.';
            // Wenn kaum/kein Kontext vorhanden ist, Live-Wissens-Snippet aus dem Web laden (Wikipedia)
            let liveSnippet = '';
            if (!context || context.includes('Keine relevanten Informationen') || context.length < 80) {
                try {
                    const [wiki, cse] = await Promise.all([
                        this.fetchLiveSnippet(request.query),
                        this.fetchGoogleCSESnippet(request.query),
                    ]);
                    // beide Quellen kombinieren
                    liveSnippet = [wiki, cse].filter(Boolean).join('\n\n');
                }
                catch (e) {
                    console.warn('Live-Snippet fehlgeschlagen:', e);
                }
            }
            // KI-Prompt mit Kontext erstellen
            const mergedContext = [context, liveSnippet].filter(Boolean).join('\n\n');
            const systemPrompt = this.createSystemPrompt(mergedContext);
            const userPrompt = this.createUserPrompt(request.query, request.context);
            // LLM Router aufrufen (OpenAI primär, Gemini Fallback)
            const llmUrl = process.env.LLM_ENDPOINT || 'https://us-central1-sunriza26.cloudfunctions.net/llm';
            const r = await globalThis.fetch(llmUrl, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    messages: [
                        { role: 'system', content: systemPrompt },
                        { role: 'user', content: userPrompt },
                    ],
                    maxTokens: request.maxTokens || 500,
                    temperature: (_a = request.temperature) !== null && _a !== void 0 ? _a : 0.7,
                }),
            });
            if (!r.ok) {
                throw new Error(`LLM Router HTTP ${r.status}`);
            }
            const jr = await r.json();
            const response = (jr === null || jr === void 0 ? void 0 : jr.answer) || 'Entschuldigung, ich konnte keine Antwort generieren.';
            // Quellen aus Kontext extrahieren
            const sources = this.extractSources(mergedContext);
            // Confidence basierend auf Kontext-Länge berechnen
            const confidence = this.calculateConfidence(mergedContext, sources.length);
            return {
                response,
                sources,
                confidence,
                context: mergedContext,
            };
        }
        catch (error) {
            console.error('Error generating avatar response:', error);
            throw error;
        }
    }
    /// Erstellt System-Prompt für KI-Avatar
    createSystemPrompt(context) {
        const today = new Date().toISOString().split('T')[0];
        return `Du bist der Avatar und sprichst strikt in der Ich-Form; den Nutzer sprichst du mit "du" an.

REGELN:
1) Erkenne und korrigiere Tippfehler automatisch, ohne die Bedeutung zu ändern.
2) Verwende vorrangig den bereitgestellten Kontext (Pinecone/Avatar-Wissen), wenn er relevant ist.
3) Falls der Kontext keine ausreichende Antwort liefert, nutze zusätzlich das bereitgestellte Live-Wissens-Snippet (z. B. Wikipedia-Auszug).
4) Sage nicht, ob die Antwort aus Kontext oder Modellwissen kommt – antworte direkt und natürlich.
5) Gib klare, verständliche Antworten, auch bei unpräzisen Eingaben.
6) Antworte in der Sprache der Nutzerfrage; wenn unklar, auf Deutsch, kurz (max. 1–2 Sätze).
7) Heutiges Datum: ${today}. Wenn die Frage zeitkritisch ist ("dieses Jahr", "aktuell"), orientiere dich am neuesten Kontext/Live-Snippet.
8) Tonfall & Beziehung: Nutze Verwandtschaft/Beziehungsrolle aus dem Kontext (z. B. Schwager, Schwester, Ehemann). Sei warm, aber nicht übergriffig. Verwende Kosenamen nur, wenn sie explizit im Kontext/profil stehen (z. B. gespeicherter Kosename) oder bei sehr enger Beziehung (Ehe/Partner). Für Rollen wie "Schwager" nutze nur gelegentlich (ca. 1 von 5 Antworten) eine lockere, leichte Anrede (z. B. "Schwagerlein") und sonst neutrale, freundliche Anrede. Vermeide überintime Formulierungen wie "mein Schatz", falls Beziehung nicht Partner/Ehe ist.

KONTEXT (falls vorhanden):
${context}`;
    }
    /// Erstellt User-Prompt
    createUserPrompt(query, additionalContext) {
        let prompt = `Frage: ${query}`;
        if (additionalContext) {
            prompt += `\n\nZusätzlicher Kontext: ${additionalContext}`;
        }
        // Leichte stilistische Leitplanken: empathisch, aber mit professioneller Distanz
        prompt += `\n\nStil: freundlich, zugewandt, kurz. Beziehungston orientiert sich an Rolle (z. B. Schwager = locker, nicht zu intim). Kosenamen nur, wenn im Profil hinterlegt.`;
        return prompt;
    }
    /// Extrahiert Quellen aus Kontext
    extractSources(context) {
        const sources = [];
        const lines = context.split('\n');
        for (const line of lines) {
            if (line.startsWith('[IMAGE]') || line.startsWith('[VIDEO]') ||
                line.startsWith('[TEXT]') || line.startsWith('[AUDIO]')) {
                const source = line.replace(/^\[.*?\]\s*/, '');
                if (source.trim()) {
                    sources.push(source.trim());
                }
            }
            // Live-Snippet-Markierung
            if (line.startsWith('[LIVE]')) {
                const src = line.replace(/^\[LIVE\]\s*/, '');
                if (src.trim())
                    sources.push(src.trim());
            }
        }
        return sources;
    }
    /// Berechnet Confidence-Score
    calculateConfidence(context, sourceCount) {
        // Basis-Confidence basierend auf Kontext-Länge
        let confidence = Math.min(context.length / 1000, 1.0);
        // Bonus für mehr Quellen
        confidence += Math.min(sourceCount * 0.1, 0.3);
        // Bonus, wenn Live-Snippet enthalten ist
        if (context.includes('[LIVE]'))
            confidence += 0.1;
        // Mindest-Confidence
        return Math.max(confidence, 0.1);
    }
    // Holt ein kurzes Live-Snippet (Wikipedia-Lead) ohne Abhängigkeit von externen Paketen
    async fetchLiveSnippet(query) {
        try {
            const q = encodeURIComponent(query.replace(/\?+$/, ''));
            const url = `https://de.wikipedia.org/api/rest_v1/page/summary/${q}`;
            const r = await globalThis.fetch(url);
            if (!r.ok)
                return '';
            const j = await r.json();
            const title = (j.title || '').toString();
            const extract = (j.extract || '').toString();
            if (!extract)
                return '';
            const snippet = `[LIVE] ${title}: ${extract.substring(0, 600)}...`;
            return snippet;
        }
        catch (_a) {
            return '';
        }
    }
    // Google Custom Search Snippet
    async fetchGoogleCSESnippet(query) {
        try {
            const keys = await this.getCSEKeys();
            if (!keys)
                return '';
            const { apiKey, cx } = keys;
            const q = encodeURIComponent(query);
            const url = `https://www.googleapis.com/customsearch/v1?key=${apiKey}&cx=${cx}&q=${q}&num=3&hl=de&gl=de`;
            const r = await globalThis.fetch(url);
            if (!r.ok)
                return '';
            const j = await r.json();
            if (!j.items || !Array.isArray(j.items) || j.items.length === 0)
                return '';
            const top = j.items.slice(0, 2).map((it) => {
                const title = (it.title || '').toString();
                const snippet = (it.snippet || '').toString();
                const link = (it.link || '').toString();
                return `[LIVE] ${title}: ${snippet}${link ? ` (Quelle: ${link})` : ''}`;
            });
            return top.join('\n');
        }
        catch (_a) {
            return '';
        }
    }
    // Keys aus Secret Manager oder Env holen (best effort)
    async getCSEKeys() {
        var _a, _b, _c, _d, _e, _f;
        const envKey = (_a = process.env.GOOGLE_CSE_API_KEY) === null || _a === void 0 ? void 0 : _a.trim();
        const envCx = (_b = process.env.GOOGLE_CSE_CX) === null || _b === void 0 ? void 0 : _b.trim();
        if (envKey && envCx)
            return { apiKey: envKey, cx: envCx };
        try {
            const { SecretManagerServiceClient } = await Promise.resolve().then(() => __importStar(require('@google-cloud/secret-manager')));
            const client = new SecretManagerServiceClient();
            const [keyV] = await client.accessSecretVersion({
                name: `projects/sunriza26/secrets/GOOGLE_CSE_API_KEY/versions/latest`,
            });
            const [cxV] = await client.accessSecretVersion({
                name: `projects/sunriza26/secrets/GOOGLE_CSE_CX/versions/latest`,
            });
            const apiKey = (_d = (_c = keyV.payload) === null || _c === void 0 ? void 0 : _c.data) === null || _d === void 0 ? void 0 : _d.toString();
            const cx = (_f = (_e = cxV.payload) === null || _e === void 0 ? void 0 : _e.data) === null || _f === void 0 ? void 0 : _f.toString();
            if (apiKey && cx)
                return { apiKey, cx };
            return null;
        }
        catch (_g) {
            return null;
        }
    }
    /// Sucht ähnliche Inhalte
    async searchSimilarContent(userId, query, type) {
        try {
            const filter = type ? { type } : undefined;
            const results = await this.pineconeService.searchSimilarDocuments(query, userId, 10, filter);
            return results.map(doc => ({
                id: doc.id,
                type: doc.metadata.type,
                fileName: doc.metadata.originalFileName,
                uploadDate: doc.metadata.uploadDate,
                description: doc.metadata.description,
            }));
        }
        catch (error) {
            console.error('Error searching similar content:', error);
            throw error;
        }
    }
    /// Löscht alle Daten eines Users
    async deleteUserData(userId) {
        try {
            await this.pineconeService.deleteUserDocuments(userId);
            console.log(`All data for user ${userId} deleted from RAG system`);
        }
        catch (error) {
            console.error('Error deleting user data:', error);
            throw error;
        }
    }
    /// Generiert Zusammenfassung der gespeicherten Daten
    async generateDataSummary(userId) {
        try {
            await this.pineconeService.getIndexStats();
            // Suche nach allen Dokumenten des Users
            const userDocs = await this.pineconeService.searchSimilarDocuments('summary', userId, 100);
            const typeCounts = userDocs.reduce((acc, doc) => {
                acc[doc.metadata.type] = (acc[doc.metadata.type] || 0) + 1;
                return acc;
            }, {});
            let summary = `Gespeicherte Daten für User ${userId}:\n\n`;
            Object.entries(typeCounts).forEach(([type, count]) => {
                summary += `- ${type.toUpperCase()}: ${count} Dokumente\n`;
            });
            summary += `\nGesamt: ${userDocs.length} Dokumente`;
            return summary;
        }
        catch (error) {
            console.error('Error generating data summary:', error);
            return 'Fehler beim Generieren der Zusammenfassung.';
        }
    }
    /// Validiert RAG-System Status
    async validateRAGSystem() {
        try {
            await this.pineconeService.initializeIndex();
            const stats = await this.pineconeService.getIndexStats();
            console.log('RAG System Status:', {
                indexReady: true,
                totalVectors: stats.totalVectorCount,
                dimension: stats.dimension,
            });
            return true;
        }
        catch (error) {
            console.error('RAG System validation failed:', error);
            return false;
        }
    }
}
exports.RAGService = RAGService;
//# sourceMappingURL=rag_service.js.map