from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status

from .services.client import XtreamClient
from .services import transcoder
from .normalizers import normalize_login, normalize_categories, normalize_channels
from .errors import build_error_response


@api_view(["POST"])
def xtream_login(request):
    username = request.data.get("username")
    password = request.data.get("password")

    if not username or not password:
        return Response(
            {
                "success": False,
                "error_code": "missing_credentials",
                "message": "Usuario y contraseña son obligatorios."
            },
            status=status.HTTP_400_BAD_REQUEST
        )

    try:
        client = XtreamClient()
        data = client.authenticate(username, password)

        user = normalize_login(data)

        # Xtream responde HTTP 200 con auth: 0 cuando las credenciales
        # son incorrectas, por eso se valida aquí y no en el except.
        if user["auth"] != 1:
            return Response(
                {
                    "success": False,
                    "error_code": "invalid_credentials",
                    "message": "Usuario o contraseña incorrectos."
                },
                status=status.HTTP_401_UNAUTHORIZED
            )

        # La línea autenticó (auth == 1) pero solo puede ingresar si la
        # cuenta está activa. Si status no es "Active" (vencida, deshabilitada,
        # baneada, etc.) se bloquea el acceso con inactive_account.
        if not user["is_active"]:
            return Response(
                {
                    "success": False,
                    "error_code": "inactive_account",
                    "message": "La cuenta no se encuentra activa."
                },
                status=status.HTTP_403_FORBIDDEN
            )

        return Response({
            "success": True,
            "user": user
        })

    except Exception as error:
        payload, http_status = build_error_response(error)
        return Response(payload, status=http_status)


@api_view(["POST"])
def live_categories(request):
    username = request.data.get("username")
    password = request.data.get("password")

    if not username or not password:
        return Response(
            {
                "success": False,
                "error_code": "missing_credentials",
                "message": "Usuario y contraseña son obligatorios."
            },
            status=status.HTTP_400_BAD_REQUEST
        )

    try:
        client = XtreamClient()
        data = client.get_live_categories(username, password)

        return Response({
            "success": True,
            "categories": normalize_categories(data)
        })

    except Exception as error:
        payload, http_status = build_error_response(error)
        return Response(payload, status=http_status)


@api_view(["POST"])
def live_streams(request):
    username = request.data.get("username")
    password = request.data.get("password")
    category_id = request.data.get("category_id")

    if not username or not password:
        return Response(
            {
                "success": False,
                "error_code": "missing_credentials",
                "message": "Usuario y contraseña son obligatorios."
            },
            status=status.HTTP_400_BAD_REQUEST
        )

    try:
        client = XtreamClient()
        data = client.get_live_streams(username, password, category_id)

        return Response({
            "success": True,
            "channels": normalize_channels(data)
        })

    except Exception as error:
        payload, http_status = build_error_response(error)
        return Response(payload, status=http_status)
    
@api_view(["POST"])
def live_stream_url(request):
    username = request.data.get("username")
    password = request.data.get("password")
    stream_id = request.data.get("stream_id")
    output = request.data.get("output", "ts")

    if not username or not password or not stream_id:
        return Response(
            {
                "success": False,
                "error_code": "missing_credentials",
                "message": "Usuario, contraseña y stream_id son obligatorios."
            },
            status=status.HTTP_400_BAD_REQUEST
        )

    try:
        client = XtreamClient()
        stream_url = client.build_live_stream_url(
            username=username,
            password=password,
            stream_id=stream_id,
            output=output
        )

        return Response({
            "success": True,
            "stream_url": stream_url
        })

    except Exception as error:
        payload, http_status = build_error_response(error)
        return Response(payload, status=http_status)


@api_view(["POST"])
def live_proxy_url(request):
    """
    Endpoint experimental de proxy/transcoder HLS.

    Toma un stream original de Xtream, lanza FFmpeg y devuelve una URL HLS
    limpia (index.m3u8) que el web player puede consumir cuando un canal no
    reproduce directo. La URL original con credenciales NUNCA se devuelve.
    """
    username = request.data.get("username")
    password = request.data.get("password")
    stream_id = request.data.get("stream_id")

    if not username or not password or not stream_id:
        return Response(
            {
                "success": False,
                "error_code": "validation_error",
                "message": "Usuario, contraseña y stream_id son obligatorios."
            },
            status=status.HTTP_400_BAD_REQUEST
        )

    # Saneamiento del stream_id: solo alfanuméricos (evita path traversal
    # al usarlo como nombre de carpeta de salida HLS).
    try:
        safe_stream_id = transcoder.sanitize_stream_id(stream_id)
    except ValueError:
        return Response(
            {
                "success": False,
                "error_code": "validation_error",
                "message": "stream_id inválido."
            },
            status=status.HTTP_400_BAD_REQUEST
        )

    try:
        # URL original de Xtream (entrada para FFmpeg). Se usa el formato TS
        # crudo del canal en vivo; no se expone en la respuesta.
        client = XtreamClient()
        source_url = client.build_live_stream_url(
            username=username,
            password=password,
            stream_id=safe_stream_id,
            output="ts",
        )

        # Si XTREAM_BASE_URL no está configurado, la URL saldría incompleta
        # (sin http://host) y FFmpeg fallaría más adelante. Se corta aquí con
        # stream_url_error para no lanzar un proceso inútil.
        if not source_url.lower().startswith(("http://", "https://")):
            raise transcoder.StreamUrlError(
                "No se pudo construir la URL original del stream."
            )

        _, reused, mode = transcoder.start_hls_transcode(
            source_url, safe_stream_id
        )

        if not reused and not transcoder.wait_for_hls_index(safe_stream_id):
            return Response(
                {
                    "success": False,
                    "error_code": "hls_output_error",
                    "message": "FFmpeg inició, pero no generó la salida HLS."
                },
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )

        return Response({
            "success": True,
            "stream_id": safe_stream_id,
            "hls_url": transcoder.build_hls_url(request, safe_stream_id),
            "mode": mode,
            "reused": reused,
        })

    except transcoder.TranscoderError as error:
        return Response(
            {
                "success": False,
                "error_code": error.error_code,
                "message": str(error),
            },
            status=error.http_status
        )

    except Exception as error:
        payload, http_status = build_error_response(error)
        return Response(payload, status=http_status)