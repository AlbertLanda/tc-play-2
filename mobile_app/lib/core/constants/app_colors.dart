import 'package:flutter/material.dart';

/// Paleta de color de TC Play — construida únicamente a partir de los
/// tonos del isotipo (azul marino profundo + blanco), sin acentos neón.
/// Todo el resto de colores funcionales (alertas, error, etiquetas) son
/// variaciones tonales del mismo azul para mantener una identidad única
/// y profesional en toda la app.
class AppColors {
  AppColors._();

  // -------------------------------------------------------------------
  // Base — extraída directamente del logo (azul marino #01076B)
  // -------------------------------------------------------------------

  /// Fondo principal. Azul marino casi negro: profundo, sobrio, propio
  /// de apps de streaming profesionales (no negro puro, para no perder
  /// la identidad de marca).
  static const Color background = Color(0xFF060A26);

  /// Fondo secundario (barras, nav inferior).
  static const Color surface = Color(0xFF0C1240);

  /// Tarjetas y tiles.
  static const Color card = Color(0xFF121A52);

  /// Color de marca — el azul exacto del logo.
  static const Color primary = Color(0xFF141C7A);

  /// Variante oscura del azul de marca (usada en degradados y estados
  /// presionados).
  static const Color primaryDark = Color(0xFF080B3E);

  /// Variante clara del azul de marca — reemplaza cualquier acento
  /// "neón": es el mismo azul, solo más luminoso, para usarse en
  /// bordes activos, íconos seleccionados y focos de inputs.
  static const Color accent = Color(0xFF5661C9);

  // -------------------------------------------------------------------
  // Texto
  // -------------------------------------------------------------------

  static const Color textPrimary = Color(0xFFF4F5FA);

  static const Color textSecondary = Color(0xFFA3AAD1);

  // Compatibilidad con componentes existentes
  static const Color subtitle = textSecondary;

  static const Color white = Colors.white;

  static const Color white70 = Colors.white70;

  static const Color black = Colors.black;

  // Compatibilidad con código existente
  static const Color inputBackground = surface;

  static const Color title = textPrimary;

  // Antes apuntaban al cian neón; ahora usan el azul de marca para
  // conservar una sola paleta.
  static const Color green = primary;

  static const Color neonGreen = primary;

  // -------------------------------------------------------------------
  // Colores funcionales — versiones atenuadas (no saturadas) para que
  // convivan con el azul de marca sin verse ajenas al logo.
  // -------------------------------------------------------------------

  /// Usado en "Suscríbete", la etiqueta "EN VIVO" y la barra de
  /// progreso del reproductor. Rojo desaturado, no neón.
  static const Color liveRed = Color(0xFF2962FF);

  /// Dorado sobrio para favoritos / destacados, en vez del ámbar puro.
  static const Color favoriteGold = Color(0xFFC9A24B);


  /// Verde institucional de canales de terceros (p. ej. tiles como
  /// "Latina"): se mantiene porque representa la marca de ese canal,
  /// no la identidad visual de TC Play.
  static const Color brandGreen = Color(0xFF1F8A55);

  /// Naranja atenuado para variedad en íconos de categorías.
  static const Color orange = Color(0xFFC97A3E);

  static const Color error = Color(0xFFCC5566);

  /// Fondo translúcido para chips / pills sobre imágenes.
  static Color scrim(double opacity) => Colors.black.withValues(alpha: opacity);

  /// Degradado de marca — mismo azul en distintos tonos, sin mezclar
  /// con colores externos.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDark, primary, accent],
  );
}
