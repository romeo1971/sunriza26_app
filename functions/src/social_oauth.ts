import * as admin from 'firebase-admin';
import { onRequest } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import fetch from 'node-fetch';

if (!admin.apps.length) {
  try { admin.initializeApp(); } catch {}
}

// Secrets (setze via: firebase functions:secrets:set IG_APP_ID / IG_APP_SECRET / IG_REDIRECT_URI)
const IG_APP_ID = defineSecret('IG_APP_ID');
const IG_APP_SECRET = defineSecret('IG_APP_SECRET');
const IG_REDIRECT_URI = defineSecret('IG_REDIRECT_URI'); // e.g. https://us-central1-sunriza26.cloudfunctions.net/igCallback

/**
 * GET /igConnect?avatarId=...
 * Redirect zu Meta OAuth (Basic Display/Graph scopes minimal)
 */
export const igConnect = onRequest({ region: 'us-central1', secrets: [IG_APP_ID, IG_REDIRECT_URI] }, async (req, res) => {
  const avatarId = String(req.query.avatarId || '').trim();
  const appId = IG_APP_ID.value();
  const redirect = IG_REDIRECT_URI.value();
  if (!avatarId || !appId || !redirect) {
    res.status(400).send('Bad request');
    return;
  }
  const state = encodeURIComponent(avatarId);
  const scopes = [
    'instagram_basic',
    'instagram_graph_user_media',
  ].join(',');
  const url = new URL('https://www.facebook.com/v17.0/dialog/oauth');
  url.searchParams.set('client_id', appId);
  url.searchParams.set('redirect_uri', redirect);
  url.searchParams.set('scope', scopes);
  url.searchParams.set('response_type', 'code');
  url.searchParams.set('state', state);
  res.redirect(url.toString());
});

/**
 * GET /igCallback?code=...&state=avatarId
 * Tauscht Code gegen Token, versucht Long-Lived Token, speichert unter avatars/{avatarId}/social_accounts
 */
export const igCallback = onRequest({ region: 'us-central1', secrets: [IG_APP_ID, IG_APP_SECRET, IG_REDIRECT_URI] }, async (req, res) => {
  try {
    const code = String(req.query.code || '').trim();
    const avatarId = String(req.query.state || '').trim();
    const appId = IG_APP_ID.value();
    const appSecret = IG_APP_SECRET.value();
    const redirect = IG_REDIRECT_URI.value();
    if (!code || !avatarId || !appId || !appSecret || !redirect) {
      res.status(400).send('Bad request');
      return;
    }
    // 1) Short-lived access token
    const tokenUrl = new URL('https://graph.facebook.com/v17.0/oauth/access_token');
    tokenUrl.searchParams.set('client_id', appId);
    tokenUrl.searchParams.set('client_secret', appSecret);
    tokenUrl.searchParams.set('redirect_uri', redirect);
    tokenUrl.searchParams.set('code', code);
    const tokResp = await fetch(tokenUrl.toString());
    if (!tokResp.ok) {
      const text = await tokResp.text();
      res.status(500).send(`OAuth exchange failed: ${text}`);
      return;
    }
    const shortJson = await tokResp.json() as any;
    const shortToken = shortJson.access_token as string;

    // 2) Try long-lived (Basic Display)
    let longToken = shortToken;
    try {
      const llUrl = new URL('https://graph.instagram.com/access_token');
      llUrl.searchParams.set('grant_type', 'ig_exchange_token');
      llUrl.searchParams.set('client_secret', appSecret);
      llUrl.searchParams.set('access_token', shortToken);
      const llResp = await fetch(llUrl.toString());
      if (llResp.ok) {
        const llJson = await llResp.json() as any;
        longToken = llJson.access_token || longToken;
      }
    } catch {}

    // 3) Try to get user info (Basic Display)
    let igBasicUser: any = undefined;
    try {
      const meUrl = new URL('https://graph.instagram.com/me');
      meUrl.searchParams.set('fields', 'id,username');
      meUrl.searchParams.set('access_token', longToken);
      const meResp = await fetch(meUrl.toString());
      if (meResp.ok) igBasicUser = await meResp.json();
    } catch {}

    const docData: any = {
      providerName: 'Instagram',
      connected: true,
      access_token: longToken,
      updatedAt: Date.now(),
    };
    if (igBasicUser?.id) {
      docData.ig_user_id = String(igBasicUser.id);
      docData.ig_username = igBasicUser.username;
    }

    await admin.firestore()
      .collection('avatars').doc(avatarId)
      .collection('social_accounts').doc('instagram')
      .set(docData, { merge: true });

    res.status(200).send('Instagram verbunden. Du kannst dieses Fenster schließen.');
  } catch (e: any) {
    res.status(500).send(`Error: ${e?.message || 'unknown'}`);
  }
});


