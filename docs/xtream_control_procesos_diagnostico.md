# Control de procesos y diagnóstico de canales Xtream

Documento técnico del control de procesos FFmpeg y del diagnóstico de
códecs para canales Xtream. Corresponde al Día 8 del plan de trabajo
backend (rama `feature/backend-xtream-process-control`).

> ⚠️ El transcoder sigue siendo una prueba técnica controlada. Este día
> lleva a Xtream lo que el Día 7 hizo para Astra (detener, monitorear,
> limpiar) y suma un endpoint de **diagnóstico** de códecs.

## 1. Contexto

El endpoint `POST /api/xtream/live/proxy-url/` ya podía **iniciar** un proxy
HLS de un canal Xtream, pero no había forma de **detenerlo**, **monitorear**
el estado ni **diagnosticar** por qué un canal reproduce directo y otro no.
Este día agrega esos tres endpoints, reutilizando el servicio
`xtream/services/transcoder.py` ya existente.

## 2. Endpoints

| Método | Endpoint | Uso |
|---|---|---|
| POST | `/api/xtream/live/stop-proxy/` | Detener FFmpeg de un canal y borrar su salida HLS. |
| GET | `/api/xtream/live/proxy-status/` | Consultar procesos activos, límite y salidas HLS. |
| POST | `/api/xtream/live/diagnose-stream/` | Diagnosticar códecs y modo recomendado de un canal. |

### 2.1 `POST /api/xtream/live/stop-proxy/`

Recibe el `stream_id`, lo sanitiza, detiene el proceso FFmpeg asociado y
borra la carpeta HLS para no reutilizar una salida muerta.

Body:

```json
{ "stream_id": 41 }
```

Respuesta:

```json
{
  "success": true,
  "stream_id": "41",
  "stopped": true,
  "output_removed": true
}
```

- `stopped: false` = no había proceso registrado para ese canal (no es error).
- `output_removed` = si existía carpeta HLS que borrar.

### 2.2 `GET /api/xtream/live/proxy-status/`

Estado global del transcoder. Sin body. Nunca expone URLs de origen,
usuarios ni contraseñas.

```json
{
  "success": true,
  "active_processes": 1,
  "max_concurrent": 5,
  "outputs": [
    {
      "stream_id": "41",
      "process_alive": true,
      "index_exists": true,
      "index_age_seconds": 2.5,
      "index_size_bytes": 350,
      "segments": 6,
      "damaged": false
    }
  ]
}
```

### 2.3 `POST /api/xtream/live/diagnose-stream/`

Construye la URL del stream con las credenciales enviadas, la sondea con
**ffprobe** (sin descargar ni transcodificar) y devuelve los códecs, la
compatibilidad web y el modo recomendado. La URL con credenciales **nunca**
se devuelve.

Body:

```json
{
  "username": "cliente_prueba",
  "password": "password_prueba",
  "stream_id": 41,
  "output": "m3u8"
}
```

Respuesta:

```json
{
  "success": true,
  "stream_id": "41",
  "video_codec": "h264",
  "audio_codec": "aac",
  "web_compatible": true,
  "recommended_mode": "remux"
}
```

| `recommended_mode` | Significado |
|---|---|
| `remux` | Video y audio ya compatibles: solo re-empaqueta (CPU ~0). |
| `transcode_audio` | Video h264 OK pero audio incompatible: recodifica solo el audio. |
| `transcode` | Video incompatible o códec no legible: recodifica todo (CPU alta). |

> El diagnóstico ejecuta **un solo** `ffprobe` y decide el modo sobre esos
> códecs con `transcoder.mode_from_codecs()`, sin sondear dos veces.

## 3. Códigos de error

| Código | HTTP | Cuándo ocurre |
|---|---|---|
| `missing_stream_id` | 400 | No se envió `stream_id`. |
| `invalid_stream_id` | 400 | El `stream_id` tiene caracteres no permitidos (anti path traversal). |
| `missing_credentials` | 400 | No se envió `username` o `password` (solo diagnose-stream). |
| `stream_url_error` | 502 | No se pudo construir/validar la URL del stream (p. ej. `XTREAM_BASE_URL` vacío). |
| `ffmpeg_not_available` | 503 | FFmpeg/ffprobe no está disponible. |
| `transcoder_busy` | 503 | Se alcanzó el límite de procesos concurrentes (aplica al iniciar en proxy-url). |
| `unexpected_error` | 500 | Error inesperado controlado. |

## 4. Reutilización del servicio transcoder

Los endpoints no duplican lógica; reutilizan `xtream/services/transcoder.py`:

| Endpoint | Funciones usadas |
|---|---|
| stop-proxy | `sanitize_stream_id`, `stop_hls_transcode`, `remove_hls_output` |
| proxy-status | `get_transcoder_status` |
| diagnose-stream | `is_ffmpeg_available`, `probe_codecs`, `is_web_compatible`, `mode_from_codecs` |

`decide_mode()` se refactorizó para apoyarse en la nueva función pura
`mode_from_codecs()`, que el diagnóstico usa directamente (evita un segundo
sondeo con ffprobe). El comportamiento de `decide_mode()` no cambió.

## 5. Pruebas

Automáticas (en `xtream/tests.py`):

```
python manage.py check
python manage.py test xtream
python manage.py test astra
```

Cubren: `stop-proxy` (faltante/ inválido/ detiene/ stopped=false),
`proxy-status` (estado y solo-GET) y `diagnose-stream` (credenciales,
ffmpeg no disponible, URL inválida, remux, transcode y no-filtrado de
credenciales), más `mode_from_codecs`.

## 6. Pruebas manuales (PowerShell)

```powershell
# Detener proxy
$body = @{ stream_id = 41 } | ConvertTo-Json
Invoke-RestMethod -Uri "http://127.0.0.1:8000/api/xtream/live/stop-proxy/" `
  -Method POST -ContentType "application/json" -Body $body

# Estado
Invoke-RestMethod -Uri "http://127.0.0.1:8000/api/xtream/live/proxy-status/" -Method GET

# Diagnóstico
$body = @{ username = "cliente_prueba"; password = "password_prueba"; stream_id = 41; output = "m3u8" } | ConvertTo-Json
Invoke-RestMethod -Uri "http://127.0.0.1:8000/api/xtream/live/diagnose-stream/" `
  -Method POST -ContentType "application/json" -Body $body
```

## 7. Evidencias

_(Agregar capturas: proxy-url iniciando un canal, proxy-status con el
proceso activo, stop-proxy deteniéndolo, diagnose-stream de un canal
compatible (remux) y de uno incompatible (transcode), y los tests en verde.)_
