import { useEffect, useMemo, useState } from 'react';
import { getAstraChannels } from '../api/astraApi';

export function AstraChannelsPage({ onBack, onSelectChannel }) {
  const [channels, setChannels] = useState([]);
  const [searchTerm, setSearchTerm] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState('');

  async function loadChannels() {
    try {
      setIsLoading(true);
      setErrorMessage('');

      const data = await getAstraChannels();
      setChannels(data);
    } catch (error) {
      setErrorMessage(error.message || 'Error al cargar canales de Astra.');
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    loadChannels();
  }, []);

  const filteredChannels = useMemo(() => {
    const value = searchTerm.trim().toLowerCase();

    if (!value) return channels;

    return channels.filter((channel) =>
      channel.name?.toLowerCase().includes(value)
    );
  }, [channels, searchTerm]);

  return (
    <main className="page">
      <section className="page-header">
        <button type="button" className="back-button" onClick={onBack}>
          ← Volver
        </button>

        <div>
          <p className="eyebrow">Fuente Astra</p>
          <h1>Canales HLS</h1>
          <p className="muted-text">
            Lista obtenida desde el backend Django para evitar consumir la IP directamente desde React.
          </p>
        </div>
      </section>

      <section className="panel">
        <div className="search-box">
          <input
            type="text"
            placeholder="Buscar canal Astra..."
            value={searchTerm}
            onChange={(event) => setSearchTerm(event.target.value)}
          />
        </div>

        {!isLoading && !errorMessage && (
          <p className="muted-text">
            Mostrando {filteredChannels.length} de {channels.length} canales.
          </p>
        )}

        {isLoading && (
          <div className="state-card">
            <h2>Cargando canales...</h2>
            <p>Consultando playlist de Astra.</p>
          </div>
        )}

        {errorMessage && (
          <div className="state-card">
            <h2>Error al cargar Astra</h2>
            <p>{errorMessage}</p>
            <button type="button" onClick={loadChannels}>
              Reintentar
            </button>
          </div>
        )}

        {!isLoading && !errorMessage && filteredChannels.length === 0 && (
          <div className="state-card">
            <h2>Sin resultados</h2>
            <p>No se encontraron canales con ese nombre.</p>
          </div>
        )}

        {!isLoading && !errorMessage && filteredChannels.length > 0 && (
          <div className="channels-grid">
            {filteredChannels.map((channel) => (
              <button
                type="button"
                className="channel-card"
                key={channel.id}
                onClick={() => onSelectChannel(channel)}
              >
                <div className="channel-logo">
                  {channel.logo ? (
                    <img src={channel.logo} alt={channel.name} />
                  ) : (
                    <span>📺</span>
                  )}
                </div>

                <div>
                  <h3>{channel.name}</h3>
                  <p>ID: {channel.id}</p>
                  <p>Fuente: {channel.source}</p>
                </div>
              </button>
            ))}
          </div>
        )}
      </section>
    </main>
  );
}