import { API_ENDPOINTS } from '../constants/apiConstants';

export async function getAstraChannels() {
  const response = await fetch(API_ENDPOINTS.astraChannels);

  const data = await response.json();

  if (!response.ok || data.success !== true) {
    throw new Error(data.message || 'No se pudieron cargar los canales de Astra.');
  }

  return data.channels || [];
}

export async function getAstraProxyUrl(channelId) {
  const response = await fetch(API_ENDPOINTS.astraProxyUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      channel_id: channelId,
    }),
  });

  const data = await response.json();

  if (!response.ok || data.success !== true) {
    throw new Error(data.message || 'No se pudo generar el proxy de Astra.');
  }

  return data.hls_url;
}