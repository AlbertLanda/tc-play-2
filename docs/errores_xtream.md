# Errores de la API — Integración Xtream

- **Rama:** `feature/backend-normalizar-xtream`
- **Fecha:** 07/07/2026
- **Responsable:** Kevin

Guía de los errores que devuelve el backend y ejemplos de los casos más comunes,
para que la app (Flutter) los maneje de forma uniforme.

---

## Forma general

Cuando `success` es `false`, la respuesta siempre trae `error_code` y `message`:

```json
{
  "success": false,
  "error_code": "invalid_credentials",
  "message": "Usuario o contraseña incorrectos."
}
```

> La app debe decidir el mensaje al usuario en base a **`error_code`** (estable),
> no al `message` (que puede cambiar de texto).

---

## Tabla de errores

| Caso | `error_code` | HTTP | Mensaje |
|------|--------------|------|---------|
| Faltan usuario o contraseña | `missing_credentials` | 400 | Usuario y contraseña son obligatorios. |
| Credenciales inválidas | `invalid_credentials` | 401 | Usuario o contraseña incorrectos. |
| Cuenta no activa (vencida / deshabilitada / baneada) | `inactive_account` | 403 | La cuenta no se encuentra activa. |
| Xtream no responde | `xtream_unavailable` | 502 | No se pudo conectar con el servicio de TV. |
| Tiempo de espera agotado | `connection_timeout` | 504 | Tiempo de espera agotado al conectar con Xtream. |
| Error no esperado | `unexpected_error` | 500 | Ocurrió un error inesperado. |

---

## Ejemplos de errores comunes

### 1. Body vacío / faltan credenciales — HTTP 400

```json
{
  "success": false,
  "error_code": "missing_credentials",
  "message": "Usuario y contraseña son obligatorios."
}
```

### 2. Usuario o contraseña incorrectos — HTTP 401

```json
{
  "success": false,
  "error_code": "invalid_credentials",
  "message": "Usuario o contraseña incorrectos."
}
```

### 3. Cuenta autenticada pero no activa — HTTP 403

Las credenciales son correctas (`auth == 1`), pero la cuenta **no está activa**
(vencida, deshabilitada o baneada), por lo que **no** se permite el acceso.

```json
{
  "success": false,
  "error_code": "inactive_account",
  "message": "La cuenta no se encuentra activa."
}
```

### 4. Servicio de TV caído / VPN inactiva — HTTP 502

```json
{
  "success": false,
  "error_code": "xtream_unavailable",
  "message": "No se pudo conectar con el servicio de TV."
}
```

### 5. Tiempo de espera agotado — HTTP 504

```json
{
  "success": false,
  "error_code": "connection_timeout",
  "message": "Tiempo de espera agotado al conectar con Xtream."
}
```

### 6. Error inesperado — HTTP 500

```json
{
  "success": false,
  "error_code": "unexpected_error",
  "message": "Ocurrió un error inesperado."
}
```

---

## Nota sobre credenciales inválidas

Algunos paneles Xtream devuelven **HTTP 200 con `auth: 0`** ante credenciales
incorrectas; otros devuelven **HTTP 404**. En ambos casos el backend responde
`invalid_credentials`, para que la app maneje un único código.

## Nota sobre cuenta no activa (`inactive_account`)

El login solo es válido cuando se cumplen **ambas** condiciones:

- `auth == 1` (las credenciales son correctas), **y**
- `status == "Active"` (la cuenta está vigente).

Diferencia importante para la app:

- Si `auth != 1` → `invalid_credentials` (401): el usuario o la contraseña están mal.
- Si `auth == 1` pero `status != "Active"` → `inactive_account` (403): las credenciales
  son correctas, pero la cuenta está vencida, deshabilitada o baneada. La app debería
  mostrar un mensaje del tipo *"tu cuenta no está activa, renueva tu plan"*, distinto
  al de credenciales incorrectas.
