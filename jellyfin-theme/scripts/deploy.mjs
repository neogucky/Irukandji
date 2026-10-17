import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { root, compile } from './build.mjs';
import { connect } from './jellyfin.mjs';

export const hash = value => createHash('sha256').update(value || '').digest('hex');

export async function deploy(command, backupFile, env = process.env) {
  if (!['apply', 'rollback', 'status'].includes(command)) throw new Error('Use apply, status, or rollback <backup.json>.');
  const css = command === 'apply' ? await readFile(path.join(root, 'dist/alphane.css'), 'utf8') : null;
  if (css !== null && css !== await compile()) throw new Error('The compiled stylesheet is out of date. Run npm run build first.');
  const client = await connect(env);
  try {
    const before = await client.request('/Branding/Configuration');
    if (command === 'status') return { cssBytes: Buffer.byteLength(before.CustomCss || ''), sha256: hash(before.CustomCss) };
    const restored = command === 'rollback' ? JSON.parse(await readFile(backupFile || '', 'utf8')) : null;
    if (restored && (restored.schema !== 1 || typeof restored.branding?.CustomCss !== 'string' || restored.sha256 !== hash(restored.branding.CustomCss))) throw new Error('Not a verified Alphane theme backup.');
    const state = env.ALPHANE_STATE_DIR || path.join(root, '.private');
    const directory = path.join(state, 'backups'); await mkdir(directory, { recursive: true, mode: 0o700 });
    const backup = path.join(directory, `branding-${Date.now()}.json`);
    const branding = { ...before, CustomCss: before.CustomCss || '' };
    await writeFile(backup, JSON.stringify({ schema: 1, savedAt: new Date().toISOString(), sha256: hash(branding.CustomCss), branding }, null, 2), { flag: 'wx', mode: 0o600 });
    const targetCss = restored ? restored.branding.CustomCss : css;
    // Change only CSS; retain the server's current disclaimer/splash options.
    await client.request('/System/Configuration/branding', 'POST', { ...before, CustomCss: targetCss });
    const after = await client.request('/Branding/Configuration');
    if (after.CustomCss !== targetCss) throw new Error(`CSS verification failed; restore from ${backup}.`);
    await writeFile(path.join(state, 'last-deployment.json'), JSON.stringify({ command, backup, sha256: hash(targetCss), appliedAt: new Date().toISOString() }, null, 2), { mode: 0o600 });
    return { command, backup, cssBytes: Buffer.byteLength(targetCss), sha256: hash(targetCss), verified: true };
  } finally { await client.close(); }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { console.log(JSON.stringify(await deploy(process.argv[2], process.argv[3]), null, 2)); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
