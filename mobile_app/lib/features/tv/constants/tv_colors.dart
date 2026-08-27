import 'package:flutter/material.dart';

/// Paleta exclusiva del modo TV: negro y blanco, igual que el isotipo
/// de la app (fondo negro + trazo blanco), sin el azul de marca que
/// usa el resto de la app (ver AppColors, en core/constants).
///
/// Es un archivo independiente a propósito: así este cambio de color
/// queda contenido a las pantallas de TV y no afecta login/home/
/// cuenta/etc. del lado móvil, que siguen usando AppColors.
class TvColors {
  TvColors._();

  static const Color background = Color(0xFF000000);

  /// Fondo de la barra superior — casi negro, apenas se distingue
  /// del fondo principal.
  static const Color surface = Color(0xFF0D0D0D);

  /// Fondo de paneles y tarjetas (categorías, canales, diálogos).
  static const Color card = Color(0xFF161616);

  /// Gris claro — indicador de "seleccionado" (borde, ícono, texto).
  static const Color primary = Color(0xFFD0D0D0);

  /// Blanco puro — indicador de "foco" del control (más brillante
  /// que `primary`, para que se note cuál tiene el foco del D-pad).
  static const Color accent = Color(0xFFFFFFFF);

  static const Color textPrimary = Color(0xFFFFFFFF);

  static const Color textSecondary = Color(0xFF9A9A9A);

  static const Color error = Color(0xFFE05252);
}
