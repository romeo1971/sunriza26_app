"use strict";
/**
 * Konfiguration für Firebase Cloud Functions
 * Stand: 04.09.2025 - Optimiert für Live AI-Assistenten mit geklonter Stimme
 */
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
exports.loadConfig = loadConfig;
exports.getConfig = getConfig;
/**
 * Lädt Konfiguration aus Firebase Secret Manager
 * Fallback auf Umgebungsvariablen für lokale Entwicklung
 */
async function loadConfig() {
    var _a, _b, _c, _d, _e, _f, _g, _h;
    const { SecretManagerServiceClient } = await Promise.resolve().then(() => __importStar(require('@google-cloud/secret-manager')));
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
            projectId: ((_b = (_a = projectIdSecret.payload) === null || _a === void 0 ? void 0 : _a.data) === null || _b === void 0 ? void 0 : _b.toString()) || 'sunriza26',
            location: ((_d = (_c = locationSecret.payload) === null || _c === void 0 ? void 0 : _c.data) === null || _d === void 0 ? void 0 : _d.toString()) || 'us-central1',
            customVoiceName: ((_f = (_e = customVoiceSecret.payload) === null || _e === void 0 ? void 0 : _e.data) === null || _f === void 0 ? void 0 : _f.toString()) || 'projects/sunriza26/locations/us-central1/voices/default-voice',
            referenceVideoUrl: ((_h = (_g = videoUrlSecret.payload) === null || _g === void 0 ? void 0 : _g.data) === null || _h === void 0 ? void 0 : _h.toString()) || 'gs://sunriza26.firebasestorage.app/reference-video.mp4',
            vertexAiModelId: 'imagen-video-generator',
            vertexAiEndpoint: 'us-central1-aiplatform.googleapis.com',
        };
    }
    catch (error) {
        console.warn('Fehler beim Laden der Secrets, verwende Fallback-Konfiguration:', error);
        // Fallback auf Umgebungsvariablen oder Standardwerte
        return {
            projectId: process.env.GOOGLE_CLOUD_PROJECT_ID,
            location: process.env.GOOGLE_CLOUD_LOCATION,
            customVoiceName: process.env.CUSTOM_VOICE_NAME,
            referenceVideoUrl: process.env.REFERENCE_VIDEO_URL,
            vertexAiModelId: process.env.VERTEX_AI_MODEL_ID,
            vertexAiEndpoint: process.env.VERTEX_AI_ENDPOINT,
        };
    }
}
/**
 * Cached Konfiguration für bessere Performance
 */
let cachedConfig = null;
async function getConfig() {
    if (!cachedConfig) {
        cachedConfig = await loadConfig();
    }
    return cachedConfig;
}
//# sourceMappingURL=config.js.map