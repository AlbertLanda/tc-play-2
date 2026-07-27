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

      Map<String, dynamic> data = {};

      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        data = {};
      }

      final message = data['message'] ?? data['detail'];

      if (response.statusCode == 200 && data['success'] == true) {
        return true;
      }

      if (response.statusCode == 401) {
        throw Exception('Usuario o contraseña incorrectos.');
      }

      if (response.statusCode == 403) {
        throw Exception('Cuenta inactiva.');
      }

      throw Exception(message ?? 'No fue posible iniciar sesión.');
    } on http.ClientException {
      throw Exception('Sin conexión. Verifica tu internet e inténtalo nuevamente.');
    } catch (e) {
      final error = e.toString().toLowerCase();

      if (error.contains('usuario') ||
          error.contains('contraseña') ||
          error.contains('credenciales') ||
          error.contains('incorrect')) {
        throw Exception('Usuario o contraseña incorrectos.');
      }

      if (error.contains('403') ||
          error.contains('inactive') ||
          error.contains('inactiva')) {
        throw Exception('Cuenta inactiva.');
      }

      if (error.contains('socket') ||
          error.contains('host') ||
          error.contains('connection') ||
          error.contains('network')) {
        throw Exception('Sin conexión. Verifica tu internet e inténtalo nuevamente.');
      }

      rethrow;
    }
  }
}