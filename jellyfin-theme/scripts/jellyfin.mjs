import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';

export async function connect(env = process.env) {
  const base = new URL(env.ALPHANE_SERVER || 'http://127.0.0.1:8096');
  if (!['http:', 'https:'].includes(base.protocol) || base.username || base.password) throw new Error('Use an HTTP(S) server URL without embedded credentials.');
  let token = env.ALPHANE_API_KEY_FILE ? (await readFile(env.ALPHANE_API_KEY_FILE, 'utf8')).trim() : '';
  const apiKey = Boolean(token);
  async function request(route, method = 'GET', payload, json = true) {
    const response = await fetch(base.href.replace(/\/$/, '') + route, {
      method, signal: AbortSignal.timeout(30000), redirect: 'error',
      headers: { Authorization: token ? `MediaBrowser Token="${token}"` : `MediaBrowser Client="Alphane theme", Device="Theme maintenance", DeviceId="${randomUUID()}", Version="1.0"`, ...(payload === undefined ? {} : { 'Content-Type': 'application/json' }) },
      body: payload === undefined ? undefined : JSON.stringify(payload)
    });
    if (!response.ok) throw new Error(`Jellyfin ${method} ${route.split('?')[0]} returned HTTP ${response.status}.`);
    const text = await response.text();
    return json ? (text ? JSON.parse(text) : null) : text;
  }
  if (!token) {
    const password = env.ALPHANE_PASSWORD_FILE ? (await readFile(env.ALPHANE_PASSWORD_FILE, 'utf8')).replace(/\r?\n$/, '') : env.ALPHANE_PASSWORD;
    if (!env.ALPHANE_USERNAME || !password) throw new Error('Set ALPHANE_USERNAME and ALPHANE_PASSWORD_FILE (or ALPHANE_PASSWORD), or ALPHANE_API_KEY_FILE.');
    const auth = await request('/Users/AuthenticateByName', 'POST', { Username: env.ALPHANE_USERNAME, Pw: password });
    token = auth.AccessToken;
    if (!token) throw new Error('Jellyfin did not return an authentication token.');
  }
  return { request, close: async () => { if (!apiKey && token) { try { await request('/Sessions/Logout', 'POST'); } finally { token = ''; } } } };
}
