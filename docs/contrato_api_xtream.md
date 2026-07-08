# Contrato de API — Integración Xtream (para Flutter)

- **Rama:** `feature/backend-normalizar-xtream`
- **Fecha:** 07/07/2026
- **Responsable:** Kevin
- **Estado:** respuestas normalizadas (Día 2)

Este documento define el **contrato** entre el backend Django y la app Flutter:
qué se envía (request) y qué se recibe (response) en cada endpoint, ya con las
respuestas **normalizadas** (sin datos sensibles de Xtream).

---

## Convenciones generales

- Todos los endpoints se consumen por **POST**.
- Todas las rutas **deben terminar en `/`** (un POST sin la barra final falla).
- El cuerpo (`body`) siempre va en **JSON**.
- Las credenciales de la **línea de cliente** (`username`, `password`) viajan en el body.
- Toda respuesta incluye el campo booleano **`success`**:
  - `true` → operación correcta, vienen los datos.
  - `false` → hubo un error, vienen `error_code` y `message`.
- Requiere **VPN/NOC activa** para alcanzar al servidor de Xtream.

### Base URL (desarrollo interno)

```
http://127.0.0.1:8000
```

---

## 1. Login — `POST /api/xtream/login/`

**Request:**

```json
{
  "username": "usuario_cliente",
  "password": "password_cliente"
}
```

**Response esperada (200):**

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

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `username` | string | Usuario de la línea de cliente. |
| `auth` | int | `1` = autenticado. |
| `status` | string | Estado de la cuenta (`Active`, etc.). |
| `is_active` | bool | `true` si `status == "Active"`. |
| `max_connections` | int | Conexiones simultáneas permitidas. |
| `active_connections` | int | Conexiones activas en este momento. |
| `exp_date` | string \| null | Vencimiento (timestamp Unix en texto) o `null`. |

> No se envía `password`, `server_info` ni datos internos del servidor.

---

## 2. Categorías — `POST /api/xtream/live/categories/`

**Request:**

```json
{
  "username": "usuario_cliente",
  "password": "password_cliente"
}
```

**Response esperada (200):**

```json
{
  "success": true,
  "categories": [
    { "id": "1", "name": "NACIONALES" },
    { "id": "2", "name": "DEPORTES" }
  ]
}
```

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | string | Identificador de la categoría. |
| `name` | string | Nombre visible de la categoría. |

> Si la línea de cliente no tiene **bouquets asignados**, `categories` puede venir
> vacío (`[]`) aunque el login sea exitoso.

---

## 3. Canales — `POST /api/xtream/live/streams/`

**Request** (el `category_id` es opcional; filtra por categoría):

```json
{
  "username": "usuario_cliente",
  "password": "password_cliente",
  "category_id": "1"
}
```

**Response esperada (200):**

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

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | int | Identificador del canal (`stream_id`). |
| `name` | string | Nombre del canal. |
| `category_id` | string | Categoría a la que pertenece. |
| `icon` | string | URL del logo del canal. |
| `stream_type` | string | Tipo de stream (`live`). |

---

## 4. URL de reproducción — `POST /api/xtream/live/stream-url/`

**Request:**

```json
{
  "username": "usuario_cliente",
  "password": "password_cliente",
  "stream_id": "43"
}
```

**Response esperada (200):**

```json
{
  "success": true,
  "stream_url": "http://host:puerto/live/usuario/password/43.ts"
}
```

> ⚠️ **Seguridad:** la `stream_url` **contiene el usuario y la contraseña en texto
> plano**, porque así lo exige el reproductor de Xtream. En producción se evaluará
> un **proxy o token temporal** para no exponer las credenciales a la app.

---

## Errores

Cuando `success` es `false`, la respuesta trae `error_code` y `message`. El detalle
del contrato de errores y sus ejemplos está en
[`respuestas_xtream.md`](respuestas_xtream.md).

---

## Notas para Flutter y Web

Recomendaciones para consumir esta API desde las apps cliente:

- **Siempre revisar `success` primero.** Si es `true`, usar los datos; si es `false`,
  mostrar el mensaje según `error_code`.
- **Decidir el mensaje por `error_code`, no por `message`.** El `error_code` es
  estable; el texto de `message` puede cambiar. Ideal mapear cada código a un texto
  propio localizado en la app.
- **Todas las rutas terminan en `/`** y se consumen por **POST** con `Content-Type:
  application/json`.
- **Tipos de datos a tener en cuenta (importante para Dart/TypeScript):**
  - `categories[].id` llega como **string** (`"1"`).
  - `channels[].id` llega como **int** (`43`), y `channels[].category_id` como
    **string**. Parsear con cuidado hasta que se unifique el tipo (ver pendientes).
  - `exp_date` puede ser `null` o un **timestamp Unix en texto** (ej. `"1785474000"`).
- **La `stream_url` contiene credenciales** en texto plano; no mostrarla ni loguearla
  en el cliente. Úsala solo para inicializar el reproductor.
- **Listas vacías no son error:** si `categories` o `channels` vienen como `[]`, es
  porque la línea de cliente no tiene bouquets; la app debe manejar el caso "sin
  contenido" sin tratarlo como fallo.
- **Manejo de red:** ante `xtream_unavailable` o `connection_timeout`, sugerir
  reintentar; suelen deberse a la VPN/NOC o a que Xtream no responde.

---

## Propuesta futura: endpoint mock sin VPN/NOC

**Problema:** hoy todos los endpoints requieren **VPN/NOC activa** para alcanzar a
Xtream. Esto complica el desarrollo de Flutter/Web y las pruebas automáticas cuando
no se tiene acceso a la red interna.

**Propuesta (no implementada aún):** ofrecer un **modo mock** del backend que
devuelva respuestas normalizadas de ejemplo **sin llamar a Xtream**, para que los
equipos de front puedan desarrollar y probar contra un contrato estable.

Opciones a evaluar:

- **Flag de entorno**, por ejemplo `XTREAM_MOCK=true` en el `.env`, que haga que las
  vistas devuelvan datos de ejemplo fijos (mismos formatos de este contrato).
- **Endpoints espejo** bajo un prefijo `/api/xtream/mock/...` con respuestas
  quemadas, dejando los reales intactos.
- **Fixtures JSON** reutilizables tanto por el modo mock como por los tests
  automáticos.

**Beneficios:** desarrollo de front sin VPN, pruebas reproducibles, demos sin
depender de la infraestructura interna. **No** reemplaza la validación real contra
Xtream, solo la complementa.
