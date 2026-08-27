export function HomePage({ onLogout }) {
  return (
    <main className="home-layout">
      <header className="home-header">
        <h1>TC Play 2.0</h1>
        <button type="button" onClick={onLogout}>
          Cerrar sesión
        </button>
      </header>

      <section className="home-content">
        <div className="home-card success-card">
          <span>✓</span>
          <h2>¡Inicio de sesión exitoso!</h2>
          <p>Bienvenido a TC Play 2.0</p>
        </div>
      </section>
    </main>
  );
}