# Diagnóstico y compatibilidad HLS para Android — Día 9

**Proyecto:** TC Play 2.0
**Responsable:** Kevin
**Rama:** `feature/backend-hls-android-compat`
**Insumo:** Reporte de pruebas móviles de Joleydi (Cargan / Sin audio / Reintentar)

---

## 1. Resumen ejecutivo

El reporte móvil marcaba la mayoría de canales como **"SIN AUDIO"** (video sí, audio no) y algunos
como **"REINTENTAR"**. Tras el diagnóstico se concluye:

- **El backend/transcoder genera HLS válido** y convierte el audio incompatible (mp2/ac3/aac_latm) a
  **AAC**. Verificado con `ffprobe` y con la **APK instalada en un dispositivo Android real** (se instaló
  Flutter, se generó el APK y se instaló en el móvil).
- Al reproducir usando la **salida del proxy** (`/live/proxy-url/`), los canales que figuraban como
  **"SIN AUDIO"** (audio mp2/ac3) **reproducen con audio y video correctamente**. Se recomienda tener en
  consideración que el reproductor consuma la salida del proxy para aprovechar la conversión de audio que
  ya realiza el backend.
- Los canales **"REINTENTAR"** son en su mayoría **streams caídos/inestables del proveedor** (p. ej.
  Azteca Deportes devuelve HTTP 404), ajenos al backend.

En esta rama se implementaron mejoras de compatibilidad Android en el transcoder, un endpoint de
diagnóstico HLS y esta documentación.

---

## 2. Cambios implementados (backend)

### 2.1 Canales de solo audio (radios) — corrección
`mode_from_codecs()` enviaba los streams **sin video** (`video_codec = None`) al modo `transcode`, que
fuerza `libx264` sobre algo que no tiene video → FFmpeg fallaba (no generaba HLS). Ahora se detecta el
caso de solo audio y se decide **por el audio**:

- audio ya compatible (aac/mp3) → `remux`
- audio incompatible (aac_latm, mp2, …) → `transcode_audio` (convierte a AAC sin tocar video)

### 2.2 Compatibilidad Android en `transcode` completo
Se agregó `-pix_fmt yuv420p` al modo `transcode`. El decoder de hardware de Android rechaza formatos
como `yuv422p` o 10-bit; se fuerza 4:2:0 8-bit.

```
-c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p -c:a aac
```

> `-profile:v baseline` y `-level 3.1` quedan como opción **solo si un grupo de equipos Android sigue
> fallando** (no se fuerzan por defecto para no degradar canales HD).

### 2.3 Modo `transcode_audio`
Confirmado que convierte audio a AAC manteniendo el video sin recodificar (`-c:v copy -c:a aac`). En
streams de solo audio, `-c:v copy` no tiene video que copiar y la salida queda solo con el audio en AAC.

### 2.4 Endpoint de diagnóstico HLS (nuevo)
`GET /api/xtream/live/hls-status/<stream_id>/` — ver sección 4.

---

## 3. Validación end-to-end y recomendación

La compatibilidad se validó de forma completa en un entorno real:

- Se instaló **Flutter** y se generó un **APK de prueba**, instalado en un **dispositivo Android real**.
- Se reprodujeron canales usando la **salida del proxy** (`/live/proxy-url/`).
- Los canales que figuraban como **"SIN AUDIO"** (audio mp2/ac3) **reproducen con audio y video
  correctamente** en la app instalada (APK), al consumir la salida del proxy que entrega el audio en AAC.
- La salida del proxy se verificó además con **`ffprobe`** (`h264 + aac`).

**Recomendación:** para aprovechar la conversión de audio del backend, se sugiere tener en consideración
que el reproductor consuma la **salida del proxy** (`/live/proxy-url/`) en lugar de la URL directa del
stream. El método correspondiente ya existe en el servicio de la app.

---

## 4. Endpoint de diagnóstico HLS

```
GET /api/xtream/live/hls-status/<stream_id>/
```

Ejemplo: `GET /api/xtream/live/hls-status/71/`

| Campo | Descripción |
|-------|-------------|
| `success` | Indica si la consulta fue exitosa. |
| `stream_id` | ID del canal consultado. |
| `index_exists` | Indica si existe `index.m3u8`. |
| `index_size_bytes` | Tamaño del `index.m3u8`. |
| `segments` | Cantidad de segmentos `.ts` generados. |
| `damaged` | Indica si la salida HLS está vacía, incompleta o dañada. |
| `process_alive` | Indica si el proceso FFmpeg asociado sigue activo. |

**Respuesta de ejemplo (sin salida generada):**
```json
{"success": true, "stream_id": "999", "index_exists": false,
 "index_size_bytes": 0, "segments": 0, "damaged": false, "process_alive": false}
```

No expone usuario, contraseña ni la URL original del stream. Permite diferenciar si un canal falla por
**HLS incompleto** (index/segmentos ausentes), **proceso muerto** (`process_alive=false`) o **stream
caído** (nunca genera salida).

---

## 5. Matriz de diagnóstico (canales representativos)

Códecs obtenidos con `/api/xtream/live/diagnose-stream/`. "Modo" = modo del transcoder que se activa.

| Categoría | Canal | ID | Resultado móvil | Video | Audio | Modo | Diagnóstico / acción |
|-----------|-------|----|-----------------|-------|-------|------|----------------------|
| Nacionales | Nativa | 41 | Carga correctamente | h264 | aac | remux | **Referencia.** Ya compatible; reproduce directo. |
| Deportes | Willax | 151 | Sin audio | h264 | mp2 | transcode_audio | Audio mp2 → AAC vía proxy. **Validado con audio en Android real.** |
| Deportes | ESPN 5 | 71 | Sin audio | h264 | mp2 | transcode_audio | Igual que Willax; audio mp2 → AAC vía proxy. |
| Radio | Radio Felicidad | 187 | Carga (solo sonido) | — | aac_latm | transcode_audio | **Solo audio.** Corregido: ya no cae en `transcode`/libx264. |
| Deportes | Azteca Deportes | 213 | Reintentar | — | — | — | **Stream caído en el proveedor (HTTP 404).** Ajeno al backend. |

Patrón general observado en todo el catálogo:

- **Carga bien** = `h264 + aac` → `remux`.
- **Sin audio** = `h264 + mp2/ac3` → `transcode_audio` (con proxy: audio → AAC → suena).
- **Reintentar** = ffprobe sin media / 404 → **stream caído o inestable del proveedor**.

---

## 6. Casos que requieren ajuste backend vs. streams caídos

| Caso | Dónde se atiende |
|------|------------------|
| Audio mp2/ac3/aac_latm → AAC | Backend (ya lo hace vía `transcode_audio`) |
| Video no-h264 → H.264 + yuv420p | Backend (modo `transcode`, ya con `-pix_fmt yuv420p`) |
| Canales solo audio (radio) | Backend (corregido en esta rama) |
| Consumir la salida del proxy (`proxy-url`) para obtener el audio en AAC | Recomendación para la app |
| Detener el proxy al cambiar/cerrar canal (evitar acumular FFmpeg) | Recomendación para la app (usar `/live/stop-proxy/`) |
| Canales que devuelven 404 / sin media (Azteca Deportes, AXN, USA, Uncp, Atv Sur, Energeek, Radio Inolvidable) | Proveedor Xtream (streams caídos) |

---

## 7. Comandos de validación

```bash
# Verificar FFmpeg
ffmpeg -version
ffprobe -version

# Revisar salidas HLS generadas
dir .\media\hls
dir .\media\hls\71

# Limpiar procesos y salidas en pruebas locales
taskkill /F /IM ffmpeg.exe
Remove-Item -Recurse -Force .\media\hls\*

# Validación final
.\.venv\Scripts\activate
python manage.py check
python manage.py test xtream
python manage.py test astra
```

Resultado: `check` sin issues, **51 tests xtream** y **11 tests astra** en verde.

---

## 8. Conclusión

- Se validó, en un dispositivo Android real (Flutter + APK), que el transcoder del backend entrega
  **audio AAC y HLS compatible con Android**. Los canales que figuraban como "SIN AUDIO" reproducen con
  audio y video al consumir la salida del proxy.
- Se agregaron mejoras de compatibilidad Android (`-pix_fmt yuv420p`, canales solo audio) y el endpoint
  `hls-status` para diagnosticar salidas por `stream_id`.
- **Recomendaciones a tener en consideración:** que el reproductor consuma la salida del proxy
  (`/api/xtream/live/proxy-url/`) para obtener el audio en AAC, y que se detenga el proxy al cambiar o
  cerrar un canal (`/api/xtream/live/stop-proxy/`) para no acumular procesos FFmpeg.
