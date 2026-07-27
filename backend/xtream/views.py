import logging
import time

from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status

from .services.client import XtreamClient
from .services import transcoder
from .normalizers import normalize_login, normalize_categories, normalize_channels
from .errors import build_error_response


logger = logging.getLogger(__name__)


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

    # device_profile OPCIONAL: selecciona el perfil de salida (mobile / tv /
    # web). Si no se envía, se usa el default (mobile) para no romper la app
    # móvil actual. Un valor no reconocido se rechaza de forma controlada.
    try:
        device_profile = transcoder.normalize_device_profile(
            request.data.get("device_profile")
        )
    except ValueError:
        return Response(
            {
                "success": False,
                "error_code": "invalid_device_profile",
                "message": "device_profile inválido. Use 'mobile', 'tv' o 'web'."
            },
            status=status.HTTP_400_BAD_REQUEST
        )

    # hls_profile OPCIONAL: empaquetado HLS para la prueba A/B de arranque
    # (mobile_stable = actual, mobile_fast = arranque rápido). Default:
    # mobile_stable, idéntico al comportamiento previo.
    try:
        hls_profile = transcoder.normalize_hls_profile(
            request.data.get("hls_profile")
        )
    except ValueError:
        return Response(
            {
                "success": False,
                "error_code": "invalid_hls_profile",
                "message": "hls_profile inválido. Use 'mobile_stable' o 'mobile_fast'."
            },
            status=status.HTTP_400_BAD_REQUEST
        )

    try:
        # Medición de tiempos del arranque (plan 5.1): cada etapa se registra
        # en ms para localizar el cuello de botella (Xtream, ffprobe, FFmpeg
        # o el ready check). Solo métricas; nunca credenciales ni URLs.
        request_started = time.monotonic()

        # URL original de Xtream (entrada para FFmpeg). Se usa el formato TS
        # crudo del canal en vivo; no se expone en la respuesta.
        client = XtreamClient()
        source_url = client.build_live_stream_url(
            username=username,
            password=password,
            stream_id=safe_stream_id,
            output="ts",
        )
        xtream_source_ms = round((time.monotonic() - request_started) * 1000)

        # Si XTREAM_BASE_URL no está configurado, la URL saldría incompleta
        # (sin http://host) y FFmpeg fallaría más adelante. Se corta aquí con
        # stream_url_error para no lanzar un proceso inútil.
        if not source_url.lower().startswith(("http://", "https://")):
            raise transcoder.StreamUrlError(
                "No se pudo construir la URL original del stream."
            )

        # El modo (remux / transcode_audio / transcode) lo decide el backend
        # sondeando el stream (incluye la normalización móvil por fps: HD a
        # 60fps -> transcode 720p30). Ver transcoder.decide_mode().
        # output_key = "<stream_id>-<device_profile>". Es la identidad real de
        # la salida: a partir de aquí TODO (espera, diagnóstico, limpieza y
        # URL) se hace sobre esta clave, nunca sobre el stream_id suelto, para
        # que el HLS de un perfil no se cruce con el de otro.
        output_key = transcoder.build_output_key(safe_stream_id, device_profile)

        replace_profile_value = request.data.get("replace_profile", False)
        replace_profile = str(replace_profile_value).strip().lower() in (
            "1",
            "true",
            "yes",
            "si",
            "sí",
        )

        replaced_outputs = []
        if replace_profile:
            # remove_async=True: el FFmpeg viejo se detiene YA (libera CPU y
            # evita audio duplicado); el borrado de su carpeta HLS se hace en
            # segundo plano para no retrasar el arranque del canal nuevo.
            replaced_outputs = transcoder.stop_outputs_for_device_profile(
                device_profile,
                keep_output_key=output_key,
                remove_async=True,
            )

        start_metrics = {}
        output_key, reused, mode = transcoder.start_hls_transcode(
            source_url,
            safe_stream_id,
            device_profile=device_profile,
            output_key=output_key,
            hls_profile=hls_profile,
            metrics=start_metrics,
        )

        # El transcode completo tarda más en producir el primer segmento
        # (libx264 llena su buffer); se le da más margen que a un remux para
        # no fallar por timeout. min_segments lo decide el hls_profile:
        # mobile_fast devuelve la URL con 1 solo segmento en disco.
        ready_timeout = 40 if mode == "transcode" else 15
        min_segments = transcoder.hls_profile_min_segments(hls_profile)
        wait_metrics = {
            "ready": True, "index_ms": None, "first_segment_ms": None,
            "ready_ms": None, "segments": None,
        }
        if not reused:
            wait_metrics = transcoder.wait_for_hls_ready_metrics(
                output_key,
                timeout_seconds=ready_timeout,
                min_segments=min_segments,
            )

        if not wait_metrics["ready"]:
            # Se captura el diagnóstico ANTES de limpiar, para explicar por qué
            # no quedó listo (faltó index, segmentos, proceso vivo o dañado).
            hls_status = transcoder.get_hls_status(output_key)
            transcoder.stop_hls_transcode(output_key)
            transcoder.remove_hls_output(output_key)

            return Response(
                {
                    "success": False,
                    "error_code": "hls_not_ready",
                    "message": "El canal no generó segmentos HLS suficientes a tiempo.",
                    "stream_id": safe_stream_id,
                    "hls_status": hls_status,
                },
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )

        ready_total_ms = round((time.monotonic() - request_started) * 1000)
        segments = wait_metrics["segments"]
        if segments is None:
            segments = transcoder.count_ts_segments(output_key)

        timings = {
            "xtream_source_ms": xtream_source_ms,
            "probe_ms": start_metrics.get("probe_ms"),
            "ffmpeg_start_ms": start_metrics.get("ffmpeg_spawn_ms"),
            "index_ms": wait_metrics.get("index_ms"),
            "first_segment_ms": wait_metrics["first_segment_ms"],
            "ready_total_ms": ready_total_ms,
        }

        # Solo se acumulan arranques reales: una reutilización no dice nada
        # sobre cuánto cuesta levantar el canal desde cero.
        if not reused:
            transcoder.record_start_timing(
                safe_stream_id, device_profile, hls_profile, mode, timings
            )

        # Log técnico seguro con el desglose de tiempos del plan (sección 6).
        # Cada campo corresponde a una etapa del arranque, para ubicar dónde
        # está el cuello de botella. No expone usuario, contraseña ni la URL
        # original del stream.
        logger.info(
            "proxy_url stream_id=%s profile=%s hls_profile=%s mode=%s "
            "xtream_source_ms=%s probe_ms=%s ffmpeg_start_ms=%s index_ms=%s "
            "first_segment_ms=%s ready_total_ms=%s segments=%s reused=%s "
            "replaced_outputs=%s",
            safe_stream_id,
            device_profile,
            hls_profile,
            mode,
            timings["xtream_source_ms"],
            timings["probe_ms"],
            timings["ffmpeg_start_ms"],
            timings["index_ms"],
            timings["first_segment_ms"],
            timings["ready_total_ms"],
            segments,
            reused,
            replaced_outputs,
        )

        return Response({
            "success": True,
            "stream_id": safe_stream_id,
            "hls_url": transcoder.build_hls_url(request, output_key),
            "mode": mode,
            "device_profile": device_profile,
            "hls_profile": hls_profile,
            "reused": reused,
            "replaced_outputs": replaced_outputs,
            "segments": segments,
            "timings": timings,
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
    Detiene el proceso FFmpeg asociado a un canal de Xtream y borra su salida
    HLS, para que un canal cerrado no deje procesos vivos ni carpetas muertas
    reutilizables. Equivalente al stop-proxy de Astra.

    device_profile OPCIONAL (default mobile): detiene SOLO la salida de ese
    perfil. Cerrar el canal en la TV no debe matar el FFmpeg que está viendo
    alguien más desde el celular.
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
        device_profile = transcoder.normalize_device_profile(
            request.data.get("device_profile")
        )
    except ValueError:
        return Response(
            {
                "success": False,
                "error_code": "invalid_device_profile",
                "message": "device_profile inválido. Use 'mobile', 'tv' o 'web'.",
            },
            status=status.HTTP_400_BAD_REQUEST,
        )

    try:
        output_key = transcoder.build_output_key(safe_stream_id, device_profile)
        stopped = transcoder.stop_hls_transcode(output_key)
        # Se borra también la salida HLS: si quedara un index.m3u8 "fresco",
        # un proxy-url inmediato lo reutilizaría aunque ya no haya proceso.
        output_removed = transcoder.remove_hls_output(output_key)

        return Response({
            "success": True,
            "stream_id": safe_stream_id,
            "device_profile": device_profile,
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
            # Tiempos promedio por canal (plan 5.6): permite comparar canales
            # rápidos contra lentos sin releer los logs a mano.
            "channel_timings": transcoder.get_timing_summary(),
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
    Diagnóstico de la salida HLS generada por el backend para un canal.

    Informa si existe index.m3u8, su tamaño, la cantidad de segmentos .ts,
    si la salida está dañada y si el proceso FFmpeg sigue vivo. Sirve para
    diferenciar un canal que falla por HLS incompleto de uno cuyo proceso
    murió. No expone usuario, contraseña ni la URL original del stream.

    El perfil se pasa como query param (?device_profile=tv) y por defecto es
    mobile: cada perfil tiene su propia salida y por tanto su propio estado.
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
        device_profile = transcoder.normalize_device_profile(
            request.query_params.get("device_profile")
        )
    except ValueError:
        return Response(
            {
                "success": False,
                "error_code": "invalid_device_profile",
                "message": "device_profile inválido. Use 'mobile', 'tv' o 'web'.",
            },
            status=status.HTTP_400_BAD_REQUEST,
        )

    try:
        hls_status = transcoder.get_hls_status(
            transcoder.build_output_key(safe_stream_id, device_profile)
        )

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


@api_view(["POST"])
def live_benchmark_stream(request):
    """
    Benchmark de arranque de UN canal sin depender de la app (plan 5.2).

    Ejecuta el flujo completo de proxy-url midiendo cada etapa desde CERO
    (si había una salida previa del canal, se limpia antes, para que el
    resultado refleje un arranque frío real) y devuelve:

        source_ok, ffmpeg_started, first_segment_seconds, ready_seconds,
        segments, mode, device_profile, hls_profile.

    Parámetros opcionales:
        - device_profile: mobile (default) / tv / web.
        - hls_profile: mobile_stable (default) / mobile_fast, para la
          comparación A/B de arranque.
        - keep_output: por defecto false; el benchmark detiene FFmpeg y borra
          la salida al terminar para no dejar procesos consumiendo CPU.

    Sirve para comparar canales rápidos vs lentos y stable vs fast. Nunca
    devuelve la URL original ni credenciales.
    """
    username = request.data.get("username")
    password = request.data.get("password")
    stream_id = request.data.get("stream_id")

    if not username or not password or not stream_id:
        return Response(
            {
                "success": False,
                "error_code": "validation_error",
                "message": "Usuario, contraseña y stream_id son obligatorios.",
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
        device_profile = transcoder.normalize_device_profile(
            request.data.get("device_profile")
        )
        hls_profile = transcoder.normalize_hls_profile(
            request.data.get("hls_profile")
        )
    except ValueError:
        return Response(
            {
                "success": False,
                "error_code": "invalid_profile",
                "message": "device_profile u hls_profile inválido.",
            },
            status=status.HTTP_400_BAD_REQUEST,
        )

    keep_output = str(request.data.get("keep_output", "")).strip().lower() in (
        "1", "true", "yes", "si", "sí",
    )

    if not transcoder.is_ffmpeg_available():
        return Response(
            {
                "success": False,
                "error_code": "ffmpeg_not_available",
                "message": "FFmpeg no está disponible.",
            },
            status=status.HTTP_503_SERVICE_UNAVAILABLE,
        )

    output_key = transcoder.build_output_key(safe_stream_id, device_profile)
    result = {
        "success": True,
        "stream_id": safe_stream_id,
        "device_profile": device_profile,
        "hls_profile": hls_profile,
        "source_ok": False,
        "ffmpeg_started": False,
        "index_seconds": None,
        "first_segment_seconds": None,
        "ready_seconds": None,
        "segments": 0,
        "mode": None,
        "probe_seconds": None,
    }

    try:
        benchmark_started = time.monotonic()

        client = XtreamClient()
        source_url = client.build_live_stream_url(
            username=username,
            password=password,
            stream_id=safe_stream_id,
            output="ts",
        )
        if not source_url.lower().startswith(("http://", "https://")):
            return Response({**result, "success": False,
                             "error_code": "stream_url_error"},
                            status=status.HTTP_502_BAD_GATEWAY)
        result["source_ok"] = True

        # Arranque FRÍO: si quedó una salida previa (de la app o de otro
        # benchmark), se limpia para que los tiempos no midan reutilización.
        transcoder.stop_hls_transcode(output_key)
        transcoder.remove_hls_output(output_key)

        start_metrics = {}
        output_key, reused, mode = transcoder.start_hls_transcode(
            source_url,
            safe_stream_id,
            device_profile=device_profile,
            output_key=output_key,
            hls_profile=hls_profile,
            metrics=start_metrics,
        )
        result["ffmpeg_started"] = True
        result["mode"] = mode
        probe_ms = start_metrics.get("probe_ms")
        result["probe_seconds"] = (
            round(probe_ms / 1000, 2) if probe_ms is not None else None
        )

        ready_timeout = 40 if mode == "transcode" else 15
        wait_metrics = transcoder.wait_for_hls_ready_metrics(
            output_key,
            timeout_seconds=ready_timeout,
            min_segments=transcoder.hls_profile_min_segments(hls_profile),
        )

        result["segments"] = wait_metrics["segments"]
        if wait_metrics.get("index_ms") is not None:
            result["index_seconds"] = round(wait_metrics["index_ms"] / 1000, 2)
        if wait_metrics["first_segment_ms"] is not None:
            result["first_segment_seconds"] = round(
                wait_metrics["first_segment_ms"] / 1000, 2
            )
        if wait_metrics["ready"]:
            result["ready_seconds"] = round(
                (time.monotonic() - benchmark_started), 2
            )
            transcoder.record_start_timing(
                safe_stream_id, device_profile, hls_profile, mode,
                {
                    "probe_ms": start_metrics.get("probe_ms"),
                    "index_ms": wait_metrics.get("index_ms"),
                    "first_segment_ms": wait_metrics.get("first_segment_ms"),
                    "ready_total_ms": round(result["ready_seconds"] * 1000),
                },
            )
        else:
            result["success"] = False
            result["error_code"] = "hls_not_ready"

        logger.info(
            "benchmark stream_id=%s profile=%s hls_profile=%s mode=%s "
            "source_ok=%s ffmpeg_started=%s probe_seconds=%s index_seconds=%s "
            "first_segment_seconds=%s ready_seconds=%s segments=%s",
            safe_stream_id,
            device_profile,
            hls_profile,
            mode,
            result["source_ok"],
            result["ffmpeg_started"],
            result["probe_seconds"],
            result["index_seconds"],
            result["first_segment_seconds"],
            result["ready_seconds"],
            result["segments"],
        )

        return Response(result)

    except transcoder.TranscoderError as error:
        return Response(
            {**result, "success": False, "error_code": error.error_code},
            status=error.http_status,
        )

    except Exception as error:
        payload, http_status = build_error_response(error)
        return Response(payload, status=http_status)

    finally:
        # El benchmark no debe dejar procesos vivos salvo que se pida
        # explícitamente conservar la salida (keep_output=true).
        if not keep_output:
            transcoder.stop_hls_transcode(output_key)
            transcoder.remove_hls_output(output_key)