import { useEffect, useState } from 'react';
import { getLiveChannels } from '../api/liveTvApi';

export function ChannelsPage({ session, category, onBack }) {
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
    <main className="home-layout">
      <header className="home-header">
        <div>
          <h1>{category?.name || 'Canales'}</h1>
          <p>Canales disponibles - TC Play 2.0</p>
        </div>

        <button type="button" onClick={onBack}>
          Volver
        </button>
      </header>

      <section className="channels-content">
        {isLoading && <p className="state-message">Cargando canales...</p>}

        {!isLoading && errorMessage && (
          <div className="state-card error-state">
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
              <button type="button" className="channel-card" key={channel.id}>
                <div className="channel-logo">
                  {channel.icon ? (
                    <img src={channel.icon} alt={channel.name} />
                  ) : (
                    <span>📺</span>
                  )}
                </div>

                <div>
                  <h3>{channel.name}</h3>
                  <p>ID: {channel.id}</p>
                  <p>Categoría: {channel.category_id}</p>
                </div>
              </button>
            ))}
          </div>
        )}
      </section>
    </main>
  );
}