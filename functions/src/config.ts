/**
 * Konfiguration für Firebase Cloud Functions
 * Stand: 04.09.2025 - Optimiert für Live AI-Assistenten mit geklonter Stimme
 */

export interface AppConfig {
  projectId: string;
  location: string;
  customVoiceName: string;
  referenceVideoUrl: string;
  vertexAiModelId: string;
  vertexAiEndpoint: string;
}

/**
 * Lädt Konfiguration aus Firebase Secret Manager
 * Fallback auf Umgebungsvariablen für lokale Entwicklung
 */
export async function loadConfig(): Promise<AppConfig> {
  const { SecretManagerServiceClient } = await import('@google-cloud/secret-manager');
  const client = new SecretManagerServiceClient();

  try {
    // Versuche Secrets aus Secret Manager zu laden
    const [projectIdSecret] = await client.accessSecretVersion({
      name: `projects/sunriza26/secrets/GOOGLE_CLOUD_PROJECT_ID/versions/latest`,
    });
    
    const [locationSecret] = await client.accessSecretVersion({
      name: `projects/sunriza26/secrets/GOOGLE_CLOUD_LOCATION/versions/latest`,
    });

    const [customVoiceSecret] = await client.accessSecretVersion({
      name: `projects/sunriza26/secrets/CUSTOM_VOICE_NAME/versions/latest`,
    });

    const [videoUrlSecret] = await client.accessSecretVersion({
      name: `projects/sunriza26/secrets/REFERENCE_VIDEO_URL/versions/latest`,
    });

    return {
      projectId: projectIdSecret.payload?.data?.toString() || 'sunriza26',
      location: locationSecret.payload?.data?.toString() || 'us-central1',
      customVoiceName: customVoiceSecret.payload?.data?.toString() || 'projects/sunriza26/locations/us-central1/voices/default-voice',
      referenceVideoUrl: videoUrlSecret.payload?.data?.toString() || 'gs://sunriza26.firebasestorage.app/reference-video.mp4',
      vertexAiModelId: 'imagen-video-generator',
      vertexAiEndpoint: 'us-central1-aiplatform.googleapis.com',
    };
  } catch (error) {
    console.warn('Fehler beim Laden der Secrets, verwende Fallback-Konfiguration:', error);
    
    // Fallback auf Umgebungsvariablen oder Standardwerte
    return {
      projectId: process.env.GOOGLE_CLOUD_PROJECT_ID || 'sunriza26',
      location: process.env.GOOGLE_CLOUD_LOCATION || 'us-central1',
      customVoiceName: process.env.CUSTOM_VOICE_NAME || 'projects/sunriza26/locations/us-central1/voices/default-voice',
      referenceVideoUrl: process.env.REFERENCE_VIDEO_URL || 'gs://sunriza26.firebasestorage.app/reference-video.mp4',
      vertexAiModelId: process.env.VERTEX_AI_MODEL_ID || 'imagen-video-generator',
      vertexAiEndpoint: process.env.VERTEX_AI_ENDPOINT || 'us-central1-aiplatform.googleapis.com',
    };
  }
}

/**
 * Cached Konfiguration für bessere Performance
 */
let cachedConfig: AppConfig | null = null;

export async function getConfig(): Promise<AppConfig> {
  if (!cachedConfig) {
    cachedConfig = await loadConfig();
  }
  return cachedConfig;
}
