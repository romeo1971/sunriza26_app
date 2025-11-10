"use strict";
/**
 * Cloud Function: LinkedIn Thumbnail Proxy
 * Ruft einen LinkedIn-Post ab und extrahiert og:image / twitter:image
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.linkedinThumb = void 0;
const https_1 = require("firebase-functions/v2/https");
const node_fetch_1 = __importDefault(require("node-fetch"));
exports.linkedinThumb = (0, https_1.onRequest)({ cors: true }, async (req, res) => {
    let url = req.query.url || '';
    if (!url || !url.toLowerCase().includes('linkedin.com/')) {
        res.status(400).json({ error: 'Invalid LinkedIn URL' });
        return;
    }
    try {
        // Normalisieren: /embed/ -> / und Query entfernen
        if (url.includes('/embed/'))
            url = url.replace('/embed/', '/');
        if (url.includes('?'))
            url = url.split('?')[0];
        const tryFetch = async (target) => {
            return await (0, node_fetch_1.default)(target, {
                headers: {
                    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
                    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
                    'Accept-Language': 'en-US,en;q=0.5',
                },
            });
        };
        let resp = await tryFetch(url);
        if (!resp.ok) {
            // Fallback: probiere Embed
            const embedUrl = url.replace('//www.linkedin.com/', '//www.linkedin.com/embed/');
            resp = await tryFetch(embedUrl);
        }
        if (!resp.ok) {
            res.status(502).json({ error: 'Failed to fetch LinkedIn post' });
            return;
        }
        const html = await resp.text();
        const regs = [
            /<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i,
            /<meta[^>]+property=["']og:image:url["'][^>]+content=["']([^"']+)["']/i,
            /<meta[^>]+property=["']og:image:secure_url["'][^>]+content=["']([^"']+)["']/i,
            /<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']+)["']/i,
            /<meta[^>]+name=["']twitter:image:src["'][^>]+content=["']([^"']+)["']/i,
        ];
        let thumb = '';
        for (const re of regs) {
            const m = re.exec(html);
            if (m) {
                thumb = m[1];
                break;
            }
        }
        if (thumb) {
            // HTML-Entities in URLs entfernen
            if (thumb.includes('&amp;'))
                thumb = thumb.replace(/&amp;/g, '&');
            res.json({ thumb });
        }
        else {
            res.status(404).json({ error: 'No thumbnail found' });
        }
    }
    catch (err) {
        console.error('LinkedIn Thumb Error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
});
//# sourceMappingURL=linkedin_thumb.js.map