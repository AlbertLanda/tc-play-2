"""
Servicio de transcoder HLS (prueba técnica controlada).

Toma una URL de stream original de Xtream, lanza un proceso FFmpeg en
segundo plano (sin bloquear el hilo de Django) y produce una salida HLS
"limpia" compuesta por un index.m3u8 y segmentos .ts, pensada para los
canales que llegan bien por red pero fallan en el navegador por códec o
empaquetado.

Objetivos de diseño:
    - El backend NO debe caerse si FFmpeg no está instalado.
    - No duplicar procesos si ya hay un HLS activo para el mismo stream_id.
    - No exponer la URL original (con credenciales) al cliente.

Ver riesgos y límites en docs/transcoder_hls.md. Esto es una prueba
técnica, no una configuración lista para producción.
"""

import json
import re
import shutil
import subprocess
import threading
import time

from django.conf import settings


# Códecs que el navegador reproduce de forma nativa (vía hls.js). Si el canal
# ya llega con estos, basta un remux (re-empaquetar sin recodificar). Cualquier
# otra cosa (hevc, ac3, mpeg2, etc.) obliga a transcodificar.
WEB_COMPATIBLE_VIDEO = {"h264"}
WEB_COMPATIBLE_AUDIO = {"aac", "mp3"}


# --- Excepciones del transcoder -------------------------------------------
# Cada una mapea a un error_code / HTTP definido en el plan del día.

class TranscoderError(Exception):
    """Base para errores controlados del transcoder."""
    error_code = "transcoder_start_error"
    http_status = 500


class FFmpegNotAvailableError(TranscoderError):
    error_code = "ffmpeg_not_available"
    http_status = 503


class HlsOutputError(TranscoderError):
    error_code = "hls_output_error"
    http_status = 500


class TranscoderStartError(TranscoderError):
    error_code = "transcoder_start_error"
    http_status = 500


class StreamUrlError(TranscoderError):
    error_code = "stream_url_error"
    http_status = 502


class TranscoderBusyError(TranscoderError):
    error_code = "transcoder_busy"
    http_status = 503


# --- Registro de procesos en memoria --------------------------------------
# Mapa stream_id -> subprocess.Popen del FFmpeg lanzado. Es un registro
# simple por proceso de Django; en producción se necesitaría algo más
# robusto (cola de trabajos, límite de concurrencia, etc.).
_processes = {}
_lock = threading.Lock()

# Solo se permiten stream_id alfanuméricos para construir la ruta de salida
# y evitar path traversal (p. ej. "../../etc"). Xtream usa IDs numéricos.
_SAFE_STREAM_ID = re.compile(r"^[A-Za-z0-9_-]+$")


def sanitize_stream_id(stream_id) -> str:
    """
    Normaliza el stream_id a un texto seguro para usarlo como nombre de
    carpeta. Lanza ValueError si contiene caracteres no permitidos.
    """
    value = str(stream_id).strip()
    if not value or not _SAFE_STREAM_ID.match(value):
        raise ValueError("stream_id inválido")
    return value


def is_ffmpeg_available() -> bool:
    """
    Indica si FFmpeg se puede ejecutar. No lanza excepción: si algo falla
    (no está en PATH, permisos, etc.) simplemente devuelve False para que
    la vista responda ffmpeg_not_available de forma controlada.
    """
    ffmpeg_bin = getattr(settings, "FFMPEG_BIN", "ffmpeg")

    # Si es una ruta absoluta o un nombre en PATH, shutil.which lo resuelve.
    if shutil.which(ffmpeg_bin):
        return True

    try:
        result = subprocess.run(
            [ffmpeg_bin, "-version"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
        )
        return result.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def _hls_dir(stream_id: str):
    return settings.HLS_ROOT / stream_id


def _index_path(stream_id: str):
    return _hls_dir(stream_id) / "index.m3u8"


def build_hls_url(request, stream_id: str) -> str:
    """
    Construye la URL pública del index.m3u8 a partir de MEDIA_URL y del
    host de la petición, sin credenciales.
    """
    relative = f"{settings.MEDIA_URL}hls/{stream_id}/index.m3u8"
    return request.build_absolute_uri("/" + relative.lstrip("/"))


def is_stream_active(stream_id: str) -> bool:
    """
    True si ya existe un HLS "vivo" para este stream_id: hay un proceso
    FFmpeg registrado y en ejecución, o existe un index.m3u8 reciente
    (dentro de HLS_ACTIVE_TTL_SECONDS). Sirve para no duplicar procesos.
    """
    with _lock:
        process = _processes.get(stream_id)

    if process is not None and process.poll() is None:
        return True

    index = _index_path(stream_id)
    if index.exists():
        ttl = getattr(settings, "HLS_ACTIVE_TTL_SECONDS", 30)
        edad = time.time() - index.stat().st_mtime
        if edad <= ttl:
            return True

    return False


def probe_codecs(stream_url: str):
    """
    Lee el códec de video y audio del stream ORIGINAL con ffprobe, sin
    descargar ni transcodificar (solo inspecciona los primeros paquetes).

    Devuelve (video_codec, audio_codec) en minúsculas, o (None, None) si no
    se pudo determinar (ffprobe ausente, canal caído, timeout, etc.).
    """
    ffprobe_bin = getattr(settings, "FFPROBE_BIN", "ffprobe")
    try:
        result = subprocess.run(
            [
                ffprobe_bin,
                "-v", "error",
                "-show_entries", "stream=codec_type,codec_name",
                "-of", "json",
                stream_url,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=20,
        )
        data = json.loads(result.stdout or b"{}")
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
        return None, None

    video = audio = None
    for stream in data.get("streams", []):
        if stream.get("codec_type") == "video" and video is None:
            video = stream.get("codec_name")
        elif stream.get("codec_type") == "audio" and audio is None:
            audio = stream.get("codec_name")
    return video, audio


def is_web_compatible(video_codec, audio_codec) -> bool:
    """True si el navegador puede reproducir estos códecs directamente."""
    return video_codec in WEB_COMPATIBLE_VIDEO and audio_codec in WEB_COMPATIBLE_AUDIO


def decide_mode(stream_url: str) -> str:
    """
    Decide cómo procesar el canal según su códec original, gastando la menor
    CPU posible:
      - "remux"           -> video y audio ya compatibles: solo re-empaqueta
                             (CPU ~0).
      - "transcode_audio" -> video h264 OK pero audio incompatible (p. ej.
                             mp2): copia el video y recodifica solo el audio
                             a AAC (CPU baja).
      - "transcode"       -> video incompatible (hevc, mpeg2, etc.): recodifica
                             video y audio a H.264/AAC (CPU alta).

    Si no se puede determinar el códec, se transcodifica por seguridad
    (garantiza compatibilidad aunque consuma más CPU).
    """
    video, audio = probe_codecs(stream_url)

    # No se pudo leer el códec -> transcode completo por seguridad.
    if video is None and audio is None:
        return "transcode"

    # Video incompatible -> hay que recodificar el video (lo más caro).
    if video not in WEB_COMPATIBLE_VIDEO:
        return "transcode"

    # Video ya es h264. Si el audio también es compatible (o no hay audio),
    # basta un remux. Si solo el audio molesta, se recodifica solo el audio.
    if audio is None or audio in WEB_COMPATIBLE_AUDIO:
        return "remux"
    return "transcode_audio"


def _build_ffmpeg_command(stream_url: str, output_path, mode: str) -> list:
    """
    Construye el comando FFmpeg según el modo elegido y empaqueta en HLS con
    segmentos rotatorios (sección 8 del plan).

    - mode "remux": -c copy (no recodifica, consumo mínimo).
    - mode "transcode_audio": copia el video y recodifica solo el audio a AAC.
    - mode "transcode": recodifica video a H.264 y audio a AAC.
    """
    ffmpeg_bin = getattr(settings, "FFMPEG_BIN", "ffmpeg")
    command = [ffmpeg_bin, "-y", "-i", stream_url]

    if mode == "remux":
        command += ["-c", "copy"]
    elif mode == "transcode_audio":
        command += ["-c:v", "copy", "-c:a", "aac"]
    else:
        command += [
            "-c:v", "libx264",
            "-preset", "veryfast",
            "-tune", "zerolatency",
            "-c:a", "aac",
        ]

    command += [
        "-f", "hls",
        "-hls_time", "3",
        "-hls_list_size", "6",
        "-hls_flags", "delete_segments",
        str(output_path),
    ]
    return command


def start_hls_transcode(stream_url: str, stream_id: str):
    """
    Lanza (o reutiliza) un proceso FFmpeg que genera la salida HLS para el
    stream_id dado.

    Devuelve una tupla (stream_id, reused: bool, mode: str|None). No bloquea
    el request: FFmpeg corre en segundo plano vía subprocess.Popen. En caso de
    reutilización, mode es None (no se vuelve a decidir).

    Lanza FFmpegNotAvailableError / HlsOutputError / TranscoderStartError
    según el punto de falla.
    """
    if not is_ffmpeg_available():
        raise FFmpegNotAvailableError("FFmpeg no está disponible.")

    # Si ya hay algo activo para este stream, se reutiliza la salida.
    if is_stream_active(stream_id):
        return stream_id, True, None

    # Límite de procesos concurrentes: si ya se alcanzó, no se lanza otro
    # para no saturar el servidor.
    max_concurrent = getattr(settings, "MAX_CONCURRENT_TRANSCODES", 5)
    if count_active_processes() >= max_concurrent:
        raise TranscoderBusyError(
            "Se alcanzó el límite de procesos de transcoder concurrentes."
        )

    # Preparar la carpeta de salida.
    output_dir = _hls_dir(stream_id)
    try:
        output_dir.mkdir(parents=True, exist_ok=True)
    except OSError as error:
        raise HlsOutputError("No se pudo crear la carpeta HLS.") from error

    # ffprobe decide: remux si el códec ya es compatible con web, transcode
    # si no. Así solo se gasta CPU cuando realmente hace falta.
    mode = decide_mode(stream_url)
    command = _build_ffmpeg_command(stream_url, _index_path(stream_id), mode)

    try:
        process = subprocess.Popen(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise TranscoderStartError("No se pudo iniciar FFmpeg.") from error

    with _lock:
        _processes[stream_id] = process

    # Asegura que el hilo de limpieza automática esté corriendo.
    ensure_cleanup_thread()

    return stream_id, False, mode


def count_active_processes() -> int:
    """Número de procesos FFmpeg vivos en el registro."""
    with _lock:
        return sum(1 for p in _processes.values() if p.poll() is None)


def stop_hls_transcode(stream_id: str) -> bool:
    """
    Detiene el proceso FFmpeg asociado a un stream_id, si existe.
    Devuelve True si había un proceso que detener. (Base para limpieza
    manual; ver tareas opcionales del plan.)
    """
    with _lock:
        process = _processes.pop(stream_id, None)

    if process is None:
        return False

    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()

    return True


def cleanup_inactive():
    """
    Limpieza automática de salidas HLS inactivas.

    Recorre las carpetas de HLS_ROOT y, para cada stream cuya salida no se ha
    actualizado en HLS_CLEANUP_TTL_SECONDS (FFmpeg murió, se estancó o la
    carpeta quedó huérfana), detiene el proceso asociado y borra la carpeta.
    Una salida "fresca" (FFmpeg sigue escribiendo segmentos) NO se toca.

    Devuelve la lista de stream_id limpiados.
    """
    ttl = getattr(settings, "HLS_CLEANUP_TTL_SECONDS", 300)
    hls_root = settings.HLS_ROOT
    cleaned = []

    if not hls_root.exists():
        return cleaned

    for folder in hls_root.iterdir():
        if not folder.is_dir():
            continue

        index = folder / "index.m3u8"
        if index.exists():
            idle = time.time() - index.stat().st_mtime
        else:
            # Carpeta sin playlist -> huérfana, se fuerza su limpieza.
            idle = ttl + 1

        if idle <= ttl:
            continue  # salida fresca: FFmpeg sigue produciendo, no tocar.

        stop_hls_transcode(folder.name)
        shutil.rmtree(folder, ignore_errors=True)
        cleaned.append(folder.name)

    return cleaned


_cleanup_started = False


def _cleanup_loop():
    interval = getattr(settings, "HLS_CLEANUP_INTERVAL_SECONDS", 60)
    while True:
        time.sleep(interval)
        try:
            cleanup_inactive()
        except Exception:
            # La limpieza nunca debe tumbar el hilo; se reintenta al próximo ciclo.
            pass


def ensure_cleanup_thread():
    """Arranca (una sola vez) el hilo daemon de limpieza automática."""
    global _cleanup_started
    with _lock:
        if _cleanup_started:
            return
        _cleanup_started = True

    thread = threading.Thread(
        target=_cleanup_loop, daemon=True, name="hls-cleanup"
    )
    thread.start()
