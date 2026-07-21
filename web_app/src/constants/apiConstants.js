export const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || 'http://127.0.0.1:8000';

export const API_ENDPOINTS = {
  login: `${API_BASE_URL}/api/xtream/login/`,
  liveCategories: `${API_BASE_URL}/api/xtream/live/categories/`,
  liveStreams: `${API_BASE_URL}/api/xtream/live/streams/`,
  streamUrl: `${API_BASE_URL}/api/xtream/live/stream-url/`,
  proxyUrl: `${API_BASE_URL}/api/xtream/live/proxy-url/`,
  stopProxy: `${API_BASE_URL}/api/xtream/live/stop-proxy/`,
  hlsStatus: (streamId) =>
    `${API_BASE_URL}/api/xtream/live/hls-status/${streamId}/`,

  astraChannels: `${API_BASE_URL}/api/astra/channels/`,
  astraProxyUrl: `${API_BASE_URL}/api/astra/proxy-url/`,
  astraStopProxy: `${API_BASE_URL}/api/astra/stop-proxy/`,
};