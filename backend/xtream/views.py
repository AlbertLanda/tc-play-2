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
            transcoder.stop_hls_transcode(safe_stream_id)
            transcoder.remove_hls_output(safe_stream_id)

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


@api_view(["POST"])
def live_stop_proxy(request):
    """
    Detiene el proceso FFmpeg asociado a un stream_id de Xtream y borra su
    salida HLS, para que un canal cerrado no deje procesos vivos ni carpetas
    muertas reutilizables. Equivalente al stop-proxy de Astra.
    """
    stream_id = request.data.get("stream_id")

    if not stream_id:
        return Response(
            {
                "success": False,
                "error_code": "missing_stream_id",
                "message": "El campo stream_id es obligatorio.",
            },
            status=status.HTTP_400_BAD_REQUEST,
        )

    try:
        safe_stream_id = transcoder.sanitize_stream_id(stream_id)
    except ValueError:
        return Response(
            {
                "success": False,
                "error_code": "invalid_stream_id",
                "message": "El stream_id enviado no es válido.",
            },
            status=status.HTTP_400_BAD_REQUEST,
        )

    try:
        stopped = transcoder.stop_hls_transcode(safe_stream_id)
        # Se borra también la salida HLS: si quedara un index.m3u8 "fresco",
        # un proxy-url inmediato lo reutilizaría aunque ya no haya proceso.
        output_removed = transcoder.remove_hls_output(safe_stream_id)

        return Response({
            "success": True,
            "stream_id": safe_stream_id,
            "stopped": stopped,
            "output_removed": output_removed,
        })

    except Exception:
        return Response(
            {
                "success": False,
                "error_code": "unexpected_error",
                "message": "Ocurrió un error inesperado al detener el proxy.",
            },
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )


@api_view(["GET"])
def live_proxy_status(request):
    """
    Devuelve el estado global del transcoder: procesos FFmpeg activos, límite
    configurado y salidas HLS detectadas. Solo datos de monitoreo; nunca
    URLs de origen, usuarios ni contraseñas.
    """
    try:
        transcoder_status = transcoder.get_transcoder_status()

        return Response({
            "success": True,
            **transcoder_status,
        })

    except Exception:
        return Response(
            {
                "success": False,
                "error_code": "unexpected_error",
                "message": "Ocurrió un error inesperado al consultar el estado.",
            },
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )


@api_view(["GET"])
def live_hls_status(request, stream_id):
    """
    Diagnóstico de la salida HLS generada por el backend para un stream_id.

    Informa si existe index.m3u8, su tamaño, la cantidad de segmentos .ts,
    si la salida está dañada y si el proceso FFmpeg sigue vivo. Sirve para
    diferenciar un canal que falla por HLS incompleto de uno cuyo proceso
    murió. No expone usuario, contraseña ni la URL original del stream.
    """
    try:
        safe_stream_id = transcoder.sanitize_stream_id(stream_id)
    except ValueError:
        return Response(
            {
                "success": False,
                "error_code": "invalid_stream_id",
                "message": "El stream_id enviado no es válido.",
            },
            status=status.HTTP_400_BAD_REQUEST,
        )

    try:
        hls_status = transcoder.get_hls_status(safe_stream_id)

        return Response({
            "success": True,
            **hls_status,
        })

    except Exception:
        return Response(
            {
                "success": False,
                "error_code": "unexpected_error",
                "message": "Ocurrió un error inesperado al consultar el estado HLS.",
            },
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )


@api_view(["POST"])
def live_diagnose_stream(request):
    """
    Diagnóstico técnico de un canal Xtream: construye la URL del stream con
    las credenciales enviadas, la sondea con ffprobe y devuelve los códecs,
    la compatibilidad web y el modo de procesamiento recomendado.

    Ayuda a entender por qué un canal reproduce directo y otro necesita
    transcode. La URL con credenciales NUNCA se devuelve.
    """
    username = request.data.get("username")
    password = request.data.get("password")
    stream_id = request.data.get("stream_id")
    output = request.data.get("output", "m3u8")

    if not username or not password:
        return Response(
            {
                "success": False,
                "error_code": "missing_credentials",
                "message": "Usuario y contraseña son obligatorios.",
            },
            status=status.HTTP_400_BAD_REQUEST,
        )

    if not stream_id:
        return Response(
            {
                "success": False,
                "error_code": "missing_stream_id",
                "message": "El campo stream_id es obligatorio.",
            },
            status=status.HTTP_400_BAD_REQUEST,
        )

    try:
        safe_stream_id = transcoder.sanitize_stream_id(stream_id)
    except ValueError:
        return Response(
            {
                "success": False,
                "error_code": "invalid_stream_id",
                "message": "El stream_id enviado no es válido.",
            },
            status=status.HTTP_400_BAD_REQUEST,
        )

    # ffprobe es parte del paquete de FFmpeg; si no está, no hay diagnóstico.
    if not transcoder.is_ffmpeg_available():
        return Response(
            {
                "success": False,
                "error_code": "ffmpeg_not_available",
                "message": "FFmpeg/ffprobe no está disponible.",
            },
            status=status.HTTP_503_SERVICE_UNAVAILABLE,
        )

    try:
        client = XtreamClient()
        stream_url = client.build_live_stream_url(
            username=username,
            password=password,
            stream_id=safe_stream_id,
            output=output,
        )

        # Sin XTREAM_BASE_URL la URL sale incompleta y ffprobe fallaría.
        if not stream_url.lower().startswith(("http://", "https://")):
            return Response(
                {
                    "success": False,
                    "error_code": "stream_url_error",
                    "message": "No se pudo construir la URL del stream.",
                },
                status=status.HTTP_502_BAD_GATEWAY,
            )

        # Un solo sondeo con ffprobe; el modo se decide sobre esos códecs.
        video_codec, audio_codec = transcoder.probe_codecs(stream_url)
        web_compatible = transcoder.is_web_compatible(video_codec, audio_codec)
        recommended_mode = transcoder.mode_from_codecs(video_codec, audio_codec)

        return Response({
            "success": True,
            "stream_id": safe_stream_id,
            "video_codec": video_codec,
            "audio_codec": audio_codec,
            "web_compatible": web_compatible,
            "recommended_mode": recommended_mode,
        })

    except Exception as error:
        payload, http_status = build_error_response(error)
        return Response(payload, status=http_status)