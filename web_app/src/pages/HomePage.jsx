import { useEffect, useState } from 'react';
import { getAstraChannels } from '../api/astraApi';
import { AccountMenu } from '../components/AccountMenu';
import { ChannelRail } from '../components/ChannelRail';
import logoMark from '../assets/brand/tc-play-logo.png';
import { IconHome, IconTv, IconAlert } from '../components/Icons';

export function HomePage({
  session,
  onLogout,
  onGoToAstra,
  onSelectChannel,
  isOpeningLiveTv = false,
  homeErrorMessage = '',
  favoriteChannels = [],
}) {
  const username = session?.user?.username || session?.username || 'Usuario';

  const [channels, setChannels] = useState([]);
  const [isLoadingChannels, setIsLoadingChannels] = useState(true);

  useEffect(() => {
    let isMounted = true;

    getAstraChannels()
      .then((data) => {
        if (isMounted) setChannels(data);
      })
      .catch(() => {
        // The hero CTA / "Ver TV en vivo" flow already surfaces load errors;
        // the home rails simply stay empty if this quiet fetch fails.
      })
      .finally(() => {
        if (isMounted) setIsLoadingChannels(false);
      });

    return () => {
      isMounted = false;
    };
  }, []);

  const favoriteIds = new Set(favoriteChannels.map((item) => item.id));

  const recommendedSource = channels.filter(
    (channel) => !favoriteIds.has(channel.id),
  );
  const recommendedChannels =
    recommendedSource.length > 12
      ? recommendedSource.slice(0, 12)
      : [...recommendedSource].reverse();

  function handleSelectFromRail(channel) {
    onSelectChannel(channel, channels.length ? channels : favoriteChannels);
  }

  return (
    <main className="streaming-home">
      <header className="streaming-header">
        <div className="brand-area">
          <a className="brand-mark" href="#" onClick={(event) => event.preventDefault()}>
            <img src={logoMark} alt="TC Play" />
            <span className="brand-mark-text">
              <strong>TC Play</strong>
              <span>2.0</span>
            </span>
          </a>

          <nav className="streaming-nav" aria-label="Navegación principal">
            <button type="button" className="is-active">
              <IconHome /> Inicio
            </button>
            <button type="button" onClick={onGoToAstra}>
              <IconTv /> TV en vivo
            </button>
          </nav>
        </div>

        <div className="header-actions">
          <AccountMenu username={username} onLogout={onLogout} />
        </div>
      </header>

      <section className="streaming-hero">
        <div className="hero-glow" />
        <div className="hero-ring" />

        <div className="hero-content">
          <span className="eyebrow-pill">
            <IconTv /> Televisión en vivo para clientes Telecable
          </span>

          <h1>Tus canales favoritos, en un solo lugar.</h1>

          <p>
            Accede a la señal disponible desde tu navegador, busca tus canales
            y reproduce TV en vivo de forma simple y sin interrupciones.
          </p>

          <div className="hero-actions">
            <button
              type="button"
              className="hero-primary-button"
              onClick={onGoToAstra}
              disabled={isOpeningLiveTv}
            >
              <IconTv />
              {isOpeningLiveTv ? 'Preparando TV en vivo...' : 'Ver TV en vivo'}
            </button>

            <span className="hero-note">
              Incluido para usuarios autorizados de Telecable.
            </span>
          </div>

          {homeErrorMessage && (
            <div className="hero-error">
              <IconAlert />
              <div>
                <strong>No se pudo abrir TV en vivo.</strong>
                <span>{homeErrorMessage}</span>
              </div>
            </div>
          )}
        </div>
      </section>

      <section className="streaming-sections">
        <ChannelRail
          title="Canales favoritos"
          eyebrow="Para ti"
          channels={favoriteChannels}
          onSelectChannel={handleSelectFromRail}
          onSeeAll={onGoToAstra}
        />

        <ChannelRail
          title="Recomendados"
          eyebrow="Descubre"
          channels={isLoadingChannels ? [] : recommendedChannels}
          onSelectChannel={handleSelectFromRail}
          onSeeAll={onGoToAstra}
        />
      </section>
    </main>
  );
}
