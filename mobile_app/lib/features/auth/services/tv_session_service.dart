import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Credenciales guardadas de forma segura para "Mantener sesión iniciada"
/// en Android TV.
class TvSessionData {
  const TvSessionData({required this.username, required this.password});

  final String username;
  final String password;
}

/// Persistencia segura de la sesión de Android TV.
///
/// El backend actual no entrega un token de sesión persistente, así que
/// mientras eso no exista, "Mantener sesión iniciada" se implementa
/// guardando usuario y contraseña respaldados por el Android Keystore
/// (a través de `flutter_secure_storage`), nunca en `SharedPreferences`
/// ni en texto plano. En cada apertura de la app, estas credenciales se
/// vuelven a validar contra `AuthService.login()` antes de dar acceso
/// automático; nunca se usan para saltarse esa validación.
///
/// Esto es exclusivo del flujo de TV: el "Recordarme" del móvil sigue
/// usando `SharedPreferences` y solo guarda el usuario, sin cambios.
class TvSessionService {
  TvSessionService._();

  // Sin opciones especiales: el plugin ya respalda el almacenamiento en
  // Android con el Keystore por defecto (no se guarda nada en
  // SharedPreferences sin cifrar). No se fija un `AndroidOptions`
  // explícito porque su forma cambia entre versiones mayores del
  // paquete y el comportamiento por defecto ya cumple el requisito de
  // no usar SharedPreferences ni texto plano.
  static const _storage = FlutterSecureStorage();

  static const String _usernameKey = 'tv_session_username';
  static const String _passwordKey = 'tv_session_password';

  /// Guarda usuario y contraseña para reingreso automático en TV.
  static Future<void> saveSession({
    required String username,
    required String password,
  }) async {
    try {
      await _storage.write(key: _usernameKey, value: username);
      await _storage.write(key: _passwordKey, value: password);
    } catch (_) {
      // Si el almacenamiento seguro falla, simplemente no habrá
      // reingreso automático; no debe romper el login manual.
    }
  }

  /// Recupera la sesión guardada, si existe.
  static Future<TvSessionData?> getSession() async {
    try {
      final username = await _storage.read(key: _usernameKey);
      final password = await _storage.read(key: _passwordKey);

      if (username == null || username.isEmpty || password == null) {
        return null;
      }

      return TvSessionData(username: username, password: password);
    } catch (_) {
      return null;
    }
  }

  /// Elimina la sesión persistida (sesión inválida, logout o el usuario
  /// desactivó "Mantener sesión iniciada").
  static Future<void> clearSession() async {
    try {
      await _storage.delete(key: _usernameKey);
      await _storage.delete(key: _passwordKey);
    } catch (_) {}
  }
}