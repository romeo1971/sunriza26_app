import { onRequest } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';

const UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

async function fetchText(url: string): Promise<string> {
  const r = await fetch(url, {
    headers: {
      'User-Agent': UA,
      Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9,de;q=0.8',
      Referer: 'https://x.com/',
    } as any,
    redirect: 'follow' as any,
  } as any);
  return await r.text();
}

function extractTweetId(u: string): string | null {
  const m = u.match(/\/status\/(\d+)/);
  return m && m[1] ? m[1] : null;
}

function extractThumb(html: string): string | null {
  const mOg = html.match(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i);
  if (mOg && mOg[1]) return mOg[1];
  const mTw = html.match(/<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']+)["']/i);
  if (mTw && mTw[1]) return mTw[1];
  return null;
}

async function rehostImageToGCS(srcUrl: string, key: string): Promise<string> {
  const r: any = await fetch(srcUrl, {
    headers: {
      'User-Agent': UA,
      Accept: 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
      Referer: 'https://x.com/',
    } as any,
    redirect: 'follow' as any,
  } as any);
  if (!(r as any).ok) throw new Error(`fetch image ${ (r as any).status }`);
  const buf = Buffer.from(await (r as any).arrayBuffer());
  const ct = (r as any).headers?.get?.('content-type') || 'image/jpeg';
  const bucket = admin.storage().bucket();
  const file = bucket.file(`social/x/${key}.jpg`);
  await file.save(buf, {
    resumable: false,
    contentType: ct,
    metadata: { cacheControl: 'public, max-age=31536000, immutable' },
  } as any);
  const [signed] = await file.getSignedUrl({ action: 'read', expires: '2099-01-01' } as any);
  return signed;
}

export const xThumb = onRequest({ cors: true, region: 'us-central1', timeoutSeconds: 20 }, async (req, res) => {
  try {
    // Proxy raw image when ?img=... is provided
    const img = (req.query.img as string || '').trim();
    if (img) {
      try {
        const r = await fetch(img, {
          headers: {
            'User-Agent': UA,
            Accept: 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
            Referer: 'https://x.com/',
          } as any,
          redirect: 'follow' as any,
        } as any);
        if (!(r as any).ok) {
          res.status((r as any).status || 502).send('bad gateway');
          return;
        }
        const ct = (r as any).headers?.get?.('content-type') || 'image/jpeg';
        res.setHeader('content-type', ct);
        const buf = Buffer.from(await (r as any).arrayBuffer());
        res.status(200).send(buf);
        return;
      } catch (e: any) {
        res.status(502).json({ error: e?.message || 'proxy failed' });
        return;
      }
    }

    const url = (req.query.url as string || '').trim();
    if (!url) {
      res.status(400).json({ error: 'missing url' });
      return;
    }
    // 0) Unofficial CDN JSON (stabil: liefert photos/video_poster)
    try {
      const id = extractTweetId(url);
      if (id) {
        const cdn = await fetch(`https://cdn.syndication.twimg.com/tweet?id=${encodeURIComponent(id)}`, {
          headers: { 'User-Agent': UA, Accept: 'application/json', Referer: 'https://x.com/' } as any,
        } as any);
        if ((cdn as any).ok) {
          const j: any = await (cdn as any).json();
          let t: string | null = null;
          let title: string | null = (typeof j?.text === 'string' && j.text.trim()) ? j.text.trim() : null;
          if (Array.isArray(j?.photos) && j.photos.length > 0) {
            t = j.photos[0]?.url || null;
          }
          if (!t && typeof j?.video_poster === 'string' && j.video_poster) {
            t = j.video_poster;
          }
          if (t) {
            if (t.includes('&amp;')) t = t.replace(/&amp;/g, '&');
            const hosted = await rehostImageToGCS(t, id);
            res.status(200).json({ thumb: hosted, title: title || undefined });
            return;
          }
        }
      }
    } catch {}
    // 1) Versuche direkt die Statusseite
    try {
      const html = await fetchText(url);
      let t = extractThumb(html);
      const mTitle = html.match(/<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']/i)
        || html.match(/<meta[^>]+name=["']twitter:title["'][^>]+content=["']([^"']+)["']/i)
        || html.match(/<meta[^>]+property=["']og:description["'][^>]+content=["']([^"']+)["']/i);
      const title = mTitle && mTitle[1] ? mTitle[1] : null;
      if (t) {
        if (t.includes('&amp;')) t = t.replace(/&amp;/g, '&');
        const id = extractTweetId(url) || String(Date.now());
        const hosted = await rehostImageToGCS(t, id);
        res.status(200).json({ thumb: hosted, title: title || undefined });
        return;
      }
    } catch {}
    // 2) publish.oembed (liefert oft nur HTML, aber manchmal Bilder in Cards)
    try {
      const o = await fetch(`https://publish.twitter.com/oembed?url=${encodeURIComponent(url)}`, {
        headers: { 'User-Agent': UA, Accept: 'application/json' } as any,
      } as any);
      if ((o as any).ok) {
        const j: any = await (o as any).json();
        const html = String(j?.html || '');
        // Schätze Bild-URL aus eingebetteten img (falls vorhanden)
        const mImg = html.match(/<img[^>]+src=["']([^"']+)["']/i);
        if (mImg && mImg[1]) {
          let t = mImg[1];
          if (t.includes('&amp;')) t = t.replace(/&amp;/g, '&');
          const id = extractTweetId(url) || String(Date.now());
          const hosted = await rehostImageToGCS(t, id);
          // Versuch, Titel zu schätzen: entferne Tags aus HTML
          const txt = html.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
          res.status(200).json({ thumb: hosted, title: txt || undefined });
          return;
        }
      }
    } catch {}
    // 3) Fallback: r.jina.ai statisches HTML
    try {
      const jinaUrl = `https://r.jina.ai/http://${url.replace(/^https?:\/\//, '')}`;
      const r: any = await fetch(jinaUrl, { headers: { 'User-Agent': UA, Accept: 'text/html' } as any } as any);
      if ((r as any).ok) {
        const html = await (r as any).text();
        let t = extractThumb(html);
        const mTitle = html.match(/<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']/i)
          || html.match(/<meta[^>]+name=["']twitter:title["'][^>]+content=["']([^"']+)["']/i)
          || html.match(/<meta[^>]+property=["']og:description["'][^>]+content=["']([^"']+)["']/i);
        const title = mTitle && mTitle[1] ? mTitle[1] : null;
        if (t) {
          if (t.includes('&amp;')) t = t.replace(/&amp;/g, '&');
          const id = extractTweetId(url) || String(Date.now());
          const hosted = await rehostImageToGCS(t, id);
          res.status(200).json({ thumb: hosted, title: title || undefined });
          return;
        }
      }
    } catch {}
    res.status(404).json({ error: 'thumb not found' });
  } catch (e: any) {
    res.status(500).json({ error: e?.message || 'internal error' });
  }
});


