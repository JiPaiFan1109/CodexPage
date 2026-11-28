import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

test('native light and dark text stays readable over the opposite wallpaper extremes', {
  skip: process.platform !== 'win32',
}, async () => {
  const edge = path.join(process.env['ProgramFiles(x86)'], 'Microsoft/Edge/Application/msedge.exe');
  await fs.access(edge);
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'skin-contrast-'));
  try {
    const css = await fs.readFile(new URL('../engine/assets/earth-background.css', import.meta.url), 'utf8');
    const file = path.join(directory, 'contrast.html');
    await fs.writeFile(file, `<!doctype html><html data-dream-skin="active"><head><style>${css}</style></head>
      <body><div id="codex-dream-skin-image"></div><div id="codex-dream-skin-video-overlay"></div>
      <div data-app-shell-frame style="background-image:linear-gradient(#18181880,#18181880)">
        <div data-app-shell-surface-backing aria-hidden="true" style="background-color:#181818"></div>
        <main class="main-surface">Native text</main>
      </div><pre id="result"></pre><script>
      const results = [];
      const rgb = value => value.match(/[\\d.]+/g).map(Number);
      const luminance = channels => channels.slice(0, 3).map(v => {
        const s = v / 255; return s <= .04045 ? s / 12.92 : ((s + .055) / 1.055) ** 2.4;
      }).reduce((sum, v, i) => sum + v * [.2126, .7152, .0722][i], 0);
      for (const [mode, foreground, artwork] of [['light', 0, 0], ['dark', 255, 255]]) {
        document.documentElement.setAttribute('data-dream-shell', mode);
        document.body.style.color = 'rgb(' + [foreground, foreground, foreground].join(',') + ')';
        const image = document.getElementById('codex-dream-skin-image');
        image.style.background = 'rgb(' + [artwork, artwork, artwork].join(',') + ')';
        const filter = getComputedStyle(image).filter;
        const brightness = filter.match(/brightness\\(([\\d.]+)\\)/)?.[1] ?? 1;
        const overlay = rgb(getComputedStyle(document.getElementById('codex-dream-skin-video-overlay')).backgroundColor);
        const alpha = overlay[3] ?? 1;
        const background = overlay.slice(0, 3).map(v => v * alpha + artwork * brightness * (1 - alpha));
        const text = rgb(getComputedStyle(document.querySelector('main')).color);
        const a = luminance(text), b = luminance(background);
        const frame = getComputedStyle(document.querySelector('[data-app-shell-frame]'));
        const backing = getComputedStyle(document.querySelector('[data-app-shell-surface-backing]'));
        results.push({mode, foreground, frameImage: frame.backgroundImage, backingColor: backing.backgroundColor,
          nativeText: text, contrast: (Math.max(a,b) + .05) / (Math.min(a,b) + .05)});
      }
      document.getElementById('result').textContent = JSON.stringify(results);
      </script></body></html>`);
    const run = spawnSync(edge, ['--headless', '--disable-gpu', '--no-first-run',
      '--disable-background-networking', '--user-data-dir=' + path.join(directory, 'profile'),
      '--dump-dom', pathToFileURL(file).href], {
      encoding: 'utf8', timeout: 45000, maxBuffer: 2 * 1024 * 1024, windowsHide: true,
    });
    assert.ifError(run.error);
    assert.equal(run.status, 0, run.stderr);
    const match = run.stdout.match(/<pre id="result">([^<]+)<\/pre>/);
    assert.ok(match, 'Headless browser did not execute the contrast fixture');
    const results = JSON.parse(match[1]);
    assert.equal(results.length, 2);
    for (const result of results) {
      assert.equal(result.backingColor, 'rgba(0, 0, 0, 0)', 'Opaque workspace backing covers the wallpaper');
      assert.equal(result.frameImage, 'none', 'Native window gradient dims the wallpaper twice');
      assert.deepEqual(result.nativeText.slice(0,3), Array(3).fill(result.foreground), 'Native text color changed');
      assert.ok(result.contrast >= 4.5, result.mode + ' wallpaper contrast was ' + result.contrast.toFixed(2));
    }
  } finally {
    // Only remove the temporary directory created by this test.
    assert.equal(path.dirname(directory), path.resolve(os.tmpdir()));
    assert.ok(path.basename(directory).startsWith('skin-contrast-'));
    await fs.rm(directory, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 });
  }
});
