import test, { before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import React, { act } from 'react';
import { createRoot } from 'react-dom/client';
import { JSDOM } from 'jsdom';
import { createServer } from 'vite';

let dom, vite, PlayerPage, root, container;
let calls, intervals, blocked;
const originalFetch = globalThis.fetch;
const originalSetInterval = globalThis.setInterval;
const originalClearInterval = globalThis.clearInterval;
const props = {
  session: { username: 'test-user', password: 'test-password' },
  channel: { id: 123, name: 'Canal de prueba' },
  onBack() {},
};
const response = (url) => new Response(JSON.stringify({ success: true, stream_url: url }), {
  headers: { 'Content-Type': 'application/json' },
});
const flush = () => act(async () => { await new Promise((resolve) => setTimeout(resolve, 0)); });

before(async () => {
  dom = new JSDOM('<div id="root"></div>', { url: 'http://localhost/', pretendToBeVisual: true });
  for (const key of ['window', 'document', 'self', 'navigator', 'HTMLElement', 'HTMLMediaElement', 'XMLHttpRequest']) {
    Object.defineProperty(globalThis, key, { configurable: true, value: key === 'self' ? dom.window : dom.window[key] });
  }
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  dom.window.HTMLMediaElement.prototype.canPlayType = () => 'probably';
  dom.window.HTMLMediaElement.prototype.load = function () {};
  dom.window.HTMLMediaElement.prototype.pause = function () {
    Object.defineProperty(this, 'paused', { configurable: true, value: true });
    this.dispatchEvent(new dom.window.Event('pause'));
  };
  dom.window.HTMLMediaElement.prototype.play = async function () {
    if (blocked) throw new dom.window.DOMException('User action required', 'NotAllowedError');
    Object.defineProperty(this, 'paused', { configurable: true, value: false });
    this.dispatchEvent(new dom.window.Event('playing'));
  };
  vite = await createServer({
    root: process.cwd(), server: { middlewareMode: true, hmr: false, watch: null },
    appType: 'custom', logLevel: 'error',
  });
  ({ PlayerPage } = await vite.ssrLoadModule('/src/pages/PlayerPage.jsx'));
});

beforeEach(() => {
  calls = [];
  intervals = new Map();
  blocked = false;
  globalThis.fetch = async (url, options) => {
    calls.push({ url: String(url), body: JSON.parse(options.body) });
    return response('https://source.invalid/live/123.m3u8');
  };
  globalThis.setInterval = (callback, delay, ...args) => {
    if (delay !== 4000) return originalSetInterval(callback, delay, ...args);
    const handle = {};
    intervals.set(handle, callback);
    return handle;
  };
  globalThis.clearInterval = (handle) => {
    if (intervals.delete(handle)) return;
    originalClearInterval(handle);
  };
  container = document.getElementById('root');
  root = createRoot(container);
});

afterEach(async () => {
  await act(async () => root.unmount());
  assert.equal(intervals.size, 0, 'the playback watchdog must be cleared on unmount');
  globalThis.fetch = originalFetch;
  globalThis.setInterval = originalSetInterval;
  globalThis.clearInterval = originalClearInterval;
});

after(async () => {
  await vite?.close();
  dom?.window.close();
});

async function mount(custom = props) {
  await act(async () => root.render(React.createElement(PlayerPage, custom)));
  await flush();
}
async function tickWatchdog() {
  await act(async () => {
    for (let i = 0; i < 4; i += 1) for (const callback of [...intervals.values()]) callback();
  });
  await flush();
}

test('the actual page attaches native HLS after metadata loading and closes without proxy calls', async () => {
  await mount();
  const video = container.querySelector('video');
  assert.ok(video);
  assert.equal(video.src, 'https://source.invalid/live/123.m3u8');
  assert.equal(calls.length, 1);
  assert.ok(calls[0].url.endsWith('/live/stream-url/'));
  assert.equal(calls[0].body.output, 'm3u8');
  await act(async () => container.querySelector('[aria-label="Volver"]').click());
  assert.equal(calls.length, 1);
  assert.equal(container.querySelector('video'), null);
});

test('a native playback error reports direct failure without requesting a transcoder', async () => {
  await mount();
  await act(async () => container.querySelector('video').dispatchEvent(new dom.window.Event('error')));
  await flush();
  assert.match(container.textContent, /señal directa/);
  assert.equal(calls.length, 1);
});

test('autoplay denial prompts the user and does not activate fallback on watchdog ticks', async () => {
  blocked = true;
  await mount();
  assert.match(container.textContent, /Presiona reproducir/);
  await tickWatchdog();
  assert.equal(calls.length, 1);
  assert.doesNotMatch(container.textContent, /señal directa/);
});

test('a deliberate pause does not activate fallback on watchdog ticks', async () => {
  await mount();
  await act(async () => container.querySelector('[aria-label="Pausar"]').click());
  await tickWatchdog();
  assert.equal(calls.length, 1);
  assert.doesNotMatch(container.textContent, /señal directa/);
});

test('a slow previous selection cannot replace the newer channel in the actual page', async () => {
  let resolveOld;
  globalThis.fetch = async (url, options) => {
    const body = JSON.parse(options.body);
    calls.push({ url: String(url), body });
    if (body.stream_id === 123) return new Promise((resolve) => { resolveOld = resolve; });
    return response('https://source.invalid/live/456.m3u8');
  };
  await mount();
  await mount({ ...props, channel: { id: 456, name: 'Canal nuevo' } });
  assert.equal(container.querySelector('video').src, 'https://source.invalid/live/456.m3u8');
  await act(async () => resolveOld(response('https://source.invalid/live/123.m3u8')));
  await flush();
  assert.equal(container.querySelector('video').src, 'https://source.invalid/live/456.m3u8');
  assert.equal(calls.length, 2);
});

test('startup without advancing frames reaches a visible error instead of hanging or starting FFmpeg', async () => {
  await mount();
  await tickWatchdog();
  assert.match(container.textContent, /señal directa/);
  assert.equal(calls.length, 1);
});

test('retry after a direct failure reattaches HLS without sending stop-proxy', async () => {
  await mount();
  await act(async () => container.querySelector('video').dispatchEvent(new dom.window.Event('error')));
  await flush();
  await act(async () => container.querySelector('.retry-button').click());
  await flush();
  assert.equal(container.querySelector('video').src, 'https://source.invalid/live/123.m3u8');
  assert.equal(calls.length, 2);
  assert.ok(calls.every((call) => call.url.endsWith('/live/stream-url/')));
  assert.doesNotMatch(container.textContent, /señal directa/);
});
