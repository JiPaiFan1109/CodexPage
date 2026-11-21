// These self-contained functions execute in the renderer. Cache API keys are
// identifiers only: no request is sent to this reserved .invalid domain.
export async function restoreVideoCache(config, key, token, timeoutMs = 2000) {
  if (typeof caches === 'undefined' || typeof crypto === 'undefined' || !crypto.subtle) return false;
  const s = window.__CODEX_DREAM_SKIN_STATE__;
  const active = () => !window.__CODEX_DREAM_SKIN_DISABLED__ && s &&
    window.__CODEX_DREAM_SKIN_STATE__ === s && s.installToken === token && typeof s.attachVideoBlob === 'function';
  if (!active()) return false;
  let timer;
  let abandoned = false;
  const available = () => !abandoned && active();
  try {
    const lookup = (async () => {
      const cache = await caches.open('codex-dream-skin-video-v1');
      if (!available()) return null;
      const cacheKey = 'https://codex-dream-skin.invalid/current-video';
      const response = await cache.match(cacheKey);
      if (!available() || !response || response.headers.get('x-video-sha256') !== config.fileSha256 ||
          response.headers.get('content-length') !== String(config.fileSize)) return null;
      const blob = await response.blob();
      if (!available()) return null;
      if (blob.size !== config.fileSize) { await cache.delete(cacheKey); return null; }
      const bytes = await blob.arrayBuffer();
      if (!available()) return null;
      const hash = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
      if (!available()) return null;
      const hex = Array.from(hash, b => b.toString(16).padStart(2, '0')).join('');
      if (hex !== config.fileSha256) { await cache.delete(cacheKey); return null; }
      return blob;
    })().catch(() => null);
    // A blocked/quota-limited storage service must never hold up normal loading.
    // Late lookup results have no attachment side effects.
    const blob = await Promise.race([lookup, new Promise(resolve => {
      timer = setTimeout(() => {
        abandoned = true;
        resolve(null);
      }, timeoutMs);
    })]);
    if (!blob || !active()) return false;
    const previousUrl = s.videoBlobUrl, previousKey = s.videoBlobKey;
    const url = URL.createObjectURL(blob);
    s.videoBlobUrl = url; s.videoBlobKey = key;
    try {
      if (await s.attachVideoBlob(url) === false || !active()) throw Error('Cached video attachment cancelled');
      if (previousUrl && previousUrl !== url) URL.revokeObjectURL(previousUrl);
      return true;
    } catch {
      URL.revokeObjectURL(url);
      if (s.videoBlobUrl === url) {
        if (previousUrl) s.videoBlobUrl = previousUrl; else delete s.videoBlobUrl;
        if (previousKey) s.videoBlobKey = previousKey; else delete s.videoBlobKey;
      }
      return false;
    }
  } catch { return false; }
  finally { clearTimeout(timer); }
}

export async function persistVideoCache(blob, config) {
  if (typeof caches === 'undefined') return;
  try {
    const cache = await caches.open('codex-dream-skin-video-v1');
    // One fixed entry bounds storage to one video (at most the validated 128 MiB).
    await cache.put('https://codex-dream-skin.invalid/current-video', new Response(blob, {
      headers: { 'content-type':'video/mp4', 'content-length':String(config.fileSize), 'x-video-sha256':config.fileSha256 },
    }));
  } catch { /* Playback must work when storage is denied or full. */ }
}
