# Prueba manual — Canal RPP (`stream_id 65`) — Día 11

**Proyecto:** TC Play 2.0
**Responsable:** Kevin
**Rama:** `feature/backend-hls-dead-process-recovery`
**Entorno:** APK de prueba (Android) + backend local `runserver 0.0.0.0:8000`
**Motivo:** Joleydi reportó que el canal RPP se paraliza durante la reproducción.

---

## Resultado

**El canal reprodujo ~7 minutos sin paralizarse.** El fallo reportado **no se reprodujo** en esta corrida.

| Canal | ID | Duración | Resultado |
|-------|----|----------|-----------|
| RPP | 65 | ~7 min | Reproducción continua, sin congelamiento |

## Estado observado en `/api/xtream/live/hls-status/65/`

| Campo | Valor | Lectura |
|-------|-------|---------|
| `ready` | `true` | Hay contenido HLS reproducible. |
| `process_alive` | `true` | FFmpeg vivo y registrado durante toda la prueba. |
| `segments` | `7` | Valor **estacionario esperado**, no un síntoma (ver nota). |

Las validaciones se mantuvieron estables durante toda la reproducción.

## Notas de lectura

- **`segments=7` constante es correcto.** FFmpeg usa segmentos rotatorios
  (`-hls_list_size 6 -hls_flags delete_segments`): los `.ts` viejos se borran al salir de la playlist, así
  que el conteo se estabiliza en ~6-7 y no crece. Un canal sano y uno congelado muestran el mismo número.
- **`process_alive=true` es confiable aquí.** Confirma que no hubo reinicios del backend durante la
  prueba (ese registro vive en memoria y se pierde al reiniciar Django).

## Conclusión

En esta corrida el backend se comportó de forma estable: HLS listo, FFmpeg vivo y reproducción continua
durante ~7 minutos en la APK.

**La prueba no descarta el problema.** El congelamiento reportado es intermitente, por lo que 7 minutos
sin fallo no lo cierran. Para confirmarlo hay que capturar el estado **en el momento exacto en que se
paralice** y verificar el campo `live` (agregado en esta rama):

- `ready=true` + `live=true` → backend sano; el problema se deriva a la app móvil.
- `ready=true` + `live=false` → salida congelada; se corrige en backend/transcoder.
