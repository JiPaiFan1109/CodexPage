import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { externalSourceUnavailable, loadPayload } from '../engine/scripts/injector.mjs';

test('converted media stops when either source disappears or is replaced and disables persistent video cache', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'steam-cache-'));
  try {
    const source = path.join(root, 'scene.pkg');
    const preview = path.join(root, 'preview.png');
    await fs.writeFile(source, 'scene');
    await fs.copyFile(new URL('../engine/assets/demo-background.png', import.meta.url), preview);
    const dependencies = await Promise.all([source, preview].map(async (file) => {
      const stat = await fs.stat(file);
      return {path:file, size:stat.size, lastWriteTimeUtc:stat.mtime.toISOString()};
    }));
    await fs.writeFile(path.join(root, 'theme.json'), JSON.stringify({schemaVersion:1,image:'preview.png', sourceDependencies:dependencies}));
    assert.equal(await externalSourceUnavailable(root), false);
    const payload = await loadPayload(root, null, {url:`http://127.0.0.1:49152/${'a'.repeat(64)}/video.mp4`,fileSize:100,fileSha256:'b'.repeat(64)});
    assert.equal(payload.video.persistentCache, false);
    await fs.utimes(source, new Date(0), new Date(0));
    assert.equal(await externalSourceUnavailable(root), true);
    await fs.utimes(source, new Date(dependencies[0].lastWriteTimeUtc), new Date(dependencies[0].lastWriteTimeUtc));
    assert.equal(await externalSourceUnavailable(root), false);
    await fs.unlink(preview);
    assert.equal(await externalSourceUnavailable(root), true);
  } finally { await fs.rm(root, {recursive:true,force:true}); }
});
