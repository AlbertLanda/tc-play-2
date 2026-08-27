# Publicar TC Play en Google Play Console

Guía paso a paso para subir la app (celular + Android TV) a Play Store,
usando la cuenta de desarrollador ya creada ("TeleCable Perú").

## 0. Antes de empezar: verificación de la cuenta

En la pantalla de Play Console vas a ver "Termina de configurar tu cuenta
de desarrollador" con tres pasos: verificar identidad, verificar acceso a
un dispositivo Android, verificar número de teléfono. **Google puede
tardar varios días en aprobar la identidad.** No bloquea que prepares
todo lo de abajo mientras tanto, pero sí bloquea el envío final a
revisión — mejor arrancarla ahora si no la has empezado.

## 1. ID de la aplicación (ya resuelto en el código)

Se cambió el `applicationId` de `com.example.tc_play_app` (el de
plantilla de Flutter, que Play Store rechaza) a **`pe.telecable.tcplay`**
en `mobile_app/android/app/build.gradle.kts`.

Esto es **permanente**: una vez publicada la primera versión, este ID no
se puede volver a cambiar. Si quieres uno distinto, avisa antes de subir
la primera versión.

## 2. Generar el keystore de release

La app hoy se firma con la llave de debug, que Play Store no acepta para
publicar. Hay que generar un keystore real **en tu máquina** (no en este
entorno remoto: es un archivo que debes guardar tú mismo de forma segura,
nunca en git — si se pierde, no vas a poder subir actualizaciones a esta
misma ficha de Play Store nunca más).

```powershell
# Desde PowerShell, en la carpeta donde quieras guardar el keystore
# (fuera del repo, por ejemplo en tu carpeta de usuario):
& "$env:JAVA_HOME\bin\keytool" -genkey -v -keystore tcplay-release.jks `
  -keyalg RSA -keysize 2048 -validity 10000 -alias tcplay
```

Te va a pedir una contraseña para el keystore, tus datos (nombre,
organización, etc. — pueden ser genéricos, no afectan la app) y una
contraseña para la llave (puede ser la misma que la del keystore).

**Guarda en un lugar seguro (gestor de contraseñas, no en el chat ni en
el repo):**
- El archivo `tcplay-release.jks`
- La contraseña del keystore
- La contraseña de la llave
- El alias (`tcplay` si usaste el comando de arriba)

Luego, en `mobile_app/android/`, copia `key.properties.example` a
`key.properties` (ese nombre exacto, sin `.example`) y rellena los 4
valores con los datos de arriba, por ejemplo:

```properties
storePassword=tu_contraseña_del_keystore
keyPassword=tu_contraseña_de_la_llave
keyAlias=tcplay
storeFile=C:/Users/aalrp/tcplay-release.jks
```

`android/key.properties` ya está en `.gitignore` — no se sube a git.
En cuanto exista ese archivo, `flutter build appbundle --release` firma
automáticamente con tu keystore real (antes de crearlo, sigue usando la
firma de debug para no romper `flutter run --release` mientras
desarrollas).

## 3. Generar el archivo para subir (.aab)

Google Play pide un **Android App Bundle** (`.aab`), no el `.apk` que
usas para probar en la TV con `flutter run`.

```powershell
cd C:\Users\aalrp\Proyectos\tc-play-2\mobile_app
flutter build appbundle --release
```

El archivo queda en:
```
build\app\outputs\bundle\release\app-release.aab
```

Si al correr esto ves un error de firma, revisa que `key.properties`
tenga la ruta absoluta correcta al `.jks` y que las contraseñas sean
exactas.

## 4. Crear la app en Play Console

1. Entra a [Play Console](https://play.google.com/console) → **Crear app**.
2. Nombre: `TC Play` (o el que prefieran mostrar en la tienda — puede
   diferir del nombre interno).
3. Idioma predeterminado: Español (Perú/Latinoamérica).
4. Tipo: **App** (no juego).
5. Gratuita o de pago: según el modelo de negocio.
6. Acepta las declaraciones de políticas (contenido, exportación, etc.).

## 5. Ficha de la tienda (Store listing)

En **Presencia en la tienda → Ficha principal de Play Store**, necesitas
preparar (fuera de este chat, son diseño/marketing, no código):

- **Descripción corta** (máx. 80 caracteres) y **completa** (máx. 4000).
- **Ícono** de la app: 512×512 px, PNG con fondo, sin transparencia.
- **Gráfico destacado**: 1024×500 px.
- **Capturas de pantalla**: mínimo 2, tanto de celular como — muy
  importante para esta app — **de TV** (formato apaisado, 16:9). Usa
  capturas reales de `TvHomeScreen` (el mini panel y la pantalla
  completa que ya probamos).
- Categoría: probablemente "Entretenimiento" o "Video players y
  editores".
- Datos de contacto: correo de soporte visible públicamente.

## 6. Declaraciones obligatorias (Play Console las va guiando)

- **Cuestionario de clasificación de contenido** (IARC): describe qué
  tipo de contenido transmite la app (TV en vivo, sin contenido
  generado por el usuario, etc.).
- **Seguridad de los datos** (Data safety): qué datos recolecta la app.
  Hoy la app envía usuario/contraseña al backend propio para
  autenticar contra Xtream — hay que declarar eso como "información de
  cuenta" recolectada, sin compartir con terceros.
- **Audiencia objetivo y contenido**: probablemente 18+ o según el
  contenido de los canales que se retransmiten.
- **Anuncios**: declarar si la app muestra anuncios (el banner
  promocional "Nuevos planes disponibles" es propio, no de una red
  publicitaria de terceros — probablemente se declara "No" a anuncios,
  a menos que en el futuro se integre AdMob u otra red).
- **Países de distribución**: normalmente Perú, o los países donde
  Telecable tiene cobertura/licencia para retransmitir esos canales.

## 7. Subir el .aab

En **Producción** (o mejor, primero en **Pruebas internas** — ver
sección 8), botón **Crear nueva versión**, sube el
`app-release.aab` generado en el paso 3, escribe las notas de la
versión, y guarda/revisa.

## 8. Recomendado: probar antes de producción

Antes de mandarlo a revisión pública, usa una pista de **Pruebas
internas** (Internal testing): permite instalar la app en dispositivos
reales (celulares y TVs) vía un link privado, sin pasar por la revisión
completa de Google, para confirmar que todo funciona igual que probado
localmente. Cuando estén conformes, promocionan esa misma versión a
Producción desde la misma pantalla.

## 9. Nota específica de Android TV

El manifest (`AndroidManifest.xml`) ya declara lo necesario para que
Play Store reconozca la app como compatible con TV
(`android.software.leanback` y `android.hardware.touchscreen` como no
requeridos, más la categoría `LEANBACK_LAUNCHER`). Para que se vea bien
en el listado de Play Store para TV, conviene además:

- Un **banner de TV** (320×180 px) — Google lo pide como imagen
  separada del ícono normal, para el launcher de Android TV. Si quieren,
  lo puedo declarar en el manifest en cuanto tengan el archivo de imagen
  listo.
- Capturas de pantalla en formato TV (mencionado en el punto 5).

## 10. Después de aprobada

La primera revisión de una app nueva suele tardar más (puede ser horas
a pocos días). Las actualizaciones posteriores, subiendo un nuevo
`.aab` con `versionCode` mayor (en `mobile_app/pubspec.yaml`, el
número después del `+`, ej. `1.0.0+2`), normalmente se revisan más
rápido.
