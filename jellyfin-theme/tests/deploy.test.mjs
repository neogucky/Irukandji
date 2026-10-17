import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { once } from 'node:events';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { deploy } from '../scripts/deploy.mjs';

test('deployment and rollback preserve unrelated branding and never store credentials', async () => {
  const directory = await mkdtemp(path.join(tmpdir(), 'alphane-theme-test-'));
  const original = { CustomCss: '/* previous theme */', LoginDisclaimer: 'Existing disclaimer', SplashscreenEnabled: false };
  let branding = { ...original }, logouts = 0;
  const server = http.createServer(async (request, response) => {
    const chunks = [];for await (const chunk of request) chunks.push(chunk);
    const body = chunks.length ? JSON.parse(Buffer.concat(chunks)) : null;
    response.setHeader('Content-Type', 'application/json');
    if (request.url === '/Users/AuthenticateByName') response.end(JSON.stringify({ AccessToken: 'fixture-token' }));
    else if (request.url === '/Sessions/Logout') { logouts++;response.end(); }
    else if (request.url === '/Branding/Configuration') response.end(JSON.stringify(branding));
    else if (request.url === '/System/Configuration/branding') { branding = body;response.end(); }
    else { response.statusCode = 404;response.end(); }
  });
  server.listen(0, '127.0.0.1');await once(server, 'listening');
  const env = { ALPHANE_SERVER: `http://127.0.0.1:${server.address().port}`, ALPHANE_USERNAME: 'fixture', ALPHANE_PASSWORD: 'fixture-password', ALPHANE_STATE_DIR: directory };
  try {
    const applied = await deploy('apply', null, env);
    assert.equal(applied.verified, true);assert.match(branding.CustomCss, /Alphane Jellyfin Web theme/);
    assert.equal(branding.LoginDisclaimer, original.LoginDisclaimer);assert.equal(branding.SplashscreenEnabled, false);
    const backup = await readFile(applied.backup, 'utf8');
    assert.doesNotMatch(backup, /fixture-password|fixture-token/);
    await deploy('rollback', applied.backup, env);
    assert.deepEqual(branding, original);assert.equal(logouts, 2);
  } finally {
    server.closeAllConnections();await new Promise(resolve => server.close(resolve));
    assert.equal(path.dirname(path.resolve(directory)), path.resolve(tmpdir()));
    assert.ok(path.basename(directory).startsWith('alphane-theme-test-'));
    await rm(directory, { recursive: true, force: true });
  }
});
