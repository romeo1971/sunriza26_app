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
Object.defineProperty(exports, "__esModule", { value: true });
exports.xThumb = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
async function fetchText(url) {
    const r = await fetch(url, {
        headers: {
            'User-Agent': UA,
            Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.9,de;q=0.8',
            Referer: 'https://x.com/',
        },
        redirect: 'follow',
    });
    return await r.text();
}
function extractTweetId(u) {
    const m = u.match(/\/status\/(\d+)/);
    return m && m[1] ? m[1] : null;
}
function extractThumb(html) {
    const mOg = html.match(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i);
    if (mOg && mOg[1])
        return mOg[1];
    const mTw = html.match(/<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']+)["']/i);
    if (mTw && mTw[1])
        return mTw[1];
    return null;
}
async function rehostImageToGCS(srcUrl, key) {
    var _a, _b;
    const r = await fetch(srcUrl, {
        headers: {
            'User-Agent': UA,
            Accept: 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
            Referer: 'https://x.com/',
        },
        redirect: 'follow',
    });
    if (!r.ok)
        throw new Error(`fetch image ${r.status}`);
    const buf = Buffer.from(await r.arrayBuffer());
    const ct = ((_b = (_a = r.headers) === null || _a === void 0 ? void 0 : _a.get) === null || _b === void 0 ? void 0 : _b.call(_a, 'content-type')) || 'image/jpeg';
    const bucket = admin.storage().bucket();
    const file = bucket.file(`social/x/${key}.jpg`);
    await file.save(buf, {
        resumable: false,
        contentType: ct,
        metadata: { cacheControl: 'public, max-age=31536000, immutable' },
    });
    const [signed] = await file.getSignedUrl({ action: 'read', expires: '2099-01-01' });
    return signed;
}
exports.xThumb = (0, https_1.onRequest)({ cors: true, region: 'us-central1', timeoutSeconds: 20 }, async (req, res) => {
    var _a, _b, _c;
    try {
        // Proxy raw image when ?img=... is provided
        const img = (req.query.img || '').trim();
        if (img) {
            try {
                const r = await fetch(img, {
                    headers: {
                        'User-Agent': UA,
                        Accept: 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
                        Referer: 'https://x.com/',
                    },
                    redirect: 'follow',
                });
                if (!r.ok) {
                    res.status(r.status || 502).send('bad gateway');
                    return;
                }
                const ct = ((_b = (_a = r.headers) === null || _a === void 0 ? void 0 : _a.get) === null || _b === void 0 ? void 0 : _b.call(_a, 'content-type')) || 'image/jpeg';
                res.setHeader('content-type', ct);
                const buf = Buffer.from(await r.arrayBuffer());
                res.status(200).send(buf);
                return;
            }
            catch (e) {
                res.status(502).json({ error: (e === null || e === void 0 ? void 0 : e.message) || 'proxy failed' });
                return;
            }
        }
        const url = (req.query.url || '').trim();
        if (!url) {
            res.status(400).json({ error: 'missing url' });
            return;
        }
        // 0) Unofficial CDN JSON (stabil: liefert photos/video_poster)
        try {
            const id = extractTweetId(url);
            if (id) {
                const cdn = await fetch(`https://cdn.syndication.twimg.com/tweet?id=${encodeURIComponent(id)}`, {
                    headers: { 'User-Agent': UA, Accept: 'application/json', Referer: 'https://x.com/' },
                });
                if (cdn.ok) {
                    const j = await cdn.json();
                    let t = null;
                    let title = (typeof (j === null || j === void 0 ? void 0 : j.text) === 'string' && j.text.trim()) ? j.text.trim() : null;
                    if (Array.isArray(j === null || j === void 0 ? void 0 : j.photos) && j.photos.length > 0) {
                        t = ((_c = j.photos[0]) === null || _c === void 0 ? void 0 : _c.url) || null;
                    }
                    if (!t && typeof (j === null || j === void 0 ? void 0 : j.video_poster) === 'string' && j.video_poster) {
                        t = j.video_poster;
                    }
                    if (t) {
                        if (t.includes('&amp;'))
                            t = t.replace(/&amp;/g, '&');
                        const hosted = await rehostImageToGCS(t, id);
                        res.status(200).json({ thumb: hosted, title: title || undefined });
                        return;
                    }
                }
            }
        }
        catch (_d) { }
        // 1) Versuche direkt die Statusseite
        try {
            const html = await fetchText(url);
            let t = extractThumb(html);
            const mTitle = html.match(/<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']/i)
                || html.match(/<meta[^>]+name=["']twitter:title["'][^>]+content=["']([^"']+)["']/i)
                || html.match(/<meta[^>]+property=["']og:description["'][^>]+content=["']([^"']+)["']/i);
            const title = mTitle && mTitle[1] ? mTitle[1] : null;
            if (t) {
                if (t.includes('&amp;'))
                    t = t.replace(/&amp;/g, '&');
                const id = extractTweetId(url) || String(Date.now());
                const hosted = await rehostImageToGCS(t, id);
                res.status(200).json({ thumb: hosted, title: title || undefined });
                return;
            }
        }
        catch (_e) { }
        // 2) publish.oembed (liefert oft nur HTML, aber manchmal Bilder in Cards)
        try {
            const o = await fetch(`https://publish.twitter.com/oembed?url=${encodeURIComponent(url)}`, {
                headers: { 'User-Agent': UA, Accept: 'application/json' },
            });
            if (o.ok) {
                const j = await o.json();
                const html = String((j === null || j === void 0 ? void 0 : j.html) || '');
                // Schätze Bild-URL aus eingebetteten img (falls vorhanden)
                const mImg = html.match(/<img[^>]+src=["']([^"']+)["']/i);
                if (mImg && mImg[1]) {
                    let t = mImg[1];
                    if (t.includes('&amp;'))
                        t = t.replace(/&amp;/g, '&');
                    const id = extractTweetId(url) || String(Date.now());
                    const hosted = await rehostImageToGCS(t, id);
                    // Versuch, Titel zu schätzen: entferne Tags aus HTML
                    const txt = html.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
                    res.status(200).json({ thumb: hosted, title: txt || undefined });
                    return;
                }
            }
        }
        catch (_f) { }
        // 3) Fallback: r.jina.ai statisches HTML
        try {
            const jinaUrl = `https://r.jina.ai/http://${url.replace(/^https?:\/\//, '')}`;
            const r = await fetch(jinaUrl, { headers: { 'User-Agent': UA, Accept: 'text/html' } });
            if (r.ok) {
                const html = await r.text();
                let t = extractThumb(html);
                const mTitle = html.match(/<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']/i)
                    || html.match(/<meta[^>]+name=["']twitter:title["'][^>]+content=["']([^"']+)["']/i)
                    || html.match(/<meta[^>]+property=["']og:description["'][^>]+content=["']([^"']+)["']/i);
                const title = mTitle && mTitle[1] ? mTitle[1] : null;
                if (t) {
                    if (t.includes('&amp;'))
                        t = t.replace(/&amp;/g, '&');
                    const id = extractTweetId(url) || String(Date.now());
                    const hosted = await rehostImageToGCS(t, id);
                    res.status(200).json({ thumb: hosted, title: title || undefined });
                    return;
                }
            }
        }
        catch (_g) { }
        res.status(404).json({ error: 'thumb not found' });
    }
    catch (e) {
        res.status(500).json({ error: (e === null || e === void 0 ? void 0 : e.message) || 'internal error' });
    }
});
//# sourceMappingURL=x_thumb.js.map