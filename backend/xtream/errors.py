"""
Manejo uniforme de errores para los endpoints que consumen Xtream.

Convierte cualquier excepción en una respuesta consistente con la forma
{ "success": false, "error_code": "...", "message": "..." } y NUNCA
expone credenciales, URLs internas ni datos de infraestructura al frontend.
"""

import requests


def _payload(error_code: str, message: str) -> dict:
    return {
        "success": False,
        "error_code": error_code,
        "message": message,
    }


def build_error_response(error: Exception):
    """
    Mapea una excepción a una tupla (payload, http_status) uniforme.

    Devuelve un mensaje seguro y genérico; el detalle técnico no se
    envía al cliente para no filtrar información sensible.
    """
    # Tiempo de espera agotado al conectar con Xtream.
    if isinstance(error, requests.exceptions.Timeout):
        return _payload(
            "connection_timeout",
            "Tiempo de espera agotado al conectar con Xtream.",
        ), 504

    # Xtream respondió con un código HTTP de error (4xx / 5xx).
    if isinstance(error, requests.exceptions.HTTPError):
        status_code = getattr(error.response, "status_code", None)
        # Este panel Xtream devuelve 404/401/403 cuando las credenciales
        # de la línea de cliente no son válidas.
        if status_code in (401, 403, 404):
            return _payload(
                "invalid_credentials",
                "Usuario o contraseña incorrectos.",
            ), 401
        return _payload(
            "xtream_unavailable",
            "No se pudo conectar con el servicio de TV.",
        ), 502

    # No se pudo establecer conexión con el servidor de Xtream.
    if isinstance(error, requests.exceptions.ConnectionError):
        return _payload(
            "xtream_unavailable",
            "No se pudo conectar con el servicio de TV.",
        ), 502

    # Cualquier otro error no contemplado.
    return _payload(
        "unexpected_error",
        "Ocurrió un error inesperado.",
    ), 500
