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
exports.igCallback = exports.igConnect = void 0;
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
// Secrets (setze via: firebase functions:secrets:set IG_APP_ID / IG_APP_SECRET / IG_REDIRECT_URI)
const IG_APP_ID = (0, params_1.defineSecret)('IG_APP_ID');
const IG_APP_SECRET = (0, params_1.defineSecret)('IG_APP_SECRET');
const IG_REDIRECT_URI = (0, params_1.defineSecret)('IG_REDIRECT_URI'); // e.g. https://us-central1-sunriza26.cloudfunctions.net/igCallback
/**
 * GET /igConnect?avatarId=...
 * Redirect zu Meta OAuth (Basic Display/Graph scopes minimal)
 */
exports.igConnect = (0, https_1.onRequest)({ region: 'us-central1', secrets: [IG_APP_ID, IG_REDIRECT_URI] }, async (req, res) => {
    const avatarId = String(req.query.avatarId || '').trim();
    const appId = IG_APP_ID.value();
    const redirect = IG_REDIRECT_URI.value();
    if (!avatarId || !appId || !redirect) {
        res.status(400).send('Bad request');
        return;
    }
    const state = encodeURIComponent(avatarId);
    const scopes = [
        'instagram_basic',
        'instagram_graph_user_media',
    ].join(',');
    const url = new URL('https://www.facebook.com/v17.0/dialog/oauth');
    url.searchParams.set('client_id', appId);
    url.searchParams.set('redirect_uri', redirect);
    url.searchParams.set('scope', scopes);
    url.searchParams.set('response_type', 'code');
    url.searchParams.set('state', state);
    res.redirect(url.toString());
});
/**
 * GET /igCallback?code=...&state=avatarId
 * Tauscht Code gegen Token, versucht Long-Lived Token, speichert unter avatars/{avatarId}/social_accounts
 */
exports.igCallback = (0, https_1.onRequest)({ region: 'us-central1', secrets: [IG_APP_ID, IG_APP_SECRET, IG_REDIRECT_URI] }, async (req, res) => {
    try {
        const code = String(req.query.code || '').trim();
        const avatarId = String(req.query.state || '').trim();
        const appId = IG_APP_ID.value();
        const appSecret = IG_APP_SECRET.value();
        const redirect = IG_REDIRECT_URI.value();
        if (!code || !avatarId || !appId || !appSecret || !redirect) {
            res.status(400).send('Bad request');
            return;
        }
        // 1) Short-lived access token
        const tokenUrl = new URL('https://graph.facebook.com/v17.0/oauth/access_token');
        tokenUrl.searchParams.set('client_id', appId);
        tokenUrl.searchParams.set('client_secret', appSecret);
        tokenUrl.searchParams.set('redirect_uri', redirect);
        tokenUrl.searchParams.set('code', code);
        const tokResp = await (0, node_fetch_1.default)(tokenUrl.toString());
        if (!tokResp.ok) {
            const text = await tokResp.text();
            res.status(500).send(`OAuth exchange failed: ${text}`);
            return;
        }
        const shortJson = await tokResp.json();
        const shortToken = shortJson.access_token;
        // 2) Try long-lived (Basic Display)
        let longToken = shortToken;
        try {
            const llUrl = new URL('https://graph.instagram.com/access_token');
            llUrl.searchParams.set('grant_type', 'ig_exchange_token');
            llUrl.searchParams.set('client_secret', appSecret);
            llUrl.searchParams.set('access_token', shortToken);
            const llResp = await (0, node_fetch_1.default)(llUrl.toString());
            if (llResp.ok) {
                const llJson = await llResp.json();
                longToken = llJson.access_token || longToken;
            }
        }
        catch (_a) { }
        // 3) Try to get user info (Basic Display)
        let igBasicUser = undefined;
        try {
            const meUrl = new URL('https://graph.instagram.com/me');
            meUrl.searchParams.set('fields', 'id,username');
            meUrl.searchParams.set('access_token', longToken);
            const meResp = await (0, node_fetch_1.default)(meUrl.toString());
            if (meResp.ok)
                igBasicUser = await meResp.json();
        }
        catch (_b) { }
        const docData = {
            providerName: 'Instagram',
            connected: true,
            access_token: longToken,
            updatedAt: Date.now(),
        };
        if (igBasicUser === null || igBasicUser === void 0 ? void 0 : igBasicUser.id) {
            docData.ig_user_id = String(igBasicUser.id);
            docData.ig_username = igBasicUser.username;
        }
        await admin.firestore()
            .collection('avatars').doc(avatarId)
            .collection('social_accounts').doc('instagram')
            .set(docData, { merge: true });
        res.status(200).send('Instagram verbunden. Du kannst dieses Fenster schließen.');
    }
    catch (e) {
        res.status(500).send(`Error: ${(e === null || e === void 0 ? void 0 : e.message) || 'unknown'}`);
    }
});
//# sourceMappingURL=social_oauth.js.map