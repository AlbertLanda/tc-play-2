import { useEffect, useRef, useState } from 'react';
import Hls from 'hls.js';
import mpegts from 'mpegts.js';
import { getStreamUrl, getProxyStreamUrl, stopProxy } from '../api/liveTvApi';
import { getAstraProxyUrl, stopAstraProxy } from '../api/astraApi';
import { getChannelLogo } from '../constants/channelLogos';
import { isChannelFavorite, toggleFavoriteChannel } from '../utils/favorites';
import { createPlaybackSession } from '../utils/playbackSession';

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
  IconHeart,
} from '../components/Icons';

const ALLOW_STREAM_PROXY = import.meta.env.VITE_ENABLE_STREAM_PROXY === 'true';
const playbackApi = { getStreamUrl, getProxyStreamUrl, stopProxy, getAstraProxyUrl, stopAstraProxy };

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

  const playbackSessionRef = useRef(null);
  const fallbackRequestRef = useRef(null);
  const userPausedRef = useRef(false);
  const autoplayBlockedRef = useRef(false);
  const mediaErrorCountRef = useRef(0);
  const lastTimeRef = useRef(0);
  const stallTimerRef = useRef(null);
  const playerContainerRef = useRef(null);
  const controlsTimerRef = useRef(null);

  const [playback, setPlayback] = useState(null);
  const streamUrl = playback?.url || '';
  const playerMode = playback?.mode || 'hls';
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState('');
  const [signalMessage, setSignalMessage] = useState('');
  const [showSignalOverlay, setShowSignalOverlay] = useState(false);
  const [isPlaying, setIsPlaying] = useState(false);
  const [showControls, setShowControls] = useState(true);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [isFavorite, setIsFavorite] = useState(false);

  useEffect(() => {
    setIsFavorite(isChannelFavorite(channel));
  }, [channel]);

  function handleToggleFavorite() {
    if (!channel?.id) return;
    setIsFavorite(toggleFavoriteChannel(channel));
  }

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

  const video = videoRef.current;

  if (video) {
    try {
      video.pause();
      video.removeAttribute('src');
      video.load();
    } catch {
      console.warn('[TC Play] No se pudo limpiar el reproductor');
    }
  }
}

  function newPlaybackSession() {
    return createPlaybackSession({ channel, session, api: playbackApi, allowProxy: ALLOW_STREAM_PROXY });
  }

  function closeSession(playbackSession) {
    return playbackSession?.close().catch(() => {
      console.warn('[TC Play] No se pudo liberar la reproducción anterior');
    });
  }

  async function switchToFallback(playbackSession = playbackSessionRef.current) {
    if (!playbackSession || playbackSession.closed ||
        playbackSessionRef.current !== playbackSession ||
        fallbackRequestRef.current === playbackSession) return;

    fallbackRequestRef.current = playbackSession;
    try {
      showSignalStatus('Reconectando señal...');
      setErrorMessage('');
      destroyPlayers();
      mediaErrorCountRef.current = 0;
      lastTimeRef.current = 0;
      autoplayBlockedRef.current = false;
      const next = await playbackSession.fallback({
        canPlayTs: Boolean(mpegts.getFeatureList().mseLivePlayback),
      });
      if (next && playbackSessionRef.current === playbackSession && !playbackSession.closed) {
        setPlayback(next);
      }
    } catch (error) {
      if (playbackSessionRef.current === playbackSession && !playbackSession.closed) {
        setErrorMessage(getFriendlyErrorMessage(error.message));
        hideSignalStatus();
      }
    } finally {
      if (fallbackRequestRef.current === playbackSession) fallbackRequestRef.current = null;
    }
  }

  function startPlaybackMonitor(playbackSession) {
    const video = videoRef.current;
    let stalledCount = 0;
    if (!video) return;
    if (stallTimerRef.current) clearInterval(stallTimerRef.current);

    stallTimerRef.current = setInterval(() => {
      if (playbackSessionRef.current !== playbackSession || playbackSession.closed ||
          userPausedRef.current || autoplayBlockedRef.current || video.ended) return;
      const currentTime = video.currentTime;
      if (currentTime > lastTimeRef.current) {
        lastTimeRef.current = currentTime;
        stalledCount = 0;
        return;
      }
      stalledCount += 1;
      // This also covers startup: video.paused is true until the first frame.
      if (stalledCount >= 3) switchToFallback(playbackSession);
    }, 4000);
  }

  useEffect(() => {
    const playbackSession = newPlaybackSession();
    playbackSessionRef.current = playbackSession;
    setPlayback(null);
    setIsLoading(true);
    setErrorMessage('');
    hideSignalStatus();
    userPausedRef.current = false;
    autoplayBlockedRef.current = false;
    mediaErrorCountRef.current = 0;
    lastTimeRef.current = 0;

    playbackSession.start().then((next) => {
      if (next && playbackSessionRef.current === playbackSession && !playbackSession.closed) {
        setPlayback(next);
      }
    }).catch((error) => {
      if (playbackSessionRef.current === playbackSession && !playbackSession.closed) {
        setErrorMessage(getFriendlyErrorMessage(error.message));
      }
    }).finally(() => {
      if (playbackSessionRef.current === playbackSession && !playbackSession.closed) setIsLoading(false);
    });

    return () => {
      if (playbackSessionRef.current === playbackSession) playbackSessionRef.current = null;
      closeSession(playbackSession);
      if (controlsTimerRef.current) clearTimeout(controlsTimerRef.current);
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

    const playbackSession = playbackSessionRef.current;
    if (isLoading || !video || !streamUrl || !playbackSession || playbackSession.closed) {
      return undefined;
    }

    destroyPlayers();
    setErrorMessage('');
    const isCurrent = () => playbackSessionRef.current === playbackSession &&
      !playbackSession.closed && playbackSession.current === playback;
    const tryPlay = () => {
      video.play().catch((error) => {
        if (!isCurrent()) return;
        if (error.name === 'NotAllowedError') {
          autoplayBlockedRef.current = true;
          showSignalStatus('Presiona reproducir para iniciar el canal.');
        } else if (error.name !== 'AbortError') {
          switchToFallback(playbackSession);
        }
      });
    };

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
      if (isCurrent()) switchToFallback(playbackSession);
    };

    video.addEventListener('waiting', handleWaiting);
    video.addEventListener('stalled', handleStalled);
    video.addEventListener('playing', handlePlaying);
    video.addEventListener('pause', handlePause);
    video.addEventListener('canplay', handleCanPlay);
    video.addEventListener('error', handleVideoError);

    startPlaybackMonitor(playbackSession);

    if (playerMode === 'hls' || playerMode === 'astra-proxy' || playerMode === 'xtream-proxy') {
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
          if (!isCurrent()) return;
          console.info('[TC Play] Reproducción HLS iniciada');
          hideSignalStatus();

          tryPlay();
        });

        hls.on(Hls.Events.ERROR, (_, data) => {
          if (!isCurrent()) return;
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
              mediaErrorCountRef.current >= 20 &&
              video.currentTime === 0
            ) {
              switchToFallback(playbackSession);
            }

            return;
          }

          if (type === Hls.ErrorTypes.NETWORK_ERROR) {
            console.warn('[TC Play] Error fatal de red. Activando fallback...');
            switchToFallback(playbackSession);
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

            switchToFallback(playbackSession);
            return;
          }

          switchToFallback(playbackSession);
        });
      } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
        video.src = streamUrl;

        tryPlay();
      } else {
        switchToFallback(playbackSession);
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

        tryPlay();

        player.on(mpegts.Events.ERROR, () => {
          if (!isCurrent()) return;
          console.warn('[TC Play] MPEG-TS error detectado');

          if (video.currentTime > 0) {
            console.warn(
              '[TC Play] MPEG-TS reportó error, pero el video avanzó. Manteniendo player visible.',
            );
            return;
          }
          switchToFallback(playbackSession);
        });
      } else {
        switchToFallback(playbackSession);
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
  }, [playback, isLoading]);

  function leaveChannel() {
    const playbackSession = playbackSessionRef.current;
    playbackSessionRef.current = null;
    closeSession(playbackSession);
    destroyPlayers();
    setPlayback(null);
    setIsPlaying(false);
    setErrorMessage('');
    hideSignalStatus();
  }

  function handleBack() {
    leaveChannel();
    onBack();
  }

  async function handleRetry() {
    const previous = playbackSessionRef.current;
    const replacement = newPlaybackSession();
    playbackSessionRef.current = replacement;
    destroyPlayers();
    setPlayback(null);
    setIsLoading(true);
    setErrorMessage('');
    hideSignalStatus();
    userPausedRef.current = false;
    autoplayBlockedRef.current = false;
    mediaErrorCountRef.current = 0;
    lastTimeRef.current = 0;
    try {
      await closeSession(previous);
      if (playbackSessionRef.current !== replacement) return;
      const next = await replacement.start();
      if (next && playbackSessionRef.current === replacement && !replacement.closed) setPlayback(next);
    } catch (error) {
      if (playbackSessionRef.current === replacement && !replacement.closed) {
        setErrorMessage(getFriendlyErrorMessage(error.message));
      }
    } finally {
      if (playbackSessionRef.current === replacement && !replacement.closed) setIsLoading(false);
    }
  }

  function handlePreviousChannel() {
    if (!onPreviousChannel) return;
    leaveChannel();
    onPreviousChannel();
  }

  function handleNextChannel() {
    if (!onNextChannel) return;
    leaveChannel();
    onNextChannel();
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
        userPausedRef.current = false;
        autoplayBlockedRef.current = false;
        await video.play();
        setIsPlaying(true);
        return;
      }

      userPausedRef.current = true;
      video.pause();
      setIsPlaying(false);
    } catch {
      autoplayBlockedRef.current = true;
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
                className={`player-side-nav player-side-nav-prev ${
                  showControls ? 'player-side-nav-visible' : ''
                }`}
              >
                <button
                  type="button"
                  className="side-nav-btn"
                  onClick={handlePreviousChannel}
                  disabled={!onPreviousChannel}
                  aria-label="Canal anterior"
                >
                  <IconChevronLeft />
                </button>
              </div>

              <div
                className={`player-side-nav player-side-nav-next ${
                  showControls ? 'player-side-nav-visible' : ''
                }`}
              >
                <button
                  type="button"
                  className="side-nav-btn"
                  onClick={handleNextChannel}
                  disabled={!onNextChannel}
                  aria-label="Canal siguiente"
                >
                  <IconChevronRight />
                </button>
              </div>

              <button
                type="button"
                className={`fullscreen-btn ${
                  showControls ? 'fullscreen-btn-visible' : ''
                }`}
                onClick={handleFullscreen}
                aria-label={
                  isFullscreen ? 'Salir de pantalla completa' : 'Pantalla completa'
                }
              >
                {isFullscreen ? <IconCompress /> : <IconExpand />}
              </button>

              <div
                className={`player-bottom-bar ${
                  showControls ? 'player-bottom-bar-visible' : ''
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

                <div className="bottom-bar-status">
                  <span className="bottom-bar-live-dot" />
                  <span className="bottom-bar-channel-name">{channel?.name}</span>
                </div>

                <div className="channel-counter">
                  {channels.length > 0
                    ? `${currentChannelIndex + 1} / ${channels.length}`
                    : 'TV en vivo'}
                </div>
              </div>
            </div>

            <aside className="player-info">
              <button
                type="button"
                className={`player-favorite-toggle ${isFavorite ? 'is-active' : ''}`}
                onClick={handleToggleFavorite}
                aria-pressed={isFavorite}
                aria-label={
                  isFavorite ? 'Quitar de favoritos' : 'Agregar a favoritos'
                }
              >
                <IconHeart filled={isFavorite} />
              </button>

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