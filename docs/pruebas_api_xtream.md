# Pruebas manuales — API normalizada de Xtream

- **Fecha:** 07/07/2026
- **Responsable:** Kevin Junior Rivera Ravichagua
- **Rama:** `feature/backend-validacion-api-normalizada`
- **Entorno:** Local (Django `runserver`) en `http://127.0.0.1:8000`
- **Herramienta:** Thunder Client
- **Requisito:** VPN/NOC activa para alcanzar el servidor de Xtream

> ⚠️ Por seguridad, en este documento **no** se incluyen usuarios ni contraseñas
> reales. Las pruebas se hicieron con una línea de cliente de prueba.

---

## Verificación previa

- `python manage.py check` → **System check identified no issues (0 silenced).** ✅
- Servidor Django levantado correctamente en `http://127.0.0.1:8000`. ✅

---

## Resultados de las pruebas

| # | Endpoint | Caso de prueba | HTTP | Resultado | Observación |
|---|----------|----------------|------|-----------|-------------|
| 1 | `POST /api/xtream/login/` | Usuario correcto | 200 | `success: true` + `user` normalizado | No expone `password` ni `server_info`. |
| 2 | `POST /api/xtream/login/` | Body vacío | 400 | `missing_credentials` | Validación previa a llamar a Xtream. |
| 3 | `POST /api/xtream/login/` | Credenciales incorrectas | 401 | `invalid_credentials` | Este panel devuelve 404; el backend lo mapea a `invalid_credentials`. |
| 4 | `POST /api/xtream/live/categories/` | Usuario correcto | 200 | `categories` con `id` y `name` | Vacío si la línea no tiene bouquets. |
| 5 | `POST /api/xtream/live/streams/` | Sin `category_id` | 200 | `channels` normalizados | Devuelve `id`, `name`, `category_id`, `icon`, `stream_type`. |
| 6 | `POST /api/xtream/live/streams/` | Con `category_id` | 200 | `channels` filtrados por categoría | Filtro aplicado correctamente. |
| 7 | `POST /api/xtream/live/stream-url/` | `stream_id` válido | 200 | `stream_url` generado | La URL contiene credenciales (ver observaciones). |

---

## Detalle de cada prueba (request y respuesta obtenida)

### 1. Login correcto

**Request** `POST /api/xtream/login/`:

```json
{ "username": "<linea_de_cliente>", "password": "<password>" }
```

**Respuesta (200):**

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
    "exp_date": "1785474000"
  }
}
```

Se confirma que la respuesta **no incluye** `password` ni `server_info`.

### 2. Body vacío → `missing_credentials`

**Request** `POST /api/xtream/login/` con body `{}`.

**Respuesta (400):**

```json
{
  "success": false,
  "error_code": "missing_credentials",
  "message": "Usuario y contraseña son obligatorios."
}
```

### 3. Credenciales incorrectas → `invalid_credentials`

**Request** `POST /api/xtream/login/` con una contraseña inválida.

**Respuesta (401):**

```json
{
  "success": false,
  "error_code": "invalid_credentials",
  "message": "Usuario o contraseña incorrectos."
}
```

> Este panel Xtream responde HTTP 404 ante credenciales inválidas; el backend lo
> traduce a `invalid_credentials` (401).

### 4. Categorías normalizadas

**Request** `POST /api/xtream/live/categories/` con usuario correcto.

**Respuesta (200):**

```json
{
  "success": true,
  "categories": [
    { "id": "1", "name": "NACIONALES" },
    { "id": "2", "name": "DEPORTES" }
  ]
}
```

Devuelve únicamente `id` y `name`.

### 5. Canales normalizados (sin `category_id`)

**Request** `POST /api/xtream/live/streams/` con usuario correcto.

**Respuesta (200):**

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

Devuelve solo `id`, `name`, `category_id`, `icon` y `stream_type`.

### 6. Canales filtrados (con `category_id`)

**Request** `POST /api/xtream/live/streams/`:

```json
{ "username": "<linea_de_cliente>", "password": "<password>", "category_id": "1" }
```

**Respuesta (200):** misma estructura que la prueba 5, pero **solo los canales de esa
categoría** (todos con `category_id: "1"`).

### 7. URL de reproducción

**Request** `POST /api/xtream/live/stream-url/`:

```json
{ "username": "<linea_de_cliente>", "password": "<password>", "stream_id": "43" }
```

**Respuesta (200):**

```json
{
  "success": true,
  "stream_url": "http://host:puerto/live/usuario/password/43.ts"
}
```

> La `stream_url` contiene las credenciales en texto plano (ver observaciones).

---

## Observaciones

- **Líneas sin bouquets:** si la línea de cliente no tiene bouquets asignados,
  `categories` y `channels` regresan vacíos (`[]`) aunque el login sea exitoso.
  No es un error del backend, es configuración de la cuenta en Xtream.
- **VPN/NOC:** todas las pruebas que consultan Xtream (login correcto, categorías,
  canales) requieren la VPN/NOC activa. Sin ella, el backend responde
  `xtream_unavailable`.
- **Rutas con `/`:** todas las rutas deben terminar en `/`. Un POST sin la barra
  final falla.
- **Credenciales en `stream_url`:** la URL de reproducción incluye usuario y
  contraseña en texto plano (`.../live/usuario/password/stream_id.ts`). Es un
  riesgo conocido y propio del reproductor de Xtream. **En producción se evaluará
  un proxy o token temporal** para no exponer credenciales a la app.
- **Sin fuga de datos internos:** ninguna respuesta de error expone IP, puerto,
  `server_info` ni credenciales.

---

## Pendientes técnicos (para los siguientes días)

- Unificar el **tipo del campo `id`**: hoy es `string` en categorías y `int` en
  canales; conviene una convención única para Flutter/Web.
- Agregar **tests automáticos** (`xtream/tests.py`) que mockeen a Xtream y validen
  los 5 `error_code` y la forma de las respuestas normalizadas.
- Evaluar un **endpoint mock** que permita probar la API sin depender de la VPN/NOC.
- Evaluar si el login debe considerarse válido solo cuando `auth == 1` **y**
  `status == "Active"`. **Hallazgo:** hoy el login solo valida `auth == 1`; una
  cuenta con `auth: 1` pero `status` distinto de `Active` (ej. `Expired`,
  `Disabled`, `Banned`) **pasaría el login**. Se recomienda exigir también
  `status == "Active"` (idealmente con un `error_code` propio tipo
  `inactive_account`). Pendiente de decisión con el equipo; no implementado.
