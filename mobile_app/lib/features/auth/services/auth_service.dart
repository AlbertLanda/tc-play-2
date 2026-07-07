import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';

class AuthService {
  Future<bool> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(ApiConstants.login),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (data['success'] == true) {
          return true;
        }

        throw Exception(data['detail'] ?? 'Credenciales incorrectas.');
      }

      throw Exception(data['detail'] ?? 'Error al iniciar sesión.');
    } catch (_) {
      throw Exception(
        'No fue posible conectar con el servidor. Verifique su conexión.',
      );
    }
  }
}