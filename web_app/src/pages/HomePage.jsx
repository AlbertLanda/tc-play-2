import { HomeMenuCard } from '../components/HomeMenuCard';

export function HomePage({
  session,
  onLogout,
  onGoToCategories,
  onGoToAstra,
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
          <h2>Panel principal</h2>
          <p>Selecciona una opción para continuar.</p>
        </div>

        <div className="home-menu-grid">
          <HomeMenuCard
            icon="📺"
            title="TV en vivo"
            description="Explorar categorías y canales disponibles desde Xtream."
            onClick={onGoToCategories}
          />

          <HomeMenuCard
            icon="🛰️"
            title="Canales Astra"
            description="Reproducir canales HLS desde la playlist técnica de Astra."
            onClick={onGoToAstra}
          />

          <HomeMenuCard
            icon="🗂️"
            title="Categorías"
            description="Ver agrupaciones de canales por plan o contenido."
            onClick={onGoToCategories}
          />

          <HomeMenuCard
            icon="👤"
            title="Mi cuenta"
            description="Información básica del usuario conectado."
            onClick={() => alert('Módulo de cuenta pendiente.')}
          />
        </div>
      </section>
    </main>
  );
}