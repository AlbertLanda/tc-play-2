"""
Servicio de transcoder HLS (prueba técnica controlada).

Toma una URL de stream original de Xtream, lanza un proceso FFmpeg en
segundo plano (sin bloquear el hilo de Django) y produce una salida HLS
"limpia" compuesta por un index.m3u8 y segmentos .ts, pensada para los
canales que llegan bien por red pero fallan en el navegador por códec o
empaquetado.

Objetivos de diseño:
    - El backend NO debe caerse si FFmpeg no está instalado.
    - No duplicar procesos si ya hay un HLS activo para el mismo canal Y el
      mismo perfil de dispositivo (ver "Clave de salida HLS" más abajo).
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


# --- Perfiles de salida por dispositivo (device_profile) -------------------
# El backend entrega una salida HLS optimizada según el tipo de dispositivo.
# El perfil decide DOS cosas:
#   1. normalize_fps: mobile/tv fuerzan transcode a 30fps cuando el origen
#      viene a más de 30fps (el decoder del cel batalla con HD a 60fps y la
#      TV prioriza estabilidad). web=False respeta el fps original (el
#      navegador/PC decodifica 60fps sin problema).
#   2. Los parámetros del transcode a H.264 (escala, bitrate, GOP).
#
# Perfil "mobile" reproduce EXACTAMENTE el comportamiento previo (720p30 /
# 2500k / g90) para no romper la app móvil actual: es el default cuando no se
# envía device_profile.
DEVICE_PROFILES = {
    "mobile": {
            "max_height": 720,
            "target_fps": 30,
            "video_bitrate": "1800k",
            "maxrate": "2000k",
            "bufsize": "4000k",
            "gop": "60",
            "normalize_fps": True,
        },
    "tv": {
        # TV / TV Box: COPY-FIRST. normalize_fps=False -> NO se fuerza transcode
        # por framerate; se respeta el video original (1080p60 incluido) y solo
        # se arregla el audio si el códec no es compatible (remux /
        # transcode_audio). Motivo: la validación de 720p30 se hizo en un
        # celular; el decoder de un TV Box es mucho más capaz y probablemente
        # reproduce el 1080p60 nativo sin recodificar (CPU ~0, mejor calidad).
        # La normalización a 720p30 queda para MÓVIL hasta medir el desempeño
        # real en una TV con el player final.
        #
        # Los parámetros de transcode (720p30/3000k) se conservan como FALLBACK:
        # si en las pruebas el player de TV muestra inestabilidad, basta poner
        # normalize_fps=True (o forzar el modo transcode) sin tocar nada más.
        "max_height": 720,
        "target_fps": 30,
        "video_bitrate": "3000k",
        "maxrate": "3000k",
        "bufsize": "6000k",
        "gop": "60",
        "normalize_fps": False,
    },
    "web": {
        # Navegador/PC: perfil automático actual. No reescala ni normaliza fps;
        # deja que decide_mode haga remux/transcode_audio y solo recodifica el
        # video cuando el códec no es web-compatible (preservando resolución).
        "max_height": None,
        "target_fps": None,
        "video_bitrate": None,
        "maxrate": None,
        "bufsize": None,
        "gop": "90",
        "normalize_fps": False,
    },
}

DEFAULT_DEVICE_PROFILE = "mobile"


# --- Perfiles de empaquetado HLS (hls_profile) -----------------------------
# Independientes del device_profile: controlan CÓMO se corta el HLS, no cómo
# se codifica el video. Sirven para la prueba A/B de arranque del plan:
#   - mobile_stable: comportamiento actual (segmentos de 2s, lista de 8,
#     exige 2 segmentos antes de devolver hls_url). Prioriza estabilidad.
#   - mobile_fast: segmentos de 1s, lista de 6, devuelve hls_url con 1 solo
#     segmento. Prioriza velocidad de arranque; NO dejar en producción si
#     genera pausas constantes.
HLS_PROFILES = {
    "mobile_stable": {"hls_time": "2", "hls_list_size": "8", "min_segments": 2},
    "mobile_fast": {"hls_time": "1", "hls_list_size": "6", "min_segments": 1},
}

DEFAULT_HLS_PROFILE = "mobile_stable"


def normalize_hls_profile(value) -> str:
    """
    Normaliza el hls_profile recibido a uno válido. None o cadena vacía caen
    al default (mobile_stable), igual que normalize_device_profile, para que
    los clientes actuales sigan funcionando sin enviar el parámetro.
    """
    if value is None or str(value).strip() == "":
        return DEFAULT_HLS_PROFILE
    profile = str(value).strip().lower()
    if profile not in HLS_PROFILES:
        raise ValueError(f"hls_profile inválido: {value}")
    return profile


def hls_profile_min_segments(hls_profile) -> int:
    """Segmentos mínimos que exige el ready check para este perfil HLS."""
    profile = normalize_hls_profile(hls_profile)
    return HLS_PROFILES[profile]["min_segments"]


def normalize_device_profile(value) -> str:
    """
    Normaliza el device_profile recibido a uno válido.

    None o cadena vacía -> DEFAULT_DEVICE_PROFILE (mobile), para que la app
    móvil actual siga funcionando sin enviar el parámetro. Un valor no
    reconocido lanza ValueError, para que la vista responda de forma
    controlada (invalid_device_profile) en vez de reventar.
    """
    if value is None or str(value).strip() == "":
        return DEFAULT_DEVICE_PROFILE
    profile = str(value).strip().lower()
    if profile not in DEVICE_PROFILES:
        raise ValueError(f"device_profile inválido: {value}")
    return profile


# --- Clave de salida HLS (stream_id + device_profile) ----------------------
# La salida HLS NO se identifica solo por stream_id: si lo hiciera, una TV que
# pide el canal 123 reutilizaría el HLS 720p30 que generó un celular y nunca
# recibiría su perfil. La unidad de identidad real es la pareja
# (stream_id, device_profile), y se representa como un texto plano:
#
#     123 + mobile -> "123-mobile"  ->  MEDIA/hls/123-mobile/index.m3u8
#     123 + tv     -> "123-tv"      ->  MEDIA/hls/123-tv/index.m3u8
#
# Se eligió la convención PLANA (un solo nivel de carpeta) y no la anidada
# (hls/tv/123/) porque cleanup_inactive() y get_transcoder_status() recorren
# los directorios de primer nivel de HLS_ROOT y tratan folder.name como la
# clave: con un nivel extra dejarían de limpiar en silencio.
#
# Todas las funciones de disco/proceso reciben ya la CLAVE (output_key), no el
# stream_id suelto. El llamador la construye una sola vez con
# build_output_key() y la pasa hacia abajo.

def build_output_key(stream_id, device_profile=DEFAULT_DEVICE_PROFILE) -> str:
    """
    Construye la clave de salida que aísla el HLS por perfil de dispositivo.

    Valida ambas partes: stream_id lanza ValueError si trae caracteres no
    permitidos (path traversal) y device_profile lanza ValueError si no es un
    perfil conocido. None/"" en el perfil cae a mobile (default).
    """
    return f"{sanitize_stream_id(stream_id)}-{normalize_device_profile(device_profile)}"


def split_output_key(output_key: str):
    """
    Descompone una clave de salida en (stream_id, device_profile).

    Devuelve device_profile None cuando la clave no trae sufijo de perfil
    conocido (carpetas antiguas anteriores a esta separación, o claves crudas).
    Como el stream_id admite guiones, se corta por el ÚLTIMO "-" y solo se
    acepta el sufijo si es un perfil válido: así "canal-01-tv" se parte bien
    en ("canal-01", "tv") y "canal-01" queda como ("canal-01", None).
    """
    stream_id, _, suffix = str(output_key).rpartition("-")
    if stream_id and suffix in DEVICE_PROFILES:
        return stream_id, suffix
    return str(output_key), None


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
# Mapa output_key ("123-tv") -> subprocess.Popen del FFmpeg lanzado. La llave
# incluye el perfil, así que el mismo canal puede tener un proceso por
# dispositivo sin pisarse. Es un registro simple por proceso de Django; en
# producción se necesitaría algo más robusto (cola de trabajos, etc.).
_processes = {}
# Mapa output_key -> timestamp (time.time()) en que se lanzó ese FFmpeg. Sirve
# para calcular el uptime del proceso. Vive en memoria igual que _processes,
# así que se pierde al reiniciar Django (uptime = None tras un reinicio).
_process_started_at = {}
# Mapa output_key -> device_profile con el que se lanzó ese FFmpeg. Para
# Xtream el perfil se deriva de la clave; para salidas estables sin sufijo,
# como Astra, este registro permite informar el preset mientras el proceso de
# Django siga vivo.
_process_profile = {}
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


def _hls_dir(output_key: str):
    return settings.HLS_ROOT / output_key


def _index_path(output_key: str):
    return _hls_dir(output_key) / "index.m3u8"

def wait_for_hls_index(output_key: str, timeout_seconds: int = 8) -> bool:
    """
    Espera unos segundos a que FFmpeg genere el index.m3u8.
    Devuelve True si el archivo existe; False si no aparece dentro del tiempo.

    Espera "ligera": solo mira el index. Para Android úsese
    wait_for_hls_ready(), que además exige segmentos .ts suficientes.
    """
    index = _index_path(output_key)
    deadline = time.time() + timeout_seconds

    while time.time() < deadline:
        if index.exists() and index.stat().st_size > 0:
            return True
        time.sleep(0.5)

    return False


def count_ts_segments(output_key: str) -> int:
    """Número de segmentos .ts en disco para una salida (0 si no hay carpeta)."""
    folder = _hls_dir(output_key)
    if not folder.exists():
        return 0
    return len(list(folder.glob("*.ts")))


def _hls_is_ready(output_key: str, min_segments: int) -> bool:
    """
    True si la salida HLS ya es reproducible: index.m3u8 existe con tamaño
    mayor a 0, no está dañada y hay al menos ``min_segments`` segmentos .ts.
    """
    index = _index_path(output_key)
    if not index.exists() or index.stat().st_size == 0:
        return False
    if is_hls_output_damaged(output_key):
        return False
    return count_ts_segments(output_key) >= min_segments


def wait_for_hls_ready(
    output_key: str, timeout_seconds: int = 15, min_segments: int = 2
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
        if _hls_is_ready(output_key, min_segments):
            return True

        # Si el proceso FFmpeg ya terminó y la salida aún no está lista, no
        # tiene sentido seguir esperando: el canal no va a producir más.
        with _lock:
            process = _processes.get(output_key)
        if process is not None and process.poll() is not None:
            return _hls_is_ready(output_key, min_segments)

        time.sleep(0.5)

    return False

def wait_for_hls_ready_metrics(
    output_key: str, timeout_seconds: int = 15, min_segments: int = 2
) -> dict:
    """
    Igual que wait_for_hls_ready(), pero además mide los tiempos del arranque
    para la instrumentación del plan. Devuelve un dict con:

        - ready:            True si la salida quedó reproducible a tiempo.
        - index_ms:         ms hasta que apareció el index.m3u8, o None.
        - first_segment_ms: ms hasta observar el PRIMER segmento .ts, o None
                            si nunca apareció.
        - ready_ms:         ms hasta que el ready check pasó, o None.
        - segments:         segmentos .ts en disco al terminar la espera.

    Separar index_ms de first_segment_ms es lo que permite ubicar el cuello de
    botella: si el index tarda, el problema es que FFmpeg no logra abrir el
    origen (Xtream/red); si el index sale rápido pero el primer .ts tarda, el
    costo está en la codificación.

    Misma salida anticipada que wait_for_hls_ready: si el proceso FFmpeg
    murió y la salida no está lista, no se sigue esperando en vano.
    """
    started = time.monotonic()
    deadline = started + timeout_seconds
    index = _index_path(output_key)
    index_ms = None
    first_segment_ms = None

    def _elapsed_ms():
        return round((time.monotonic() - started) * 1000)

    def _result(ready: bool) -> dict:
        return {
            "ready": ready,
            "index_ms": index_ms,
            "first_segment_ms": first_segment_ms,
            "ready_ms": _elapsed_ms() if ready else None,
            "segments": count_ts_segments(output_key),
        }

    while time.monotonic() < deadline:
        if index_ms is None and index.exists() and index.stat().st_size > 0:
            index_ms = _elapsed_ms()

        if first_segment_ms is None and count_ts_segments(output_key) >= 1:
            first_segment_ms = _elapsed_ms()

        if _hls_is_ready(output_key, min_segments):
            return _result(True)

        with _lock:
            process = _processes.get(output_key)
        if process is not None and process.poll() is not None:
            return _result(_hls_is_ready(output_key, min_segments))

        time.sleep(0.25)

    return _result(False)


def build_hls_url(request, output_key: str) -> str:
    """
    Construye la URL pública del index.m3u8 a partir de MEDIA_URL y del
    host de la petición, sin credenciales.

    En consumidores con varios perfiles, la clave lleva el perfil incrustado:
    .../hls/123-mobile/... y .../hls/123-tv/.... Consumidores con una única
    salida estable pueden usar una clave sin sufijo, como .../hls/astra-5/.
    """
    relative = f"{settings.MEDIA_URL}hls/{output_key}/index.m3u8"
    return request.build_absolute_uri("/" + relative.lstrip("/"))


def is_hls_output_damaged(output_key: str) -> bool:
    """
    True si la salida HLS existe pero no sirve para TV en vivo:
    - index.m3u8 vacío,
    - carpeta sin segmentos .ts,
    - playlist cerrada con #EXT-X-ENDLIST.

    En TV en vivo, #EXT-X-ENDLIST significa que FFmpeg terminó y la salida
    ya no se renovará; no debe reutilizarse.
    """
    index = _index_path(output_key)
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

    # index con contenido pero sin segmentos en disco -> playlist rota.
    segments = list(_hls_dir(output_key).glob("*.ts"))
    return len(segments) == 0


def get_index_age_seconds(output_key: str):
    """
    Segundos transcurridos desde la última escritura del index.m3u8, o None
    si no existe. FFmpeg reescribe la playlist cada vez que cierra un
    segmento (~HLS_TIME), así que este número es la señal más fiable de si
    la salida sigue recibiendo contenido nuevo.
    """
    index = _index_path(output_key)
    if not index.exists():
        return None
    return round(time.time() - index.stat().st_mtime, 1)


def get_process_uptime_seconds(output_key: str):
    """
    Segundos que lleva CORRIENDO el proceso FFmpeg de esta salida, o None
    si no hay un proceso vivo registrado.

    Se basa en el registro en memoria (_process_started_at), así que —igual
    que process_alive— devuelve None tras un reinicio de Django aunque FFmpeg
    siga vivo. Solo cuenta si el proceso sigue en ejecución: si ya terminó,
    el uptime deja de tener sentido y se devuelve None.
    """
    with _lock:
        process = _processes.get(output_key)
        started = _process_started_at.get(output_key)

    if process is None or started is None:
        return None
    if process.poll() is not None:  # el proceso ya terminó
        return None
    return round(time.time() - started, 1)


def is_output_live(output_key: str) -> bool:
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
    if is_hls_output_damaged(output_key):
        return False

    age = get_index_age_seconds(output_key)
    if age is None:
        return False

    ttl = getattr(settings, "HLS_ACTIVE_TTL_SECONDS", 30)
    return age <= ttl


def _log_recovery(output_key: str, reason: str, reused: bool = False) -> None:
    """
    Log técnico SEGURO de una decisión de recuperación de HLS.

    Registra solo stream_id + device_profile + métricas de la salida en disco
    (reason, ready, live, index_age_seconds, segments, reused). Nunca la URL
    original, el usuario ni la contraseña.
    """
    status = get_hls_status(output_key)
    logger.info(
        "hls_recovery stream_id=%s device_profile=%s reason=%s ready=%s live=%s "
        "index_age_seconds=%s segments=%s hls_reused=%s",
        status["stream_id"],
        status["device_profile"],
        reason,
        status["ready"],
        status["live"],
        status["index_age_seconds"],
        status["segments"],
        reused,
    )


def is_stream_active(output_key: str) -> bool:
    """
    True si ya existe un HLS reutilizable para ESTA salida (stream_id +
    device_profile); False si hay que (re)generarlo.

    Al recibir la clave con el perfil incrustado, un HLS "mobile" activo NO
    hace que la consulta "tv" del mismo canal dé activo: son dos salidas
    distintas y cada una se evalúa contra su propia carpeta y su propio
    proceso. Recuperación automática de salidas muertas:

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
        process = _processes.get(output_key)

    # Proceso FFmpeg registrado y vivo -> activo, se reutiliza.
    if process is not None and process.poll() is None:
        return True

    index = _index_path(output_key)
    if not index.exists():
        return False

    # Salida dañada (index vacío o sin segmentos): no reutilizarla.
    if is_hls_output_damaged(output_key):
        _log_recovery(output_key, "damaged_hls_output")
        remove_hls_output(output_key)
        return False

    # HLS con index fresco (live=True) -> sigue produciendo, se reutiliza.
    if is_output_live(output_key):
        return True

    # HLS listo pero muerto (ready=True + live=False): se limpia el proceso
    # zombie y la salida para forzar la regeneración en el siguiente request.
    _log_recovery(output_key, "dead_hls_output")
    stop_hls_transcode(output_key)
    remove_hls_output(output_key)
    return False


def remove_hls_output(output_key: str) -> bool:
    """
    Borra la carpeta HLS de UNA salida (stream_id + perfil): index.m3u8 y sus
    segmentos. Devuelve True si existía algo que borrar. Borrar la salida
    "123-tv" no afecta a "123-mobile". No toca el proceso: para detenerlo
    usar stop_hls_transcode().
    """
    folder = _hls_dir(output_key)
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
        profile_snapshot = dict(_process_profile)

    alive = {sid for sid, proc in snapshot.items() if proc.poll() is None}

    outputs = []
    hls_root = settings.HLS_ROOT
    if hls_root.exists():
        for folder in sorted(hls_root.iterdir()):
            if not folder.is_dir():
                continue

            # El nombre de la carpeta ES la clave de salida ("123-tv"); de ahí
            # se derivan el stream_id y el perfil que se reportan por separado.
            output_key = folder.name
            stream_id, device_profile = split_output_key(output_key)
            if device_profile is None:
                device_profile = profile_snapshot.get(output_key)
            index = folder / "index.m3u8"
            if index.exists():
                stat = index.stat()
                index_age = round(time.time() - stat.st_mtime, 1)
                index_size = stat.st_size
            else:
                index_age = None
                index_size = 0

            outputs.append({
                "output_key": output_key,
                "stream_id": stream_id,
                "device_profile": device_profile,
                "process_alive": output_key in alive,
                "index_exists": index.exists(),
                "index_age_seconds": index_age,
                "index_size_bytes": index_size,
                "segments": len(list(folder.glob("*.ts"))),
                "damaged": is_hls_output_damaged(output_key),
            })

    return {
        "active_processes": len(alive),
        "max_concurrent": getattr(settings, "MAX_CONCURRENT_TRANSCODES", 5),
        "outputs": outputs,
    }


def get_hls_status(output_key: str) -> dict:
    """
    Estado de UNA salida HLS (stream_id + device_profile), para el endpoint de
    diagnóstico hls-status. Informa si existe el index, su tamaño, cuántos
    segmentos hay, si la salida está dañada y si sigue generándose contenido
    nuevo. El perfil se reporta siempre: se deriva de la propia clave, así que
    sigue siendo correcto aunque Django se haya reiniciado y el registro en
    memoria se haya perdido.

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
    folder = _hls_dir(output_key)
    index = _index_path(output_key)
    index_exists = index.exists()
    index_size = index.stat().st_size if index_exists else 0
    segments = len(list(folder.glob("*.ts"))) if folder.exists() else 0
    damaged = is_hls_output_damaged(output_key)

    stream_id, device_profile = split_output_key(output_key)

    with _lock:
        process = _processes.get(output_key)
        # La clave manda; el registro en memoria cubre claves estables sin
        # sufijo de perfil, como las salidas de Astra.
        if device_profile is None:
            device_profile = _process_profile.get(output_key)
    process_alive = process is not None and process.poll() is None

    min_segments_required = getattr(settings, "HLS_MIN_SEGMENTS", 2)
    ready = (
        index_exists
        and index_size > 0
        and not damaged
        and segments >= min_segments_required
    )
    live = is_output_live(output_key)

    # la salida necesita recuperación cuando es reproducible pero ya
    # no se renueva (ready=True + live=False). El backend debe limpiarla y
    # regenerarla en vez de reutilizar segmentos que el player agotará.
    recovery_required = ready and not live

    # Uptime del proceso FFmpeg: cuánto lleva corriendo este canal. Se expone
    # también en minutos para leerlo cómodo. None si no hay proceso vivo
    # registrado (o tras reiniciar Django, igual que process_alive).
    uptime_seconds = get_process_uptime_seconds(output_key)
    uptime_minutes = (
        round(uptime_seconds / 60, 2) if uptime_seconds is not None else None
    )

    return {
        "output_key": output_key,
        "stream_id": stream_id,
        "device_profile": device_profile,
        "index_exists": index_exists,
        "index_size_bytes": index_size,
        "index_age_seconds": get_index_age_seconds(output_key),
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


# --- Caché de sondeos ffprobe ----------------------------------------------
# ffprobe sobre el stream original puede tardar varios segundos (hasta 20s de
# timeout) y es una de las etapas más caras del arranque. Los códecs de un
# canal no cambian entre un zapping y otro, así que se cachea el resultado por
# stream_id durante PROBE_CACHE_TTL_SECONDS: el segundo arranque del mismo
# canal se salta el sondeo completo. La clave es el stream_id (no la URL, que
# lleva credenciales y no debe vivir en estructuras de larga duración).
_probe_cache = {}


def _get_cached_probe(cache_key):
    if cache_key is None:
        return None
    ttl = getattr(settings, "PROBE_CACHE_TTL_SECONDS", 300)
    with _lock:
        entry = _probe_cache.get(cache_key)
    if entry is None:
        return None
    cached_at, info = entry
    if time.time() - cached_at > ttl:
        with _lock:
            _probe_cache.pop(cache_key, None)
        return None
    return info


def _store_cached_probe(cache_key, info) -> None:
    if cache_key is None:
        return
    # Un sondeo fallido (todo None) no se cachea: pudo ser un problema
    # transitorio de red y cachearlo condenaría al canal a transcode.
    if all(value is None for value in info.values()):
        return
    with _lock:
        _probe_cache[cache_key] = (time.time(), info)


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


def decide_mode(
    stream_url: str, device_profile: str = DEFAULT_DEVICE_PROFILE,
    cache_key=None,
) -> str:
    """
    Sondea el stream original y decide cómo procesarlo, gastando la menor CPU
    posible. Si no se puede determinar el códec, transcodifica por seguridad.
    Ver mode_from_codecs() para la tabla base de decisión.

    Normalización por fps (perfiles mobile/tv): si el video se copiaría tal
    cual (remux / transcode_audio) pero viene a más de MOBILE_TRANSCODE_MAX_FPS
    (30 por defecto), se fuerza transcode completo. Motivo: el decodificador de
    hardware del cel batalla con HD a 60fps (bloques / fotogramas soltados) y
    el perfil TV prioriza estabilidad; el transcode reescala a 720p30 limpio.
    Los 30fps/29.97 quedan intactos.

    Perfil web: normalize_fps=False -> respeta el fps original (el navegador/PC
    decodifica 60fps sin problema), así que solo remux/transcode_audio según
    el códec, sin forzar transcode por framerate.

    cache_key (opcional, típicamente el stream_id): reutiliza el sondeo
    ffprobe cacheado durante PROBE_CACHE_TTL_SECONDS. Acelera el segundo
    arranque del mismo canal, que se salta el ffprobe completo.
    """
    info = _get_cached_probe(cache_key)
    if info is None:
        info = probe_stream_info(stream_url)
        _store_cached_probe(cache_key, info)
    mode = mode_from_codecs(info["video_codec"], info["audio_codec"])

    profile = DEVICE_PROFILES.get(device_profile, DEVICE_PROFILES[DEFAULT_DEVICE_PROFILE])
    if not profile["normalize_fps"]:
        return mode

    max_fps = getattr(settings, "MOBILE_TRANSCODE_MAX_FPS", 30)
    if (
        mode in ("remux", "transcode_audio")
        and info["video_codec"] is not None
        and info["fps"] is not None
        and info["fps"] > max_fps + 0.5
    ):
        return "transcode"
    return mode


def _build_ffmpeg_command(
    stream_url: str, output_path, mode: str,
    device_profile: str = DEFAULT_DEVICE_PROFILE,
    hls_profile: str = DEFAULT_HLS_PROFILE,
) -> list:
    """
    Construye el comando FFmpeg según el modo elegido y empaqueta en HLS con
    segmentos rotatorios (sección 8 del plan).

    - mode "remux": -c copy (no recodifica, consumo mínimo).
    - mode "transcode_audio": copia el video y recodifica solo el audio a AAC.
      (En streams de solo audio, -c:v copy no tiene video que copiar y la
       salida queda solo con el audio ya convertido a AAC.)
    - mode "transcode": recodifica video a H.264 y audio a AAC, con los
      parámetros del perfil (device_profile): resolución/fps/bitrate.

    El device_profile solo afecta al modo "transcode": mobile y tv acotan la
    resolución y normalizan fps; web preserva resolución y fps del origen.
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
        # Transcode a H.264 según el PERFIL del dispositivo:
        #   - mobile: 720p30 / 2500k. El decoder del cel no aguanta 1080p60.
        #   - tv:     720p30 / 3000k. Mejor calidad sin saturar CPU (fase 1).
        #   - web:    resolución y fps originales, calidad por CRF. El
        #             navegador/PC decodifica de sobra; solo se recodifica
        #             porque el códec de origen no es web-compatible.
        # scale=-2:'min(H,ih)' no reescala hacia arriba (canales SD quedan
        # igual). -pix_fmt yuv420p: el decoder de Android rechaza yuv422p o
        # 10-bit; se fuerza 4:2:0 8-bit (universal).
        profile = DEVICE_PROFILES.get(
            device_profile, DEVICE_PROFILES[DEFAULT_DEVICE_PROFILE]
        )

        preset = "ultrafast" if device_profile == "mobile" else "veryfast"

        command += [
            "-c:v", "libx264",
            "-preset", preset,
            "-tune", "zerolatency",
        ]

        video_filters = []
        if profile["max_height"] is not None:
            video_filters.append(f"scale=-2:'min({profile['max_height']},ih)'")
        if profile["target_fps"] is not None:
            video_filters.append(f"fps={profile['target_fps']}")
        if video_filters:
            command += ["-vf", ",".join(video_filters)]

        if profile["video_bitrate"] is not None:
            command += [
                "-b:v", profile["video_bitrate"],
                "-maxrate", profile["maxrate"],
                "-bufsize", profile["bufsize"],
            ]
        else:
            # web sin bitrate objetivo: calidad constante, preserva resolución.
            command += ["-crf", "23"]

        command += [
            "-pix_fmt", "yuv420p",
            "-g", profile["gop"],
            "-c:a", "aac",
            "-b:a", "128k",
        ]

    output_path = Path(output_path).resolve()
    segment_pattern = output_path.parent / "segment_%03d.ts"

    # El empaquetado HLS lo decide el hls_profile (A/B stable vs fast); el
    # default reproduce el comportamiento previo (2s x 8 segmentos).
    packaging = HLS_PROFILES[normalize_hls_profile(hls_profile)]

    command += [
        "-f", "hls",
        "-hls_time", packaging["hls_time"],
        "-hls_list_size", packaging["hls_list_size"],
        "-hls_flags", "delete_segments+append_list+omit_endlist",
        "-hls_segment_filename", str(segment_pattern),
        str(output_path),
    ]
    return command


def start_hls_transcode(
    stream_url: str, stream_id: str, forced_mode: str = None,
    device_profile: str = DEFAULT_DEVICE_PROFILE,
    output_key: str = None,
    hls_profile: str = None,
    metrics: dict = None,
):
    """
    Lanza (o reutiliza) un proceso FFmpeg que genera la salida HLS para el
    stream_id dado, según el device_profile (mobile / tv / web).

    Devuelve una tupla (output_key, reused: bool, mode: str|None). Por
    defecto, output_key es "<stream_id>-<device_profile>". Un consumidor que
    tiene una única salida estable (Astra) puede proporcionar una clave
    explícita para conservar su ruta histórica sin acoplarla al perfil de
    codificación. No bloquea el request: FFmpeg corre en segundo plano vía
    subprocess.Popen. En caso de reutilización, mode es None.

    AISLAMIENTO POR PERFIL: cuando no se proporciona output_key, la
    reutilización se evalúa contra la clave completa. Por eso una TV que pide
    el canal 123 NO hereda el HLS que dejó un celular. output_key desacopla la
    identidad de almacenamiento del preset de FFmpeg, pero no debe usarse en
    endpoints que permiten seleccionar varios perfiles.

    hls_profile (opcional): perfil de empaquetado HLS (mobile_stable /
    mobile_fast) para la prueba A/B de arranque. None cae al default.

    metrics (opcional): dict del llamador donde se registran los tiempos de
    cada etapa en ms (probe_ms, ffmpeg_spawn_ms) para la medición del plan.

    Lanza FFmpegNotAvailableError / HlsOutputError / TranscoderStartError
    según el punto de falla, y ValueError si stream_id o device_profile no
    son válidos.
    """
    if metrics is None:
        metrics = {}

    if not is_ffmpeg_available():
        raise FFmpegNotAvailableError("FFmpeg no está disponible.")

    device_profile = normalize_device_profile(device_profile)
    hls_profile = normalize_hls_profile(hls_profile)
    if output_key is None:
        output_key = build_output_key(stream_id, device_profile)
    else:
        output_key = sanitize_stream_id(output_key)

    # Si ya hay algo activo para ESTA salida (stream + perfil), se reutiliza.
    if is_stream_active(output_key):
        return output_key, True, None

    # Antes de contar procesos, limpia referencias muertas del registry.
    cleanup_finished_process_registry()

    # Límite de procesos concurrentes: si ya se alcanzó, no se lanza otro
    # para no saturar el servidor.
    max_concurrent = getattr(settings, "MAX_CONCURRENT_TRANSCODES", 5)
    if count_active_processes() >= max_concurrent:
        raise TranscoderBusyError(
            "Se alcanzó el límite de procesos de transcoder concurrentes."
        )

    # Preparar la carpeta de salida (una por perfil).
    output_dir = _hls_dir(output_key)
    try:
        output_dir.mkdir(parents=True, exist_ok=True)
    except OSError as error:
        raise HlsOutputError("No se pudo crear la carpeta HLS.") from error

    # ffprobe decide: remux si el códec ya es compatible con web, transcode
    # si no (y según el perfil, se normaliza fps). Así solo se gasta CPU
    # cuando realmente hace falta. El sondeo se cachea por stream_id para
    # que el zapping de vuelta al mismo canal se salte el ffprobe.
    probe_started = time.monotonic()
    mode = forced_mode or decide_mode(
        stream_url, device_profile, cache_key=sanitize_stream_id(stream_id)
    )
    metrics["probe_ms"] = round((time.monotonic() - probe_started) * 1000)

    command = _build_ffmpeg_command(
        stream_url, _index_path(output_key), mode, device_profile, hls_profile
    )

    spawn_started = time.monotonic()
    try:
        process = subprocess.Popen(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise TranscoderStartError("No se pudo iniciar FFmpeg.") from error
    metrics["ffmpeg_spawn_ms"] = round((time.monotonic() - spawn_started) * 1000)

    with _lock:
        _processes[output_key] = process
        _process_started_at[output_key] = time.time()
        _process_profile[output_key] = device_profile

    # Asegura que el hilo de limpieza automática esté corriendo.
    ensure_cleanup_thread()

    return output_key, False, mode


def count_active_processes() -> int:
    """Número de procesos FFmpeg vivos en el registro."""
    with _lock:
        return sum(1 for p in _processes.values() if p.poll() is None)


# --- Tiempos de arranque acumulados por canal (plan 5.6) -------------------
# Registro en memoria de las últimas mediciones de arranque de cada salida,
# para responder "cuánto tarda en promedio este canal" sin tener que leer los
# logs a mano. Igual que _processes, vive en el proceso de Django y se pierde
# al reiniciar: es material de diagnóstico, no una métrica persistente.
_timing_samples = {}


def record_start_timing(
    stream_id, device_profile, hls_profile, mode, timings: dict
) -> None:
    """
    Guarda una muestra de tiempos de arranque para un canal.

    Solo debe llamarse en arranques REALES (no en reutilizaciones), para que
    los promedios reflejen lo que tarda levantar el canal desde cero.
    """
    key = build_output_key(stream_id, device_profile)
    max_samples = getattr(settings, "TIMING_SAMPLES_PER_CHANNEL", 20)

    sample = dict(timings)
    sample["mode"] = mode
    sample["hls_profile"] = hls_profile

    with _lock:
        samples = _timing_samples.setdefault(key, [])
        samples.append(sample)
        # Ventana deslizante: solo se conservan las últimas N muestras.
        del samples[:-max_samples]


def _average(samples, field):
    """Promedio de un campo ignorando las muestras donde no se pudo medir."""
    values = [s.get(field) for s in samples if s.get(field) is not None]
    if not values:
        return None
    return round(sum(values) / len(values))


def get_timing_summary() -> list:
    """
    Resumen de tiempos por canal para el endpoint de monitoreo: cuántos
    arranques se midieron, el promedio de cada etapa y el peor caso.

    Sirve para comparar canales rápidos contra lentos sin releer los logs.
    No expone credenciales ni URLs de origen.
    """
    with _lock:
        snapshot = {key: list(samples) for key, samples in _timing_samples.items()}

    summary = []
    for key, samples in sorted(snapshot.items()):
        if not samples:
            continue

        stream_id, device_profile = split_output_key(key)
        ready_values = [
            s["ready_total_ms"] for s in samples
            if s.get("ready_total_ms") is not None
        ]

        summary.append({
            "output_key": key,
            "stream_id": stream_id,
            "device_profile": device_profile,
            "samples": len(samples),
            "last_mode": samples[-1].get("mode"),
            "last_hls_profile": samples[-1].get("hls_profile"),
            "avg_probe_ms": _average(samples, "probe_ms"),
            "avg_index_ms": _average(samples, "index_ms"),
            "avg_first_segment_ms": _average(samples, "first_segment_ms"),
            "avg_ready_total_ms": _average(samples, "ready_total_ms"),
            "worst_ready_total_ms": max(ready_values) if ready_values else None,
        })

    return summary


def reset_timing_samples() -> None:
    """Vacía las muestras acumuladas (útil entre tandas de pruebas)."""
    with _lock:
        _timing_samples.clear()

def cleanup_finished_process_registry() -> list:
    """
    Limpia del registro en memoria los procesos FFmpeg que ya terminaron.

    Esto evita que el backend conserve referencias viejas después de cambios
    rápidos de canal o errores de FFmpeg. No borra salidas HLS; solo limpia
    el registry de procesos muertos.
    """
    removed = []

    with _lock:
        snapshot = dict(_processes)

    for output_key, process in snapshot.items():
        if process.poll() is None:
            continue

        with _lock:
            current = _processes.get(output_key)
            if current is process and current.poll() is not None:
                _processes.pop(output_key, None)
                _process_started_at.pop(output_key, None)
                _process_profile.pop(output_key, None)
                removed.append(output_key)

    if removed:
        logger.info("cleanup_finished_process_registry removed=%s", removed)

    return removed


def stop_outputs_for_device_profile(
    device_profile: str, keep_output_key: str = None, remove_async: bool = False
) -> list:
    """
    Detiene salidas HLS existentes para un perfil específico.

    Uso principal en staging móvil: antes de abrir un nuevo canal mobile,
    se limpian otros canales mobile anteriores para no saturar Azure con
    procesos FFmpeg acumulados.

    remove_async=True: el proceso FFmpeg se detiene SIEMPRE en el momento
    (eso es lo urgente al cambiar de canal: liberar CPU y evitar audio
    duplicado), pero el borrado de la carpeta HLS vieja se hace en un hilo
    aparte para no retrasar la respuesta del canal nuevo. Las carpetas son
    distintas por (stream_id, perfil), así que borrar la vieja en paralelo
    no toca la salida nueva.
    """
    profile = normalize_device_profile(device_profile)
    stopped = []
    to_remove = []
    keys = set()

    with _lock:
        keys.update(_processes.keys())

    hls_root = settings.HLS_ROOT
    if hls_root.exists():
        for folder in hls_root.iterdir():
            if folder.is_dir():
                keys.add(folder.name)

    for output_key in sorted(keys):
        if keep_output_key is not None and output_key == keep_output_key:
            continue

        _, output_profile = split_output_key(output_key)
        if output_profile != profile:
            continue

        stopped_process = stop_hls_transcode(output_key)

        if remove_async:
            had_output = _hls_dir(output_key).exists()
            if had_output:
                to_remove.append(output_key)
            removed_output = had_output
        else:
            removed_output = remove_hls_output(output_key)

        if stopped_process or removed_output:
            stopped.append(output_key)

    if to_remove:
        threading.Thread(
            target=lambda keys=to_remove: [remove_hls_output(k) for k in keys],
            daemon=True,
            name="hls-remove-replaced",
        ).start()

    if stopped:
        logger.info(
            "stop_outputs_for_device_profile profile=%s keep=%s stopped=%s",
            profile,
            keep_output_key,
            stopped,
        )

    return stopped


def stop_hls_transcode(output_key: str) -> bool:
    """
    Detiene el proceso FFmpeg asociado a UNA clave de salida, si existe.
    Devuelve True si había un proceso que detener. Detener "123-tv" deja
    intacto "123-mobile"; detener "astra-5" afecta solo esa salida web.
    """
    with _lock:
        process = _processes.pop(output_key, None)
        _process_started_at.pop(output_key, None)
        _process_profile.pop(output_key, None)

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
