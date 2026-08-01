import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class LiveTvPlayerController {
  // 1. INSTANCIA GLOBAL (Singleton): Garantiza que solo exista UN reproductor en toda la app.
  static Player? _globalPlayer;
  
  late final Player player;
  late final VideoController videoController;

  bool hasError = false;

  LiveTvPlayerController() {
    // Si el motor global no existe, lo creamos. Si ya existe, lo reutilizamos.
    _globalPlayer ??= Player(
      configuration: const PlayerConfiguration(
        bufferSize: 1024 * 1024 * 32, // 32MB de buffer
      ),
    );
    
    player = _globalPlayer!;
    videoController = VideoController(player);
  }

  Future<void> initializePlayer(String url) async {
    try {
      hasError = false;
      
      // 2. DETENCIÓN FORZADA: Cortamos de raíz cualquier canal que estuviera sonando
      await player.stop();

      final media = Media(
        url,
        httpHeaders: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36',
          'Accept': '*/*',
          'Connection': 'keep-alive',
        },
      );

      await player.open(media);
      await player.play();
      
    } catch (e) {
      debugPrint("MEDIA KIT ERROR: $e");
      hasError = true;
    }
  }

  Future<void> dispose() async {
    // 3. EN LUGAR DE DESTRUIR EL MOTOR, SOLO LO DETENEMOS
    // Así mantenemos la instancia global lista para el siguiente canal y matamos el audio.
    //await player.stop(); 
  }
  Future<void> disposePlayer() async {
    await player.dispose();
    _globalPlayer = null;
  }
}
