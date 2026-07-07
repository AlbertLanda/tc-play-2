# Validación de la Integración Xtream

- **Rama:** `feature/backend-validacion-xtream`
- **Fecha:** 06/07/2026
- **Responsable:** Kevin

## Resumen

Se validaron los endpoints del backend que consumen la API de Xtream. Todos
respondieron correctamente (HTTP 200) desde el entorno local con VPN/NOC activa.

| Endpoint | Método | Estado |
|----------|--------|--------|
| Health | GET | ✅ |
| Login Xtream | POST | ✅ |
| Categorías | POST | ✅ |
| Canales | POST | ✅ |
| URL de reproducción | POST | ✅ |

## Notas de la validación

- La conexión hacia Xtream requiere **VPN/NOC activa**.
- El usuario `admin` del panel no sirve para la API de cliente; se debe usar una
  **línea de cliente** con **bouquets asignados**. Sin bouquets, las categorías y
  canales regresan vacíos aunque el login sea exitoso.
- Todas las rutas deben terminar en `/` (un POST sin la barra final falla).

## Datos sensibles a filtrar (siguiente etapa)

El backend hoy reenvía la respuesta de Xtream tal cual. Antes de exponer datos a la app
se debe evitar enviar:

- La **contraseña** del usuario (Xtream la devuelve en el login).
- Las **credenciales incrustadas** en la URL de reproducción.
- Los **datos internos de infraestructura** (host y puertos del servidor).

## Recomendaciones

- Normalizar las respuestas para devolver solo los campos necesarios a la app.
- Diferenciar "credenciales inválidas" de "error de gateway" en el manejo de errores.
- Evaluar HTTPS para el tráfico app ↔ backend en producción.

---

# Respuestas normalizadas (Día 2)

- **Rama:** `feature/backend-normalizar-xtream`
- **Fecha:** 07/07/2026
- **Responsable:** Kevin

A partir del Día 2 el backend **ya no reenvía la respuesta cruda de Xtream**. Cada
endpoint devuelve solo los campos que la app (Flutter) necesita y oculta datos
sensibles (contraseña, `server_info`, host y puertos internos).

**Request:**
```json
{
  "username": "usuario_cliente",
  "password": "password_cliente"
}
```

**Response normalizada (200):**

```json
{
  "success": true,
  "user": {
    "username": "cliente.demo",
    "auth": 1,
    "status": "Active",
    "is_active": true,
    "max_connections": 1,
    "active_connections": 0,
    "exp_date": null
  }
}
```

No se envía: `password`, `server_info`, ni datos internos del servidor.
`exp_date` puede venir como `null` o como timestamp Unix en texto.

**Request:**

```json
{
  "username": "usuario_cliente",
  "password": "password_cliente"
}
```

**Response normalizada (200):**

```json
{
  "success": true,
  "categories": [
    { "id": "1", "name": "NACIONALES" },
    { "id": "2", "name": "DEPORTES" }
  ]
}
```

> Si la línea de cliente no tiene **bouquets asignados**, `categories` puede venir
> vacío (`[]`) aunque el login sea exitoso.

**Request** (el `category_id` es opcional para filtrar por categoría):

```json
{
  "username": "usuario_cliente",
  "password": "password_cliente",
  "category_id": "1"
}
```

**Response normalizada (200):**

```json
{
  "success": true,
  "channels": [
    {
      "id": 43,
      "name": "ONTV",
      "category_id": "1",
      "icon": "http://.../logo.png",
      "stream_type": "live"
    }
  ]
}
```

**Request:**

```json
{
  "username": "usuario_cliente",
  "password": "password_cliente",
  "stream_id": "43"
}
```

**Response (200):**

```json
{
  "success": true,
  "stream_url": "http://host:puerto/live/usuario/password/43.ts"
}
```

> ⚠️ **Nota de seguridad:** la `stream_url` **contiene el usuario y la contraseña
> incrustados en texto plano**, porque así lo exige el reproductor de Xtream. Es un
> riesgo conocido. **En producción se evaluará usar un proxy o un token temporal**
> para que la app nunca reciba las credenciales directamente. (Mejora futura, no
> implementada en el Día 2.)

## Manejo de errores (uniforme)

Todos los errores responden con la misma forma, para que la app pueda leer
`error_code` y mostrar un mensaje claro. Nunca se exponen credenciales ni datos
internos del servidor.

```json
{
  "success": false,
  "error_code": "invalid_credentials",
  "message": "Usuario o contraseña incorrectos."
}
```

| Caso | `error_code` | HTTP | Mensaje |
|------|--------------|------|---------|
| Faltan usuario o contraseña | `missing_credentials` | 400 | Usuario y contraseña son obligatorios. |
| Credenciales inválidas | `invalid_credentials` | 401 | Usuario o contraseña incorrectos. |
| Xtream no responde | `xtream_unavailable` | 502 | No se pudo conectar con el servicio de TV. |
| Tiempo de espera agotado | `connection_timeout` | 504 | Tiempo de espera agotado al conectar con Xtream. |
| Error no esperado | `unexpected_error` | 500 | Ocurrió un error inesperado. |

> Nota: algunos paneles Xtream devuelven **HTTP 200 con `auth: 0`** ante credenciales
> incorrectas; otros devuelven **HTTP 404**. El backend contempla ambos casos y en
> los dos responde `invalid_credentials`.
