# Endpoints de integración Xtream

## Base URL

Para desarrollo interno mediante VPN/NOC:

```env
XTREAM_BASE_URL=http://172.16.25.12:25461

El puerto 25500 corresponde al panel administrativo de Xtream UI.
El puerto 25461 corresponde al servicio HTTP/API cliente.

Login de usuario
POST /api/xtream/login/

Body:

{
  "username": "usuario_cliente",
  "password": "password_cliente"
}

Resultado esperado:

{
  "success": true,
  "data": {
    "user_info": {
      "auth": 1,
      "status": "Active"
    }
  }
}
Categorías de TV en vivo
POST /api/xtream/live/categories/

Body:

{
  "username": "usuario_cliente",
  "password": "password_cliente"
}

Devuelve categorías como:

DEPORTES
NACIONALES
REGIONALES
DOCUMENTALES
INFANTILES
Canales en vivo
POST /api/xtream/live/streams/

Body:

{
  "username": "usuario_cliente",
  "password": "password_cliente"
}

También permite filtrar por categoría:

{
  "username": "usuario_cliente",
  "password": "password_cliente",
  "category_id": "1"
}

Datos importantes devueltos por Xtream

Los canales devuelven campos como:

name
stream_id
stream_icon
category_id
stream_type

Para reproducir un canal se debe construir la URL de reproducción con:

http://host:puerto/live/usuario/password/stream_id.ts

o según el formato permitido:

m3u8
ts
rtmp

---

## 4. Mejora recomendada al backend: endpoint para URL de reproducción

Ahora que ya obtenemos los canales, nos falta un endpoint útil para la app: construir la URL del canal.

En `xtream/services/client.py`, agrega este método dentro de la clase `XtreamClient`:

```python
    def build_live_stream_url(self, username: str, password: str, stream_id: str, output: str = "ts"):
        """
        Construye la URL de reproducción para un canal en vivo.
        Formatos comunes: ts, m3u8.
        """
        return f"{self.base_url}/live/{username}/{password}/{stream_id}.{output}"