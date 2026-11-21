import { test } from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { earlyPayloadFor } from '../engine/scripts/injector.mjs';

function sandbox() {
  let now = 0;
  let surface = false;
  const timers = [];
  const schedule = (fn, ms, repeat) => { const t = { fn, at: now + ms, ms, repeat, live: true }; timers.push(t); return t; };
  const clear = t => { if (t) t.live = false; };
  const window = {};
  const context = {
    window,
    location: { protocol: 'app:' },
    document: {
      documentElement: {},
      querySelector: () => (surface ? {} : null),
      addEventListener() {},
    },
    setInterval: (fn, ms) => schedule(fn, ms, true),
    clearInterval: clear,
    setTimeout: (fn, ms) => schedule(fn, ms, false),
    clearTimeout: clear,
  };
  vm.createContext(context);
  return {
    context, window,
    showSurface() { surface = true; },
    advance(ms) {
      const end = now + ms;
      for (;;) {
        const next = timers.filter(t => t.live && t.at <= end).sort((a, b) => a.at - b.at)[0];
        if (!next) break;
        now = next.at;
        if (next.repeat) next.at += next.ms; else next.live = false;
        next.fn();
      }
      now = end;
    },
    pending: () => timers.some(t => t.live),
  };
}

test('early wallpaper waits for a Codex shell that appears 20 s after a reload', () => {
  const box = sandbox();
  vm.runInContext(earlyPayloadFor('window.__installed = (window.__installed ?? 0) + 1;', 'rev-1'), box.context);
  box.advance(20000);
  assert.equal(box.window.__installed, undefined);
  box.showSurface();
  box.advance(300);
  assert.equal(box.window.__installed, 1);
  assert.equal(box.window.__CODEX_DREAM_SKIN_EARLY_APPLIED__, 'rev-1');
  assert.equal(box.pending(), false, 'polling and the deadline stop after installing');
});

test('early wallpaper still stops polling when no Codex shell ever appears', () => {
  const box = sandbox();
  vm.runInContext(earlyPayloadFor('window.__installed = 1;', 'rev-2'), box.context);
  box.advance(46000);
  assert.equal(box.pending(), false);
  box.showSurface();
  box.advance(1000);
  assert.equal(box.window.__installed, undefined);
});
