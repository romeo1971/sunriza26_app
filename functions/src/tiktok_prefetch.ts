import { onRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

if (!admin.apps.length) {
  admin.initializeApp();
}
const db = admin.firestore();

export const tiktokPrefetch = onRequest({ cors: true, timeoutSeconds: 60, region: "us-central1" }, async (req, res) => {
  try {
    const avatarId = (req.query.avatarId as string) || "";
    const profileUrl = (req.query.profileUrl as string) || "";
    const limit = Math.max(1, Math.min(20, parseInt((req.query.limit as string) || "10", 10)));
    console.log(`[tiktokPrefetch] avatarId=${avatarId} limit=${limit} profileUrl=${profileUrl}`);
    if (!avatarId || !profileUrl) {
      res.status(400).json({ error: "Missing avatarId or profileUrl" });
      return;
    }
    const ua =
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";
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
    } as any);
    const html = await r.text();
    const found: string[] = [];
    const seen = new Set<string>();
    // Preferred: parse embedded JSON state
    try {
      const mJson = html.match(/<script id="SIGI_STATE"[^>]*>([\s\S]*?)<\/script>/);
      if (mJson && mJson[1]) {
        const state = JSON.parse(mJson[1]);
        const itemModule = state?.ItemModule || {};
        const ids = Object.keys(itemModule);
        console.log(`[tiktokPrefetch] SIGI_STATE items=${ids.length}`);
        for (const id of ids) {
          const item = itemModule[id];
          const author =
            item?.author ||
            item?.authorName ||
            item?.authorUniqueId ||
            "";
          if (author && id) {
            const url = `https://www.tiktok.com/@${author}/video/${id}`;
            if (!seen.has(url)) {
              seen.add(url);
              found.push(url);
            }
            if (found.length >= limit) break;
          }
        }
      }
    } catch {
      // ignore, fallback to regex
    }
    // Fallback: regex video urls
    if (found.length < limit) {
      const re = /https:\/\/www\.tiktok\.com\/@[^\/\s]+\/video\/(\d+)/g;
      let m: RegExpExecArray | null;
      while ((m = re.exec(html)) !== null) {
        const url = m[0];
        if (!seen.has(url)) {
          seen.add(url);
          found.push(url);
        }
        if (found.length >= limit) break;
      }
      console.log(`[tiktokPrefetch] regex found=${found.length}`);
    }
    // Additional fallback: relative links like /@user/video/123
    if (found.length < limit) {
      const reRel = /\/@[^\/\s]+\/video\/(\d+)/g;
      let m: RegExpExecArray | null;
      while ((m = reRel.exec(html)) !== null) {
        const url = `https://www.tiktok.com${m[0]}`;
        if (!seen.has(url)) {
          seen.add(url);
          found.push(url);
        }
        if (found.length >= limit) break;
      }
      console.log(`[tiktokPrefetch] relative found total=${found.length}`);
    }
    // Validate via TikTok oEmbed and keep only embeddable URLs
    const validated: string[] = [];
    for (const url of found) {
      if (validated.length >= limit) break;
      try {
        const resp = await fetch(`https://www.tiktok.com/oembed?url=${encodeURIComponent(url)}`, {
          headers: { "User-Agent": ua, Accept: "application/json" },
        });
        if (resp.ok) {
          validated.push(url);
        }
      } catch {
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
      .set(
        {
          providerName: "TikTok",
          profileUrl,
          manualUrls,
          connected: true,
          updatedAt: Date.now(),
        },
        { merge: true }
      );
    // Browser/Client cacht Embeds selbst.
    res.json({ urlsCount: manualUrls.length, urls: manualUrls });
  } catch (e: any) {
    res.status(500).json({ error: e?.message || "prefetch failed" });
  }
});


