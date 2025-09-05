/// RAG Service für KI-Avatar Training
/// Stand: 04.09.2025 - Retrieval-Augmented Generation mit Pinecone

import { PineconeService, DocumentMetadata } from './pinecone_service';
import { OpenAI } from 'openai';

export interface RAGRequest {
  userId: string;
  query: string;
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
  private openai: OpenAI;

  constructor() {
    this.pineconeService = new PineconeService();
    this.openai = new OpenAI({
      apiKey: process.env.OPENAI_API_KEY || 'your-openai-api-key',
    });
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

      // Kontext aus ähnlichen Dokumenten generieren
      const context = await this.pineconeService.generateAvatarContext(
        request.query,
        request.userId,
        2000
      );

      // KI-Prompt mit Kontext erstellen
      const systemPrompt = this.createSystemPrompt(context);
      const userPrompt = this.createUserPrompt(request.query, request.context);

      // OpenAI API aufrufen
      const completion = await this.openai.chat.completions.create({
        model: 'gpt-4',
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userPrompt },
        ],
        max_tokens: request.maxTokens || 500,
        temperature: request.temperature || 0.7,
      });

      const response = completion.choices[0]?.message?.content || 'Entschuldigung, ich konnte keine Antwort generieren.';

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
    return `Du bist ein KI-Avatar, der auf Basis von persönlichen Daten, Erinnerungen und Gedanken einer Person antwortet.

KONTEXT AUS GESPEICHERTEN DATEN:
${context}

ANWEISUNGEN:
- Antworte im Stil und Ton der Person, basierend auf den gespeicherten Daten
- Verwende nur Informationen aus dem bereitgestellten Kontext
- Sei authentisch und persönlich, nicht generisch
- Wenn du keine relevanten Informationen hast, sage das ehrlich
- Antworte auf Deutsch, es sei denn, die Person spricht eine andere Sprache
- Sei einfühlsam und verständnisvoll
- Verwende "Ich" als würde die Person selbst sprechen

WICHTIG: Antworte nur basierend auf den bereitgestellten Daten. Erfinde nichts hinzu.`;
  }

  /// Erstellt User-Prompt
  private createUserPrompt(query: string, additionalContext?: string): string {
    let prompt = `Frage: ${query}`;
    
    if (additionalContext) {
      prompt += `\n\nZusätzlicher Kontext: ${additionalContext}`;
    }

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
    }

    return sources;
  }

  /// Berechnet Confidence-Score
  private calculateConfidence(context: string, sourceCount: number): number {
    // Basis-Confidence basierend auf Kontext-Länge
    let confidence = Math.min(context.length / 1000, 1.0);
    
    // Bonus für mehr Quellen
    confidence += Math.min(sourceCount * 0.1, 0.3);
    
    // Mindest-Confidence
    return Math.max(confidence, 0.1);
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
      const stats = await this.pineconeService.getIndexStats();
      
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
