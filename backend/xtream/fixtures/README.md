# Fixtures de ejemplo — Xtream (datos mock)

Respuestas **crudas** de ejemplo (como las devuelve el panel Xtream) para reutilizar
en pruebas automáticas y en el futuro modo mock, **sin depender de la VPN/NOC**.

> ⚠️ Todos los datos son **ficticios**. No contienen usuarios, contraseñas ni URLs
> reales. No usar en producción.

## Archivos

| Archivo | Representa |
|---------|-----------|
| `login_active.json` | Login de cuenta correcta y activa (`auth: 1`, `status: "Active"`). |
| `login_inactive.json` | Login autenticado pero cuenta no activa (`auth: 1`, `status: "Disabled"`). |
| `login_invalid.json` | Credenciales inválidas (`auth: 0`). |
| `live_categories.json` | Lista de categorías en vivo. |
| `live_streams.json` | Lista de canales en vivo. |

Estos ejemplos incluyen a propósito campos como `password` y `server_info` para
verificar que el backend **no** los reenvía al cliente tras normalizar.
