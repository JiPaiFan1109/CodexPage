import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, writeFile, rm, readdir, mkdir } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import { startVideoServer, parseSingleRange } from '../engine/scripts/video-server.mjs';

async function fixture(t) {
  const root = await mkdtemp(path.join(os.tmpdir(), 'skin-video-server-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const bytes = Buffer.alloc(1024 * 1024, 7);
  const filePath = path.join(root, 'video.mp4');
  await writeFile(filePath, bytes);
  const server = await startVideoServer({ filePath, expectedSize: bytes.length,
    expectedSha256: createHash('sha256').update(bytes).digest('hex') });
  t.after(() => server.close());
  return { server, bytes, filePath };
}

test('range boundaries reject invalid and unsafe numbers', () => {
  for (const header of ['bytes=', 'bytes=-0', 'bytes=10-9', 'bytes=100-',
    'bytes=0-1,3-4', 'bytes=9007199254740992-', 'items=0-1']) {
    assert.equal(parseSingleRange(header, 100), null, header);
  }
  assert.deepEqual(parseSingleRange('bytes=-200', 100), { start: 0, end: 99 });
  assert.deepEqual(parseSingleRange('bytes=99-999', 100), { start: 99, end: 99 });
});

test('loopback server serves exact bytes, HEAD, ranges and rejects invalid requests', async t => {
  const { server, bytes } = await fixture(t);
  const response = await fetch(server.url);
  assert.deepEqual(Buffer.from(await response.arrayBuffer()), bytes);
  const head = await fetch(server.url, { method: 'HEAD' });
  assert.equal(head.headers.get('content-length'), String(bytes.length));
  assert.equal((await head.arrayBuffer()).byteLength, 0);
  const partial = await fetch(server.url, { headers: { Range: 'bytes=10-19' } });
  assert.equal(partial.status, 206);
  assert.deepEqual(Buffer.from(await partial.arrayBuffer()), bytes.subarray(10, 20));
  for (const [url, options, status] of [
    [server.url + '?extra=1', {}, 404],
    [server.url, { method: 'POST' }, 405],
    [server.url, { headers: { Range: 'bytes=999999999-' } }, 416],
  ]) {
    const result = await fetch(url, options);
    assert.equal(result.status, status);
    await result.arrayBuffer();
  }
});

test('malformed URL returns 400 and the server remains usable', async t => {
  const { server } = await fixture(t);
  const status = await new Promise((resolve, reject) => {
    const request = http.request({ hostname: '127.0.0.1', port: server.address.port,
      path: 'http://[invalid', method: 'GET' }, response => {
      response.resume(); response.on('end', () => resolve(response.statusCode));
    });
    request.on('error', reject); request.end();
  });
  assert.equal(status, 400);
  const response = await fetch(server.playerUrl);
  assert.equal(response.status, 200);
  await response.arrayBuffer();
});

test('missing video closes the request without crashing the server', async t => {
  const { server, filePath } = await fixture(t);
  await rm(filePath);
  for (const options of [{}, { headers: { Range: 'bytes=0-9' } }]) {
    await assert.rejects(async () => {
      const response = await fetch(server.url, options);
      await response.arrayBuffer();
    });
  }
  const response = await fetch(server.playerUrl);
  assert.equal(response.status, 200);
  await response.arrayBuffer();
});

test('cancelled video requests leave the service available', async t => {
  const { server } = await fixture(t);
  for (let index = 0; index < 20; index++) {
    const response = await fetch(server.url);
    await response.body.cancel();
  }
  const response = await fetch(server.url, { headers: { Range: 'bytes=0-9' } });
  assert.equal((await response.arrayBuffer()).byteLength, 10);
});

test('CLI exits and removes temporary readiness files when readiness commit fails', async t => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'skin-video-ready-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const bytes = Buffer.from('isolated fixture');
  const filePath = path.join(root, 'video.mp4');
  const configPath = path.join(root, 'config.json');
  const readyPath = path.join(root, 'ready.json');
  await writeFile(filePath, bytes);
  await writeFile(configPath, JSON.stringify({ filePath, expectedSize: bytes.length,
    expectedSha256: createHash('sha256').update(bytes).digest('hex') }));
  // An existing directory makes rename fail after listening and writing the temp file.
  await mkdir(readyPath);
  const child = spawn(process.execPath, [fileURLToPath(new URL('../engine/scripts/video-server.mjs', import.meta.url)),
    '--config', configPath, '--ready', readyPath], { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
  let stderr = '', stdout = '', forced = false;
  child.stderr.on('data', chunk => { stderr += chunk; });
  child.stdout.on('data', chunk => { stdout += chunk; });
  const timeout = setTimeout(() => { forced = true; child.kill(); }, 5000);
  t.after(() => { clearTimeout(timeout); if (child.exitCode === null) child.kill(); });
  const exitCode = await new Promise((resolve, reject) => {
    child.once('error', reject); child.once('close', resolve);
  });
  clearTimeout(timeout);
  assert.equal(forced, false, 'failed startup left the HTTP listener/process alive');
  assert.equal(exitCode, 1);
  assert.match(stderr, /Video server failed/);
  assert.equal(stdout, '');
  assert.deepEqual((await readdir(root)).filter(name => name.startsWith('ready.json.tmp-')), []);
});
