# Control de procesos del proxy/transcoder Astra

Documento técnico del control de procesos FFmpeg para el proxy Astra.
Corresponde al Día 7 del plan de trabajo backend
(rama `feature/backend-astra-process-control`).

> ⚠️ El transcoder sigue siendo una prueba técnica controlada. Este día
> agrega el **ciclo de vida** de los procesos (detener, consultar,
> limpiar) para que el backend no se sature al cambiar de canal.

## 1. Problema que resuelve

Al probar varios canales Astra seguidos, cada `proxy-url` lanza un FFmpeg
nuevo y los procesos se acumulan hasta responder:

```
"Se alcanzó el límite de procesos de transcoder concurrentes"  (transcoder_busy)
```

La solución NO es subir `MAX_CONCURRENT_TRANSCODES`, sino controlar el
ciclo de vida: el frontend detiene el canal anterior al hacer zapping y
la limpieza automática elimina salidas muertas o dañadas.

## 2. Endpoints

### 2.1 `POST /api/astra/proxy-url/` (existente)

Inicia o reutiliza el HLS transcodeado de un canal Astra.

```json
{ "channel_id": "astra-5" }
```

### 2.2 `POST /api/astra/stop-proxy/` (nuevo)

Detiene el proceso FFmpeg del canal y **borra su salida HLS** (si quedara
un `index.m3u8` fresco, un `proxy-url` inmediato reutilizaría una salida
sin proceso detrás).

Body:

```json
{ "channel_id": "astra-5" }
```

Respuesta:

```json
{
  "success": true,
  "channel_id": "astra-5",
  "stopped": true,
  "output_removed": true
}
```

- `stopped: false` significa que no había proceso registrado para ese
  canal (no es un error: puede haber muerto solo o haber sido limpiado).
- `output_removed` indica si existía carpeta HLS que borrar.

### 2.3 `GET /api/astra/proxy-status/` (nuevo)

Devuelve el estado global del transcoder. Sin body. Solo datos de
monitoreo; **nunca** URLs de origen ni credenciales.

Respuesta:

```json
{
  "success": true,
  "active_processes": 1,
  "max_concurrent": 5,
  "outputs": [
    {
      "stream_id": "astra-5",
      "process_alive": true,
      "index_exists": true,
      "index_age_seconds": 2.4,
      "index_size_bytes": 356,
      "segments": 6,
      "damaged": false
    }
  ]
}
```

| Campo | Significado |
|---|---|
| `active_processes` | Procesos FFmpeg vivos registrados. |
| `max_concurrent` | Límite configurado (`MAX_CONCURRENT_TRANSCODES`). |
| `outputs` | Carpetas HLS detectadas en `media/hls/`. |
| `process_alive` | Si el FFmpeg de esa salida sigue corriendo. |
| `index_age_seconds` | Segundos desde la última escritura del `index.m3u8` (bajo = FFmpeg produciendo). |
| `segments` | Cantidad de segmentos `.ts` en disco. |
| `damaged` | `true` si el index está vacío o no hay segmentos (salida rota). |

## 3. Salidas dañadas: detección y regeneración

Una salida se considera **dañada** cuando existe `index.m3u8` pero:

- el archivo está vacío, o
- la carpeta no contiene ningún segmento `.ts`.

`is_stream_active()` ya no reutiliza salidas dañadas: si no hay proceso
vivo y la salida está rota, la borra en el momento y devuelve `False`,
de modo que el siguiente `proxy-url` regenera el HLS desde cero.

## 4. Códigos de error

| Código | Cuándo ocurre | HTTP |
|---|---|---|
| `missing_channel_id` | No se envía `channel_id` en el body. | 400 |
| `invalid_channel_id` | El ID contiene caracteres no permitidos (sanitización anti path traversal). | 400 |
| `astra_channel_not_found` | El ID no existe en la playlist Astra. | 404 |
| `astra_playlist_error` | No se pudo leer o parsear la playlist de Astra. | 502 |
| `ffmpeg_not_available` | FFmpeg no está instalado o no está en PATH. | 503 |
| `hls_output_error` | FFmpeg inició pero no generó `index.m3u8`. | 500 |
| `transcoder_busy` | Se llegó al máximo de procesos concurrentes. | 503 |
| `unexpected_error` | Cualquier fallo no contemplado. | 500 |

**Acción recomendada para frontend:** ante `transcoder_busy`, detener el
canal anterior con `stop-proxy` y reintentar; ante `damaged`/errores 5xx,
reintentar una vez (la salida dañada se limpia sola).

## 5. Configuración sugerida (entorno local)

```
MAX_CONCURRENT_TRANSCODES=5
HLS_ACTIVE_TTL_SECONDS=30
HLS_CLEANUP_TTL_SECONDS=120
HLS_CLEANUP_INTERVAL_SECONDS=30
```

## 6. Pruebas manuales

| Prueba | Acción | Resultado esperado |
|---|---|---|
| Iniciar proxy | `POST /api/astra/proxy-url/` con `astra-5` | `success: true`, `hls_url`, `mode: transcode`. |
| Ver estado | `GET /api/astra/proxy-status/` | `active_processes` refleja el proceso. |
| Detener proxy | `POST /api/astra/stop-proxy/` con `astra-5` | `stopped: true`, baja el conteo. |
| Zapping | Iniciar `astra-5`, `astra-12`, `astra-20` deteniendo los anteriores | No se dispara `transcoder_busy`. |
| Límite controlado | Iniciar más canales que `MAX_CONCURRENT_TRANSCODES` sin detener | 503 controlado con `transcoder_busy`. |

Comandos de validación:

```
python manage.py check
python manage.py test astra
python manage.py test xtream
```

## 7. Evidencias

_(Agregar capturas de las pruebas manuales: proxy-url, proxy-status con
procesos activos, stop-proxy, zapping sin `transcoder_busy` y el límite
controlado.)_
