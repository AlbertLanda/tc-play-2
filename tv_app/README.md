# TC Play para LG webOS

Primera implementación independiente en la rama `feature/tv-lg`. La aplicación está en `tv_app/`; las carpetas heredadas del repositorio sirven de referencia. No modifica `mobile_app/`, `web_app/`, el backend ni los workflows de Azure.

## Funciones incluidas

- Login con la API existente, categorías y canales.
- Navegación con flechas, OK, Atrás (461), CH+ y CH−; también admite clic del Magic Remote.
- Catálogo paginado de 12 canales para reducir nodos en televisores con pocos recursos.
- Reproducción HLS (`m3u8`) mediante el elemento video y el reproductor del televisor, con miniatura y pantalla completa.
- URL directa de Xtream: no llama a `proxy-url`, `stop-proxy` ni FFmpeg.
- Cancelación de respuestas antiguas al cambiar canal/categoría y al cerrar sesión.
- Límite de espera para inicio/buffering, reintento manual y liberación del video al ocultar/salir de la app.
- Credenciales únicamente en memoria; no se guardan en localStorage ni en archivos. Se requiere login al reiniciar la app.

## Preparar en Windows

Requiere Node.js 18 o posterior. Desde PowerShell:

```powershell
Set-Location C:\Users\aalrp\Proyectos\tc-play-lg\tv_app
npm ci
Copy-Item config.example.json config.local.json
```

Edita `config.local.json` y coloca la URL del backend de pruebas aprobado en `apiBaseUrl`, sin `/api/xtream/`. Por ejemplo, `https://tu-backend-de-pruebas`. No pongas usuario ni contraseña en este archivo. Su valor inicial vacío evita conectar automáticamente con el servidor usado por clientes. No sobrescribas este archivo si ya está configurado.

```powershell
npm test
npm run build
npm start
```

La vista de desarrollo está en `http://localhost:4173`. Permite revisar interfaz y solicitudes, pero un navegador de PC no verifica el reproductor de webOS ni los codecs del TV. `npm run build` copia los archivos a `dist/`; no produce todavía el paquete IPK ni lo instala.

## Empaquetar para el televisor

Instala la CLI oficial de webOS y prepara un televisor con Developer Mode siguiendo la documentación enlazada abajo. Desde `tv_app/`, con `ares-package` disponible:

```powershell
ares-package --no-minify dist
```

El identificador de prueba es `pe.telecable.tcplay.lg`, versión `0.1.0`. Antes de una publicación comercial se revisarán identificadores, iconos, privacidad, comportamiento de salida y requisitos de la tienda. El botón Atrás se recibe mediante `disableBackHistoryAPI`; la salida usa diálogo propio y `window.close()`.

## Compatibilidad y validación pendiente

El código que corre en TV tiene sintaxis ES5 y no requiere React, módulos ES, fetch, Promise ni Media Source Extensions. Esto reduce dependencias de motores recientes; **no certifica compatibilidad con todos los modelos**. La familia objetivo es LG webOS, no NetCast.

Se necesita medir en televisores antiguos y recientes: teclado virtual, foco, Magic Remote, pantalla completa, audio/video, buffering, retorno desde Home y comportamiento de salida. Probar HLS real de Xtream y acceso directo desde la red del cliente; redirecciones, TLS, codecs y características del manifiesto pueden variar por modelo. No se convierte un stream incompatible a través de proxy: se muestra un error y permite reintentar.

Las pruebas automatizadas verifican la API simulada, carreras de solicitudes, navegación de la interfaz en jsdom y el adaptador con eventos de video simulados. No hubo conexión a Xtream, pruebas en TV real ni generación de IPK en este entorno. No es una entrega lista para tienda. Favoritos, EPG, VOD, sesión persistente y mejoras finales de diseño quedan para siguientes entregas.

## Referencias oficiales

- [Apps empaquetadas de webOS](https://webostv.developer.lge.com/develop/getting-started/web-app-types)
- [CLI y empaquetado IPK](https://webostv.developer.lge.com/develop/tools/cli-dev-guide)
- [Developer Mode](https://webostv.developer.lge.com/develop/getting-started/developer-mode-app)
- [Botón Atrás](https://webostv.developer.lge.com/develop/guides/back-button)
- [Streaming HLS y restricciones](https://webostv.developer.lge.com/develop/specifications/streaming-protocol-drm)
