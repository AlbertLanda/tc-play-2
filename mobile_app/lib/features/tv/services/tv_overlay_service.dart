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

  // Banner nativo de zapping (indicador de canal).
  //
  // Se implementa como una vista Android normal, independiente del
  // video, porque el SurfaceView del reproductor usa
  // setZOrderMediaOverlay(true) para poder verse por encima de
  // FlutterView: cualquier widget dibujado por Flutter en esa misma
  // zona quedaría oculto debajo del video.
  static Future<void> showChannelBanner({
    required String title,
    required String subtitle,
    required int x,
    required int y,
    required int width,
    required int height,
    int autoHideMs = 0,
  }) async {
    await _channel.invokeMethod(
      'showChannelBanner',
      {
        'title': title,
        'subtitle': subtitle,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'autoHideMs': autoHideMs,
      },
    );
  }

  static Future<void> hideChannelBanner() async {
    await _channel.invokeMethod('hideChannelBanner');
  }
}