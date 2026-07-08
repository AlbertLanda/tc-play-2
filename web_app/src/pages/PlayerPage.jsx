import { useEffect, useRef, useState } from 'react';
import Hls from 'hls.js';
import { getStreamUrl } from '../api/liveTvApi';

export function PlayerPage({ session, channel, onBack }) {
  const videoRef = useRef(null);

  const [streamUrl, setStreamUrl] = useState('');
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState('');

  useEffect(() => {
    async function loadStreamUrl() {
      try {
        setIsLoading(true);
        setErrorMessage('');

        const url = await getStreamUrl(
          session.username,
          session.password,
          channel.id,
          'm3u8',
        );

        setStreamUrl(url);
      } catch (error) {
        setErrorMessage(error.message || 'No se pudo cargar el canal.');
      } finally {
        setIsLoading(false);
      }
    }

    if (channel?.id) {
      loadStreamUrl();
    }
  }, [session.username, session.password, channel]);

  useEffect(() => {
    const video = videoRef.current;

    if (!video || !streamUrl) {
      return undefined;
    }

    let hls;

    if (Hls.isSupported()) {
      hls = new Hls();
      hls.loadSource(streamUrl);
      hls.attachMedia(video);

      hls.on(Hls.Events.ERROR, (_, data) => {
        if (data.fatal) {
          setErrorMessage('No se pudo reproducir el canal con HLS.');
        }
      });
    } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
      video.src = streamUrl;
    } else {
      setErrorMessage('Este navegador no soporta reproducción HLS.');
    }

    return () => {
      if (hls) {
        hls.destroy();
      }
    };
  }, [streamUrl]);

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

        {!isLoading && errorMessage && (
          <div className="state-card error-state">
            <h2>No se pudo reproducir el canal</h2>
            <p>{errorMessage}</p>
          </div>
        )}

        {!isLoading && !errorMessage && streamUrl && (
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
                {channel.icon ? (
                  <img src={channel.icon} alt={channel.name} />
                ) : (
                  <span>📺</span>
                )}
              </div>

              <h2>{channel.name}</h2>
              <p>ID: {channel.id}</p>
              <p>Categoría: {channel.category_id}</p>
              <p className="warning-text">
                Reproducción web con HLS. Si no carga, validar si Xtream entrega .m3u8
                correctamente o si existe bloqueo CORS/red.
              </p>
            </aside>
          </div>
        )}
      </section>
    </main>
  );
}