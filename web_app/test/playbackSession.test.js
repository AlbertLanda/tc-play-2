import test from 'node:test';
import assert from 'node:assert/strict';
import { createPlaybackSession } from '../src/utils/playbackSession.js';

const session = { username: 'test-user', password: 'test-password' };
const channel = { id: 123, name: 'Canal de prueba' };
function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
function fixture(options = {}) {
  const calls = [];
  const api = {
    async getStreamUrl(...args) { calls.push(['direct', ...args]); return `https://source.invalid/123.${args[3]}`; },
    async getProxyStreamUrl(...args) { calls.push(['xtream-proxy', ...args]); return 'https://backend.invalid/123-web/index.m3u8'; },
    async getAstraProxyUrl(id) { calls.push(['astra-proxy', id]); return 'https://backend.invalid/astra-1/index.m3u8'; },
    async stopProxy(id) { calls.push(['stop-xtream', id]); },
    async stopAstraProxy(id) { calls.push(['stop-astra', id]); },
  };
  return { api, calls, player: createPlaybackSession({ channel, session, api, ...options }) };
}

test('Xtream starts directly with HLS and closing does not stop any backend output', async () => {
  const { player, calls } = fixture();
  assert.deepEqual(await player.start(), { url: 'https://source.invalid/123.m3u8', mode: 'hls' });
  await player.close();
  assert.deepEqual(calls, [['direct', session.username, session.password, 123, 'm3u8']]);
});

test('a failed direct HLS playback tries direct TS, never a proxy by default', async () => {
  const { player, calls } = fixture();
  await player.start();
  assert.equal((await player.fallback()).mode, 'ts');
  await assert.rejects(player.fallback(), /señal directa/);
  await player.close();
  assert.deepEqual(calls.map((x) => [x[0], x[4]]), [['direct', 'm3u8'], ['direct', 'ts']]);
});

test('a browser without TS support does not request a TS stream or implicit proxy', async () => {
  const { player, calls } = fixture();
  await player.start();
  await assert.rejects(player.fallback({ canPlayTs: false }), /señal directa/);
  assert.equal(calls.length, 1);
});

test('opt-in proxy is attempted only after HLS and TS fail', async () => {
  const { player, calls } = fixture({ allowProxy: true });
  await player.start();
  await player.fallback();
  assert.equal((await player.fallback()).mode, 'xtream-proxy');
  await assert.rejects(player.fallback(), /señal directa/);
  await player.close();
  await player.close();
  assert.deepEqual(calls.map((x) => x[0]), ['direct', 'direct', 'xtream-proxy', 'stop-xtream']);
});

test('opt-in proxy may follow HLS when the browser cannot play TS', async () => {
  const { player, calls } = fixture({ allowProxy: true });
  await player.start();
  assert.equal((await player.fallback({ canPlayTs: false })).mode, 'xtream-proxy');
  assert.deepEqual(calls.map((x) => x[0]), ['direct', 'xtream-proxy']);
  await player.close();
});

test('Astra keeps its direct URL and does not call Xtream or proxy endpoints', async () => {
  const { player, calls } = fixture({ channel: { id: 'astra-1', isAstra: true, stream_url: 'https://astra.invalid/live.m3u8' } });
  assert.deepEqual(await player.start(), { url: 'https://astra.invalid/live.m3u8', mode: 'hls' });
  await assert.rejects(player.fallback(), /señal directa/);
  await player.close();
  assert.deepEqual(calls, []);
});

test('opt-in Astra fallback releases only the Astra output', async () => {
  const { player, calls } = fixture({ allowProxy: true, channel: { id: 'astra-1', isAstra: true, url: 'https://astra.invalid/live.m3u8' } });
  await player.start();
  assert.equal((await player.fallback()).mode, 'astra-proxy');
  await player.close();
  assert.deepEqual(calls, [['astra-proxy', 'astra-1'], ['stop-astra', 'astra-1']]);
});

test('late direct response cannot revive a selection closed by navigation', async () => {
  const { api, player, calls } = fixture();
  const request = deferred();
  api.getStreamUrl = () => request.promise;
  const loading = player.start();
  await player.close();
  request.resolve('https://source.invalid/123.m3u8');
  assert.equal(await loading, null);
  assert.equal(player.current, null);
  assert.deepEqual(calls, []);
});

test('late proxy result is released after its selection has closed', async () => {
  const { api, player, calls } = fixture({ allowProxy: true });
  await player.start();
  const request = deferred();
  api.getProxyStreamUrl = () => request.promise;
  const loading = player.fallback({ canPlayTs: false });
  await player.close();
  request.resolve('https://backend.invalid/123-web/index.m3u8');
  assert.equal(await loading, null);
  await player.close();
  assert.deepEqual(calls.map((x) => x[0]), ['direct', 'stop-xtream']);
});

test('overlapping media errors do not launch multiple fallback requests', async () => {
  const { api, player } = fixture();
  await player.start();
  const request = deferred();
  let requests = 0;
  api.getStreamUrl = () => { requests += 1; return request.promise; };
  const first = player.fallback();
  assert.equal(await player.fallback(), null);
  request.resolve('https://source.invalid/123.ts');
  assert.equal((await first).mode, 'ts');
  assert.equal(requests, 1);
});

test('a newer channel stays independent of an older delayed request', async () => {
  const old = fixture();
  const request = deferred();
  old.api.getStreamUrl = () => request.promise;
  const delayed = old.player.start();
  await old.player.close();
  const next = fixture({ channel: { id: 456 } });
  await next.player.start();
  request.resolve('https://source.invalid/123.m3u8');
  assert.equal(await delayed, null);
  assert.equal(next.calls[0][3], 456);
  assert.equal(next.player.current.mode, 'hls');
  await next.player.close();
});

test('direct metadata errors do not silently start a proxy', async () => {
  const { api, player, calls } = fixture({ allowProxy: true });
  api.getStreamUrl = async () => { throw new Error('Cuenta inactiva.'); };
  await assert.rejects(player.start(), /Cuenta inactiva/);
  assert.equal(player.current, null);
  assert.deepEqual(calls, []);
});

test('closed selections cannot start new playback or fallback requests', async () => {
  const { player, calls } = fixture({ allowProxy: true });
  await player.close();
  assert.equal(await player.start(), null);
  assert.equal(await player.fallback(), null);
  assert.deepEqual(calls, []);
});

test('missing or non-HTTP sources fail without being handed to the media player', async () => {
  for (const url of [null, '', 'javascript:alert(1)', 'file:///tmp/video.ts']) {
    const { api, player } = fixture();
    api.getStreamUrl = async () => url;
    await assert.rejects(player.start(), /dirección válida/);
    assert.equal(player.current, null);
    await player.close();
  }
});
