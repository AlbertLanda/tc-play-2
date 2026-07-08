import { useState } from 'react';
import { loginRequest } from '../api/authApi';

export function LoginPage({ onLoginSuccess }) {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState('');

  async function handleSubmit(event) {
    event.preventDefault();

    if (!username.trim() || !password.trim()) {
      setErrorMessage('Ingrese usuario y contraseña.');
      return;
    }

    try {
      setIsLoading(true);
      setErrorMessage('');

      await loginRequest(username.trim(), password);

      onLoginSuccess();
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