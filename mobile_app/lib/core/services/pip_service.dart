// Ruta en el proyecto: lib/core/services/pip_service.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class PipService {
  static const MethodChannel _channel = MethodChannel('tc_play/pip');

  static final StreamController<bool> _pipModeController =
      StreamController<bool>.broadcast();

  /// Emite `true` cuando la app entra al mini-reproductor (PiP) y `false`
  /// cuando vuelve a pantalla completa. Cualquier widget puede suscribirse
  /// (por ejemplo PlayerScreen) para ocultar/mostrar sus controles.
  static Stream<bool> get pipModeStream => _pipModeController.stream;

  static bool _isInPipMode = false;
  static bool get isInPipMode => _isInPipMode;

  static bool _handlerRegistered = false;

  /// Debe llamarse una vez (por ejemplo en main()) para empezar a escuchar
  /// los avisos de Android cuando cambia el modo PiP.
  static void init() {
    if (_handlerRegistered) return;
    _handlerRegistered = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPipModeChanged') {
        _isInPipMode = call.arguments as bool? ?? false;
        _pipModeController.add(_isInPipMode);
      }
    });
  }

  static Future<bool> enterPictureInPicture() async {
    if (!Platform.isAndroid) return false;

    try {
      final result = await _channel.invokeMethod<bool>('enterPip');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Avisa al lado nativo si en este momento corresponde permitir que
  /// Android entre a PiP automáticamente al apretar Home
  /// (`onUserLeaveHint` en MainActivity).
  ///
  /// Esto es necesario porque `onUserLeaveHint` se dispara en el lado
  /// nativo ANTES de que Flutter reciba cualquier aviso de ciclo de vida
  /// (`AppLifecycleState.paused`), así que no alcanza con decidir del
  /// lado Dart si hay que pausar o no: para cuando Dart se entera,
  /// Android ya pudo haber encogido en la ventanita de PiP lo que sea
  /// que estuviera en pantalla en ese instante (por ejemplo, otra
  /// sección de la app con el mini-reproductor propio flotando encima,
  /// en vez de solo el video).
  ///
  /// Se debe llamar con `true` solo mientras PlayerScreen está
  /// realmente a pantalla completa, y con `false` en cualquier otro
  /// caso (incluido cuando solo está activo el mini-reproductor propio
  /// dentro de la app).
  static Future<void> setEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;

    try {
      await _channel.invokeMethod('setPipEnabled', {'enabled': enabled});
    } catch (_) {
      // Si falla (por ejemplo, en versiones viejas de la app nativa sin
      // este método todavía), no es crítico: en el peor caso queda el
      // comportamiento anterior en ese dispositivo puntual.
    }
  }
}