/// Pinecone Service für RAG-System
/// Stand: 04.09.2025 - Vektordatenbank für KI-Avatar Training

import { Pinecone } from '@pinecone-database/pinecone';
import { OpenAI } from 'openai';

export interface DocumentMetadata {
  type: 'image' | 'video' | 'text' | 'audio';
  userId: string;
  uploadDate: string;
  originalFileName: string;
  contentType: string;
  size: number;
  description?: string;
  tags?: string[];
}

export interface DocumentVector {
  id: string;
  values: number[];
  metadata: DocumentMetadata;
}

export class PineconeService {
  private pinecone: Pinecone;
  private openai: OpenAI;
  private indexName: string;

  constructor() {
    // Pinecone initialisieren
    this.pinecone = new Pinecone({
      apiKey: process.env.PINECONE_API_KEY!.trim(),
    });

    // OpenAI für Embeddings
    this.openai = new OpenAI({
      apiKey: process.env.OPENAI_API_KEY!.trim(),
    });

    // PYTHON-KOMPATIBILITÄT: Nutze gleichen Index wie Python-Backend
    this.indexName = process.env.PINECONE_INDEX || 'avatars-index';
  }

  /// Initialisiert den Pinecone Index
  async initializeIndex(): Promise<void> {
    try {
      const indexes = await this.pinecone.listIndexes();
      const indexExists = indexes.indexes?.some(index => index.name === this.indexName);

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
        await this.waitForIndexReady();
      }

      console.log(`Pinecone index ${this.indexName} is ready`);
    } catch (error) {
      console.error('Error initializing Pinecone index:', error);
      throw error;
    }
  }

  /// Wartet bis Index bereit ist
  private async waitForIndexReady(): Promise<void> {
    const maxRetries = 30;
    let retries = 0;

    while (retries < maxRetries) {
      try {
        const index = this.pinecone.index(this.indexName);
        const stats = await index.describeIndexStats();
        
        if (stats.totalRecordCount !== undefined) {
          console.log('Pinecone index is ready');
          return;
        }
      } catch (error) {
        console.log(`Waiting for index to be ready... (${retries + 1}/${maxRetries})`);
      }

      retries++;
      await new Promise(resolve => setTimeout(resolve, 2000));
    }

    throw new Error('Pinecone index did not become ready in time');
  }

  /// Generiert Embeddings für Text
  async generateTextEmbedding(text: string): Promise<number[]> {
    try {
      const response = await this.openai.embeddings.create({
        model: 'text-embedding-3-small',
        input: text,
      });

      return response.data[0].embedding;
    } catch (error) {
      console.error('Error generating text embedding:', error);
      throw error;
    }
  }

  /// Generiert Embeddings für Bild (über Beschreibung)
  async generateImageEmbedding(imageDescription: string): Promise<number[]> {
    // Für Bilder verwenden wir die Beschreibung als Text-Embedding
    return this.generateTextEmbedding(imageDescription);
  }

  /// Generiert Embeddings für Video (über Beschreibung)
  async generateVideoEmbedding(videoDescription: string): Promise<number[]> {
    // Für Videos verwenden wir die Beschreibung als Text-Embedding
    return this.generateTextEmbedding(videoDescription);
  }

  /// Speichert Dokument im Pinecone Index
  async storeDocument(
    documentId: string,
    content: string,
    metadata: DocumentMetadata
  ): Promise<void> {
    try {
      await this.initializeIndex();

      const index = this.pinecone.index(this.indexName);
      
      // Embedding generieren basierend auf Content-Typ
      let embedding: number[];
      if (metadata.type === 'text') {
        embedding = await this.generateTextEmbedding(content);
      } else if (metadata.type === 'image') {
        embedding = await this.generateImageEmbedding(content);
      } else if (metadata.type === 'video') {
        embedding = await this.generateVideoEmbedding(content);
      } else {
        // Für Audio verwenden wir den Text-Content
        embedding = await this.generateTextEmbedding(content);
      }

      // Vektor in Pinecone speichern
      await index.upsert([
        {
          id: documentId,
          values: embedding,
          metadata: metadata as Record<string, any>,
        },
      ]);

      console.log(`Document ${documentId} stored in Pinecone`);
    } catch (error) {
      console.error('Error storing document in Pinecone:', error);
      throw error;
    }
  }

  /// Sucht ähnliche Dokumente
  async searchSimilarDocuments(
    query: string,
    userId: string,
    topK: number = 5,
    filter?: Partial<DocumentMetadata>,
    avatarId?: string
  ): Promise<DocumentVector[]> {
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
      const results: DocumentVector[] = searchResponse.matches?.map(match => ({
        id: match.id,
        values: match.values || [],
        metadata: match.metadata as unknown as DocumentMetadata,
      })) || [];

      return results;
    } catch (error) {
      console.error('Error searching similar documents:', error);
      throw error;
    }
  }

  /// Löscht Dokument aus Pinecone
  async deleteDocument(documentId: string): Promise<void> {
    try {
      await this.initializeIndex();

      const index = this.pinecone.index(this.indexName);
      await index.deleteOne(documentId);

      console.log(`Document ${documentId} deleted from Pinecone`);
    } catch (error) {
      console.error('Error deleting document from Pinecone:', error);
      throw error;
    }
  }

  /// Löscht alle Dokumente eines Users
  async deleteUserDocuments(userId: string): Promise<void> {
    try {
      await this.initializeIndex();

      const index = this.pinecone.index(this.indexName);
      await index.deleteMany({
        userId: { $eq: userId },
      });

      console.log(`All documents for user ${userId} deleted from Pinecone`);
    } catch (error) {
      console.error('Error deleting user documents from Pinecone:', error);
      throw error;
    }
  }

  /// Generiert Kontext für KI-Avatar basierend auf Query
  async generateAvatarContext(
    query: string,
    userId: string,
    maxContextLength: number = 2000
  ): Promise<string> {
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
        } else {
          break;
        }
      }

      return context.trim();
    } catch (error) {
      console.error('Error generating avatar context:', error);
      return 'Fehler beim Generieren des Kontexts.';
    }
  }

  /// Extrahiert Content aus Metadaten
  private extractContentFromMetadata(metadata: DocumentMetadata): string {
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
  async getIndexStats(): Promise<any> {
    try {
      await this.initializeIndex();

      const index = this.pinecone.index(this.indexName);
      const stats = await index.describeIndexStats();

      return stats;
    } catch (error) {
      console.error('Error getting index stats:', error);
      throw error;
    }
  }
}
