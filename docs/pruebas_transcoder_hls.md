# Pruebas del transcoder HLS

Registro de pruebas del endpoint `POST /api/xtream/live/proxy-url/`.

> No se colocan usuarios, contraseñas ni URLs reales en este documento.

## 1. Entorno

- FFmpeg: `ffmpeg version 2026-04-09-git-d3d0b7a5ee-full_build www.gyan.dev`
  (salida de `ffmpeg -version`).
- Ruta binario: `C:\ffmpeg\bin\ffmpeg`.
- Django check: `System check identified no issues (0 silenced).`

## 2. Pruebas automáticas (mock, sin credenciales)

`python manage.py test xtream`

```
Ran 25 tests in 0.099s
OK
```

Casos cubiertos para el proxy (`LiveProxyUrlTests`):

| Test | Verifica |
|---|---|
| `test_faltan_datos` | `validation_error` (400) si falta `stream_id`. |
| `test_stream_id_invalido` | `validation_error` (400) ante `../../etc`. |
| `test_ffmpeg_no_disponible` | `ffmpeg_not_available` (503). |
| `test_proxy_exitoso` | 200 con `hls_url` y `mode`. |
| `test_no_filtra_credenciales` | La respuesta no expone password ni URL original. |
| `test_reutiliza_proceso_activo` | `reused: true` si ya hay HLS activo. |
| `test_url_original_invalida` | `stream_url_error` (502) si la URL original no es válida. |
| `test_error_al_crear_carpeta` | `hls_output_error` (500) si no se puede crear la carpeta HLS. |
| `test_error_al_iniciar_ffmpeg` | `transcoder_start_error` (500) si FFmpeg no arranca. |

Decisión de modo remux/transcode (`TranscoderModeTests`):

| Test | Verifica |
|---|---|
| `test_remux_si_codec_compatible` | h264 + aac → `remux`. |
| `test_transcode_audio_si_solo_audio_incompatible` | h264 + mp2 → `transcode_audio`. |
| `test_remux_si_video_ok_sin_audio` | h264 sin audio → `remux`. |
| `test_transcode_si_codec_incompatible` | hevc / ac3 → `transcode`. |
| `test_transcode_si_codec_desconocido` | Sin códec legible → `transcode` (seguridad). |
| `test_build_command_*` | El comando FFmpeg usa `-c copy` / `-c:v copy` / `libx264` según el modo. |

Límite de concurrencia y limpieza automática (`TranscoderLifecycleTests`):

| Test | Verifica |
|---|---|
| `test_limite_concurrencia` | Al alcanzar `MAX_CONCURRENT_TRANSCODES` → `transcoder_busy` (503). |
| `test_cleanup_borra_inactivos_y_conserva_activos` | Borra salidas obsoletas (mtime viejo) y conserva las frescas. |
| `test_cleanup_borra_carpeta_huerfana_sin_playlist` | Borra carpetas sin `index.m3u8`. |

## 3. Prueba manual con canal real (realizada ✅)

Pasos ejecutados en local con un canal real de web:

1. Levantar el backend:
   ```
   python manage.py runserver
   ```
2. Enviar la petición (reemplazar credenciales y `stream_id` reales,
   **fuera del repo**):
   ```
   POST http://127.0.0.1:8000/api/xtream/live/proxy-url/
   {
     "username": "<usuario_real>",
     "password": "<password_real>",
     "stream_id": <id_del_canal_problematico>
   }
   ```
3. Verificar respuesta `success: true` con `hls_url`.
4. Comprobar que se generó la salida:
   ```
   backend/media/hls/<stream_id>/index.m3u8
   backend/media/hls/<stream_id>/*.ts
   ```
5. Abrir el `hls_url` en el reproductor web / VLC y confirmar reproducción.

### Resultado observado

Prueba realizada con un canal en vivo real (**TV Perú**, `stream_id` 123).

**1. Respuesta del endpoint** (Thunder Client) — `200 OK`:
```json
{
  "success": true,
  "stream_id": "123",
  "hls_url": "http://127.0.0.1:8000/media/hls/123/index.m3u8",
  "reused": false
}
```

**2. Archivos generados** en `backend/media/hls/123/`:
- `index.m3u8` creado y actualizándose en vivo.
- Segmentos `.ts` de ~1-2 MB rotando (`delete_segments` funcionando: se
  mantienen ~6 y se borran los viejos).

Contenido del `index.m3u8` (playlist válida, en vivo):
```
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:4
#EXT-X-MEDIA-SEQUENCE:15
#EXTINF:4.170833,
index15.ts
#EXTINF:4.170833,
index16.ts
...
```

**3. Reproducción:** el `hls_url` se abrió en **VLC** (Medio → Abrir
ubicación de red) y reprodujo correctamente video + audio del canal.

**4. Consumo observado** (equipo de 12 núcleos lógicos). El consumo depende
del modo elegido por el transcoder:

| Modo | CPU (1 núcleo) | RAM |
|---|---|---|
| `remux` (copia todo) | ~0-1% | ~60 MB |
| `transcode_audio` (solo audio) | ~8% | ~60 MB |
| `transcode` (video+audio) | ~82% | ~60 MB |

Medición comparativa sobre el mismo canal (Cartoon Network 210):
`transcode_audio` = **8.3%** de un núcleo vs `transcode` completo = **82.3%**
→ **~10× menos CPU**, y preserva la calidad de video al no recomprimirlo. RAM
estable en ~60 MB por proceso, sin crecimiento. El transcode en vivo va a
velocidad 1x; escala linealmente con el número de canales concurrentes.

## 4. Prueba con un canal PROBLEMÁTICO de web (actividad 7)

Canal usado: **Cartoon Network** (`stream_id` 210).

### Por qué es problemático (verificado con ffprobe)

Se inspeccionó el códec ORIGINAL del canal con ffprobe (sin transcodificar):

```
video: h264   ← compatible con web
audio: mp2    ← NO compatible con navegador (MPEG audio layer 2)
```

El navegador reproduce el video (h264) pero **no** el audio `mp2`, así que
directo en web el canal falla (llegaría sin sonido o no cargaría). Es un
canal problemático real, confirmado con dato objetivo, no por suposición.

### Cómo lo resolvió el backend

El transcoder detectó el caso y eligió el modo **`transcode_audio`**: copia
el video tal cual (`-c:v copy`) y recodifica solo el audio a AAC
(`-c:a aac`). Respuesta del endpoint (`200 OK`):

```json
{
  "success": true,
  "stream_id": "210",
  "hls_url": "http://127.0.0.1:8000/media/hls/210/index.m3u8",
  "mode": "transcode_audio",
  "reused": false
}
```

### Resultado (antes / después)

| | Directo en web | Vía proxy HLS |
|---|---|---|
| Audio `mp2` | ❌ Navegador no lo soporta | ✅ Convertido a AAC |
| Reproducción | Falla | ✅ Reproduce en VLC |

Observación adicional: al **copiar el video** en lugar de recomprimirlo, la
calidad de imagen se mantiene intacta (mejor que un transcode completo) y el
consumo de CPU es menor (el video no se procesa, solo el audio).

## 5. Matriz de resultado

| Canal (id) | Códec original | ¿Compatible web? | `mode` elegido | ¿Reproduce vía proxy? |
|---|---|---|---|---|
| Azteca Corazón (214) | h264 / aac | ✅ Sí | `remux` | ✅ Sí |
| Cartoon Network (210) | h264 / mp2 | ❌ No (audio) | `transcode_audio` | ✅ Sí (VLC) |
| TV Perú (123) | h264 | ✅ (video) | remux / audio | ✅ Sí (VLC) |

## 6. Matriz de códecs del lineup completo (89 canales)

Se sondearon con ffprobe los 89 canales del proveedor para dimensionar la
carga real del transcoder:

**Video:**

| Códec | Canales | Nota |
|---|---|---|
| h264 | 81 | Compatible con web |
| (sin respuesta) | 8 | Canal offline al momento del sondeo |

→ **Ningún canal usa hevc/mpeg2.** El 100% del video es h264 (compatible).

**Audio:**

| Códec | Canales | Modo resultante |
|---|---|---|
| mp2 | 51 | `transcode_audio` |
| aac | 22 | `remux` |
| ac3 | 5 | `transcode_audio` |
| aac_latm | 4 | `transcode_audio` |
| (sin respuesta) | 7 | — |

**Conclusión de carga:** con la lógica de 3 modos, el reparto real es
~22 canales en `remux` (CPU ~0), ~60 en `transcode_audio` (CPU baja) y
**0 en `transcode` completo**. El modo caro (recodificar video) no se activa
con este lineup y queda solo como red de seguridad para códecs desconocidos
o canales futuros. Esto reduce de forma importante el riesgo de CPU en
producción.
