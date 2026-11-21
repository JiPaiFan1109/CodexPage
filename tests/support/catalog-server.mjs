// A local stand-in for the CodexPage cloud catalog routes (GET /v1/catalog and
// GET /v1/parts/<sha>/<n>) used by the Windows cloud wallpaper tests.
//   node catalog-server.mjs <dir> <ready-file>
// <dir>/catalog.json is returned as the catalog response, <dir>/blobs/<sha> are
// served as 2 MiB parts, and every request is appended to <dir>/requests.log.
// When <dir>/corrupt exists, the first byte of every part is flipped. <dir>/delay may
// hold a per-part delay in milliseconds (used to show progress in previews).
import { createServer } from 'node:http';
import { readFile, appendFile, writeFile, access } from 'node:fs/promises';
import path from 'node:path';

const [dir, ready] = process.argv.slice(2);
const CHUNK = 2 * 1024 * 1024;
const exists = file => access(file).then(() => true, () => false);

const server = createServer(async (request, response) => {
  await appendFile(path.join(dir, 'requests.log'), request.url + '\n');
  try {
    if (request.url === '/v1/catalog') {
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(await readFile(path.join(dir, 'catalog.json')));
      return;
    }
    const match = /^\/v1\/parts\/([a-f0-9]{64})\/(\d{1,4})$/.exec(request.url);
    if (match) {
      const bytes = await readFile(path.join(dir, 'blobs', match[1]));
      const index = Number(match[2]);
      const part = Buffer.from(bytes.subarray(index * CHUNK, Math.min(bytes.length, (index + 1) * CHUNK)));
      if (!part.length) { response.writeHead(404).end(); return; }
      if (await exists(path.join(dir, 'corrupt'))) part[0] ^= 0xff;
      const delay = Number(await readFile(path.join(dir, 'delay'), 'utf8').catch(() => '0'));
      if (delay > 0) await new Promise(resolve => setTimeout(resolve, Math.min(delay, 5000)));
      response.writeHead(200, { 'content-type': 'application/octet-stream', 'content-length': String(part.length) });
      response.end(part);
      return;
    }
    response.writeHead(404).end();
  } catch {
    response.writeHead(404).end();
  }
});
server.listen(0, '127.0.0.1', async () => {
  await writeFile(ready, String(server.address().port));
});
