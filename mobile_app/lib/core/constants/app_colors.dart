import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Fondo principal
  static const Color background = Color(0xFF060B16);

  // Fondo secundario
  static const Color surface = Color(0xFF111827);

  // Tarjetas
  static const Color card = Color(0xFF1A2234);

  // Color principal TC Play
  static const Color primary = Color(0xFF00C8FF);

  // Azul oscuro
  static const Color primaryDark = Color(0xFF0095E8);

  // Azul claro
  static const Color accent = Color(0xFF59E3FF);

  // Texto
  static const Color textPrimary = Colors.white;

  static const Color textSecondary = Color(0xFFAEB8C7);

  // Compatibilidad con componentes existentes
  static const Color subtitle = textSecondary;

  static const Color white = Colors.white;

  static const Color white70 = Colors.white70;

  static const Color black = Colors.black;

  // Compatibilidad con código existente
  static const Color inputBackground = surface;

  static const Color title = textPrimary;

  static const Color green = primary;

  static const Color neonGreen = primary;

  static const Color orange = Color(0xFFFF8A00);

  static const Color error = Color(0xFFFF5C5C);

  // ---------------------------------------------------------------------
  // Nuevos colores — estilo "TV en vivo" (banner promocional, EN VIVO,
  // barra de progreso del reproductor, botón Suscríbete)
  // ---------------------------------------------------------------------

  /// Rojo usado en el botón "Suscríbete", el tag "EN VIVO" y la barra
  /// de progreso del reproductor.
  static const Color liveRed = Color(0xFFE7222B);

  /// Verde usado por tiles tipo "Latina".
  static const Color brandGreen = Color(0xFF13A44A);

  /// Fondo translúcido para chips / pills sobre imágenes.
  static Color scrim(double opacity) => Colors.black.withValues(alpha: opacity);

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDark, primary, accent],
  );
}
