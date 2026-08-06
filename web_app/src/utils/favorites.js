const STORAGE_KEY = 'tcplay:favoriteChannels';

function readStorage() {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    const parsed = raw ? JSON.parse(raw) : [];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function writeStorage(list) {
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(list));
  } catch {
    // Storage unavailable (private mode, quota, etc.) — fail silently,
    // favorites simply won't persist across reloads.
  }
}

export function getFavoriteChannels() {
  return readStorage();
}

export function isChannelFavorite(channel) {
  if (!channel?.id) return false;
  return readStorage().some((item) => item.id === channel.id);
}

export function toggleFavoriteChannel(channel) {
  if (!channel?.id) return false;

  const current = readStorage();
  const exists = current.some((item) => item.id === channel.id);

  if (exists) {
    writeStorage(current.filter((item) => item.id !== channel.id));
    return false;
  }

  const entry = {
    id: channel.id,
    name: channel.name,
    icon: channel.icon,
    logo: channel.logo,
    url: channel.stream_url || channel.url,
    isAstra: Boolean(channel.isAstra),
  };

  writeStorage([...current, entry]);
  return true;
}
