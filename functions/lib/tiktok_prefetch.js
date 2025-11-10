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
exports.tiktokPrefetch = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
if (!admin.apps.length) {
    admin.initializeApp();
}
const db = admin.firestore();
exports.tiktokPrefetch = (0, https_1.onRequest)({ cors: true, timeoutSeconds: 60, region: "us-central1" }, async (req, res) => {
    try {
        const avatarId = req.query.avatarId || "";
        const profileUrl = req.query.profileUrl || "";
        const limit = Math.max(1, Math.min(20, parseInt(req.query.limit || "10", 10)));
        console.log(`[tiktokPrefetch] avatarId=${avatarId} limit=${limit} profileUrl=${profileUrl}`);
        if (!avatarId || !profileUrl) {
            res.status(400).json({ error: "Missing avatarId or profileUrl" });
            return;
        }
        const ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";
        // Normalize URL (TikTok mag den Slash am Ende)
        const normalized = profileUrl.endsWith("/") ? profileUrl : profileUrl + "/";
        const r = await fetch(normalized, {
            headers: {
                "User-Agent": ua,
                Accept: "text/html",
                "Accept-Language": "en-US,en;q=0.9",
                Referer: "https://www.tiktok.com/",
            },
            redirect: "follow",
        });
        const html = await r.text();
        const found = [];
        const seen = new Set();
        // Preferred: parse embedded JSON state
        try {
            const mJson = html.match(/<script id="SIGI_STATE"[^>]*>([\s\S]*?)<\/script>/);
            if (mJson && mJson[1]) {
                const state = JSON.parse(mJson[1]);
                const itemModule = (state === null || state === void 0 ? void 0 : state.ItemModule) || {};
                const ids = Object.keys(itemModule);
                console.log(`[tiktokPrefetch] SIGI_STATE items=${ids.length}`);
                for (const id of ids) {
                    const item = itemModule[id];
                    const author = (item === null || item === void 0 ? void 0 : item.author) ||
                        (item === null || item === void 0 ? void 0 : item.authorName) ||
                        (item === null || item === void 0 ? void 0 : item.authorUniqueId) ||
                        "";
                    if (author && id) {
                        const url = `https://www.tiktok.com/@${author}/video/${id}`;
                        if (!seen.has(url)) {
                            seen.add(url);
                            found.push(url);
                        }
                        if (found.length >= limit)
                            break;
                    }
                }
            }
        }
        catch (_a) {
            // ignore, fallback to regex
        }
        // Fallback: regex video urls
        if (found.length < limit) {
            const re = /https:\/\/www\.tiktok\.com\/@[^\/\s]+\/video\/(\d+)/g;
            let m;
            while ((m = re.exec(html)) !== null) {
                const url = m[0];
                if (!seen.has(url)) {
                    seen.add(url);
                    found.push(url);
                }
                if (found.length >= limit)
                    break;
            }
            console.log(`[tiktokPrefetch] regex found=${found.length}`);
        }
        // Additional fallback: relative links like /@user/video/123
        if (found.length < limit) {
            const reRel = /\/@[^\/\s]+\/video\/(\d+)/g;
            let m;
            while ((m = reRel.exec(html)) !== null) {
                const url = `https://www.tiktok.com${m[0]}`;
                if (!seen.has(url)) {
                    seen.add(url);
                    found.push(url);
                }
                if (found.length >= limit)
                    break;
            }
            console.log(`[tiktokPrefetch] relative found total=${found.length}`);
        }
        // Validate via TikTok oEmbed and keep only embeddable URLs
        const validated = [];
        for (const url of found) {
            if (validated.length >= limit)
                break;
            try {
                const resp = await fetch(`https://www.tiktok.com/oembed?url=${encodeURIComponent(url)}`, {
                    headers: { "User-Agent": ua, Accept: "application/json" },
                });
                if (resp.ok) {
                    validated.push(url);
                }
            }
            catch (_b) {
                // ignore single failures
            }
        }
        const manualUrls = validated.slice(0, limit);
        console.log(`[tiktokPrefetch] validated=${manualUrls.length}`);
        await db
            .collection("avatars")
            .doc(avatarId)
            .collection("social_accounts")
            .doc("tiktok")
            .set({
            providerName: "TikTok",
            profileUrl,
            manualUrls,
            connected: true,
            updatedAt: Date.now(),
        }, { merge: true });
        // Browser/Client cacht Embeds selbst.
        res.json({ urlsCount: manualUrls.length, urls: manualUrls });
    }
    catch (e) {
        res.status(500).json({ error: (e === null || e === void 0 ? void 0 : e.message) || "prefetch failed" });
    }
});
//# sourceMappingURL=tiktok_prefetch.js.map