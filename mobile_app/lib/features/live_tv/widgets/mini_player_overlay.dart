// Ruta sugerida en el proyecto: lib/features/live_tv/widgets/mini_player_overlay.dart
//
// Ajustar los imports de abajo (app.dart, LivePlaybackManager, AppColors,
// PlayerScreen) a la ubicación real de esos archivos en tu proyecto.

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../app.dart';
import '../../../core/services/live_playback_manager.dart';
import '../screens/player_screen.dart';

/// Mini-reproductor flotante DENTRO de la app.
///
/// Se muestra por encima de cualquier pantalla mientras haya un canal
/// cargado en [LivePlaybackManager] y PlayerScreen no esté abierta a
/// pantalla completa. Es independiente del Picture-in-Picture nativo de
/// Android: ese sigue activándose solo, aparte, cuando el usuario sale
/// de la app entera (ver LivePlaybackManager._handleAppPaused).
///
/// Montado una sola vez en el `builder` de MaterialApp (ver app.dart),
/// así que sobrevive a cualquier navegación entre pantallas.
class MiniPlayerOverlay extends StatefulWidget {
  const MiniPlayerOverlay({super.key});

  @override
  State<MiniPlayerOverlay> createState() => _MiniPlayerOverlayState();
}

class _MiniPlayerOverlayState extends State<MiniPlayerOverlay> {
  static const Size _boxSize = Size(160, 92);

  Offset? _offset;

  @override
  Widget build(BuildContext context) {
    final manager = LivePlaybackManager.instance;

    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        if (!manager.showMiniPlayer) return const SizedBox.shrink();

        final channel = manager.channel!;
        final screen = MediaQuery.of(context).size;
        final safe = MediaQuery.of(context).padding;

        // Posición inicial (esquina inferior derecha, respetando safe
        // area) la primera vez que aparece; después el usuario la puede
        // arrastrar y se mantiene mientras el overlay siga montado.
        _offset ??= Offset(
          screen.width - _boxSize.width - 16,
          screen.height - _boxSize.height - safe.bottom - 24,
        );

        final clampedLeft =
            _offset!.dx.clamp(0.0, screen.width - _boxSize.width);
        final clampedTop =
            _offset!.dy.clamp(0.0, screen.height - _boxSize.height);

        return Positioned(
          left: clampedLeft,
          top: clampedTop,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() => _offset = _offset! + details.delta);
            },
            onTap: () => _reopenFullScreen(channel),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: _boxSize.width,
                height: _boxSize.height,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Video(
                        controller: manager.videoController,
                        controls: NoVideoControls,
                        fit: BoxFit.cover,
                      ),
                    ),
                    // Degradado inferior para que el nombre del canal se
                    // lea bien encima del video.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(6, 14, 26, 4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.75),
                            ],
                          ),
                        ),
                        child: Text(
                          channel.channelName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Positioned(top: 2, right: 2, child: _closeButton(manager)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _closeButton(LivePlaybackManager manager) {
    return GestureDetector(
      // Cierre explícito: acá sí se detiene la reproducción por
      // completo (a diferencia de tocar el mini-reproductor, que
      // reabre pantalla completa manteniendo el mismo canal sonando).
      onTap: () => manager.closePlayback(),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
      ),
    );
  }

  void _reopenFullScreen(LiveChannelInfo channel) {
    appNavigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          username: channel.username,
          password: channel.password,
          streamId: channel.streamId,
          channelName: channel.channelName,
          channelIcon: channel.channelIcon,
        ),
      ),
    );
  }
}