import { useState } from 'react';
import { loginRequest } from '../api/authApi';

const BYPASS_LOGIN = import.meta.env.VITE_BYPASS_LOGIN === 'true';

export function LoginPage({ onLoginSuccess }) {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState('');

  async function handleSubmit(event) {
    event.preventDefault();

    if (BYPASS_LOGIN) {
      const demoUsername = username.trim() || 'demo.staging';

      onLoginSuccess({
        username: demoUsername,
        password: password || 'demo',
        user: {
          username: demoUsername,
          status: 'Active',
          is_active: true,
        },
        bypass: true,
      });
      return;
    }

    if (!username.trim() || !password.trim()) {
      setErrorMessage('Ingresa tu usuario y contraseña.');
      return;
    }

    try {
      setIsLoading(true);
      setErrorMessage('');

      const data = await loginRequest(username.trim(), password);

      onLoginSuccess({
        username: username.trim(),
        password,
        user: data.user,
      });
    } catch (error) {
      setErrorMessage(
        error.message || 'No fue posible conectar con el servidor.',
      );
    } finally {
      setIsLoading(false);
    }
  }

  return (
    <main className="login-layout login-streaming-layout">
      <section className="login-visual-panel" aria-hidden="true">
        <div className="login-gradient-overlay" />

        <div className="login-floating-grid">
          <div className="floating-card card-live">LIVE</div>
          <div className="floating-card card-hd">HD</div>
          <div className="floating-card card-tv">TV</div>
          <div className="floating-card card-play">▶</div>
          <div className="floating-card card-247">24/7</div>
          <div className="floating-card card-tc">TC</div>
        </div>

        <div className="login-hero-copy">
          <span>TC PLAY 2.0</span>
          <h1>Televisión en vivo para clientes Telecable.</h1>
          <p>
            Accede con tu usuario autorizado y disfruta tus canales disponibles
            desde el navegador.
          </p>
        </div>
      </section>

      <section className="login-panel login-form-panel">
        <form className="login-card login-glass-card" onSubmit={handleSubmit}>
          <div className="login-card-header">
            <span className="login-brand-pill">TC PLAY 2.0</span>
            <h1>Inicia sesión</h1>
            <p>Ingresa tus datos para acceder a TV en vivo.</p>
          </div>

          <label className="login-field">
            <span>Usuario</span>
            <input
              type="text"
              placeholder="Ingresa tu usuario"
              value={username}
              autoComplete="username"
              onChange={(event) => setUsername(event.target.value)}
            />
          </label>

          <label className="login-field">
            <span>Contraseña</span>
            <div className="password-field">
              <input
                type={showPassword ? 'text' : 'password'}
                placeholder="Ingresa tu contraseña"
                value={password}
                autoComplete="current-password"
                onChange={(event) => setPassword(event.target.value)}
              />

              <button
                type="button"
                className="toggle-password-button"
                onClick={() => setShowPassword((value) => !value)}
              >
                {showPassword ? 'Ocultar' : 'Ver'}
              </button>
            </div>
          </label>

          {errorMessage && (
            <div className="login-error-box">
              <strong>No pudimos iniciar sesión</strong>
              <span>{errorMessage}</span>
            </div>
          )}

          <button
            type="submit"
            className="login-submit-button"
            disabled={isLoading}
          >
            {isLoading ? 'Validando acceso...' : 'Acceder a TC Play'}
          </button>

          <p className="login-help-text">
            Servicio disponible para usuarios autorizados de Telecable.
          </p>
        </form>
      </section>
    </main>
  );
}