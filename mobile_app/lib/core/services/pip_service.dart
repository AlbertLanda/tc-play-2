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
}