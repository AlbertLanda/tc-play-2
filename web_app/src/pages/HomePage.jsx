import { HomeMenuCard } from '../components/HomeMenuCard';

export function HomePage({
  session,
  onLogout,
  onGoToAstra,
  isOpeningLiveTv = false,
  homeErrorMessage = '',
}) {
  const username = session?.user?.username || session?.username || 'Usuario';

  return (
    <main className="home-layout streaming-home">
      <header className="streaming-header">
        <div className="brand-area">
          <span className="brand-pill">TC PLAY 2.0</span>
          <nav className="streaming-nav" aria-label="Navegación principal">
            <button type="button">Inicio</button>
            <button type="button" onClick={onGoToAstra}>
              TV en vivo
            </button>
            <button type="button">Mi cuenta</button>
          </nav>
        </div>

        <div className="header-actions">
          <span className="user-chip">Hola, {username}</span>
          <button type="button" className="logout-button" onClick={onLogout}>
            Cerrar sesión
          </button>
        </div>
      </header>

      <section className="streaming-hero">
        <div className="hero-backdrop">
          <div className="hero-tile hero-tile-1">TV</div>
          <div className="hero-tile hero-tile-2">HD</div>
          <div className="hero-tile hero-tile-3">LIVE</div>
          <div className="hero-tile hero-tile-4">▶</div>
          <div className="hero-tile hero-tile-5">TC</div>
          <div className="hero-tile hero-tile-6">24/7</div>
        </div>

        <div className="hero-content">
          <span className="hero-kicker">Televisión en vivo para clientes Telecable</span>

          <h1>
            Tus canales favoritos,
            <br />
            en vivo y en un solo lugar.
          </h1>

          <p>
            Accede a la señal disponible desde tu navegador, busca tus canales
            y reproduce TV en vivo de forma simple.
          </p>

          <div className="hero-actions">
            <button
              type="button"
              className="hero-primary-button"
              onClick={onGoToAstra}
              disabled={isOpeningLiveTv}
            >
              {isOpeningLiveTv ? 'Preparando TV en vivo...' : 'Ver TV en vivo'}
            </button>

            <span className="hero-note">
              Incluido para usuarios autorizados de Telecable.
            </span>
          </div>

          {homeErrorMessage && (
            <div className="hero-error">
              <strong>No se pudo abrir TV en vivo.</strong>
              <span>{homeErrorMessage}</span>
            </div>
          )}
        </div>
      </section>

      <section className="streaming-sections">
        <div className="section-title-row">
          <div>
            <span className="section-kicker">TV en vivo</span>
            <h2>Empieza a ver</h2>
          </div>
        </div>

        <div className="home-menu-grid streaming-menu-grid">
          <button
            type="button"
            className="home-menu-card home-menu-card-primary"
            onClick={onGoToAstra}
            disabled={isOpeningLiveTv}
          >
            <span className="home-menu-icon">📺</span>
            <h2>{isOpeningLiveTv ? 'Cargando canales...' : 'Ver canales en vivo'}</h2>
            <p>
              Explora la lista de canales disponibles y elige qué señal reproducir.
            </p>
          </button>

          <HomeMenuCard
            icon="👤"
            title="Mi cuenta"
            description="Consulta la información básica de tu servicio."
            onClick={() => alert('Módulo de cuenta pendiente.')}
          />
        </div>
      </section>
    </main>
  );
}