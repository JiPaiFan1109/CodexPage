import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { loadTheme, loadPayload, externalSourceUnavailable } from '../engine/scripts/injector.mjs';

test('Steam image loads directly, validates identity and becomes unavailable when deleted', async () => {
  // Hosted Windows TEMP may use a short path or junction. The normal-source
  // fixture must record the canonical identity required by the loader.
  const root = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), 'steam-reference-')));
  try {
    const themeDir = path.join(root, 'active-theme');
    await fs.mkdir(themeDir);
    const media = path.join(root, 'Steam image.png');
    const bytes = await fs.readFile(new URL('../engine/assets/demo-background.png', import.meta.url));
    await fs.writeFile(media, bytes);
    const source = {kind:'Image', path:media, size:bytes.length, sha256:createHash('sha256').update(bytes).digest('hex')};
    const theme = {schemaVersion:1, id:'custom', image:'external-image', externalSource:source};
    await fs.writeFile(path.join(themeDir,'theme.json'), JSON.stringify(theme));
    assert.equal((await loadTheme(themeDir)).imagePath, await fs.realpath(media));
    assert.equal(await externalSourceUnavailable(themeDir), false);
    assert.deepEqual(await fs.readdir(themeDir), ['theme.json']);
    const payload = await loadPayload(themeDir, null, {url:`http://127.0.0.1:49152/${'a'.repeat(64)}/video.mp4`, fileSize:100, fileSha256:'b'.repeat(64)});
    assert.equal(payload.video.persistentCache, false);
    const alias = path.join(root, 'linked-source');
    await fs.symlink(root, alias, process.platform === 'win32' ? 'junction' : 'dir');
    source.path = path.join(alias, 'Steam image.png');
    await fs.writeFile(path.join(themeDir,'theme.json'), JSON.stringify(theme));
    await assert.rejects(loadTheme(themeDir), /link or junction/);
    source.path = media;
    source.sha256 = '0'.repeat(64);
    await fs.writeFile(path.join(themeDir,'theme.json'), JSON.stringify(theme));
    await assert.rejects(loadTheme(themeDir), /changed/);
    await fs.unlink(media);
    assert.equal(await externalSourceUnavailable(themeDir), true);
    await assert.rejects(loadTheme(themeDir));
    source.kind = 'Video';
    await fs.writeFile(path.join(themeDir,'theme.json'), JSON.stringify(theme));
    assert.equal(await externalSourceUnavailable(themeDir), true);
    delete theme.externalSource;
    await fs.writeFile(path.join(themeDir,'theme.json'), JSON.stringify(theme));
    assert.equal(await externalSourceUnavailable(themeDir), false);
  } finally { await fs.rm(root, {recursive:true, force:true}); }
});
