import { API_ENDPOINTS } from '../constants/apiConstants';

export async function loginRequest(username, password) {
  const response = await fetch(API_ENDPOINTS.login, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      username,
      password,
    }),
  });

  const data = await response.json();

  if (!response.ok) {
    throw new Error(data.message || data.detail || 'No se pudo iniciar sesión.');
  }

  if (data.success !== true) {
    throw new Error(data.message || data.detail || 'Usuario o contraseña incorrectos.');
  }

  return data;
}