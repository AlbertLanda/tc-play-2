import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/tv_utils.dart';

class MediaCardItem {
  const MediaCardItem({
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.icon = Icons.movie_creation_rounded,
    this.showPlayOverlay = false,
    this.progress,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final String? imageUrl;
  final IconData icon;

  /// Muestra un ícono de play centrado (usado en "Continuar viendo").
  final bool showPlayOverlay;

  /// Progreso 0.0 - 1.0 para la barra inferior tipo "seguir viendo".
  final double? progress;

  final VoidCallback? onTap;
}

/// Fila horizontal de tarjetas tipo póster — usada tanto para
/// "Continuar viendo" como para "¡Cortesía de la casa!".
class MediaCardRow extends StatelessWidget {
  const MediaCardRow({
    super.key,
    required this.items,
    this.cardWidth = 132,
    this.cardHeight = 84,
  });

  final List<MediaCardItem> items;
  final double cardWidth;
  final double cardHeight;

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final isTv = TvUtils.isTv(context);

    // En TV las tarjetas crecen un poco más que en celular apaisado,
    // para que se lean cómodas a distancia de sofá.
    final effectiveWidth =
        isTv ? cardWidth * 1.45 : (isLandscape ? 110.0 : cardWidth);

    final effectiveHeight =
        isTv ? cardHeight * 1.45 : (isLandscape ? 70.0 : cardHeight);
        if (items.isEmpty) {
          return const SizedBox(
            height: 60,
            child: Center(
              child: Text(
                'Nada por aquí todavía.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          );
        }

    return SizedBox(
      height: effectiveHeight + (isTv ? 46 : (isLandscape ? 34 : 42)),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: items.length,
        separatorBuilder: (context, index) =>
            SizedBox(width: isTv ? 18 : 12),
        itemBuilder: (context, index) => _MediaCard(
          item: items[index],
          width: effectiveWidth,
          height: effectiveHeight,
          autofocus: isTv && index == 0,
        ),
      ),
    );
  }
}

class _MediaCard extends StatefulWidget {
  const _MediaCard({
    required this.item,
    required this.width,
    required this.height,
    this.autofocus = false,
  });

  final MediaCardItem item;
  final double width;
  final double height;
  final bool autofocus;

  @override
  State<_MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<_MediaCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final width = widget.width;
    final height = widget.height;
    final isTv = TvUtils.isTv(context);

    // Material + InkWell en vez de GestureDetector: mismo look, pero
    // navegable y activable con Enter/OK en TV, con anillo de foco
    // visible (igual criterio que LogoTile).
    return AnimatedScale(
      scale: _focused ? 1.05 : 1.0,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: isTv
            ? TvUtils.focusDecoration(focused: _focused, radius: 12)
            : const BoxDecoration(),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: item.onTap,
            autofocus: widget.autofocus,
            focusColor: AppColors.primary.withValues(alpha: .2),
            onFocusChange: isTv
                ? (focused) => setState(() => _focused = focused)
                : null,
            child: SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                            Image.network(
                              item.imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: AppColors.card,
                                child: Icon(item.icon,
                                    color: AppColors.textSecondary, size: 28),
                              ),
                            )
                          else
                            Container(
                              color: AppColors.card,
                              child: Icon(item.icon,
                                  color: AppColors.textSecondary, size: 28),
                            ),
                          if (item.showPlayOverlay)
                            Container(
                              color: Colors.black.withValues(alpha: .18),
                              alignment: Alignment.center,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: .5),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.play_arrow_rounded,
                                    color: Colors.white, size: 20),
                              ),
                            ),
                          if (item.progress != null)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: LinearProgressIndicator(
                                value: item.progress!.clamp(0, 1),
                                minHeight: 3,
                                backgroundColor: Colors.white.withValues(alpha: .25),
                                valueColor: const AlwaysStoppedAnimation(
                                    AppColors.liveRed),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: isTv ? 14 : 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.subtitle != null)
                    Text(
                      item.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: isTv ? 12 : 10.5,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
