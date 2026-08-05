import { useEffect, useMemo, useState } from 'react';
import { getAstraChannels } from '../api/astraApi';
import { getChannelLogo } from '../constants/channelLogos';
import { IconChevronLeft, IconSearch, IconTv, IconRefresh } from '../components/Icons';

export function AstraChannelsPage({
  channels: initialChannels = [],
  onBack,
  onSelectChannel,
}) {
  const [channels, setChannels] = useState(initialChannels);
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
      setErrorMessage(error.message || 'Error al cargar canales de TV en vivo.');
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    if (initialChannels.length > 0) {
      setChannels(initialChannels);
      return;
    }

    loadChannels();
    // oxlint-disable-next-line react-hooks/exhaustive-deps
  }, [initialChannels]);

  const filteredChannels = useMemo(() => {
    const value = searchTerm.trim().toLowerCase();

    if (!value) return channels;

    return channels.filter((channel) =>
      channel.name?.toLowerCase().includes(value)
    );
  }, [channels, searchTerm]);

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
          <h1>TV en vivo</h1>
          <p className="muted-text">
            Elige un canal para iniciar la reproducción.
          </p>
        </div>
      </header>

      <section className="panel">
        <div className="search-box">
          <IconSearch />
          <input
            type="text"
            placeholder="Buscar canal..."
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
            <p>Preparando la lista de TV en vivo.</p>
          </div>
        )}

        {errorMessage && (
          <div className="state-card">
            <h2>No se pudieron cargar los canales</h2>
            <p>{errorMessage}</p>
            <button type="button" onClick={loadChannels}>
              <IconRefresh /> Reintentar
            </button>
          </div>
        )}

        {!isLoading && !errorMessage && filteredChannels.length === 0 && (
          <div className="state-card">
            <h2>Sin resultados</h2>
            <p>No encontramos canales con ese nombre.</p>
          </div>
        )}

        {!isLoading && !errorMessage && filteredChannels.length > 0 && (
          <div className="channels-grid">
            {filteredChannels.map((channel) => {
              const logo = getChannelLogo(channel);

              return (
                <button
                  type="button"
                  className="channel-card"
                  key={channel.id}
                  onClick={() => onSelectChannel(channel)}
                >
                  <div className="channel-logo">
                    {logo ? <img src={logo} alt="" /> : <IconTv />}
                  </div>

                  <div className="channel-card-body">
                    <h3>{channel.name}</h3>
                    <span className="channel-live-tag">En vivo</span>
                  </div>
                </button>
              );
            })}
          </div>
        )}
      </section>
    </main>
  );
}
