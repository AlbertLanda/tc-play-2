# Transcoder HLS (prueba técnica)

Documento técnico del proxy/transcoder HLS con FFmpeg. Corresponde al
Día 5 del plan de trabajo backend.

> ⚠️ **Esto es una prueba técnica controlada, NO una versión de
> producción.** El transcoder consume recursos y debe usarse solo para
> canales que realmente fallen en el navegador. Los canales que ya
> reproducen directo deben mantenerse por la ruta normal de Xtream.

> ℹ️ **Control de procesos (Día 7):** el ciclo de vida de los procesos
> FFmpeg (detener, consultar estado, limpiar salidas dañadas) y los
> endpoints `stop-proxy` / `proxy-status` para Astra se documentan en
> [`astra_control_procesos.md`](astra_control_procesos.md).

> ℹ️ **Control y diagnóstico Xtream (Día 8):** los endpoints `stop-proxy`,
> `proxy-status` y `diagnose-stream` para canales Xtream (códecs y modo
> recomendado) se documentan en
> [`xtream_control_procesos_diagnostico.md`](xtream_control_procesos_diagnostico.md).

## 1. Objetivo

Algunos canales llegan bien por red pero fallan en el navegador por
incompatibilidad de códec, empaquetado o fragmentos TS. Para esos casos,
el backend puede tomar el stream original de Xtream, pasarlo por FFmpeg y
generar una salida HLS "limpia" (`index.m3u8` + segmentos `.ts`) que el
web player sí puede reproducir.

```
Xtream original → Backend Django → FFmpeg → HLS limpio → Web Player
```

## 2. Flujo del endpoint

`POST /api/xtream/live/proxy-url/`

Body (sin credenciales reales):

```json
{
  "username": "usuario_cliente_prueba",
  "password": "password_cliente_prueba",
  "stream_id": 123
}
```

Respuesta esperada:

```json
{
  "success": true,
  "stream_id": "123",
  "hls_url": "http://127.0.0.1:8000/media/hls/123/index.m3u8",
  "mode": "transcode_audio",
  "reused": false
}
```

- `mode` indica cómo se procesó el canal: `remux`, `transcode_audio` o
  `transcode` (ver sección "Decisión automática de modo"). En reutilización
  es `null`.
- `reused: true` indica que ya había un HLS activo para ese `stream_id` y
  se reutilizó en lugar de lanzar otro proceso FFmpeg.
- La URL original de Xtream (con credenciales) **nunca** se devuelve.

## 3. Componentes

| Archivo | Rol |
|---|---|
| `xtream/services/transcoder.py` | Sondea el códec (ffprobe), decide el modo, construye el comando FFmpeg, valida FFmpeg, evita duplicados y lanza el proceso. |
| `xtream/views.py` → `live_proxy_url` | Endpoint: valida entrada, arma la URL original y delega en el transcoder. |
| `xtream/urls.py` | Registra `live/proxy-url/`. |
| `config/settings.py` | `MEDIA_ROOT`, `MEDIA_URL`, `FFMPEG_BIN`, `FFPROBE_BIN`, `HLS_ROOT`, `HLS_ACTIVE_TTL_SECONDS`. |
| `config/urls.py` | Sirve `/media/` solo en `DEBUG`. |

## 4. Decisión automática de modo

Antes de lanzar FFmpeg, el transcoder inspecciona el códec ORIGINAL del canal
con `ffprobe` y elige el modo que **menos CPU** consuma garantizando
compatibilidad con el navegador:

| Códec original | Modo | FFmpeg | CPU (medido, 1 canal) |
|---|---|---|---|
| video h264 + audio aac/mp3 | `remux` | `-c copy` | ~0-1% de un núcleo |
| video h264 + audio incompatible (mp2, ac3, aac_latm) | `transcode_audio` | `-c:v copy -c:a aac` | ~8% de un núcleo |
| video incompatible (hevc, mpeg2, …) o códec desconocido | `transcode` | `-c:v libx264 -c:a aac` | ~82% de un núcleo |

Regla de compatibilidad web: video `h264` **y** audio `aac`/`mp3`. Cualquier
otra cosa se recodifica. Si `ffprobe` no puede leer el códec, se transcodifica
por seguridad (garantiza compatibilidad).

Medición comparativa sobre el mismo canal: `transcode_audio` (8.3% de un
núcleo) frente a `transcode` completo (82.3%) → **~10× menos CPU**, además de
preservar la calidad de video al no recomprimirlo.

## 5. Comando FFmpeg (salida HLS)

En cualquier modo, la salida se empaqueta en HLS igual; solo cambian los
flags de códec según la tabla anterior. Ejemplo en modo transcode:

```
ffmpeg -y -i "URL_ORIGINAL_XTREAM" \
  -c:v libx264 -preset veryfast -tune zerolatency \
  -c:a aac \
  -f hls \
  -hls_time 3 \
  -hls_list_size 6 \
  -hls_flags delete_segments \
  media/hls/<STREAM_ID>/index.m3u8
```

- `-hls_flags delete_segments` mantiene solo los últimos segmentos, evitando
  que el disco crezca de forma indefinida en un canal en vivo.
- El proceso se lanza con `subprocess.Popen` (no bloquea Django).

## 6. Configuración

| Setting | Default | Descripción |
|---|---|---|
| `FFMPEG_BIN` | `ffmpeg` | Ruta o nombre del binario de FFmpeg. Configurable por entorno. |
| `FFPROBE_BIN` | `ffprobe` | Ruta o nombre del binario de ffprobe (para leer el códec). |
| `MEDIA_ROOT` | `backend/media` | Raíz de archivos generados en runtime. |
| `HLS_ROOT` | `media/hls` | Carpeta de salidas HLS por `stream_id`. |
| `HLS_ACTIVE_TTL_SECONDS` | `30` | Ventana en la que un `index.m3u8` se considera "activo" para no duplicar procesos. |
| `MAX_CONCURRENT_TRANSCODES` | `5` | Máximo de procesos FFmpeg simultáneos; al superarlo responde `transcoder_busy`. |
| `HLS_CLEANUP_TTL_SECONDS` | `300` | Si la salida HLS no se actualiza en este tiempo, se detiene el proceso y se borra la carpeta. |
| `HLS_CLEANUP_INTERVAL_SECONDS` | `60` | Frecuencia del hilo de limpieza automática. |

Se pueden sobrescribir por variables de entorno (`.env`), p. ej.:

```
FFMPEG_BIN=C:\ffmpeg\bin\ffmpeg.exe
FFPROBE_BIN=C:\ffmpeg\bin\ffprobe.exe
```

## 7. Manejo de errores

El backend **no se cae** aunque FFmpeg no esté instalado.

| error_code | HTTP | Cuándo |
|---|---|---|
| `validation_error` | 400 | Faltan datos o `stream_id` inválido. |
| `ffmpeg_not_available` | 503 | FFmpeg no está instalado o no se puede ejecutar. |
| `hls_output_error` | 500 | No se pudo crear la carpeta de salida HLS. |
| `transcoder_start_error` | 500 | No se pudo iniciar el proceso FFmpeg. |
| `stream_url_error` | 502 | No se pudo construir/validar la URL original. |
| `transcoder_busy` | 503 | Se alcanzó el límite de procesos concurrentes. |

## 8. Seguridad

- El `stream_id` se sanea con una lista blanca (`^[A-Za-z0-9_-]+$`) antes de
  usarlo como nombre de carpeta, para evitar **path traversal**.
- La respuesta al cliente no incluye usuario, contraseña ni la URL original.
- Las credenciales viajan en el body y no se registran en logs.

## 9. Riesgos técnicos y límites (producción)

- **CPU**: el transcode completo (`libx264`) llega a ~82% de un núcleo por
  canal. La decisión automática de modo mitiga esto: en el lineup actual el
  100% del video es h264, por lo que se usa `remux` (~0%) o `transcode_audio`
  (~8%) y nunca transcode completo. Aun así, cualquier modo escala linealmente
  con la concurrencia.
- **Memoria**: cada proceso FFmpeg ocupa ~60 MB; escalan con la concurrencia.
- **Disco**: `delete_segments` limita el crecimiento, pero se necesita
  limpieza de carpetas HLS huérfanas (TTL / job programado).
- **Ancho de banda**: el backend descarga el stream de Xtream y re-sirve el
  HLS → duplica el tráfico frente a la reproducción directa.
- **Concurrencia**: se aplica un límite (`MAX_CONCURRENT_TRANSCODES`) que
  evita lanzar más procesos de los configurados. El registro sigue en memoria
  por proceso de Django; producción con varios workers requeriría un registro
  compartido (Redis / cola).
- **Ciclo de vida**: existe `stop_hls_transcode` para parada manual y un hilo
  de limpieza automática (`HLS_CLEANUP_TTL_SECONDS`) que detiene y borra las
  salidas obsoletas. La detección de "nadie está viendo" (para parar streams
  vivos sin espectadores) requeriría rastrear los accesos al playlist.

## 10. Propuestas para producción

1. ~~Remux primero, transcode solo si el códec no es compatible.~~
   **Implementado**: decisión automática remux / transcode_audio / transcode.
2. ~~TTL + tarea programada para borrar carpetas HLS inactivas.~~
   **Implementado**: hilo de limpieza automática (`HLS_CLEANUP_TTL_SECONDS`).
3. ~~Límite de procesos concurrentes (rechazar / encolar si se supera).~~
   **Implementado**: `MAX_CONCURRENT_TRANSCODES` (rechaza con `transcoder_busy`).
4. Matriz de canales: directo OK / requiere HLS proxy / falla.
5. Mover el registro de procesos a algo persistente (Redis / cola) para
   soportar varios workers de Django. Rastrear accesos al playlist para
   detener streams vivos sin espectadores. Considerar una cola de trabajos.
