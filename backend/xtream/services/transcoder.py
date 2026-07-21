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
import logging
import re
import shutil
import subprocess
import threading
import time
from pathlib import Path

from django.conf import settings


# Logger del transcoder. Los logs son técnicos y SEGUROS: nunca incluyen
# usuario, contraseña ni la URL original del stream, solo el stream_id y
# métricas de la salida HLS en disco.
logger = logging.getLogger(__name__)


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
# Mapa stream_id -> timestamp (time.time()) en que se lanzó ese FFmpeg. Sirve
# para calcular el uptime del proceso. Vive en memoria igual que _processes,
# así que se pierde al reiniciar Django (uptime = None tras un reinicio).
_process_started_at = {}
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

def wait_for_hls_index(stream_id: str, timeout_seconds: int = 8) -> bool:
    """
    Espera unos segundos a que FFmpeg genere el index.m3u8.
    Devuelve True si el archivo existe; False si no aparece dentro del tiempo.

    Espera "ligera": solo mira el index. Para Android úsese
    wait_for_hls_ready(), que además exige segmentos .ts suficientes.
    """
    index = _index_path(stream_id)
    deadline = time.time() + timeout_seconds

    while time.time() < deadline:
        if index.exists() and index.stat().st_size > 0:
            return True
        time.sleep(0.5)

    return False


def count_ts_segments(stream_id: str) -> int:
    """Número de segmentos .ts en disco para un stream_id (0 si no hay carpeta)."""
    folder = _hls_dir(stream_id)
    if not folder.exists():
        return 0
    return len(list(folder.glob("*.ts")))


def _hls_is_ready(stream_id: str, min_segments: int) -> bool:
    """
    True si la salida HLS ya es reproducible: index.m3u8 existe con tamaño
    mayor a 0, no está dañada y hay al menos ``min_segments`` segmentos .ts.
    """
    index = _index_path(stream_id)
    if not index.exists() or index.stat().st_size == 0:
        return False
    if is_hls_output_damaged(stream_id):
        return False
    return count_ts_segments(stream_id) >= min_segments


def wait_for_hls_ready(
    stream_id: str, timeout_seconds: int = 15, min_segments: int = 2
) -> bool:
    """
    Espera a que la salida HLS esté REALMENTE lista para reproducirse en
    Android, no solo a que aparezca el index.m3u8.

    Devuelve True cuando, dentro de ``timeout_seconds``:
        - index.m3u8 existe y pesa más de 0 bytes,
        - la salida no está dañada,
        - hay al menos ``min_segments`` segmentos .ts en disco.

    Devuelve False si se agota el tiempo o si el proceso FFmpeg murió antes
    de generar una salida usable (así no se espera en vano por un canal que
    ya falló).
    """
    deadline = time.time() + timeout_seconds

    while time.time() < deadline:
        if _hls_is_ready(stream_id, min_segments):
            return True

        # Si el proceso FFmpeg ya terminó y la salida aún no está lista, no
        # tiene sentido seguir esperando: el canal no va a producir más.
        with _lock:
            process = _processes.get(stream_id)
        if process is not None and process.poll() is not None:
            return _hls_is_ready(stream_id, min_segments)

        time.sleep(0.5)

    return False

def build_hls_url(request, stream_id: str) -> str:
    """
    Construye la URL pública del index.m3u8 a partir de MEDIA_URL y del
    host de la petición, sin credenciales.
    """
    relative = f"{settings.MEDIA_URL}hls/{stream_id}/index.m3u8"
    return request.build_absolute_uri("/" + relative.lstrip("/"))


def is_hls_output_damaged(stream_id: str) -> bool:
    """
    True si la salida HLS existe pero no sirve para TV en vivo:
    - index.m3u8 vacío,
    - carpeta sin segmentos .ts,
    - playlist cerrada con #EXT-X-ENDLIST.

    En TV en vivo, #EXT-X-ENDLIST significa que FFmpeg terminó y la salida
    ya no se renovará; no debe reutilizarse.
    """
    index = _index_path(stream_id)
    if not index.exists():
        return False

    if index.stat().st_size == 0:
        return True

    try:
        content = index.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return True

    if "#EXT-X-ENDLIST" in content:
        return True

    segments = list(_hls_dir(stream_id).glob("*.ts"))
    return len(segments) == 0


def get_index_age_seconds(stream_id: str):
    """
    Segundos transcurridos desde la última escritura del index.m3u8, o None
    si no existe. FFmpeg reescribe la playlist cada vez que cierra un
    segmento (~HLS_TIME), así que este número es la señal más fiable de si
    la salida sigue recibiendo contenido nuevo.
    """
    index = _index_path(stream_id)
    if not index.exists():
        return None
    return round(time.time() - index.stat().st_mtime, 1)


def get_process_uptime_seconds(stream_id: str):
    """
    Segundos que lleva CORRIENDO el proceso FFmpeg de este stream_id, o None
    si no hay un proceso vivo registrado.

    Se basa en el registro en memoria (_process_started_at), así que —igual
    que process_alive— devuelve None tras un reinicio de Django aunque FFmpeg
    siga vivo. Solo cuenta si el proceso sigue en ejecución: si ya terminó,
    el uptime deja de tener sentido y se devuelve None.
    """
    with _lock:
        process = _processes.get(stream_id)
        started = _process_started_at.get(stream_id)

    if process is None or started is None:
        return None
    if process.poll() is not None:  # el proceso ya terminó
        return None
    return round(time.time() - started, 1)


def is_output_live(stream_id: str) -> bool:
    """
    True si la salida HLS sigue PRODUCIENDO contenido nuevo.

    Se decide por la antigüedad del index.m3u8, no por el registro
    _processes: ese registro vive en memoria del proceso de Django y se
    pierde en cada reinicio, con lo que un FFmpeg perfectamente vivo
    aparecería como muerto. El disco, en cambio, no miente: si el index se
    refrescó hace poco, algo lo está escribiendo.

    Una salida "listo pero muerto" (index y segmentos en disco, pero nadie
    escribiendo) da ready=True y live=False: se puede reproducir lo ya
    grabado, pero se congela al agotarlo.
    """
    if is_hls_output_damaged(stream_id):
        return False

    age = get_index_age_seconds(stream_id)
    if age is None:
        return False

    ttl = getattr(settings, "HLS_ACTIVE_TTL_SECONDS", 30)
    return age <= ttl


def _log_recovery(stream_id: str, reason: str, reused: bool = False) -> None:
    """
    Log técnico SEGURO de una decisión de recuperación de HLS.

    Registra solo stream_id + métricas de la salida en disco (reason, ready,
    live, index_age_seconds, segments, reused).
    """
    status = get_hls_status(stream_id)
    logger.info(
        "hls_recovery stream_id=%s reason=%s ready=%s live=%s "
        "index_age_seconds=%s segments=%s hls_reused=%s",
        stream_id,
        reason,
        status["ready"],
        status["live"],
        status["index_age_seconds"],
        status["segments"],
        reused,
    )


def is_stream_active(stream_id: str) -> bool:
    """
    True si ya existe un HLS reutilizable para este stream_id; False si hay
    que (re)generarlo. Recuperación automática de salidas muertas:

        - Proceso FFmpeg registrado y vivo            -> activo (True).
        - HLS con index fresco/live=True              -> activo (True).
        - HLS listo pero live=False (muerto)          -> limpiar y regenerar.
        - HLS dañado (index vacío o sin segmentos)    -> limpiar y regenerar.
    la salida quedó reproducible en disco (ready=True) pero FFmpeg dejó de renovarla 
    (live=False), así que el player agotaría los segmentos y se congelaría. En vez de 
    reutilizarla, se detiene cualquier proceso zombie y se borra la carpeta para que 
    el caller relance FFmpeg con contenido fresco.
    """
    with _lock:
        process = _processes.get(stream_id)

    # Proceso FFmpeg registrado y vivo -> activo, se reutiliza.
    if process is not None and process.poll() is None:
        return True

    index = _index_path(stream_id)
    if not index.exists():
        return False

    # Salida dañada (index vacío o sin segmentos): no reutilizarla.
    if is_hls_output_damaged(stream_id):
        _log_recovery(stream_id, "damaged_hls_output")
        remove_hls_output(stream_id)
        return False

    # HLS con index fresco (live=True) -> sigue produciendo, se reutiliza.
    if is_output_live(stream_id):
        return True

    # HLS listo pero muerto (ready=True + live=False): se limpia el proceso
    # zombie y la salida para forzar la regeneración en el siguiente request.
    _log_recovery(stream_id, "dead_hls_output")
    stop_hls_transcode(stream_id)
    remove_hls_output(stream_id)
    return False


def remove_hls_output(stream_id: str) -> bool:
    """
    Borra la carpeta HLS de un stream_id (index.m3u8 + segmentos).
    Devuelve True si existía algo que borrar. No toca el proceso: para
    detenerlo usar stop_hls_transcode().
    """
    folder = _hls_dir(stream_id)
    if not folder.exists():
        return False
    shutil.rmtree(folder, ignore_errors=True)
    return True


def get_transcoder_status() -> dict:
    """
    Estado global del transcoder para el endpoint de monitoreo:
    procesos FFmpeg vivos, límite configurado y salidas HLS en disco.
    No expone URLs de origen ni credenciales.
    """
    with _lock:
        snapshot = dict(_processes)

    alive = {sid for sid, proc in snapshot.items() if proc.poll() is None}

    outputs = []
    hls_root = settings.HLS_ROOT
    if hls_root.exists():
        for folder in sorted(hls_root.iterdir()):
            if not folder.is_dir():
                continue

            stream_id = folder.name
            index = folder / "index.m3u8"
            if index.exists():
                stat = index.stat()
                index_age = round(time.time() - stat.st_mtime, 1)
                index_size = stat.st_size
            else:
                index_age = None
                index_size = 0

            outputs.append({
                "stream_id": stream_id,
                "process_alive": stream_id in alive,
                "index_exists": index.exists(),
                "index_age_seconds": index_age,
                "index_size_bytes": index_size,
                "segments": len(list(folder.glob("*.ts"))),
                "damaged": is_hls_output_damaged(stream_id),
            })

    return {
        "active_processes": len(alive),
        "max_concurrent": getattr(settings, "MAX_CONCURRENT_TRANSCODES", 5),
        "outputs": outputs,
    }


def get_hls_status(stream_id: str) -> dict:
    """
    Estado de la salida HLS de UN stream_id, para el endpoint de diagnóstico
    hls-status. Informa si existe el index, su tamaño, cuántos segmentos hay,
    si la salida está dañada y si sigue generándose contenido nuevo.

    Distingue dos cosas que NO son lo mismo (Día 11):
        - ready: hay contenido reproducible en disco.
        - live:  ese contenido se sigue renovando.
    Un canal congelado da ready=True + live=False: el player reproduce los
    segmentos que quedaron y se detiene al agotarlos.

    Ojo con process_alive: es solo una PISTA. El registro _processes vive en
    memoria y se pierde al reiniciar Django, así que un FFmpeg vivo puede
    reportarse como process_alive=False. Para decidir si la salida sirve,
    usar live.

    No expone usuario, contraseña ni la URL original del stream.
    """
    folder = _hls_dir(stream_id)
    index = _index_path(stream_id)
    index_exists = index.exists()
    index_size = index.stat().st_size if index_exists else 0
    segments = len(list(folder.glob("*.ts"))) if folder.exists() else 0
    damaged = is_hls_output_damaged(stream_id)

    with _lock:
        process = _processes.get(stream_id)
    process_alive = process is not None and process.poll() is None

    min_segments_required = getattr(settings, "HLS_MIN_SEGMENTS", 2)
    ready = (
        index_exists
        and index_size > 0
        and not damaged
        and segments >= min_segments_required
    )
    live = is_output_live(stream_id)

    # la salida necesita recuperación cuando es reproducible pero ya
    # no se renueva (ready=True + live=False). El backend debe limpiarla y
    # regenerarla en vez de reutilizar segmentos que el player agotará.
    recovery_required = ready and not live

    # Uptime del proceso FFmpeg: cuánto lleva corriendo este canal. Se expone
    # también en minutos para leerlo cómodo. None si no hay proceso vivo
    # registrado (o tras reiniciar Django, igual que process_alive).
    uptime_seconds = get_process_uptime_seconds(stream_id)
    uptime_minutes = (
        round(uptime_seconds / 60, 2) if uptime_seconds is not None else None
    )

    return {
        "stream_id": stream_id,
        "index_exists": index_exists,
        "index_size_bytes": index_size,
        "index_age_seconds": get_index_age_seconds(stream_id),
        "segments": segments,
        "min_segments_required": min_segments_required,
        "ready": ready,
        "live": live,
        "recovery_required": recovery_required,
        "live_max_age_seconds": getattr(settings, "HLS_ACTIVE_TTL_SECONDS", 30),
        "uptime_seconds": uptime_seconds,
        "uptime_minutes": uptime_minutes,
        "damaged": damaged,
        "process_alive": process_alive,
    }


def _parse_fps(rate) -> float:
    """Convierte 'num/den' (p.ej. '60000/1001') a float fps. None si no aplica."""
    if not rate or rate == "0/0":
        return None
    try:
        num, _, den = rate.partition("/")
        den_value = float(den) if den else 1.0
        if den_value == 0:
            return None
        return float(num) / den_value
    except (ValueError, ZeroDivisionError):
        return None


def probe_stream_info(stream_url: str) -> dict:
    """
    Sondea con ffprobe el stream ORIGINAL y devuelve un dict con:
      video_codec, audio_codec (minúsculas), height (px) y fps (float).
    Cualquier valor es None si no se pudo determinar (ffprobe ausente, canal
    caído, timeout, etc.). Un solo ffprobe: sirve tanto para decidir el modo
    como para la normalización móvil por fps/resolución.
    """
    ffprobe_bin = getattr(settings, "FFPROBE_BIN", "ffprobe")
    info = {"video_codec": None, "audio_codec": None, "height": None, "fps": None}
    try:
        result = subprocess.run(
            [
                ffprobe_bin,
                "-v", "error",
                "-show_entries",
                "stream=codec_type,codec_name,height,avg_frame_rate",
                "-of", "json",
                stream_url,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=20,
        )
        data = json.loads(result.stdout or b"{}")
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
        return info

    for stream in data.get("streams", []):
        ctype = stream.get("codec_type")
        if ctype == "video" and info["video_codec"] is None:
            info["video_codec"] = stream.get("codec_name")
            info["height"] = stream.get("height")
            info["fps"] = _parse_fps(stream.get("avg_frame_rate"))
        elif ctype == "audio" and info["audio_codec"] is None:
            info["audio_codec"] = stream.get("codec_name")
    return info


def probe_codecs(stream_url: str):
    """
    Lee el códec de video y audio del stream ORIGINAL con ffprobe.

    Devuelve (video_codec, audio_codec) en minúsculas, o (None, None) si no
    se pudo determinar. Envoltura de probe_stream_info() para el código que
    solo necesita los códecs.
    """
    info = probe_stream_info(stream_url)
    return info["video_codec"], info["audio_codec"]


def is_web_compatible(video_codec, audio_codec) -> bool:
    """True si el navegador puede reproducir estos códecs directamente."""
    return video_codec in WEB_COMPATIBLE_VIDEO and audio_codec in WEB_COMPATIBLE_AUDIO


def mode_from_codecs(video_codec, audio_codec) -> str:
    """
    Decide el modo de procesamiento a partir de códecs YA sondeados, sin
    volver a ejecutar ffprobe. Útil para el endpoint de diagnóstico, que
    ya tiene los códecs y no debe pagar un segundo sondeo.

      - "remux"           -> video y audio ya compatibles (CPU ~0).
      - "transcode_audio" -> video h264 OK pero audio incompatible (CPU baja).
      - "transcode"       -> video incompatible o códec desconocido (CPU alta).
    """
    # No se pudo leer el códec -> transcode completo por seguridad.
    if video_codec is None and audio_codec is None:
        return "transcode"

    # Stream de SOLO AUDIO (radios): no hay video que recodificar, así que
    # NO debe caer en "transcode" (forzaría libx264 sobre algo sin video y
    # FFmpeg fallaría). Se decide solo por el audio: remux si ya es
    # compatible, transcode_audio si hay que convertirlo a AAC.
    if video_codec is None and audio_codec is not None:
        if audio_codec in WEB_COMPATIBLE_AUDIO:
            return "remux"
        return "transcode_audio"

    # Video incompatible -> hay que recodificar el video (lo más caro).
    if video_codec not in WEB_COMPATIBLE_VIDEO:
        return "transcode"

    # Video ya es h264. Si el audio también es compatible (o no hay audio),
    # basta un remux. Si solo el audio molesta, se recodifica solo el audio.
    if audio_codec is None or audio_codec in WEB_COMPATIBLE_AUDIO:
        return "remux"
    return "transcode_audio"


def decide_mode(stream_url: str) -> str:
    """
    Sondea el stream original y decide cómo procesarlo, gastando la menor CPU
    posible. Si no se puede determinar el códec, transcodifica por seguridad.
    Ver mode_from_codecs() para la tabla base de decisión.

    Normalización MÓVIL: como la salida es para un celular, si el video se
    copiaría tal cual (remux / transcode_audio) pero viene a más de
    MOBILE_TRANSCODE_MAX_FPS (30 por defecto), se fuerza transcode completo.
    Motivo: el decodificador de hardware del cel batalla con HD a 60fps
    (bloques / fotogramas soltados); el transcode reescala a 720p30 limpio
    (perfil móvil de _build_ffmpeg_command). Los 30fps/29.97 quedan intactos.
    """
    info = probe_stream_info(stream_url)
    mode = mode_from_codecs(info["video_codec"], info["audio_codec"])

    max_fps = getattr(settings, "MOBILE_TRANSCODE_MAX_FPS", 30)
    if (
        mode in ("remux", "transcode_audio")
        and info["video_codec"] is not None
        and info["fps"] is not None
        and info["fps"] > max_fps + 0.5
    ):
        return "transcode"
    return mode


def _build_ffmpeg_command(stream_url: str, output_path, mode: str) -> list:
    """
    Construye el comando FFmpeg según el modo elegido y empaqueta en HLS con
    segmentos rotatorios (sección 8 del plan).

    - mode "remux": -c copy (no recodifica, consumo mínimo).
    - mode "transcode_audio": copia el video y recodifica solo el audio a AAC.
      (En streams de solo audio, -c:v copy no tiene video que copiar y la
       salida queda solo con el audio ya convertido a AAC.)
    - mode "transcode": recodifica video a H.264 y audio a AAC.
    """
    ffmpeg_bin = getattr(settings, "FFMPEG_BIN", "ffmpeg")
    command = [
        ffmpeg_bin,
        "-y",
        "-fflags", "+genpts+discardcorrupt",
        "-err_detect", "ignore_err",
        "-i", stream_url,
    ]

    if mode == "remux":
        command += ["-c", "copy"]
    elif mode == "transcode_audio":
        command += ["-c:v", "copy", "-c:a", "aac"]
    else:
        # Transcode a PERFIL MÓVIL: como la salida es para un celular, se
        # recodifica a 720p / 30fps con bitrate acotado. Motivos:
        #   - 1080p60 con libx264 no lo aguanta la CPU en tiempo real (se
        #     atrasa -> buffering). 720p30 baja ~4.5x el trabajo de encode.
        #   - 720p es de sobra para pantalla de cel; el bitrate acotado da
        #     imagen limpia y estable sin saturar la red del celular.
        #   - scale=-2:'min(720,ih)' no reescala hacia arriba si el origen ya
        #     es menor a 720p (p.ej. canales SD).
        # -pix_fmt yuv420p: el decoder de hardware de Android rechaza yuv422p
        # o 10-bit; se fuerza 4:2:0 8-bit.
        command += [
            "-c:v", "libx264",
            "-preset", "veryfast",
            "-tune", "zerolatency",
            "-vf", "scale=-2:'min(720,ih)',fps=30",
            "-b:v", "2500k",
            "-maxrate", "2500k",
            "-bufsize", "5000k",
            "-pix_fmt", "yuv420p",
            "-g", "90",
            "-c:a", "aac",
            "-b:a", "128k",
        ]

    output_path = Path(output_path).resolve()
    segment_pattern = output_path.parent / "segment_%03d.ts"

    command += [
        "-f", "hls",
        "-hls_time", "3",
        "-hls_list_size", "6",
        "-hls_flags", "delete_segments",
        "-hls_segment_filename", str(segment_pattern),
        str(output_path),
    ]
    return command


def start_hls_transcode(stream_url: str, stream_id: str, forced_mode: str = None):
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
    mode = forced_mode or decide_mode(stream_url)
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
        _process_started_at[stream_id] = time.time()

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
        _process_started_at.pop(stream_id, None)

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
