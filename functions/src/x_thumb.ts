import { onRequest } from 'firebase-functions/v2/https';

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

function extractThumb(html: string): string | null {
  const mOg = html.match(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i);
  if (mOg && mOg[1]) return mOg[1];
  const mTw = html.match(/<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']+)["']/i);
  if (mTw && mTw[1]) return mTw[1];
  return null;
}

export const xThumb = onRequest({ cors: true, region: 'us-central1', timeoutSeconds: 20 }, async (req, res) => {
  try {
    const url = (req.query.url as string || '').trim();
    if (!url) {
      res.status(400).json({ error: 'missing url' });
      return;
    }
    // 1) Versuche direkt die Statusseite
    try {
      const html = await fetchText(url);
      const t = extractThumb(html);
      if (t) {
        res.status(200).json({ thumb: t });
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
          res.status(200).json({ thumb: mImg[1] });
          return;
        }
      }
    } catch {}
    res.status(404).json({ error: 'thumb not found' });
  } catch (e: any) {
    res.status(500).json({ error: e?.message || 'internal error' });
  }
});


