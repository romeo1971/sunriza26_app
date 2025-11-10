"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.instagramThumb = void 0;
const https_1 = require("firebase-functions/v2/https");
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
function normalizePermalink(rawUrl) {
    try {
        const u = new URL(rawUrl.trim());
        const parts = u.pathname.split('/').filter(Boolean);
        const idx = parts.findIndex((s) => s === 'reel' || s === 'p' || s === 'tv');
        if (idx >= 0 && idx + 1 < parts.length) {
            const kind = parts[idx];
            const id = parts[idx + 1];
            return `https://www.instagram.com/${kind}/${id}/`;
        }
        const base = rawUrl.split('?')[0].split('#')[0];
        return base.endsWith('/') ? base : `${base}/`;
    }
    catch (_a) {
        const base = rawUrl.split('?')[0].split('#')[0];
        return base.endsWith('/') ? base : `${base}/`;
    }
}
async function fetchText(url, headers) {
    const r = await fetch(url, {
        headers: {
            'User-Agent': UA,
            Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            Referer: 'https://www.instagram.com/',
            ...headers,
        },
        redirect: 'follow',
    });
    return await r.text();
}
exports.instagramThumb = (0, https_1.onRequest)({ cors: true, region: 'us-central1', timeoutSeconds: 30 }, async (req, res) => {
    try {
        const url = (req.query.url || '').trim();
        if (!url) {
            res.status(400).json({ error: 'missing url' });
            return;
        }
        const permalink = normalizePermalink(url);
        // 1) Try oEmbed
        try {
            const r = await fetch(`https://www.instagram.com/oembed/?url=${encodeURIComponent(permalink)}`, {
                headers: { 'User-Agent': UA, Accept: 'application/json', Referer: 'https://www.instagram.com/' },
            });
            if (r.ok) {
                const m = await r.json();
                const t = (m === null || m === void 0 ? void 0 : m.thumbnail_url) || '';
                if (t) {
                    res.status(200).json({ thumb: t });
                    return;
                }
            }
        }
        catch (_a) { }
        // 2) Fallback: scrape post page
        try {
            const html = await fetchText(permalink);
            const mOg = html.match(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i);
            const mTw = html.match(/<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']+)["']/i);
            const t = (mOg && mOg[1]) || (mTw && mTw[1]) || '';
            if (t) {
                res.status(200).json({ thumb: t });
                return;
            }
        }
        catch (_b) { }
        // 3) Fallback: scrape embed page
        try {
            const html = await fetchText(`${permalink}embed`);
            const mOg = html.match(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i);
            const mTw = html.match(/<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']+)["']/i);
            const t = (mOg && mOg[1]) || (mTw && mTw[1]) || '';
            if (t) {
                res.status(200).json({ thumb: t });
                return;
            }
        }
        catch (_c) { }
        res.status(404).json({ error: 'thumb not found' });
    }
    catch (e) {
        res.status(500).json({ error: (e === null || e === void 0 ? void 0 : e.message) || 'internal error' });
    }
});
//# sourceMappingURL=instagram_thumb.js.map