import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Espacio reservado para publicidad / banners patrocinados.
///
/// No carga ningún SDK de anuncios: solo reserva el layout con las
/// medidas correctas para que, cuando se integre un proveedor (AdMob,
/// un banner propio desde el backend, etc.), baste con reemplazar el
/// contenido de este widget sin tocar las pantallas que lo usan.
///
/// Uso:
/// ```dart
/// const AdSlot(label: 'AD_SLOT_HOME_TOP', height: 90)
/// ```
class AdSlot extends StatelessWidget {
  const AdSlot({
    super.key,
    required this.label,
    this.height = 90,
    this.margin = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
  });

  /// Identificador único del espacio publicitario. Úsalo para saber,
  /// en el backend o en el SDK de anuncios, qué banner corresponde a
  /// cada zona de la app (ej: 'AD_SLOT_HOME_TOP', 'AD_SLOT_LIVE_TV').
  final String label;

  final double height;

  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.textSecondary.withValues(alpha: .25),
          style: BorderStyle.solid,
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.campaign_outlined,
              color: AppColors.textSecondary, size: 20),
          const SizedBox(height: 4),
          Text(
            'Espacio publicitario · $label',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: .3,
            ),
          ),
        ],
      ),
    );
  }
}
