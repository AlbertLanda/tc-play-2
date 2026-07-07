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

### 3. Servicio de TV caído / VPN inactiva — HTTP 502

```json
{
  "success": false,
  "error_code": "xtream_unavailable",
  "message": "No se pudo conectar con el servicio de TV."
}
```

### 4. Tiempo de espera agotado — HTTP 504

```json
{
  "success": false,
  "error_code": "connection_timeout",
  "message": "Tiempo de espera agotado al conectar con Xtream."
}
```

### 5. Error inesperado — HTTP 500

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
