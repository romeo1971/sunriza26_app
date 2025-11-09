import * as admin from 'firebase-admin';
import { onRequest } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import fetch from 'node-fetch';

if (!admin.apps.length) {
  try { admin.initializeApp(); } catch {}
}

const IG_APP_ID = defineSecret('IG_APP_ID');
const IG_REDIRECT_URI = defineSecret('IG_REDIRECT_URI'); // wir verwenden die gleiche Redirect-URL

/**
 * GET /fbConnect?avatarId=...
 * Fordert Pages-Scopes an und leitet zu OAuth.
 */
export const fbConnect = onRequest({ region: 'us-central1', secrets: [IG_APP_ID, IG_REDIRECT_URI] }, async (req, res) => {
  const avatarId = String(req.query.avatarId || '').trim();
  const appId = IG_APP_ID.value();
  const redirect = IG_REDIRECT_URI.value(); // nutzen gleiche Callback
  if (!avatarId || !appId || !redirect) {
    res.status(400).send('Bad request');
    return;
  }
  const scopes = ['pages_show_list', 'pages_read_engagement', 'public_profile'].join(',');
  const url = new URL('https://www.facebook.com/v17.0/dialog/oauth');
  url.searchParams.set('client_id', appId);
  url.searchParams.set('redirect_uri', redirect);
  url.searchParams.set('scope', scopes);
  url.searchParams.set('response_type', 'code');
  url.searchParams.set('state', encodeURIComponent(`fb:${avatarId}`)); // Präfix, um im Callback zu unterscheiden
  res.redirect(url.toString());
});

/**
 * Hilfsfunktion: verarbeitet im gemeinsamen igCallback-State den "fb:"-Fall.
 * Wird aus igCallback intern NICHT automatisch aufgerufen; wir belassen fbConnect separat.
 * Diese Utility-Funktion steht optional bereit, falls du später bündeln möchtest.
 */
export async function handleFacebookTokenExchange({
  userAccessToken,
  avatarId,
}: {
  userAccessToken: string;
  avatarId: string;
}) {
  const db = admin.firestore();
  // Hole die erste Page und Page-Token
  const mePagesUrl = new URL('https://graph.facebook.com/v17.0/me/accounts');
  mePagesUrl.searchParams.set('access_token', userAccessToken);
  const pagesResp = await fetch(mePagesUrl.toString());
  if (!pagesResp.ok) {
    throw new Error(`pages list failed: ${await pagesResp.text()}`);
  }
  const pagesJson = (await pagesResp.json()) as any;
  const first = pagesJson?.data?.[0];
  if (!first?.id || !first?.access_token) {
    throw new Error('no_page_available');
  }
  await db
    .collection('avatars')
    .doc(avatarId)
    .collection('social_accounts')
    .doc('facebook')
    .set(
      {
        providerName: 'Facebook',
        connected: true,
        page_id: String(first.id),
        page_access_token: String(first.access_token),
        updatedAt: Date.now(),
      },
      { merge: true }
    );

  // Prefetch: letzte 10 Page-Posts cachen
  try {
    const postsUrl = new URL(`https://graph.facebook.com/v17.0/${first.id}/posts`);
    postsUrl.searchParams.set('fields', 'id,full_picture,permalink_url,message,created_time');
    postsUrl.searchParams.set('limit', '10');
    postsUrl.searchParams.set('access_token', String(first.access_token));
    const r = await fetch(postsUrl.toString());
    if (r.ok) {
      const j = await r.json() as any;
      const posts = (j?.data ?? [])
        .map((p: any) => ({
          id: p.id,
          caption: p.message,
          media_type: 'IMAGE',
          media_url: p.full_picture || '',
          permalink: p.permalink_url,
          timestamp: p.created_time,
        }))
        .filter((p: any) => p.media_url)
        .slice(0, 10);
      await db
        .collection('avatars').doc(avatarId)
        .collection('social_cache').doc('facebook')
        .set({ posts, fetchedAt: Date.now() }, { merge: true });
    }
  } catch {}
}


