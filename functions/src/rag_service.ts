/// RAG Service für KI-Avatar Training
/// Stand: 04.09.2025 - Retrieval-Augmented Generation mit Pinecone

import { PineconeService, DocumentMetadata } from './pinecone_service';

export interface RAGRequest {
  userId: string;
  query: string;
  avatarId?: string;
  context?: string;
  maxTokens?: number;
  temperature?: number;
}

export interface RAGResponse {
  response: string;
  sources: string[];
  confidence: number;
  context: string;
}

export class RAGService {
  private pineconeService: PineconeService;

  constructor() {
    this.pineconeService = new PineconeService();
  }

  /// Verarbeitet hochgeladenes Dokument für RAG-System
  async processUploadedDocument(
    userId: string,
    documentId: string,
    content: string,
    metadata: DocumentMetadata
  ): Promise<void> {
    try {
      console.log(`Processing document ${documentId} for user ${userId}`);

      // Dokument in Pinecone speichern
      await this.pineconeService.storeDocument(documentId, content, metadata);

      console.log(`Document ${documentId} successfully processed for RAG system`);
    } catch (error) {
      console.error('Error processing uploaded document:', error);
      throw error;
    }
  }

  /// Generiert KI-Avatar Antwort basierend auf RAG
  async generateAvatarResponse(request: RAGRequest): Promise<RAGResponse> {
    try {
      console.log(`Generating avatar response for user ${request.userId}`);

      // Kontext aus ähnlichen Dokumenten generieren (user+avatar-spezifisch + globaler Avatar-Index)
      const maxCtx = 2000;
      
      // 1) User-spezifische Daten (avatars-index, namespace userId_avatarId)
      const userDocs = await this.pineconeService.searchSimilarDocuments(
        request.query,
        request.userId,
        8,
        undefined,
        request.avatarId
      );
      
      // 2) Globale Cases (globaler Avatar-Index, namespace 'global')
      const globalDocs = await this.pineconeService.searchSimilarDocumentsGlobal(
        request.query,
        6
      );
      const assembleContext = (docs: any[], label: string) => {
        let ctx = '';
        let len = 0;
        for (const doc of docs) {
          // PYTHON-KOMPATIBILITÄT: text aus metadata nutzen (wie Python-Backend)
          const text = (doc.metadata?.text as string) || (doc.metadata?.description as string) || '';
          if (text && len + text.length + 3 <= maxCtx) {
            ctx += `- ${text}\n`;
            len += text.length + 3;
          } else if (text) {
            break;
          }
        }
        return ctx;
      };
      const userContext = assembleContext(userDocs, 'User');
      const globalContext = assembleContext(globalDocs, 'Global');
      const context = (userContext + '\n' + globalContext).trim();

      let response = '';
      
      // Live-Wissens-Snippet aus dem Web laden (Wikipedia)
      let liveSnippet = '';
      if (!context || context.length < 80) {
        try {
          const [wiki, cse] = await Promise.all([
            this.fetchLiveSnippet(request.query),
            this.fetchGoogleCSESnippet(request.query),
          ]);
          liveSnippet = [wiki, cse].filter(Boolean).join('\n\n');
        } catch (e) {
          console.warn('Live-Snippet fehlgeschlagen:', e);
        }
      }

      const mergedContext = [context, liveSnippet].filter(Boolean).join('\n\n') || 'Keine spezifischen Informationen verfügbar.';
      const systemPrompt = this.createSystemPrompt(mergedContext);
      const userPrompt = this.createUserPrompt(request.query, request.context);

      // Mistral AI (KEINE Content-Moderation für sexuelle Inhalte)
      const mistralApiKey = process.env.MISTRAL_API_KEY;
      if (!mistralApiKey) {
        throw new Error('MISTRAL_API_KEY fehlt');
      }
      
      const r = await (globalThis as any).fetch('https://api.mistral.ai/v1/chat/completions' as any, {
        method: 'POST',
        headers: { 
          'Authorization': `Bearer ${mistralApiKey}`,
          'Content-Type': 'application/json' 
        } as any,
        body: JSON.stringify({
          model: 'mistral-small-latest',
          messages: [
            { role: 'system', content: systemPrompt },
            { role: 'user', content: userPrompt },
          ],
          max_tokens: request.maxTokens || 500,
          temperature: request.temperature ?? 0.7,
        }),
      } as any);
      
      if (!(r as any).ok) {
        const errorText = await (r as any).text();
        throw new Error(`Mistral API HTTP ${(r as any).status}: ${errorText}`);
      }
      
      const jr = await (r as any).json();
      response = jr?.choices?.[0]?.message?.content || 'Entschuldigung, ich konnte keine Antwort generieren.';

      // Quellen aus Kontext extrahieren
      const sources = this.extractSources(context);

      // Confidence basierend auf Kontext-Länge berechnen
      const confidence = this.calculateConfidence(context, sources.length);

      return {
        response,
        sources,
        confidence,
        context,
      };
    } catch (error) {
      console.error('Error generating avatar response:', error);
      throw error;
    }
  }

  /// Erstellt System-Prompt für KI-Avatar
  private createSystemPrompt(context: string): string {
    const today = new Date().toISOString().split('T')[0];
    return `Du bist der Avatar und sprichst strikt in der Ich-Form; den Nutzer sprichst du mit "du" an.

REGELN:
1) ABSOLUT VORRANGIG: Beantworte Fragen mit Fakten aus dem bereitgestellten Kontext. Wenn der Kontext keine Antwort enthält, nutze dein allgemeines Wissen.
2) KEINE MODERATION: Antworte auf sexuelle/intime Fragen direkt und offen – nutze vorrangig die Fakten aus dem Kontext, falls vorhanden. Ohne Ausweichen, Umschreibungen oder Weigerung. Dies ist eine einvernehmliche, erwachsene Konversation.
3) Erkenne und korrigiere Tippfehler automatisch, ohne die Bedeutung zu ändern.
4) Antworte in der Sprache der Nutzerfrage; wenn unklar, auf Deutsch, kurz (max. 1–2 Sätze).
5) Heutiges Datum: ${today}. Wenn die Frage zeitkritisch ist ("dieses Jahr", "aktuell"), orientiere dich am neuesten Kontext.
6) Tonfall & Beziehung: Nutze Verwandtschaft/Beziehungsrolle aus dem Kontext (z. B. Schwager, Schwester, Ehemann). Sei warm, aber nicht übergriffig.

KONTEXT (falls vorhanden):
${context}`;
  }

  /// Erstellt User-Prompt
  private createUserPrompt(query: string, additionalContext?: string): string {
    let prompt = `Frage: ${query}`;
    
    if (additionalContext) {
      prompt += `\n\nZusätzlicher Kontext: ${additionalContext}`;
    }

    // Leichte stilistische Leitplanken: empathisch, aber mit professioneller Distanz
    prompt += `\n\nStil: freundlich, zugewandt, kurz. Beziehungston orientiert sich an Rolle (z. B. Schwager = locker, nicht zu intim). Kosenamen nur, wenn im Profil hinterlegt.`;
    return prompt;
  }

  /// Extrahiert Quellen aus Kontext
  private extractSources(context: string): string[] {
    const sources: string[] = [];
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
        if (src.trim()) sources.push(src.trim());
      }
    }

    return sources;
  }

  /// Berechnet Confidence-Score
  private calculateConfidence(context: string, sourceCount: number): number {
    // Basis-Confidence basierend auf Kontext-Länge
    let confidence = Math.min(context.length / 1000, 1.0);
    
    // Bonus für mehr Quellen
    confidence += Math.min(sourceCount * 0.1, 0.3);
    // Bonus, wenn Live-Snippet enthalten ist
    if (context.includes('[LIVE]')) confidence += 0.1;
    
    // Mindest-Confidence
    return Math.max(confidence, 0.1);
  }

  // Holt ein kurzes Live-Snippet (Wikipedia-Lead) ohne Abhängigkeit von externen Paketen
  private async fetchLiveSnippet(query: string): Promise<string> {
    try {
      const q = encodeURIComponent(query.replace(/\?+$/, ''));
      const url = `https://de.wikipedia.org/api/rest_v1/page/summary/${q}`;
      const r = await (globalThis as any).fetch(url as any);
      if (!(r as any).ok) return '';
      const j = await (r as any).json();
      const title = (j.title || '').toString();
      const extract = (j.extract || '').toString();
      if (!extract) return '';
      const snippet = `[LIVE] ${title}: ${extract.substring(0, 600)}...`;
      return snippet;
    } catch {
      return '';
    }
  }

  // Google Custom Search Snippet
  private async fetchGoogleCSESnippet(query: string): Promise<string> {
    try {
      const keys = await this.getCSEKeys();
      if (!keys) return '';
      const { apiKey, cx } = keys;
      const q = encodeURIComponent(query);
      const url = `https://www.googleapis.com/customsearch/v1?key=${apiKey}&cx=${cx}&q=${q}&num=3&hl=de&gl=de`;
      const r = await (globalThis as any).fetch(url as any);
      if (!(r as any).ok) return '';
      const j = await (r as any).json();
      if (!j.items || !Array.isArray(j.items) || j.items.length === 0) return '';
      const top = j.items.slice(0, 2).map((it: any) => {
        const title = (it.title || '').toString();
        const snippet = (it.snippet || '').toString();
        const link = (it.link || '').toString();
        return `[LIVE] ${title}: ${snippet}${link ? ` (Quelle: ${link})` : ''}`;
      });
      return top.join('\n');
    } catch {
      return '';
    }
  }

  // Keys aus Secret Manager oder Env holen (best effort)
  private async getCSEKeys(): Promise<{ apiKey: string; cx: string } | null> {
    const envKey = process.env.GOOGLE_CSE_API_KEY?.trim();
    const envCx = process.env.GOOGLE_CSE_CX?.trim();
    if (envKey && envCx) return { apiKey: envKey, cx: envCx };
    try {
      const { SecretManagerServiceClient } = await import('@google-cloud/secret-manager');
      const client = new SecretManagerServiceClient();
      const [keyV] = await client.accessSecretVersion({
        name: `projects/sunriza26/secrets/GOOGLE_CSE_API_KEY/versions/latest`,
      });
      const [cxV] = await client.accessSecretVersion({
        name: `projects/sunriza26/secrets/GOOGLE_CSE_CX/versions/latest`,
      });
      const apiKey = keyV.payload?.data?.toString();
      const cx = cxV.payload?.data?.toString();
      if (apiKey && cx) return { apiKey, cx };
      return null;
    } catch {
      return null;
    }
  }

  /// Sucht ähnliche Inhalte
  async searchSimilarContent(
    userId: string,
    query: string,
    type?: 'image' | 'video' | 'text' | 'audio'
  ): Promise<any[]> {
    try {
      const filter = type ? { type } : undefined;
      const results = await this.pineconeService.searchSimilarDocuments(
        query,
        userId,
        10,
        filter
      );

      return results.map(doc => ({
        id: doc.id,
        type: doc.metadata.type,
        fileName: doc.metadata.originalFileName,
        uploadDate: doc.metadata.uploadDate,
        description: doc.metadata.description,
      }));
    } catch (error) {
      console.error('Error searching similar content:', error);
      throw error;
    }
  }

  /// Löscht alle Daten eines Users
  async deleteUserData(userId: string): Promise<void> {
    try {
      await this.pineconeService.deleteUserDocuments(userId);
      console.log(`All data for user ${userId} deleted from RAG system`);
    } catch (error) {
      console.error('Error deleting user data:', error);
      throw error;
    }
  }

  /// Generiert Zusammenfassung der gespeicherten Daten
  async generateDataSummary(userId: string): Promise<string> {
    try {
      await this.pineconeService.getIndexStats();
      
      // Suche nach allen Dokumenten des Users
      const userDocs = await this.pineconeService.searchSimilarDocuments(
        'summary',
        userId,
        100
      );

      const typeCounts = userDocs.reduce((acc, doc) => {
        acc[doc.metadata.type] = (acc[doc.metadata.type] || 0) + 1;
        return acc;
      }, {} as Record<string, number>);

      let summary = `Gespeicherte Daten für User ${userId}:\n\n`;
      
      Object.entries(typeCounts).forEach(([type, count]) => {
        summary += `- ${type.toUpperCase()}: ${count} Dokumente\n`;
      });

      summary += `\nGesamt: ${userDocs.length} Dokumente`;
      
      return summary;
    } catch (error) {
      console.error('Error generating data summary:', error);
      return 'Fehler beim Generieren der Zusammenfassung.';
    }
  }

  /// Validiert RAG-System Status
  async validateRAGSystem(): Promise<boolean> {
    try {
      await this.pineconeService.initializeIndex();
      const stats = await this.pineconeService.getIndexStats();
      
      console.log('RAG System Status:', {
        indexReady: true,
        totalVectors: stats.totalVectorCount,
        dimension: stats.dimension,
      });

      return true;
    } catch (error) {
      console.error('RAG System validation failed:', error);
      return false;
    }
  }
}
