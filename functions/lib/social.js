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
exports.socialEmbedPage = exports.instagramFeed = void 0;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const node_fetch_1 = __importDefault(require("node-fetch"));
if (!admin.apps.length) {
    try {
        admin.initializeApp();
    }
    catch (_a) { }
}
/**
 * Callable: instagramFeed
 * data: { avatarId: string }
 * Rückgabe: { posts: IgMedia[], fromCache: boolean }
 *
 * Erwartet, dass unter avatars/{avatarId}/social_accounts ein Eintrag mit providerName='Instagram'
 * und Feldern { connected: true, ig_user_id, access_token } existiert.
 * Cacht Ergebnis 10 Minuten in avatars/{avatarId}/social_cache/instagram.
 */
exports.instagramFeed = (0, https_1.onCall)({
    region: 'us-central1',
    timeoutSeconds: 20,
}, async (request) => {
    var _a, _b, _c, _d, _e;
    const avatarId = (_b = (_a = request.data) === null || _a === void 0 ? void 0 : _a.avatarId) === null || _b === void 0 ? void 0 : _b.trim();
    if (!avatarId) {
        return { posts: [], fromCache: false, error: 'avatarId_missing' };
    }
    const db = admin.firestore();
    const cacheRef = db
        .collection('avatars')
        .doc(avatarId)
        .collection('social_cache')
        .doc('instagram');
    // 1) Cache-Hit (<=10min)
    try {
        const snap = await cacheRef.get();
        const doc = snap.data();
        if (doc && doc.posts && doc.fetchedAt) {
            const ageMs = Date.now() - doc.fetchedAt;
            if (ageMs <= 10 * 60 * 1000) {
                return { posts: doc.posts, fromCache: true };
            }
        }
    }
    catch (_f) { }
    // 2) Social Account lesen
    let token;
    let igUserId;
    try {
        const qs = await db
            .collection('avatars')
            .doc(avatarId)
            .collection('social_accounts')
            .where('providerName', '==', 'Instagram')
            .where('connected', '==', true)
            .limit(1)
            .get();
        if (!qs.empty) {
            const m = qs.docs[0].data();
            token = m['access_token'] || m['igLongLivedAccessToken'];
            igUserId = m['ig_user_id'] || m['igUserId'];
        }
    }
    catch (_g) { }
    if (!token && !igUserId) {
        return { posts: [], fromCache: false, error: 'not_connected' };
    }
    // 3) Graph API: letzte 5 Medien (Business via ig_user_id) oder Basic Display via /me/media
    try {
        let posts = [];
        if (igUserId && token) {
            const url = new URL(`https://graph.facebook.com/v17.0/${igUserId}/media`);
            url.searchParams.set('fields', 'id,caption,media_type,media_url,permalink,timestamp');
            url.searchParams.set('limit', '5');
            url.searchParams.set('access_token', token);
            const resp = await (0, node_fetch_1.default)(url.toString());
            if (!resp.ok) {
                const text = await resp.text();
                throw new Error(`IG request failed: ${resp.status} ${text}`);
            }
            const json = (await resp.json());
            posts = ((_c = json.data) !== null && _c !== void 0 ? _c : []).slice(0, 5);
        }
        else if (token) {
            // Basic Display fallback
            const url = new URL('https://graph.instagram.com/me/media');
            url.searchParams.set('fields', 'id,caption,media_type,media_url,permalink,timestamp');
            url.searchParams.set('limit', '5');
            url.searchParams.set('access_token', token);
            const resp = await (0, node_fetch_1.default)(url.toString());
            if (!resp.ok) {
                const text = await resp.text();
                throw new Error(`IG Basic request failed: ${resp.status} ${text}`);
            }
            const json = (await resp.json());
            posts = ((_d = json.data) !== null && _d !== void 0 ? _d : []).slice(0, 5);
        }
        // Keine Posts
        if (!posts || posts.length === 0) {
            return { posts: [], fromCache: false, error: 'no_posts' };
        }
        // 4) Cache speichern
        try {
            await cacheRef.set({
                posts,
                fetchedAt: Date.now(),
            }, { merge: true });
        }
        catch (_h) { }
        return { posts, fromCache: false };
    }
    catch (e) {
        return { posts: [], fromCache: false, error: (_e = e === null || e === void 0 ? void 0 : e.message) !== null && _e !== void 0 ? _e : 'unknown' };
    }
});
/**
 * HTML-Embed-Seite für Social Feeds.
 * GET /socialEmbedPage?provider=instagram&avatarId=...
 * Rendert die letzten 5 Posts als simples Grid (ohne Login-Wall).
 */
exports.socialEmbedPage = (0, https_1.onRequest)({ region: 'us-central1', timeoutSeconds: 20 }, async (req, res) => {
    var _a, _b;
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    const provider = String(req.query.provider || '').toLowerCase();
    const avatarId = String(req.query.avatarId || '');
    if (!provider || !avatarId) {
        res.status(400).send('<html><body><p>Bad request</p></body></html>');
        return;
    }
    // Reuse logic per provider
    const db = admin.firestore();
    let posts = [];
    if (provider === 'instagram') {
        const cacheRef = db.collection('avatars').doc(avatarId).collection('social_cache').doc('instagram');
        try {
            const snap = await cacheRef.get();
            const doc = snap.data();
            if (doc && doc.posts && doc.fetchedAt && Date.now() - doc.fetchedAt <= 10 * 60 * 1000) {
                posts = doc.posts.slice(0, 5);
            }
        }
        catch (_c) { }
        if (posts.length === 0) {
            // Load tokens
            let token;
            let igUserId;
            try {
                const qs = await db
                    .collection('avatars')
                    .doc(avatarId)
                    .collection('social_accounts')
                    .where('providerName', '==', 'Instagram')
                    .where('connected', '==', true)
                    .limit(1)
                    .get();
                if (!qs.empty) {
                    const m = qs.docs[0].data();
                    token = m['access_token'] || m['igLongLivedAccessToken'];
                    igUserId = m['ig_user_id'] || m['igUserId'];
                }
            }
            catch (_d) { }
            if (token && igUserId) {
                try {
                    const url = new URL(`https://graph.facebook.com/v17.0/${igUserId}/media`);
                    url.searchParams.set('fields', 'id,caption,media_type,media_url,permalink,timestamp');
                    url.searchParams.set('limit', '5');
                    url.searchParams.set('access_token', token);
                    const resp = await (0, node_fetch_1.default)(url.toString());
                    if (resp.ok) {
                        const json = (await resp.json());
                        posts = ((_a = json.data) !== null && _a !== void 0 ? _a : []).slice(0, 5);
                        try {
                            await cacheRef.set({ posts, fetchedAt: Date.now() }, { merge: true });
                        }
                        catch (_e) { }
                    }
                }
                catch (_f) { }
            }
        }
    }
    else if (provider === 'facebook') {
        const cacheRef = db.collection('avatars').doc(avatarId).collection('social_cache').doc('facebook');
        try {
            const snap = await cacheRef.get();
            const doc = snap.data();
            if (doc && doc.posts && doc.fetchedAt && Date.now() - doc.fetchedAt <= 10 * 60 * 1000) {
                posts = doc.posts.slice(0, 5);
            }
        }
        catch (_g) { }
        if (posts.length === 0) {
            let pageToken;
            let pageId;
            try {
                const doc = await db
                    .collection('avatars')
                    .doc(avatarId)
                    .collection('social_accounts')
                    .doc('facebook')
                    .get();
                const m = doc.data();
                pageToken = m === null || m === void 0 ? void 0 : m.page_access_token;
                pageId = m === null || m === void 0 ? void 0 : m.page_id;
            }
            catch (_h) { }
            if (pageToken && pageId) {
                try {
                    const url = new URL(`https://graph.facebook.com/v17.0/${pageId}/posts`);
                    url.searchParams.set('fields', 'id,full_picture,permalink_url,message,created_time');
                    url.searchParams.set('limit', '5');
                    url.searchParams.set('access_token', pageToken);
                    const resp = await (0, node_fetch_1.default)(url.toString());
                    if (resp.ok) {
                        const json = (await resp.json());
                        posts = ((_b = json.data) !== null && _b !== void 0 ? _b : []).map((p) => ({
                            id: p.id,
                            caption: p.message,
                            media_type: 'IMAGE',
                            media_url: p.full_picture || '',
                            permalink: p.permalink_url,
                            timestamp: p.created_time,
                        })).filter((p) => p.media_url).slice(0, 5);
                        try {
                            await cacheRef.set({ posts, fetchedAt: Date.now() }, { merge: true });
                        }
                        catch (_j) { }
                    }
                }
                catch (_k) { }
            }
        }
    }
    else {
        res.status(400).send('<html><body><p>Unsupported provider</p></body></html>');
        return;
    }
    // Wenn keine Posts: zeige CTA zum Verbinden (öffnet OAuth in neuem Tab)
    if (!posts || posts.length === 0) {
        const base = `https://us-central1-${process.env.GCLOUD_PROJECT}.cloudfunctions.net`;
        const endpoint = provider === 'facebook' ? 'fbConnect' : 'igConnect';
        const connectUrl = `${base}/${endpoint}?avatarId=${encodeURIComponent(avatarId)}`;
        const htmlEmpty = `<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Instagram verbinden</title>
  <style>
    body { margin:0; background:#000; color:#fff; font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif; display:flex; align-items:center; justify-content:center; height:100vh; }
    .box { max-width:520px; padding:20px; background:#111; border:1px solid #222; border-radius:12px; text-align:center; }
    a.btn { display:inline-block; margin-top:12px; padding:12px 16px; border-radius:10px; background:#1e88e5; color:#fff; text-decoration:none; font-weight:600; }
    p { color:#bbb; }
  </style>
</head>
<body>
  <div class="box">
    <h3>Instagram verbinden</h3>
    <p>Einmal autorisieren – danach laden wir automatisch die neuesten Posts.</p>
    <a class="btn" href="${connectUrl}" target="_blank" rel="noopener">Jetzt verbinden</a>
    <p style="font-size:12px;margin-top:10px">Nach der Autorisierung diese Ansicht neu laden.</p>
  </div>
</body>
</html>`;
        res.status(200).send(htmlEmpty);
        return;
    }
    const itemsHtml = posts
        .map((p) => {
        const safeUrl = p.media_url;
        const link = p.permalink;
        const isVideo = (p.media_type || '').toUpperCase().includes('VIDEO');
        const mediaTag = isVideo
            ? `<video src="${safeUrl}" controls muted playsinline preload="metadata"></video>`
            : `<img src="${safeUrl}" alt="">`;
        return `<a class="card" href="${link}" target="_blank" rel="noopener noreferrer">${mediaTag}</a>`;
    })
        .join('');
    const html = `<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Instagram Feed</title>
  <style>
    body { margin: 0; background: #000; color: #fff; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 8px; padding: 8px; }
    .card { display: block; border-radius: 8px; overflow: hidden; background: #111; }
    img, video { width: 100%; height: 100%; object-fit: cover; display: block; }
  </style>
</head>
<body>
  <div class="grid">${itemsHtml}</div>
</body>
</html>`;
    res.status(200).send(html);
});
//# sourceMappingURL=social.js.map