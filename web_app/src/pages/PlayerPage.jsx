import { useEffect, useRef, useState } from 'react';
import Hls from 'hls.js';
import mpegts from 'mpegts.js';
import { getStreamUrl } from '../api/liveTvApi';
import { getAstraProxyUrl } from '../api/astraApi';

export function PlayerPage({ session, channel, onBack }) {
  const videoRef = useRef(null);
  const hlsRef = useRef(null);
  const tsPlayerRef = useRef(null);

  const hasTriedTsFallbackRef = useRef(false);
  const mediaErrorCountRef = useRef(0);
  const lastTimeRef = useRef(0);
  const stallTimerRef = useRef(null);

  const [streamUrl, setStreamUrl] = useState('');
  const [playerMode, setPlayerMode] = useState('hls');
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState('');

  function destroyPlayers() {
    if (stallTimerRef.current) {
      clearInterval(stallTimerRef.current);
      stallTimerRef.current = null;
    }

    if (hlsRef.current) {
      hlsRef.current.destroy();
      hlsRef.current = null;
    }

    if (tsPlayerRef.current) {
      tsPlayerRef.current.destroy();
      tsPlayerRef.current = null;
    }
  }

  async function loadUrl(output) {
    if (channel?.isAstra && channel?.stream_url) {
      console.log('[TC Play] Stream URL Astra:', channel.stream_url);
      return channel.stream_url;
    }

    const url = await getStreamUrl(
      session.username,
      session.password,
      channel.id,
      output,
    );

    console.log(`[TC Play] Stream URL ${output}:`, url);
    return url;
  }

  async function switchToFallback() {
    if (hasTriedTsFallbackRef.current) {
      return;
    }

    try {
      hasTriedTsFallbackRef.current = true;
      mediaErrorCountRef.current = 0;
      lastTimeRef.current = 0;
      setErrorMessage('');

      destroyPlayers();

      if (channel?.isAstra) {
        console.warn('[TC Play] Cambiando a proxy/transcoder Astra...');
        setPlayerMode('astra-proxy');

        const proxyUrl = await getAstraProxyUrl(channel.id);
        console.log('[TC Play] Astra proxy URL:', proxyUrl);

        setStreamUrl(proxyUrl);
        return;
      }

      console.warn('[TC Play] Cambiando a fallback MPEG-TS...');
      setPlayerMode('ts');

      const tsUrl = await loadUrl('ts');
      setStreamUrl(tsUrl);
    } catch (error) {
      setErrorMessage(error.message || 'No se pudo activar el fallback.');
    }
  }

  function startPlaybackMonitor() {
    const video = videoRef.current;
    let stalledCount = 0;

    if (!video) {
      return;
    }

    if (stallTimerRef.current) {
      clearInterval(stallTimerRef.current);
    }

    stallTimerRef.current = setInterval(() => {
      if (!video || video.paused || video.ended) {
        return;
      }

      const currentTime = video.currentTime;

      if (currentTime > lastTimeRef.current) {
        lastTimeRef.current = currentTime;
        stalledCount = 0;
        return;
      }

      stalledCount += 1;
      console.warn('[TC Play] El video no avanza. Intento:', stalledCount);

      if (playerMode === 'hls' && hlsRef.current) {
        try {
          hlsRef.current.recoverMediaError();
          hlsRef.current.startLoad();
        } catch (error) {
          console.warn('[TC Play] No se pudo recuperar HLS automáticamente:', error);
        }
      }

      if (
        playerMode === 'hls' &&
        video.currentTime === 0 &&
        stalledCount >= 3
      ) {
        switchToFallback();
      }
    }, 10000);
  }

  useEffect(() => {
    async function preparePlayer() {
      try {
        setIsLoading(true);
        setErrorMessage('');
        setPlayerMode('hls');

        hasTriedTsFallbackRef.current = false;
        mediaErrorCountRef.current = 0;
        lastTimeRef.current = 0;

        const url = await loadUrl(channel?.isAstra ? 'astra' : 'm3u8');
        setStreamUrl(url);
      } catch (error) {
        setErrorMessage(error.message || 'No se pudo cargar el canal.');
      } finally {
        setIsLoading(false);
      }
    }

    if (channel?.id) {
      preparePlayer();
    }

    return () => {
      destroyPlayers();
    };
  }, [session.username, session.password, channel]);

  useEffect(() => {
    const video = videoRef.current;

    if (!video || !streamUrl) {
      return undefined;
    }

    destroyPlayers();
    setErrorMessage('');

    if (playerMode === 'hls' || playerMode === 'astra-proxy') {
      if (Hls.isSupported()) {
        const hls = new Hls({
          debug: false,
          enableWorker: true,
          lowLatencyMode: false,

          maxBufferLength: 60,
          maxMaxBufferLength: 120,
          backBufferLength: 30,

          manifestLoadingTimeOut: 20000,
          manifestLoadingMaxRetry: 10,
          manifestLoadingRetryDelay: 1000,
          manifestLoadingMaxRetryTimeout: 8000,

          levelLoadingTimeOut: 20000,
          levelLoadingMaxRetry: 10,
          levelLoadingRetryDelay: 1000,
          levelLoadingMaxRetryTimeout: 8000,

          fragLoadingTimeOut: 30000,
          fragLoadingMaxRetry: 12,
          fragLoadingRetryDelay: 1000,
          fragLoadingMaxRetryTimeout: 10000,

          appendErrorMaxRetry: 8,
        });

        hlsRef.current = hls;

        hls.loadSource(streamUrl);
        hls.attachMedia(video);

        hls.on(Hls.Events.MANIFEST_PARSED, () => {
          console.log('[TC Play] HLS manifest parsed');

          video.play().catch((error) => {
            console.warn(
              '[TC Play] Autoplay bloqueado. Presionar Play manualmente:',
              error,
            );
          });

          startPlaybackMonitor();
        });

        hls.on(Hls.Events.ERROR, (_, data) => {
          console.warn('[TC Play] HLS error:', data);

          const details = data?.details || '';
          const type = data?.type || '';

          if (
            details.includes('fragParsingError') ||
            details.includes('bufferAppendError') ||
            details.includes('bufferStalledError') ||
            details.includes('bufferSeekOverHole')
          ) {
            mediaErrorCountRef.current += 1;
          }

          if (!data.fatal) {
            if (video.currentTime > 0) {
              console.warn(
                '[TC Play] Warning HLS no fatal, pero el video ya avanzó. Manteniendo HLS.',
              );
              return;
            }

            try {
              hls.recoverMediaError();
            } catch (error) {
              console.warn('[TC Play] Recuperación HLS no fatal falló:', error);
            }

            if (
              mediaErrorCountRef.current >= 10 &&
              video.currentTime === 0
            ) {
              switchToFallback();
            }

            return;
          }

          if (type === Hls.ErrorTypes.NETWORK_ERROR) {
            console.warn('[TC Play] Error fatal de red. Reintentando HLS...');
            hls.startLoad();
            return;
          }

          if (type === Hls.ErrorTypes.MEDIA_ERROR) {
            mediaErrorCountRef.current += 1;

            if (video.currentTime > 0) {
              console.warn(
                '[TC Play] Error fatal de media, pero el video ya avanzó. Manteniendo HLS.',
              );

              try {
                hls.recoverMediaError();
                hls.startLoad();
              } catch (error) {
                console.warn('[TC Play] Recuperación fatal HLS falló:', error);
              }

              return;
            }

            if (mediaErrorCountRef.current <= 8) {
              hls.recoverMediaError();
              return;
            }

            switchToFallback();
            return;
          }

          switchToFallback();
        });
      } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
        video.src = streamUrl;

        video.play().catch((error) => {
          console.warn('[TC Play] Autoplay bloqueado:', error);
        });

        startPlaybackMonitor();
      } else {
        switchToFallback();
      }
    }

    if (playerMode === 'ts') {
      if (mpegts.getFeatureList().mseLivePlayback) {
        const player = mpegts.createPlayer({
          type: 'mpegts',
          isLive: true,
          url: streamUrl,
        });

        tsPlayerRef.current = player;

        player.attachMediaElement(video);
        player.load();

        player.play().catch((error) => {
          console.warn(
            '[TC Play] Autoplay TS bloqueado. Presionar Play manualmente:',
            error,
          );
        });

        startPlaybackMonitor();

        player.on(mpegts.Events.ERROR, (type, detail) => {
          console.warn('[TC Play] MPEG-TS error:', type, detail);

          if (video.currentTime > 0) {
            console.warn(
              '[TC Play] MPEG-TS reportó error, pero el video avanzó. Manteniendo player visible.',
            );
            return;
          }

          setErrorMessage(
            'Este canal no pudo reproducirse en el navegador con HLS ni MPEG-TS.',
          );
        });
      } else {
        setErrorMessage('Este navegador no soporta reproducción MPEG-TS.');
      }
    }

    return () => {
      destroyPlayers();
    };
  }, [streamUrl, playerMode]);

  return (
    <main className="player-layout">
      <header className="home-header">
        <div>
          <h1>{channel?.name || 'Reproductor'}</h1>
          <p>Reproducción en vivo - TC Play 2.0</p>
        </div>

        <button type="button" onClick={onBack}>
          Volver
        </button>
      </header>

      <section className="player-content">
        {isLoading && <p className="state-message">Preparando canal...</p>}

        {!isLoading && streamUrl && (
          <div className="player-wrapper">
            <div className="player-box">
              <video
                ref={videoRef}
                className="video-player"
                controls
                playsInline
              >
                Tu navegador no soporta reproducción de video.
              </video>
            </div>

            <aside className="player-info">
              <div className="channel-logo large">
                {channel.icon || channel.logo ? (
                  <img src={channel.icon || channel.logo} alt={channel.name} />
                ) : (
                  <span>📺</span>
                )}
              </div>

              <h2>{channel.name}</h2>
              <p>ID: {channel.id}</p>
              <p>
                Categoría: {channel.isAstra ? 'Astra HLS' : channel.category_id}
              </p>
              <p>
                Modo:{' '}
                {playerMode === 'astra-proxy'
                  ? 'Astra Proxy HLS'
                  : playerMode === 'hls'
                    ? 'HLS'
                    : 'MPEG-TS'}
              </p>

              {errorMessage ? (
                <p className="warning-text error-warning">
                  {errorMessage}
                </p>
              ) : (
                <p className="warning-text">
                  {channel.isAstra
                    ? 'Reproductor Astra. Primero intenta HLS directo; si falla, usa proxy/transcoder del backend.'
                    : 'Reproductor web con recuperación automática. Primero intenta HLS; si no logra iniciar, prueba MPEG-TS.'}
                </p>
              )}
            </aside>
          </div>
        )}

        {!isLoading && !streamUrl && errorMessage && (
          <div className="state-card error-state">
            <h2>No se pudo cargar el canal</h2>
            <p>{errorMessage}</p>
          </div>
        )}
      </section>
    </main>
  );
}