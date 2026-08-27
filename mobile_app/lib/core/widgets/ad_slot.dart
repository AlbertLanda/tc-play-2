import 'package:flutter/material.dart';

/// Espacio reservado para publicidad / banners patrocinados.
class AdSlot extends StatelessWidget {
  const AdSlot({
    super.key,
    required this.label,
    this.height = 90,
    this.margin = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
  });

  final String label;

  final double height;

  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
