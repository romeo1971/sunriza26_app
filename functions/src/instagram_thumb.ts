import { onRequest } from 'firebase-functions/v2/https';

const UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

function normalizePermalink(rawUrl: string): string {
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
  } catch {
    const base = rawUrl.split('?')[0].split('#')[0];
    return base.endsWith('/') ? base : `${base}/`;
  }
}

async function fetchText(url: string, headers?: Record<string, string>): Promise<string> {
  const r = await fetch(url, {
    headers: {
      'User-Agent': UA,
      Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      Referer: 'https://www.instagram.com/',
      ...headers,
    } as any,
    redirect: 'follow' as any,
  } as any);
  return await r.text();
}

export const instagramThumb = onRequest({ cors: true, region: 'us-central1', timeoutSeconds: 30 }, async (req, res) => {
  try {
    const url = (req.query.url as string || '').trim();
    if (!url) {
      res.status(400).json({ error: 'missing url' });
      return;
    }
    const permalink = normalizePermalink(url);
    // 1) Try oEmbed
    try {
      const r = await fetch(`https://www.instagram.com/oembed/?url=${encodeURIComponent(permalink)}`, {
        headers: { 'User-Agent': UA, Accept: 'application/json', Referer: 'https://www.instagram.com/' } as any,
      } as any);
      if (r.ok) {
        const m: any = await r.json();
        const t = (m?.thumbnail_url as string) || '';
        if (t) {
          res.status(200).json({ thumb: t });
          return;
        }
      }
    } catch {}
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
    } catch {}
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
    } catch {}
    res.status(404).json({ error: 'thumb not found' });
  } catch (e: any) {
    res.status(500).json({ error: e?.message || 'internal error' });
  }
});


