import re
import requests

from django.conf import settings


_EXTINF_RE = re.compile(r'#EXTINF:[^,]*,(?P<name>.+)$')
_GROUP_RE = re.compile(r'group-title="(?P<group>[^"]*)"')
_TVG_LOGO_RE = re.compile(r'tvg-logo="(?P<logo>[^"]*)"')
_TVG_ID_RE = re.compile(r'tvg-id="(?P<tvg_id>[^"]*)"')


class AstraPlaylistError(Exception):
    """Error controlado al leer o procesar la playlist de Astra."""


def _extract(pattern, text, default=""):
    match = pattern.search(text or "")
    if not match:
        return default
    return next(iter(match.groupdict().values()), default)


def parse_m3u_playlist(content: str) -> list[dict]:
    """
    Convierte una playlist M3U/M3U8 en una lista de canales.
    Estructura esperada:
      #EXTINF:-1 tvg-id="..." tvg-logo="..." group-title="...",Canal
      http://...
    """
    channels = []
    pending_info = None

    lines = [line.strip() for line in content.splitlines() if line.strip()]

    for line in lines:
        if line.startswith("#EXTINF"):
            name_match = _EXTINF_RE.search(line)
            name = name_match.group("name").strip() if name_match else "Sin nombre"

            pending_info = {
                "name": name,
                "group": _extract(_GROUP_RE, line),
                "logo": _extract(_TVG_LOGO_RE, line),
                "tvg_id": _extract(_TVG_ID_RE, line),
            }
            continue

        if line.startswith("#"):
            continue

        if pending_info and line.startswith(("http://", "https://")):
            channel_number = len(channels) + 1

            channels.append({
                "id": f"astra-{channel_number}",
                "name": pending_info["name"],
                "group": pending_info["group"],
                "logo": pending_info["logo"],
                "tvg_id": pending_info["tvg_id"],
                "url": line,
                "source": "astra",
            })

            pending_info = None

    return channels


def get_astra_channels() -> list[dict]:
    playlist_url = getattr(settings, "ASTRA_PLAYLIST_URL", "")

    if not playlist_url:
        raise AstraPlaylistError("ASTRA_PLAYLIST_URL no está configurado.")

    try:
        response = requests.get(playlist_url, timeout=15)
        response.raise_for_status()
    except requests.RequestException as error:
        raise AstraPlaylistError("No se pudo obtener la playlist de Astra.") from error

    channels = parse_m3u_playlist(response.text)

    if not channels:
        raise AstraPlaylistError("La playlist de Astra no contiene canales válidos.")

    return channels