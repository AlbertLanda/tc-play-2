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

export async function getLiveChannels(username, password, categoryId) {
  const response = await fetch(API_ENDPOINTS.liveStreams, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      username,
      password,
      category_id: categoryId,
    }),
  });

  const data = await response.json();

  if (!response.ok) {
    throw new Error(data.message || 'No se pudieron cargar los canales.');
  }

  if (data.success !== true) {
    throw new Error(data.message || 'No se pudieron cargar los canales.');
  }

  return data.channels || [];
}

export async function getStreamUrl(username, password, streamId, output = 'm3u8') {
  const response = await fetch(API_ENDPOINTS.streamUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      username,
      password,
      stream_id: streamId,
      output,
    }),
  });

  const data = await response.json();

  if (!response.ok) {
    throw new Error(data.message || 'No se pudo obtener la URL de reproducción.');
  }

  if (data.success !== true) {
    throw new Error(data.message || 'No se pudo obtener la URL de reproducción.');
  }

  return data.stream_url;
}