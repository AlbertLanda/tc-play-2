"""
Funciones para normalizar las respuestas crudas de Xtream antes de
enviarlas al frontend (Flutter).

El objetivo es exponer solo los campos que la app necesita y evitar
filtrar datos sensibles (password, server_info, infraestructura interna).
"""


def _to_int(value, default=0):
    """Convierte valores de Xtream (que suelen venir como string) a int."""
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def normalize_login(raw: dict) -> dict:
    """
    Recibe la respuesta cruda del login de Xtream y devuelve solo los
    campos seguros y necesarios para la app.

    No incluye: password, server_info ni datos internos del servidor.
    """
    user_info = (raw or {}).get("user_info") or {}

    return {
        "username": user_info.get("username"),
        "auth": _to_int(user_info.get("auth")),
        "status": user_info.get("status"),
        "is_active": user_info.get("status") == "Active",
        "max_connections": _to_int(user_info.get("max_connections")),
        "active_connections": _to_int(user_info.get("active_cons")),
        "exp_date": user_info.get("exp_date"),
    }


def normalize_categories(raw) -> list:
    """
    Recibe la lista cruda de categorías de Xtream y devuelve solo
    los campos que la app necesita: id y name.
    """
    if not isinstance(raw, list):
        return []

    return [
        {
            "id": item.get("category_id"),
            "name": item.get("category_name"),
        }
        for item in raw
    ]


def normalize_channels(raw) -> list:
    """
    Recibe la lista cruda de canales de Xtream y devuelve solo los
    campos necesarios para pintar la grilla en la app.
    """
    if not isinstance(raw, list):
        return []

    return [
        {
            "id": _to_int(item.get("stream_id")),
            "name": item.get("name"),
            "category_id": item.get("category_id"),
            "icon": item.get("stream_icon"),
            "stream_type": item.get("stream_type"),
        }
        for item in raw
    ]
