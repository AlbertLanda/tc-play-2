/** One channel selection. Late responses cannot revive a closed selection. */
export function createPlaybackSession({ channel, session, api, allowProxy = false }) {
  let closed = false;
  let pending = false;
  let current = null;
  let stage = null;
  let proxy = null;
  let closePromise = null;

  async function releaseProxy() {
    const active = proxy;
    proxy = null;
    if (!active) return;
    if (active === 'astra-proxy') await api.stopAstraProxy(channel.id);
    else await api.stopProxy(channel.id);
  }

  async function load(nextStage) {
    if (closed || pending) return null;
    pending = true;
    stage = nextStage;
    try {
      let url;
      if (nextStage === 'astra-proxy') {
        url = await api.getAstraProxyUrl(channel.id);
        proxy = nextStage;
      } else if (nextStage === 'xtream-proxy') {
        url = await api.getProxyStreamUrl(session.username, session.password, channel.id);
        proxy = nextStage;
      } else if (channel.isAstra) {
        url = channel.stream_url || channel.url;
      } else {
        url = await api.getStreamUrl(
          session.username, session.password, channel.id,
          nextStage === 'ts' ? 'ts' : 'm3u8',
        );
      }
      if (closed) {
        await releaseProxy();
        return null;
      }
      if (typeof url !== 'string' || !/^https?:\/\//i.test(url)) {
        throw new Error('No se pudo obtener una dirección válida para el canal.');
      }
      current = { url, mode: nextStage };
      return current;
    } finally {
      pending = false;
    }
  }

  return {
    get current() { return current; },
    get closed() { return closed; },
    start() { return load('hls'); },
    fallback({ canPlayTs = true } = {}) {
      if (closed || pending) return Promise.resolve(null);
      if (stage === 'hls' && !channel.isAstra && canPlayTs) return load('ts');
      if ((stage === 'hls' || stage === 'ts') && allowProxy) {
        return load(channel.isAstra ? 'astra-proxy' : 'xtream-proxy');
      }
      return Promise.reject(new Error(
        'No se pudo reproducir la señal directa. Intenta nuevamente o contacta a Telecable.',
      ));
    },
    close() {
      closed = true;
      current = null;
      // A pending proxy request releases its result inside load().
      closePromise ??= releaseProxy();
      return closePromise;
    },
  };
}
