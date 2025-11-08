"use strict";
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
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.fbConnect = void 0;
exports.handleFacebookTokenExchange = handleFacebookTokenExchange;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const node_fetch_1 = __importDefault(require("node-fetch"));
if (!admin.apps.length) {
    try {
        admin.initializeApp();
    }
    catch (_a) { }
}
const IG_APP_ID = (0, params_1.defineSecret)('IG_APP_ID');
const IG_REDIRECT_URI = (0, params_1.defineSecret)('IG_REDIRECT_URI'); // wir verwenden die gleiche Redirect-URL
/**
 * GET /fbConnect?avatarId=...
 * Fordert Pages-Scopes an und leitet zu OAuth.
 */
exports.fbConnect = (0, https_1.onRequest)({ region: 'us-central1', secrets: [IG_APP_ID, IG_REDIRECT_URI] }, async (req, res) => {
    const avatarId = String(req.query.avatarId || '').trim();
    const appId = IG_APP_ID.value();
    const redirect = IG_REDIRECT_URI.value(); // nutzen gleiche Callback
    if (!avatarId || !appId || !redirect) {
        res.status(400).send('Bad request');
        return;
    }
    const scopes = ['pages_show_list', 'pages_read_engagement', 'public_profile'].join(',');
    const url = new URL('https://www.facebook.com/v17.0/dialog/oauth');
    url.searchParams.set('client_id', appId);
    url.searchParams.set('redirect_uri', redirect);
    url.searchParams.set('scope', scopes);
    url.searchParams.set('response_type', 'code');
    url.searchParams.set('state', encodeURIComponent(`fb:${avatarId}`)); // Präfix, um im Callback zu unterscheiden
    res.redirect(url.toString());
});
/**
 * Hilfsfunktion: verarbeitet im gemeinsamen igCallback-State den "fb:"-Fall.
 * Wird aus igCallback intern NICHT automatisch aufgerufen; wir belassen fbConnect separat.
 * Diese Utility-Funktion steht optional bereit, falls du später bündeln möchtest.
 */
async function handleFacebookTokenExchange({ userAccessToken, avatarId, }) {
    var _a;
    const db = admin.firestore();
    // Hole die erste Page und Page-Token
    const mePagesUrl = new URL('https://graph.facebook.com/v17.0/me/accounts');
    mePagesUrl.searchParams.set('access_token', userAccessToken);
    const pagesResp = await (0, node_fetch_1.default)(mePagesUrl.toString());
    if (!pagesResp.ok) {
        throw new Error(`pages list failed: ${await pagesResp.text()}`);
    }
    const pagesJson = (await pagesResp.json());
    const first = (_a = pagesJson === null || pagesJson === void 0 ? void 0 : pagesJson.data) === null || _a === void 0 ? void 0 : _a[0];
    if (!(first === null || first === void 0 ? void 0 : first.id) || !(first === null || first === void 0 ? void 0 : first.access_token)) {
        throw new Error('no_page_available');
    }
    await db
        .collection('avatars')
        .doc(avatarId)
        .collection('social_accounts')
        .doc('facebook')
        .set({
        providerName: 'Facebook',
        connected: true,
        page_id: String(first.id),
        page_access_token: String(first.access_token),
        updatedAt: Date.now(),
    }, { merge: true });
}
//# sourceMappingURL=social_oauth_facebook.js.map