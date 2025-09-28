/**
 * Konfiguration für Firebase Cloud Functions
 * Stand: 04.09.2025 - Optimiert für Live AI-Assistenten mit geklonter Stimme
 */

export interface AppConfig {
  projectId: string;
  location: string;
  customVoiceName: string;
  referenceVideoUrl: string;
}

// Minimal, robust: verwende Env/Fallbacks (kein Secret Manager nötig)
export async function loadConfig(): Promise<AppConfig> {
  const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT_ID || 'sunriza26';
  const location = process.env.GOOGLE_CLOUD_LOCATION || 'us-central1';
  const customVoiceName = process.env.CUSTOM_VOICE_NAME || `projects/${projectId}/locations/${location}/voices/default-voice`;
  // Wichtig: korrektes GCS-Schema verwenden
  const bucket = `${projectId}.appspot.com`;
  const referenceVideoUrl = process.env.REFERENCE_VIDEO_URL || `gs://${bucket}/reference/reference.mp4`;
  return {
    projectId,
    location,
    customVoiceName,
    referenceVideoUrl,
  };
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
