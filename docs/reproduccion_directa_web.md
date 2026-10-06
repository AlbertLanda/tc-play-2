# Reproducción directa en la web

Esta propuesta parte de `feature/web-player-joleydi-fix` (`7511ace`), donde
Xtream se abría siempre mediante FFmpeg. No integra las demás ramas ni cambia
el backend, móvil, Android TV o despliegues existentes.

## Camino por defecto

1. El backend devuelve la URL Xtream `m3u8`; el navegador lee el video del origen.
2. Si HLS falla o no avanza durante aproximadamente 12 segundos, se intenta la
   URL Xtream `ts`, si el navegador soporta MPEG-TS mediante Media Source.
3. Si las opciones directas fallan, se muestra un mensaje y se permite reintentar.
   No se solicita FFmpeg automáticamente.

Astra conserva su URL HLS directa y no usa el fallback TS de Xtream.
El bloqueo de autoplay pide una acción del usuario, sin activar un proxy.
Una pausa solicitada por el usuario tampoco cambia la fuente. Al cerrar o
cambiar un canal directo no se llama a `stop-proxy`.
Las respuestas de una selección cerrada se descartan para evitar que un canal
anterior reaparezca durante el zapping.

## Alternativa opcional

`VITE_ENABLE_STREAM_PROXY=true` permite un último intento mediante el proxy
existente, después de agotar las opciones directas. Es una opción de compilación
Vite; su valor por defecto es false. Las solicitudes Xtream de ese camino envían
`device_profile=web` al abrir y cerrar; los backends antiguos pueden ignorarlo.

El proxy existente comparte salidas por canal. Esta propuesta no corrige su
control de espectadores ni autorización; mantenerlo desactivado durante la
validación directa evita depender de ese comportamiento. Antes de habilitarlo
para múltiples usuarios hay que resolver esos hallazgos del backend.

## Validación sin alterar el servicio publicado

Crear una copia de prueba de la web y configurar `VITE_API_BASE_URL` contra un
backend de pruebas. El nombre “staging” de un servidor no asegura que esté
separado del backend usado por la app pública; verificarlo antes de desplegar.
No hace falta sustituir el AAB publicado para revisar esta propuesta web.

```sh
cd web_app
npm ci
npm test
npm run lint
npm run build
```

Las pruebas automáticas usan URLs ficticias y comprueban selección de fuentes,
ausencia de llamadas a proxy por defecto, cierre y respuestas atrasadas.
También montan la página con DOM y medios simulados para comprobar arranque,
autoplay, pausa, reintento y navegación.
No miden velocidad ni decodifican canales reales. Verificar en dispositivos:

- Imagen y audio de todos los canales objetivo; HLS y TS según el navegador.
- HTTPS en el origen cuando la web se sirve por HTTPS, y CORS tanto en la
  playlist como en los segmentos. Un códec incompatible o CORS bloqueado no
  se corrige simplemente usando una URL directa.
- Tiempo hasta el primer fotograma, zapping, volver atrás y reintentar.
- Pausa, bloqueo de autoplay, corte de red y recuperación.
- Dos clientes simultáneos: cerrar uno no debe detener la reproducción directa
  del otro. Respetar los límites de conexiones de Xtream.

La rama no coincide con el disparador de despliegue Azure existente
(`feature/backend-azure-staging`). La entrega pública sigue pendiente de
identificar el commit/AAB actual y completar estas pruebas reales.
