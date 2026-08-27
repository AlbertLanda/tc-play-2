// Ruta en el proyecto: lib/core/widgets/pip_overlay_root.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/live_playback_manager.dart';
import '../services/pip_service.dart';

/// Envuelve TODA la app (se monta una sola vez en `app.dart`).
///
/// El PiP nativo de Android no sabe recortar "solo el video": toma lo
/// que sea que Flutter esté renderizando en ese instante y lo achica
/// entero dentro de la ventanita. Si en ese momento había, por ejemplo,
/// la pantalla de inicio con el mini-reproductor propio flotando en una
/// esquina, el PiP terminaba mostrando esa pantalla completa encogida
/// (el bug reportado: "afecta a todo el aplicativo").
///
/// Este widget soluciona eso del lado de Flutter: mientras Android
/// reporta que el PiP está activo, se cubre TODA la pantalla con
/// únicamente el video, sin importar qué pantalla de la app estuviera
/// abierta debajo. El resto de la app queda oculto (con `Offstage`, no
/// destruido) para no perder la navegación ni el estado al volver.
class PipOverlayRoot extends StatefulWidget {
  final Widget child;
  const PipOverlayRoot({super.key, required this.child});

  @override
  State<PipOverlayRoot> createState() => _PipOverlayRootState();
}

class _PipOverlayRootState extends State<PipOverlayRoot> {
  StreamSubscription<bool>? _sub;
  bool _isInPip = PipService.isInPipMode;

  @override
  void initState() {
    super.initState();
    _sub = PipService.pipModeStream.listen((value) {
      if (mounted) setState(() => _isInPip = value);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // `Offstage` (no `if`): mantiene vivo el árbol de la app —
        // Navigator, pantallas, estado— aunque no se dibuje ni reciba
        // toques mientras dura el PiP. Si en cambio se reemplazara el
        // widget entero, al salir del PiP la navegación se perdería.
        Offstage(offstage: _isInPip, child: widget.child),
        if (_isInPip)
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: Video(
                controller: LivePlaybackManager.instance.videoController,
                controls: NoVideoControls,
                fit: BoxFit.cover,
              ),
            ),
          ),
      ],
    );
  }
}