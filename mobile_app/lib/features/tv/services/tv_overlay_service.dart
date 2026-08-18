import 'package:flutter/services.dart';

class TvOverlayService {
  TvOverlayService._();

  static const MethodChannel _channel =
      MethodChannel('tc_play/tv_overlay');

  static Future<void> showPlayer({
    required String url,
    required int x,
    required int y,
    required int width,
    required int height,
  }) async {
    await _channel.invokeMethod(
      'showPlayer',
      {
        'url': url,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      },
    );
  }

  static Future<void> hide() async {
    await _channel.invokeMethod('hide');
  }
}