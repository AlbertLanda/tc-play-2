// Ruta en el proyecto: lib/app.dart

import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'core/widgets/pip_overlay_root.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/live_tv/widgets/mini_player_overlay.dart';

/// Navigator global de la app.
///
/// Se necesita porque MiniPlayerOverlay vive por encima del Navigator
/// principal (se monta en el `builder` de MaterialApp, que envuelve al
/// Navigator, no al revés). Para poder reabrir PlayerScreen a pantalla
/// completa al tocar el mini-reproductor, hace falta esta referencia
/// directa en vez de `Navigator.of(context)`.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class TCPlayApp extends StatelessWidget {
  const TCPlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TC Play 2.0',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      navigatorKey: appNavigatorKey,
      home: const LoginScreen(),
      // El mini-reproductor se monta acá, una sola vez para toda la app,
      // así que sobrevive a cualquier navegación entre pantallas y no
      // depende de que PlayerScreen siga montada.
      builder: (context, child) {
        return PipOverlayRoot(
          child: Stack(
            children: [
              ?child,
              const MiniPlayerOverlay(),
            ],
          ),
        );
      },
    );
  }
}