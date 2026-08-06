import { useEffect, useRef, useState } from 'react';
import Hls from 'hls.js';
import mpegts from 'mpegts.js';
import { getStreamUrl, getProxyStreamUrl, stopProxy } from '../api/liveTvApi';
import { getAstraProxyUrl, stopAstraProxy } from '../api/astraApi';
import { getChannelLogo } from '../constants/channelLogos';
import {
  IconChevronLeft,
  IconChevronRight,
  IconPlay,
  IconPause,
  IconExpand,
  IconCompress,
  IconTv,
  IconAlert,
  IconRefresh,
  IconSignal,
  IconSparkles,
} from '../components/Icons';

export function PlayerPage({
  session,
  channel,
  channels = [],
  currentChannelIndex = 0,
  onPreviousChannel,
  onNextChannel,
  onBack,
}) {
  const videoRef = useRef(null);
  const hlsRef = useRef(null);
  const tsPlayerRef = useRef(null);

  const hasTriedTsFallbackRef = useRef(false);
  const mediaErrorCountRef = useRef(0);
  const lastTimeRef = useRef(0);
  const stallTimerRef = useRef(null);
  const playerContainerRef = useRef(null);
  const controlsTimerRef = useRef(null);

  const [streamUrl, setStreamUrl] = useState('');
  const [playerMode, setPlayerMode] = useState('hls');
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState('');
  const [signalMessage, setSignalMessage] = useState('');
  const [showSignalOverlay, setShowSignalOverlay] = useState(false);
  const [isPlaying, setIsPlaying] = useState(false);
  const [showControls, setShowControls] = useState(true);
  const [isFullscreen, setIsFullscreen] = useState(false);

  useEffect(() => {
    function handleFullscreenChange() {
      setIsFullscreen(Boolean(document.fullscreenElement));
    }

    document.addEventListener('fullscreenchange', handleFullscreenChange);
    return () =>
      document.removeEventListener('fullscreenchange', handleFullscreenChange);
  }, []);

  function showSignalStatus(message) {
    setSignalMessage(message);
    setShowSignalOverlay(true);
  }

  function hideSignalStatus() {
    setShowSignalOverlay(false);
    setSignalMessage('');
  }

  function getFriendlyErrorMessage(message) {
    const normalizedMessage = String(message || '').toLowerCase();

    if (
      normalizedMessage.includes('ffmpeg') ||
      normalizedMessage.includes('hls') ||
      normalizedMessage.includes('transcoder') ||
      normalizedMessage.includes('proxy') ||
      normalizedMessage.includes('mpeg') ||
      normalizedMessage.includes('stream')
    ) {
      return 'La señal de este canal no está disponible temporalmente. Intenta nuevamente en unos segundos.';
    }

    return message || 'No se pudo cargar el canal. Intenta nuevamente.';
  }

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

  async function loadUrl() {
    if (channel?.isAstra && channel?.stream_url) {
      console.log('[TC Play] Stream URL Astra obtenida');
      return {
        url: channel.stream_url,
        mode: 'hls',
      };
    }

    const directUrl = await getStreamUrl(
      session.username,
      session.password,
      channel.id,
      'ts',
    );

    console.log('[TC Play] Stream directo Xtream obtenido');

    return {
      url: directUrl,
      mode: 'ts',
    };
  }

  async function switchToFallback() {
    if (hasTriedTsFallbackRef.current) {
      return;
    }

    try {
      showSignalStatus('Reconectando señal...');
      hasTriedTsFallbackRef.current = true;
      mediaErrorCountRef.current = 0;
      lastTimeRef.current = 0;
      setErrorMessage('');

      destroyPlayers();

      if (channel?.isAstra) {
        console.warn('[TC Play] Cambiando a proxy/transcoder Astra...');
        setPlayerMode('astra-proxy');

        const proxyUrl = await getAstraProxyUrl(channel.id);
        console.log('[TC Play] Astra proxy URL obtenida');

        setStreamUrl(proxyUrl);
        return;
      }

      console.warn('[TC Play] Cambiando a proxy HLS Xtream...');
      setPlayerMode('hls');

      const proxyUrl = await getProxyStreamUrl(
        session.username,
        session.password,
        channel.id,
      );

      console.log('[TC Play] Proxy URL Xtream obtenida');

      setStreamUrl(proxyUrl);
    } catch (error) {
      setErrorMessage(
        getFriendlyErrorMessage(error.message || 'No se pudo activar el fallback.'),
      );
      hideSignalStatus();
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
        } catch {
          console.warn('[TC Play] No se pudo recuperar HLS automáticamente');
        }
      }

      if (
        (playerMode === 'hls' || playerMode === 'ts') &&
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
        hideSignalStatus();
        setPlayerMode('hls');

        hasTriedTsFallbackRef.current = false;
        mediaErrorCountRef.current = 0;
        lastTimeRef.current = 0;

        const playback = await loadUrl();

        setPlayerMode(playback.mode);
        setStreamUrl(playback.url);
      } catch (error) {
        setErrorMessage(getFriendlyErrorMessage(error.message || 'No se pudo cargar el canal.'));
      } finally {
        setIsLoading(false);
      }
    }

    if (channel?.id) {
      preparePlayer();
    }

    return () => {
      if (controlsTimerRef.current) {
        clearTimeout(controlsTimerRef.current);
      }

      destroyPlayers();
    };

    // oxlint-disable-next-line react-hooks/exhaustive-deps
  }, [session.username, session.password, channel]);

  useEffect(() => {
    revealPlayerControls();

    return () => {
      if (controlsTimerRef.current) {
        clearTimeout(controlsTimerRef.current);
      }
    };
  }, [channel?.id]);

  useEffect(() => {
    const video = videoRef.current;

    if (!video || !streamUrl) {
      return undefined;
    }

    destroyPlayers();
    setErrorMessage('');

    const handleWaiting = () => {
      showSignalStatus('Cargando señal...');
    };

    const handleStalled = () => {
      showSignalStatus('Recuperando señal...');
    };

    const handlePlaying = () => {
      setIsPlaying(true);
      hideSignalStatus();
    };

    const handlePause = () => {
      setIsPlaying(false);
    };

    const handleCanPlay = () => {
      hideSignalStatus();
    };

    const handleVideoError = () => {
      showSignalStatus('Reconectando canal...');
    };

    video.addEventListener('waiting', handleWaiting);
    video.addEventListener('stalled', handleStalled);
    video.addEventListener('playing', handlePlaying);
    video.addEventListener('pause', handlePause);
    video.addEventListener('canplay', handleCanPlay);
    video.addEventListener('error', handleVideoError);

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
          hideSignalStatus();

          video.play().catch((error) => {
            console.warn(
              '[TC Play] Autoplay bloqueado. Presionar Play manualmente:',
              error,
            );
          });

          startPlaybackMonitor();
        });

        hls.on(Hls.Events.ERROR, (_, data) => {
          console.warn('[TC Play] HLS error detectado');

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
            } catch {
              console.warn('[TC Play] Recuperación HLS no fatal falló');
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
              } catch {
                console.warn('[TC Play] Recuperación fatal HLS falló');
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

        video.play().catch(() => {
          console.warn('[TC Play] Autoplay bloqueado');
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

        player.on(mpegts.Events.ERROR, () => {
          console.warn('[TC Play] MPEG-TS error detectado');

          if (video.currentTime > 0) {
            console.warn(
              '[TC Play] MPEG-TS reportó error, pero el video avanzó. Manteniendo player visible.',
            );
            return;
          }
          switchToFallback();
        });
      } else {
        setErrorMessage('Este navegador no soporta este tipo de reproducción.');
        hideSignalStatus();
      }
    }

    return () => {
      video.removeEventListener('waiting', handleWaiting);
      video.removeEventListener('stalled', handleStalled);
      video.removeEventListener('playing', handlePlaying);
      video.removeEventListener('pause', handlePause);
      video.removeEventListener('canplay', handleCanPlay);
      video.removeEventListener('error', handleVideoError);

      destroyPlayers();
    };
    
    // oxlint-disable-next-line react-hooks/exhaustive-deps
  }, [streamUrl, playerMode]);

  async function handleBack() {
    try {
      if (channel?.isAstra && channel?.id && playerMode === 'astra-proxy') {
        await stopAstraProxy(channel.id);
      }

      if (!channel?.isAstra && channel?.id) {
        await stopProxy(channel.id);
      }
    } catch {
      console.warn('[TC Play] No se pudo cerrar el proxy');
    } finally {
      onBack();
    }
  }

  async function handleRetry() {
    try {
      setIsLoading(true);
      setErrorMessage('');
      showSignalStatus('Reintentando canal...');

      destroyPlayers();

      if (channel?.isAstra && playerMode === 'astra-proxy') {
        await stopAstraProxy(channel.id);
      }

      if (!channel?.isAstra && channel?.id) {
        await stopProxy(channel.id);
      }

      hasTriedTsFallbackRef.current = false;
      mediaErrorCountRef.current = 0;
      lastTimeRef.current = 0;

      const playback = await loadUrl();

      setPlayerMode(playback.mode);
      setStreamUrl(playback.url);
    } catch (error) {
      setErrorMessage(getFriendlyErrorMessage(error.message));
      hideSignalStatus();
    } finally {
      setIsLoading(false);
    }
  }

  async function handlePreviousChannel() {
    if (!onPreviousChannel) return;

    try {
      showSignalStatus('Cambiando canal...');

      if (channel?.isAstra && channel?.id && playerMode === 'astra-proxy') {
        await stopAstraProxy(channel.id);
      }

      if (!channel?.isAstra && channel?.id) {
        await stopProxy(channel.id);
      }

      destroyPlayers();
      onPreviousChannel();
    } catch {
      console.warn('[TC Play] No se pudo cambiar al canal anterior');
      onPreviousChannel();
    }
  }

  async function handleNextChannel() {
    if (!onNextChannel) return;

    try {
      showSignalStatus('Cambiando canal...');

      if (channel?.isAstra && channel?.id && playerMode === 'astra-proxy') {
        await stopAstraProxy(channel.id);
      }

      if (!channel?.isAstra && channel?.id) {
        await stopProxy(channel.id);
      }

      destroyPlayers();
      onNextChannel();
    } catch {
      console.warn('[TC Play] No se pudo cambiar al siguiente canal');
      onNextChannel();
    }
  }

  async function handleFullscreen() {
    const element = playerContainerRef.current;

    if (!element) return;

    try {
      if (document.fullscreenElement) {
        await document.exitFullscreen();
        return;
      }

      await element.requestFullscreen();
    } catch {
      console.warn('[TC Play] No se pudo activar pantalla completa');
    }
  }

  async function handleTogglePlay() {
    const video = videoRef.current;

    if (!video) return;

    try {
      if (video.paused) {
        await video.play();
        setIsPlaying(true);
        return;
      }

      video.pause();
      setIsPlaying(false);
    } catch {
      console.warn('[TC Play] No se pudo alternar reproducción');
    }
  }

  function revealPlayerControls() {
    setShowControls(true);

    if (controlsTimerRef.current) {
      clearTimeout(controlsTimerRef.current);
    }

    controlsTimerRef.current = setTimeout(() => {
      setShowControls(false);
    }, 3000);
  }

  const channelLogo = channel ? getChannelLogo(channel) || channel.icon || channel.logo : null;

  return (
    <main className="player-layout">
      <header className="player-header">
        <button
          type="button"
          className="icon-btn icon-btn-lg"
          onClick={handleBack}
          aria-label="Volver"
        >
          <IconChevronLeft />
        </button>

        <div className="player-header-titles">
          <h1>{channel?.name || 'Reproductor'}</h1>
          <span>TC Play 2.0 · Reproducción en vivo</span>
        </div>
      </header>

      <section className="player-content">
        {isLoading && <p className="state-message">Preparando canal...</p>}

        {!isLoading && streamUrl && (
          <div className="player-wrapper">
            <div
              className="player-box"
              ref={playerContainerRef}
              onMouseMove={revealPlayerControls}
              onClick={revealPlayerControls}
              onTouchStart={revealPlayerControls}
            >
              <video
                ref={videoRef}
                className="video-player"
                playsInline
              >
                Tu navegador no soporta reproducción de video.
              </video>

              {showSignalOverlay && !errorMessage && (
                <div className="player-signal-overlay">
                  <div className="signal-loader" />
                  <p>{signalMessage || 'Cargando señal...'}</p>
                </div>                
              )}

              <div
                className={`player-zapping-controls ${
                  showControls ? 'player-zapping-controls-visible' : ''
                }`}
              >
                <button
                  type="button"
                  className="play-toggle"
                  onClick={handleTogglePlay}
                  aria-label={isPlaying ? 'Pausar' : 'Reproducir'}
                >
                  {isPlaying ? <IconPause /> : <IconPlay />}
                </button>

                <button
                  type="button"
                  onClick={handlePreviousChannel}
                  disabled={!onPreviousChannel}
                  aria-label="Canal anterior"
                >
                  <IconChevronLeft />
                </button>

                <div className="channel-counter">
                  {channels.length > 0
                    ? `${currentChannelIndex + 1} / ${channels.length}`
                    : 'TV en vivo'}
                </div>

                <button
                  type="button"
                  onClick={handleNextChannel}
                  disabled={!onNextChannel}
                  aria-label="Canal siguiente"
                >
                  <IconChevronRight />
                </button>

                <button
                  type="button"
                  onClick={handleFullscreen}
                  aria-label={
                    isFullscreen ? 'Salir de pantalla completa' : 'Pantalla completa'
                  }
                >
                  {isFullscreen ? <IconCompress /> : <IconExpand />}
                </button>
              </div>
            </div>

            <aside className="player-info">
              <div className="player-info-header">
                <div className="channel-logo large">
                  {channelLogo ? (
                    <img src={channelLogo} alt="" />
                  ) : (
                    <IconTv />
                  )}
                </div>

                <div>
                  <span className="live-pill">En vivo</span>
                  <h2>{channel.name}</h2>
                </div>
              </div>

              <div className="player-meta-grid">
                <div className="player-meta-item">
                  <span>
                    <IconSignal /> Estado
                  </span>
                  <strong>En vivo</strong>
                </div>

                <div className="player-meta-item">
                  <span>
                    <IconSparkles /> Calidad
                  </span>
                  <strong>Automática</strong>
                </div>

                <div className="player-meta-item">
                  <span>
                    <IconAlert /> Señal
                  </span>
                  <strong>{errorMessage ? 'Revisar' : 'Disponible'}</strong>
                </div>
              </div>
              {errorMessage ? (
                <div className="warning-text error-warning">
                  <div className="warning-copy">
                    <IconAlert />
                    <p>{errorMessage}</p>
                  </div>
                  <button type="button" className="retry-button" onClick={handleRetry}>
                    <IconRefresh /> Reintentar canal
                  </button>
                </div>
              ) : (
                <p className="warning-text">
                  <IconSparkles />
                  La señal se ajusta automáticamente para ofrecer una mejor reproducción.
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