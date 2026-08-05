import { useEffect, useState } from 'react';
import { getLiveChannels } from '../api/liveTvApi';
import { IconChevronLeft, IconTv } from '../components/Icons';

export function ChannelsPage({ session, category, onBack, onSelectChannel }) {
  const [channels, setChannels] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState('');

  useEffect(() => {
    async function loadChannels() {
      try {
        setIsLoading(true);
        setErrorMessage('');

        const data = await getLiveChannels(
          session.username,
          session.password,
          category.id,
        );

        setChannels(data);
      } catch (error) {
        setErrorMessage(error.message || 'No se pudieron cargar los canales.');
      } finally {
        setIsLoading(false);
      }
    }

    if (category?.id) {
      loadChannels();
    }
  }, [session.username, session.password, category]);

  return (
    <main className="page">
      <header className="page-header">
        <button
          type="button"
          className="icon-btn icon-btn-lg"
          onClick={onBack}
          aria-label="Volver"
        >
          <IconChevronLeft />
        </button>

        <div>
          <span className="eyebrow-pill">TC Play 2.0</span>
          <h1>{category?.name || 'Canales'}</h1>
          <p className="muted-text">Canales disponibles en esta categoría.</p>
        </div>
      </header>

      <section className="panel">
        {isLoading && <p className="state-message">Cargando canales...</p>}

        {!isLoading && errorMessage && (
          <div className="state-card">
            <h2>No se pudieron cargar los canales</h2>
            <p>{errorMessage}</p>
          </div>
        )}

        {!isLoading && !errorMessage && channels.length === 0 && (
          <div className="state-card">
            <h2>Sin canales disponibles</h2>
            <p>No hay canales asignados para esta categoría.</p>
          </div>
        )}

        {!isLoading && !errorMessage && channels.length > 0 && (
          <div className="channels-grid">
            {channels.map((channel) => (
              <button
                type="button"
                className="channel-card"
                key={channel.id}
                onClick={() => onSelectChannel(channel)}
              >
                <div className="channel-logo">
                  {channel.icon ? (
                    <img src={channel.icon} alt="" />
                  ) : (
                    <IconTv />
                  )}
                </div>

                <div className="channel-card-body">
                  <h3>{channel.name}</h3>
                  <span className="channel-live-tag">ID {channel.id}</span>
                </div>
              </button>
            ))}
          </div>
        )}
      </section>
    </main>
  );
}
