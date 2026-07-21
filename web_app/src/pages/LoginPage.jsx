import { useState } from 'react';
import { loginRequest } from '../api/authApi';

const BYPASS_LOGIN = import.meta.env.VITE_BYPASS_LOGIN === 'true';

export function LoginPage({ onLoginSuccess }) {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState('');

  async function handleSubmit(event) {
    event.preventDefault();

    if (BYPASS_LOGIN) {
      onLoginSuccess({
        username: username.trim() || 'demo.staging',
        password: password || 'demo',
        user: {
          username: username.trim() || 'demo.staging',
          status: 'Active',
          is_active: true,
        },
        bypass: true,
      });
      return;
    }

    if (!username.trim() || !password.trim()) {
      setErrorMessage('Ingrese usuario y contraseña.');
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
      setErrorMessage(error.message || 'No fue posible conectar con el servidor.');
    } finally {
      setIsLoading(false);
    }
  }

  return (
    <main className="login-layout">
      <section className="login-panel">
        <form className="login-card" onSubmit={handleSubmit}>
          <h1>DETALLES DE ACCESO</h1>

          <input
            type="text"
            placeholder="Usuario"
            value={username}
            onChange={(event) => setUsername(event.target.value)}
          />

          <input
            type="password"
            placeholder="Contraseña"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
          />

          {errorMessage && <p className="error-message">{errorMessage}</p>}

          <button type="submit" disabled={isLoading}>
            {isLoading ? 'VALIDANDO...' : 'ACCEDER'}
          </button>
        </form>
      </section>

      <section className="brand-panel">
        <h2>TC Play 2.0</h2>
      </section>
    </main>
  );
}