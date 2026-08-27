import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';

/// Utilidades para adaptar TC Play a pantallas grandes (Android TV /
/// Google TV) sin romper el flujo de celular.
///
/// La detección es por ANCHO LÓGICO disponible, no por plataforma: así
/// también cubre tablets muy anchas apaisadas, emuladores de TV y modo
/// escritorio, y no depende de `Theme.of(context).platform`. Por debajo
/// del umbral, todo el código sigue exactamente el mismo camino que
/// antes (mismos valores, mismos widgets): el modo móvil queda intacto.
class TvUtils {
  TvUtils._();

  /// Ancho lógico (dp) a partir del cual se activa el modo TV. Un
  /// celular en horizontal rara vez supera ~900dp; una TV HD/4K reporta
  /// bastante más que eso, incluso a densidades altas.
  static const double tvBreakpoint = 900;

  /// true si el ancho actual corresponde a modo TV.
  static bool isTv(BuildContext context) =>
      isTvWidth(MediaQuery.sizeOf(context).width);

  /// Igual que [isTv] pero a partir de un ancho ya conocido (útil
  /// dentro de un `LayoutBuilder`, donde ya se tiene
  /// `constraints.maxWidth` y conviene evitar leer `MediaQuery` de
  /// nuevo).
  static bool isTvWidth(double width) => width >= tvBreakpoint;

  /// Máximo de columnas de grilla razonable para el ancho disponible,
  /// con un techo más alto en TV (pantallas anchas permiten más
  /// columnas sin que las tarjetas se vean diminutas) que en celular.
  static int gridCrossAxisCount({
    required BuildContext context,
    required double availableWidth,
    required double tileWidth,
    int mobileMin = 3,
    int mobileMax = 4,
    int tvMin = 4,
    int tvMax = 8,
  }) {
    final count = (availableWidth / tileWidth).floor();
    return isTv(context)
        ? count.clamp(tvMin, tvMax)
        : count.clamp(mobileMin, mobileMax);
  }

  /// En TV, un `TextField` puede recibir foco por control remoto
  /// (autofocus o flechas + OK) en vez de un toque táctil. Flutter solo
  /// abre el teclado en pantalla automáticamente cuando detecta un
  /// toque; si el foco llega por control remoto, el campo queda
  /// "seleccionado" (con el cursor visible) pero el teclado nunca
  /// aparece y el usuario no puede escribir.
  ///
  /// Este helper fuerza la apertura del teclado cada vez que el
  /// [FocusNode] dado gana foco, sin importar cómo lo haya obtenido.
  /// Debe llamarse una vez en `initState`, con el mismo `FocusNode` que
  /// se le pase al `TextField` correspondiente, y su listener debe
  /// quitarse en `dispose` con [FocusNode.removeListener] pasando el
  /// mismo callback devuelto por este método.
  ///
  /// Uso:
  /// ```dart
  /// late final VoidCallback _showKeyboardListener;
  ///
  /// @override
  /// void initState() {
  ///   super.initState();
  ///   _showKeyboardListener = TvUtils.showKeyboardOnFocus(_focusNode);
  /// }
  ///
  /// @override
  /// void dispose() {
  ///   _focusNode.removeListener(_showKeyboardListener);
  ///   _focusNode.dispose();
  ///   super.dispose();
  /// }
  /// ```
  static VoidCallback showKeyboardOnFocus(FocusNode focusNode) {
    void listener() {
      if (focusNode.hasFocus) {
        SystemChannels.textInput.invokeMethod('TextInput.show');
      }
    }

    focusNode.addListener(listener);
    return listener;
  }

  /// Decoración de foco compartida: borde y resplandor sutil en el azul
  /// de marca, visible a distancia de sofá. Se usa junto con
  /// `AnimatedContainer`/`AnimatedScale` en las tarjetas navegables.
  static BoxDecoration focusDecoration({
    required bool focused,
    double radius = 14,
    Color? color,
  }) {
    final ringColor = color ?? AppColors.accent;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: focused ? ringColor : Colors.transparent,
        width: 3,
      ),
      boxShadow: focused
          ? [
              BoxShadow(
                color: ringColor.withValues(alpha: .5),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ]
          : const [],
    );
  }
}
