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
    <main className="home-layout">
      <header className="home-header">
        <div>
          <h1>TC Play 2.0</h1>
          <p>Bienvenido, {username}</p>
        </div>

        <button type="button" onClick={onLogout}>
          Cerrar sesión
        </button>
      </header>

      <section className="home-content home-dashboard">
        <div className="home-title-block">
          <h2>TV en vivo</h2>
          <p>Disfruta tus canales en vivo al instante.</p>
        </div>

        {homeErrorMessage && (
          <div className="state-card error-state">
            <h2>No se pudo abrir TV en vivo</h2>
            <p>{homeErrorMessage}</p>
          </div>
        )}

        <div className="home-menu-grid">
          <button
            type="button"
            className="home-menu-card home-menu-card-primary"
            onClick={onGoToAstra}
            disabled={isOpeningLiveTv}
          >
            <span className="home-menu-icon">📺</span>
            <h2>{isOpeningLiveTv ? 'Abriendo TV en vivo...' : 'Ver TV en vivo'}</h2>
            <p>Abre automáticamente un canal disponible y cambia entre señales con un toque.</p>
          </button>

          <HomeMenuCard
            icon="👤"
            title="Mi cuenta"
            description="Consulta información básica de tu servicio."
            onClick={() => alert('Módulo de cuenta pendiente.')}
          />
        </div>
      </section>
    </main>
  );
}