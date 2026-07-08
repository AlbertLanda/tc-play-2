import { API_ENDPOINTS } from '../constants/apiConstants';

export async function getLiveCategories(username, password) {
  const response = await fetch(API_ENDPOINTS.liveCategories, {
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
    throw new Error(data.message || 'No se pudieron cargar las categorías.');
  }

  if (data.success !== true) {
    throw new Error(data.message || 'No se pudieron cargar las categorías.');
  }

  return data.categories || [];
}