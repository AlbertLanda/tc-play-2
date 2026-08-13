// Ruta sugerida en el proyecto: lib/core/utils/log_sanitizer.dart

/// Devuelve una versión segura para logs de un error/excepción.
///
/// En esta app las URLs de streaming tienen el formato de la API
/// Xtream Codes: `http://host/live/{usuario}/{contraseña}/{streamId}.ts`.
/// Eso significa que el usuario y la contraseña viajan DENTRO de la URL,
/// y cualquier excepción de red (timeout, host no disponible, etc.)
/// suele incluir esa URL completa en su mensaje (`e.toString()`).
///
/// Antes varios `catch (e) { debugPrint('... $e'); }` imprimían ese
/// mensaje tal cual, lo que podía dejar credenciales en los logs del
/// dispositivo. Esta función corta eso de raíz: si el mensaje de error
/// contiene algo que parece una URL, se descarta el contenido y solo se
/// deja el tipo de excepción; si no, se deja pasar el mensaje normal.
String sanitizeForLog(Object error) {
  final raw = error.toString();

  // Cubre http(s):// y también esquemas tipo rtmp/rtsp por las dudas,
  // ya que algunos proveedores IPTV los usan para streams en vivo.
  final urlPattern = RegExp(
    r'[a-z][a-z0-9+.-]*:\/\/[^\s"\)\]]+',
    caseSensitive: false,
  );

  if (urlPattern.hasMatch(raw)) {
    return '${error.runtimeType} (detalle omitido: el mensaje contiene una URL)';
  }

  return raw;
}