import { useState } from 'react';
import { loginRequest } from '../api/authApi';
import logoMark from '../assets/brand/tc-play-logo.png';
import {
  IconUser,
  IconLock,
  IconEye,
  IconEyeOff,
  IconAlert,
  IconTv,
} from '../components/Icons';

const BYPASS_LOGIN = import.meta.env.VITE_BYPASS_LOGIN === 'true';

export function LoginPage({ onLoginSuccess }) {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [rememberMe, setRememberMe] = useState(false);
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
    <main className="login-streaming-layout">
      <section className="login-visual-panel" aria-hidden="true">
        <div className="login-visual-glow" />
        <div className="login-orbit login-orbit-1" />
        <div className="login-orbit login-orbit-2" />
        <div className="login-orbit login-orbit-3" />

        <div className="login-visual-top">
          <a className="brand-mark" href="#" tabIndex={-1}>
            <img src={logoMark} alt="" />
            <span className="brand-mark-text">
              <strong>TC Play</strong>
              <span>2.0</span>
            </span>
          </a>
        </div>

        <div className="login-hero-copy">
          <span className="eyebrow-pill">
            <IconTv /> Televisión en vivo
          </span>
          <h1>Tus canales, siempre contigo.</h1>
          <p>
            Ingresa con tu usuario autorizado de Telecable y disfruta de TV en
            vivo directamente desde tu navegador, sin instalaciones.
          </p>
        </div>

        <div className="login-signal-row">
          <div className="login-signal-item">
            <strong>+80</strong>
            <span>Canales disponibles</span>
          </div>
          <div className="login-signal-item">
            <strong>HD</strong>
            <span>Señal en alta calidad</span>
          </div>
          <div className="login-signal-item">
            <strong>24/7</strong>
            <span>Disponible siempre</span>
          </div>
        </div>
      </section>

      <section className="login-form-panel">
        <form className="login-glass-card" onSubmit={handleSubmit}>
          <div className="login-card-brand">
            <img src={logoMark} alt="TC Play" />
          </div>

          <div className="login-card-header">
            <h1>Bienvenido a TC Play</h1>
            <p>Inicia sesión para disfrutar de televisión en vivo.</p>
          </div>

          <label className="login-field">
            <span className="login-field-label">Usuario</span>
            <span className="login-input-shell">
              <span className="login-input-icon">
                <IconUser />
              </span>
              <input
                type="text"
                placeholder="Tu usuario"
                value={username}
                autoComplete="username"
                onChange={(event) => setUsername(event.target.value)}
              />
            </span>
          </label>

          <label className="login-field">
            <span className="login-field-label">Contraseña</span>
            <span className="login-input-shell">
              <span className="login-input-icon">
                <IconLock />
              </span>
              <input
                type={showPassword ? 'text' : 'password'}
                placeholder="Tu contraseña"
                value={password}
                autoComplete="current-password"
                onChange={(event) => setPassword(event.target.value)}
              />
              <button
                type="button"
                className="login-eye-toggle"
                onClick={() => setShowPassword((value) => !value)}
                aria-label={
                  showPassword ? 'Ocultar contraseña' : 'Mostrar contraseña'
                }
              >
                {showPassword ? <IconEyeOff /> : <IconEye />}
              </button>
            </span>
          </label>

          <div className="login-row-between">
            <label className="login-remember">
              <input
                type="checkbox"
                checked={rememberMe}
                onChange={(event) => setRememberMe(event.target.checked)}
              />
              Recordarme
            </label>

            <button type="button" className="login-forgot-link">
              ¿Olvidaste tu contraseña?
            </button>
          </div>

          {errorMessage && (
            <div className="login-error-box">
              <IconAlert />
              <div>
                <strong>No pudimos iniciar sesión</strong>
                <span>{errorMessage}</span>
              </div>
            </div>
          )}

          <button
            type="submit"
            className="login-submit-button"
            disabled={isLoading}
          >
            {isLoading ? 'Validando acceso...' : 'Iniciar sesión'}
          </button>

          <p className="login-help-text">
            Servicio disponible para usuarios autorizados de Telecable.
          </p>
        </form>
      </section>
    </main>
  );
}
