import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// Cabecera con vista previa del canal destacado, igual a la franja
/// superior de la pantalla "TV en Vivo" de referencia: imagen/video de
/// fondo, botón "COMENTAR" y burbuja "Chatea ahora".
///
/// Por ahora solo pinta un fondo degradado con el ícono del canal; en
/// cuanto exista un stream de baja resolución para preview, basta con
/// sustituir el `Container` de fondo por un `VideoPlayer` en loop.
class LivePreviewHeader extends StatelessWidget {
  const LivePreviewHeader({
    super.key,
    required this.channelName,
    this.onComment,
    this.onChat,
    this.height = 210,
  });

  final String channelName;
  final VoidCallback? onComment;
  final VoidCallback? onChat;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF14202E), AppColors.background],
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.live_tv_rounded,
              size: 72,
              color: AppColors.primary.withValues(alpha: .25),
            ),
          ),
          // Degradado inferior para legibilidad de los controles
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 90,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: .75),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onComment,
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: .45),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  icon: const Icon(Icons.mode_comment_outlined, size: 16),
                  label: const Text('COMENTAR',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: onChat,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.liveRed,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Chatea ahora',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                        SizedBox(width: 4),
                        Icon(Icons.circle, color: Colors.white, size: 6),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
