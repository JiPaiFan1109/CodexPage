import { createHash, randomUUID } from 'node:crypto';
import { restoreVideoCache, persistVideoCache } from './video-cache.mjs';

const MAX_BYTES = 128 * 1024 * 1024;
const CHUNK_BYTES = 512 * 1024;
let cached = null;
const pendingReads = new Map();

function validate(config) {
  if (!config || typeof config.url !== 'string') throw Error('Video URL is required');
  const url = new URL(config.url);
  if (url.protocol !== 'http:' || url.hostname !== '127.0.0.1' ||
      !Number.isInteger(Number(url.port)) || Number(url.port) < 1024 || Number(url.port) > 65535 ||
      url.username || url.password || url.search || url.hash ||
      !/^\/[a-f0-9]{64}\/video\.mp4$/.test(url.pathname) || url.href !== config.url) {
    throw Error('Video URL must be a strict tokenized IPv4 loopback endpoint');
  }
  if (!Number.isSafeInteger(config.fileSize) || config.fileSize <= 0 || config.fileSize > MAX_BYTES) {
    throw Error('Video size exceeds the 128 MiB limit or is invalid');
  }
  if (typeof config.fileSha256 !== 'string' || !/^[a-f0-9]{64}$/.test(config.fileSha256)) {
    throw Error('Video SHA256 is invalid');
  }
  return `${config.url}:${config.fileSize}:${config.fileSha256}`;
}

async function readVerified(config, key) {
  if (cached?.key === key) return cached.bytes;
  if (pendingReads.has(key)) return pendingReads.get(key);
  const pending = downloadVerified(config, key);
  pendingReads.set(key, pending);
  try {
    return await pending;
  } finally {
    pendingReads.delete(key);
  }
}

async function downloadVerified(config, key) {
  const response = await fetch(config.url, { redirect: 'error', signal: AbortSignal.timeout(30000) });
  if (!response.ok || !response.body) throw Error(`Video download failed: HTTP ${response.status}`);
  const reader = response.body.getReader();
  const chunks = [];
  let length = 0;
  try {
    const declared = response.headers.get('content-length');
    if (declared !== null && Number(declared) !== config.fileSize) throw Error('Video content length differs from expected size');
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > config.fileSize || length > MAX_BYTES) throw Error('Video stream exceeds expected size');
      chunks.push(Buffer.from(value));
    }
    if (length !== config.fileSize) throw Error('Video stream size differs from expected size');
    const bytes = Buffer.concat(chunks, length);
    if (createHash('sha256').update(bytes).digest('hex') !== config.fileSha256) throw Error('Video SHA256 mismatch');
    cached = { key, bytes };
    return bytes;
  } catch (error) {
    await reader.cancel().catch(() => {});
    throw error;
  } finally {
    reader.releaseLock();
  }
}

export async function installVideoBlob(session, videoConfig) {
  const key = validate(videoConfig);
  const initial = await session.evaluate(`(() => {
    const s = window.__CODEX_DREAM_SKIN_STATE__;
    if (window.__CODEX_DREAM_SKIN_DISABLED__ || !s || typeof s.attachVideoBlob !== 'function' ||
        !['string', 'number'].includes(typeof s.installToken)) throw Error('Video runtime is inactive');
    return { token: s.installToken, present: s.videoBlobKey === ${JSON.stringify(key)} && Boolean(s.videoBlobUrl) };
  })()`);
  if (initial.present) return;
  const cacheConfig = { fileSize: videoConfig.fileSize, fileSha256: videoConfig.fileSha256 };
  if (videoConfig.persistentCache !== false && await session.evaluate(`(${restoreVideoCache.toString()})(${JSON.stringify(cacheConfig)}, ${JSON.stringify(key)}, ${JSON.stringify(initial.token)})`)) return;
  const bytes = await readVerified(videoConfig, key);
  const generation = randomUUID();
  const tokenLiteral = JSON.stringify(initial.token);
  const generationLiteral = JSON.stringify(generation);
  const activeCheck = `!window.__CODEX_DREAM_SKIN_DISABLED__ && s && s.installToken === ${tokenLiteral}`;
  const uploadCheck = `${activeCheck} && s.videoUpload?.generation === ${generationLiteral}`;
  try {
    const begun = await session.evaluate(`(() => {
      const s = window.__CODEX_DREAM_SKIN_STATE__;
      if (!(${activeCheck}) || typeof s.attachVideoBlob !== 'function') return false;
      s.videoUpload = { generation: ${generationLiteral}, chunks: [], size: 0 };
      return true;
    })()`);
    if (!begun) throw Error('Video upload cancelled: runtime changed');
    for (let offset = 0; offset < bytes.length; offset += CHUNK_BYTES) {
      const base64 = bytes.subarray(offset, offset + CHUNK_BYTES).toString('base64');
      const uploaded = await session.evaluate(`(() => {
        const s = window.__CODEX_DREAM_SKIN_STATE__;
        if (!(${uploadCheck})) return false;
        const text = atob(${JSON.stringify(base64)});
        const chunk = new Uint8Array(text.length);
        for (let i = 0; i < text.length; i++) chunk[i] = text.charCodeAt(i);
        s.videoUpload.chunks.push(chunk);
        s.videoUpload.size += chunk.length;
        return true;
      })()`);
      if (!uploaded) throw Error('Video upload cancelled: runtime changed');
    }
    const committed = await session.evaluate(`(async () => {
      const s = window.__CODEX_DREAM_SKIN_STATE__;
      if (!(${uploadCheck}) || s.videoUpload.size !== ${bytes.length}) return false;
      const previousUrl = s.videoBlobUrl;
      const previousKey = s.videoBlobKey;
      const blob = new Blob(s.videoUpload.chunks, { type: 'video/mp4' });
      const url = URL.createObjectURL(blob);
      s.videoUpload.chunks = [];
      s.videoBlobUrl = url;
      s.videoBlobKey = ${JSON.stringify(key)};
      try {
        if (await s.attachVideoBlob(url) === false) throw Error('Video attachment refused: upload cancelled');
        if (window.__CODEX_DREAM_SKIN_STATE__ !== s || !(${uploadCheck})) {
          throw Error('Video upload cancelled: runtime changed during attachment');
        }
        delete s.videoUpload;
        if (previousUrl && previousUrl !== url) URL.revokeObjectURL(previousUrl);
        if (${videoConfig.persistentCache !== false}) void (${persistVideoCache.toString()})(blob, ${JSON.stringify(cacheConfig)});
        return true;
      } catch (error) {
        URL.revokeObjectURL(url);
        if (s.videoBlobUrl === url) {
          if (previousUrl) s.videoBlobUrl = previousUrl; else delete s.videoBlobUrl;
          if (previousKey) s.videoBlobKey = previousKey; else delete s.videoBlobKey;
        }
        if (s.videoUpload?.generation === ${generationLiteral}) delete s.videoUpload;
        throw error;
      }
    })()`);
    if (!committed) throw Error('Video upload cancelled: runtime changed');
  } catch (error) {
    await session.evaluate(`(() => {
      const s = window.__CODEX_DREAM_SKIN_STATE__;
      if (s?.installToken === ${tokenLiteral} && s.videoUpload?.generation === ${generationLiteral}) {
        delete s.videoUpload;
      }
    })()`).catch(() => {});
    throw error;
  }
}
