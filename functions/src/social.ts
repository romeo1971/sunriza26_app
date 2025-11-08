import * as admin from 'firebase-admin';
import { onCall, onRequest } from 'firebase-functions/v2/https';
import fetch from 'node-fetch';

if (!admin.apps.length) {
  try { admin.initializeApp(); } catch {}
}

type IgMedia = {
  id: string;
  caption?: string;
  media_type: 'IMAGE' | 'VIDEO' | 'CAROUSEL_ALBUM' | string;
  media_url: string;
  permalink: string;
  timestamp: string;
};

/**
 * Callable: instagramFeed
 * data: { avatarId: string }
 * Rückgabe: { posts: IgMedia[], fromCache: boolean }
 *
 * Erwartet, dass unter avatars/{avatarId}/social_accounts ein Eintrag mit providerName='Instagram'
 * und Feldern { connected: true, ig_user_id, access_token } existiert.
 * Cacht Ergebnis 10 Minuten in avatars/{avatarId}/social_cache/instagram.
 */
export const instagramFeed = onCall(
  {
    region: 'us-central1',
    timeoutSeconds: 20,
  },
  async (request) => {
    const avatarId = (request.data?.avatarId as string | undefined)?.trim();
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
        const ageMs = Date.now() - (doc.fetchedAt as number);
        if (ageMs <= 10 * 60 * 1000) {
          return { posts: doc.posts, fromCache: true };
        }
      }
    } catch {}

    // 2) Social Account lesen
    let token: string | undefined;
    let igUserId: string | undefined;
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
        const m = qs.docs[0].data() as any;
        token = (m['access_token'] as string) || (m['igLongLivedAccessToken'] as string);
        igUserId = (m['ig_user_id'] as string) || (m['igUserId'] as string);
      }
    } catch {}

    if (!token && !igUserId) {
      return { posts: [], fromCache: false, error: 'not_connected' };
    }

    // 3) Graph API: letzte 5 Medien (Business via ig_user_id) oder Basic Display via /me/media
    try {
      let posts: IgMedia[] = [];
      if (igUserId && token) {
        const url = new URL(`https://graph.facebook.com/v17.0/${igUserId}/media`);
        url.searchParams.set('fields', 'id,caption,media_type,media_url,permalink,timestamp');
        url.searchParams.set('limit', '5');
        url.searchParams.set('access_token', token);
        const resp = await fetch(url.toString());
        if (!resp.ok) {
          const text = await resp.text();
          throw new Error(`IG request failed: ${resp.status} ${text}`);
        }
        const json = (await resp.json()) as { data?: IgMedia[] };
        posts = (json.data ?? []).slice(0, 5);
      } else if (token) {
        // Basic Display fallback
        const url = new URL('https://graph.instagram.com/me/media');
        url.searchParams.set('fields', 'id,caption,media_type,media_url,permalink,timestamp');
        url.searchParams.set('limit', '5');
        url.searchParams.set('access_token', token);
        const resp = await fetch(url.toString());
        if (!resp.ok) {
          const text = await resp.text();
          throw new Error(`IG Basic request failed: ${resp.status} ${text}`);
        }
        const json = (await resp.json()) as { data?: IgMedia[] };
        posts = (json.data ?? []).slice(0, 5);
      }
      // Keine Posts
      if (!posts || posts.length === 0) {
        return { posts: [], fromCache: false, error: 'no_posts' };
      }
      // 4) Cache speichern
      try {
        await cacheRef.set(
          {
            posts,
            fetchedAt: Date.now(),
          },
          { merge: true }
        );
      } catch {}
      return { posts, fromCache: false };
    } catch (e: any) {
      return { posts: [], fromCache: false, error: e?.message ?? 'unknown' };
    }
  }
);

/**
 * HTML-Embed-Seite für Social Feeds.
 * GET /socialEmbedPage?provider=instagram&avatarId=...
 * Rendert die letzten 5 Posts als simples Grid (ohne Login-Wall).
 */
export const socialEmbedPage = onRequest(
  { region: 'us-central1', timeoutSeconds: 20 },
  async (req, res) => {
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    const provider = String(req.query.provider || '').toLowerCase();
    const avatarId = String(req.query.avatarId || '');
    if (!provider || !avatarId) {
      res.status(400).send('<html><body><p>Bad request</p></body></html>');
      return;
    }
    // Reuse logic per provider
    const db = admin.firestore();
    let posts: IgMedia[] = [];
    if (provider === 'instagram') {
      const cacheRef = db.collection('avatars').doc(avatarId).collection('social_cache').doc('instagram');
      try {
        const snap = await cacheRef.get();
        const doc = snap.data();
        if (doc && doc.posts && doc.fetchedAt && Date.now() - (doc.fetchedAt as number) <= 10 * 60 * 1000) {
          posts = (doc.posts as IgMedia[]).slice(0, 5);
        }
      } catch {}
      if (posts.length === 0) {
        // Load tokens
        let token: string | undefined;
        let igUserId: string | undefined;
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
            const m = qs.docs[0].data() as any;
            token = (m['access_token'] as string) || (m['igLongLivedAccessToken'] as string);
            igUserId = (m['ig_user_id'] as string) || (m['igUserId'] as string);
          }
        } catch {}
        if (token && igUserId) {
          try {
            const url = new URL(`https://graph.facebook.com/v17.0/${igUserId}/media`);
            url.searchParams.set('fields', 'id,caption,media_type,media_url,permalink,timestamp');
            url.searchParams.set('limit', '5');
            url.searchParams.set('access_token', token);
            const resp = await fetch(url.toString());
            if (resp.ok) {
              const json = (await resp.json()) as { data?: IgMedia[] };
              posts = (json.data ?? []).slice(0, 5);
              try {
                await cacheRef.set({ posts, fetchedAt: Date.now() }, { merge: true });
              } catch {}
            }
          } catch {}
        }
      }
    } else if (provider === 'facebook') {
      const cacheRef = db.collection('avatars').doc(avatarId).collection('social_cache').doc('facebook');
      try {
        const snap = await cacheRef.get();
        const doc = snap.data();
        if (doc && doc.posts && doc.fetchedAt && Date.now() - (doc.fetchedAt as number) <= 10 * 60 * 1000) {
          posts = (doc.posts as IgMedia[]).slice(0, 5);
        }
      } catch {}
      if (posts.length === 0) {
        let pageToken: string | undefined;
        let pageId: string | undefined;
        try {
          const doc = await db
            .collection('avatars')
            .doc(avatarId)
            .collection('social_accounts')
            .doc('facebook')
            .get();
          const m = doc.data() as any;
          pageToken = m?.page_access_token;
          pageId = m?.page_id;
        } catch {}
        if (pageToken && pageId) {
          try {
            const url = new URL(`https://graph.facebook.com/v17.0/${pageId}/posts`);
            url.searchParams.set('fields', 'id,full_picture,permalink_url,message,created_time');
            url.searchParams.set('limit', '5');
            url.searchParams.set('access_token', pageToken);
            const resp = await fetch(url.toString());
            if (resp.ok) {
              const json = (await resp.json()) as any;
              posts = (json.data ?? []).map((p: any) => ({
                id: p.id,
                caption: p.message,
                media_type: 'IMAGE',
                media_url: p.full_picture || '',
                permalink: p.permalink_url,
                timestamp: p.created_time,
              })).filter((p: IgMedia) => p.media_url).slice(0, 5);
              try {
                await cacheRef.set({ posts, fetchedAt: Date.now() }, { merge: true });
              } catch {}
            }
          } catch {}
        }
      }
    } else {
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
  }
);


