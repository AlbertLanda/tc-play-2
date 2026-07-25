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

        throw Exception(
          data['detail'] ?? 'Usuario o contraseña incorrectos.',
        );
      }

      throw Exception(
        data['detail'] ?? 'No fue posible iniciar sesión.',
      );
      
    } on http.ClientException {
      throw Exception('Sin conexión.');
    } catch (e) {
      final error = e.toString().toLowerCase();

      if (error.contains('401') ||
          error.contains('credenciales') ||
          error.contains('incorrect')) {
        throw Exception('Usuario o contraseña incorrectos.');
      }

      if (error.contains('403') ||
          error.contains('inactive') ||
          error.contains('inactiva')) {
        throw Exception('Cuenta inactiva.');
      }

      rethrow;
    }
  }
}