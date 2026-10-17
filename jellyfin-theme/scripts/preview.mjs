import http from 'node:http';
import path from 'node:path';
import { readFile } from 'node:fs/promises';
import { root, compile } from './build.mjs';

const port = Number(process.env.PORT || 4179);
const server = http.createServer(async (request, response) => {
  try {
    const url = new URL(request.url, 'http://127.0.0.1');
    let body, type;
    if (url.pathname === '/dist/alphane.css') { body = await compile(); type = 'text/css'; }
    else if (url.pathname === '/' || url.pathname === '/fixture') { body = await readFile(path.join(root, 'tests/fixtures/showcase.html')); type = 'text/html'; }
    else if (/^\/art\/[a-z0-9-]+\.png$/.test(url.pathname)) { body = await readFile(path.join(root, '../readme/preview_video_mocks/covers', path.basename(url.pathname))); type = 'image/png'; }
    else { response.writeHead(404); response.end(); return; }
    response.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' }); response.end(body);
  } catch { response.writeHead(404); response.end(); }
});
server.listen(port, '127.0.0.1', () => console.log(`Alphane theme preview: http://127.0.0.1:${port}`));
