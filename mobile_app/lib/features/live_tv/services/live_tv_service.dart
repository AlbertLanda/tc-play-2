// TODO(backend): Cuando el endpoint real esté disponible, descomentar
// las siguientes dependencias e implementar la llamada HTTP indicada
// al final de este archivo.
// import 'dart:convert';
// import 'package:http/http.dart' as http;

/// Servicio encargado de obtener la información de TV en vivo
/// (categorías, canales, etc.).
///
/// Estructura preparada para consumir el endpoint real del backend
/// más adelante: solo es necesario reemplazar el bloque de datos
/// temporales por la llamada HTTP comentada en [getCategories].
class LiveTvService {
  // Configuración base lista para integrarse con el API principal.
  static const String _baseUrl = 'https://api.telecable.example.com';
  static const String _categoriesEndpoint = '/api/live-tv/categories';

  /// Obtiene la lista de categorías de TV en vivo disponibles.
  ///
  /// NOTA TÉCNICA: Los datos devueltos actualmente son TEMPORALES
  /// (hardcodeados en el cliente) mientras el backend expone el
  /// endpoint real de categorías. No representan información
  /// definitiva ni deben usarse como fuente de verdad en producción.
  Future<List<String>> getCategories() async {
    // Simula latencia de red para una experiencia de UI realista
    // durante el desarrollo del front-end.
    await Future.delayed(const Duration(milliseconds: 600));

    // ------------------------------------------------------------
    // DATOS TEMPORALES: reemplazar por la respuesta real del API.
    // ------------------------------------------------------------
    return const [
      'Noticias',
      'Deportes',
      'Entretenimiento',
      'Películas',
      'Infantil',
      'Música',
      'Documentales',
      'Internacional',
    ];

    // ------------------------------------------------------------
    // IMPLEMENTACIÓN FUTURA (endpoint real):
    // ------------------------------------------------------------
    // final response = await http.get(
    //   Uri.parse('$_baseUrl$_categoriesEndpoint'),
    //   headers: {
    //     'Content-Type': 'application/json',
    //     // 'Authorization': 'Bearer $token',
    //   },
    // );
    //
    // if (response.statusCode == 200) {
    //   final List<dynamic> data = jsonDecode(response.body);
    //   return data.map((e) => e.toString()).toList();
    // }
    //
    // throw Exception('Error al obtener categorías (${response.statusCode})');
  }
}
