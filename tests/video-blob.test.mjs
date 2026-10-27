import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { createHash } from 'node:crypto';
import { installVideoBlob } from '../engine/scripts/video-blob.mjs';

let fixtureIndex = 0;
function fixture(bytes = Buffer.alloc(700000, 9)) {
  const token = (++fixtureIndex).toString(16).padStart(64, '0');
  return { bytes, config: { url: `http://127.0.0.1:49152/${token}/video.mp4`,
    fileSize: bytes.length, fileSha256: createHash('sha256').update(bytes).digest('hex') } };
}
function sessionFixture() {
  const revoked = [], blobs = [], attached = [];
  const state = { installToken: 'installation-1', attachVideoBlob(url) { attached.push(url); } };
  const window = { __CODEX_DREAM_SKIN_STATE__: state, __CODEX_DREAM_SKIN_DISABLED__: false };
  const context = vm.createContext({ window, Blob, Uint8Array, atob, URL: {
    createObjectURL(blob) { blobs.push(blob); return `blob:fixture-${blobs.length}`; },
    revokeObjectURL(url) { revoked.push(url); },
  } });
  const session = { async evaluate(expression) { return vm.runInContext(expression, context); } };
  return { state, window, session, revoked, blobs, attached, context };
}
function mockFetch(t, bytes, check = () => {}) {
  let calls = 0;
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    calls++; check(url, options);
    return new Response(bytes, { headers: { 'content-length': String(bytes.length) } });
  });
  return () => calls;
}

test('uploads exact bytes as MP4 and avoids duplicate upload and fetch', async t => {
  const { bytes, config } = fixture();
  const calls = mockFetch(t, bytes, (url, options) => {
    assert.equal(url, config.url); assert.equal(options.redirect, 'error'); assert.ok(options.signal);
  });
  const f = sessionFixture();
  await installVideoBlob(f.session, config);
  assert.equal(f.blobs.length, 1); assert.equal(f.blobs[0].type, 'video/mp4');
  assert.deepEqual(Buffer.from(await f.blobs[0].arrayBuffer()), bytes);
  assert.equal(f.state.videoBlobUrl, 'blob:fixture-1');
  assert.ok(f.state.videoBlobKey); assert.equal(f.state.videoUpload, undefined);
  await installVideoBlob(f.session, config);
  assert.equal(f.blobs.length, 1); assert.equal(calls(), 1); assert.equal(f.attached.length, 1);
});
test('rejects SHA mismatch without attaching media', async t => {
  const { bytes, config } = fixture(); config.fileSha256 = '0'.repeat(64);
  mockFetch(t, bytes); const f = sessionFixture();
  await assert.rejects(installVideoBlob(f.session, config), /SHA|hash/i);
  assert.equal(f.blobs.length, 0); assert.equal(f.state.videoUpload, undefined);
});

test('Steam reference playback never opens the persistent video cache', async t => {
  const { bytes, config } = fixture(); config.persistentCache = false;
  mockFetch(t, bytes);
  const f = sessionFixture();
  let cacheReads = 0;
  Object.defineProperty(f.context, 'caches', {get(){cacheReads++; throw Error('Persistent cache is forbidden');}});
  const original = f.session.evaluate;
  f.session.evaluate = async expression => {
    assert.ok(!expression.startsWith('(async function restoreVideoCache'), 'must not attempt cache restore');
    return original(expression);
  };
  await installVideoBlob(f.session, config);
  assert.equal(f.attached.length, 1);
  assert.equal(cacheReads, 0);
});

test('concurrent windows share one verified download and attach independently', async t => {
  const { bytes, config } = fixture();
  const calls = mockFetch(t, bytes);
  const windows = Array.from({ length: 8 }, sessionFixture);
  await Promise.all(windows.map(f => installVideoBlob(f.session, config)));
  assert.equal(calls(), 1);
  for (const f of windows) {
    assert.equal(f.attached.length, 1);
    assert.deepEqual(Buffer.from(await f.blobs[0].arrayBuffer()), bytes);
    assert.equal(f.state.videoUpload, undefined);
  }
});

test('failed shared download is cleared so a later attempt can recover', async t => {
  const { bytes, config } = fixture();
  let calls = 0;
  t.mock.method(globalThis, 'fetch', async () => {
    calls++;
    if (calls === 1) throw Error('temporary network failure');
    return new Response(bytes);
  });
  const windows = [sessionFixture(), sessionFixture()];
  const results = await Promise.allSettled(windows.map(f => installVideoBlob(f.session, config)));
  assert.ok(results.every(result => result.status === 'rejected'));
  assert.equal(calls, 1);
  await installVideoBlob(windows[0].session, config);
  assert.equal(calls, 2);
  assert.equal(windows[0].attached.length, 1);
});
test('rejects invalid endpoint and oversized media before fetch', async t => {
  let calls = 0; t.mock.method(globalThis, 'fetch', async () => { calls++; throw Error('unexpected'); });
  const { config } = fixture(); const f = sessionFixture();
  for (const url of ['http://localhost:49152/a/video.mp4', config.url + '?x=1', config.url.replace('127.0.0.1', 'example.com')]) {
    await assert.rejects(installVideoBlob(f.session, { ...config, url }));
  }
  await assert.rejects(installVideoBlob(f.session, { ...config, fileSize: 129 * 1024 * 1024 }));
  assert.equal(calls, 0);
});
test('pause during chunk upload cancels and clears partial bytes', async t => {
  const { bytes, config } = fixture(); mockFetch(t, bytes); const f = sessionFixture();
  const evaluate = f.session.evaluate;
  f.session.evaluate = async expression => {
    const result = await evaluate(expression);
    if (f.state.videoUpload?.chunks?.length) f.window.__CODEX_DREAM_SKIN_DISABLED__ = true;
    return result;
  };
  await assert.rejects(installVideoBlob(f.session, config), /cancel|changed|inactive/i);
  assert.equal(f.blobs.length, 0); assert.equal(f.state.videoUpload, undefined);
});
test('attachment failure revokes newly created Blob and clears state', async t => {
  const { bytes, config } = fixture(); mockFetch(t, bytes); const f = sessionFixture();
  f.state.attachVideoBlob = () => { throw Error('attach failed'); };
  await assert.rejects(installVideoBlob(f.session, config), /attach failed/);
  assert.deepEqual(f.revoked, ['blob:fixture-1']);
  assert.equal(f.state.videoUpload, undefined); assert.equal(f.state.videoBlobUrl, undefined);
});

test('attachment refusal preserves previous media and rejects the upload', async t => {
  const { bytes, config } = fixture(); mockFetch(t, bytes); const f = sessionFixture();
  f.state.videoBlobUrl = 'blob:previous';
  f.state.videoBlobKey = 'previous-key';
  f.state.attachVideoBlob = () => false;
  await assert.rejects(installVideoBlob(f.session, config), /cancel|refus/i);
  assert.deepEqual(f.revoked, ['blob:fixture-1']);
  assert.equal(f.state.videoBlobUrl, 'blob:previous');
  assert.equal(f.state.videoBlobKey, 'previous-key');
  assert.equal(f.state.videoUpload, undefined);
});
test('navigation during transfer never attaches to replacement runtime', async t => {
  const { bytes, config } = fixture(); mockFetch(t, bytes); const f = sessionFixture();
  const evaluate = f.session.evaluate;
  f.session.evaluate = async expression => {
    const result = await evaluate(expression);
    if (f.state.videoUpload?.chunks?.length) {
      f.window.__CODEX_DREAM_SKIN_STATE__ = { installToken: 'replacement', attachVideoBlob() { throw Error('wrong runtime'); } };
    }
    return result;
  };
  await assert.rejects(installVideoBlob(f.session, config), /cancel|changed|inactive/i);
  assert.equal(f.blobs.length, 0);
  assert.equal(f.window.__CODEX_DREAM_SKIN_STATE__.videoUpload, undefined);
});
test('size mismatch fails before renderer transfer', async t => {
  const { bytes, config } = fixture(); mockFetch(t, bytes.subarray(0, 100)); const f = sessionFixture();
  await assert.rejects(installVideoBlob(f.session, config), /size|length/i);
  assert.equal(f.blobs.length, 0);
});
