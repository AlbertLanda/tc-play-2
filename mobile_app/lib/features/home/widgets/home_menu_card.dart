import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/tv_utils.dart';

/// Dark rounded tile with a colored icon/logo — used for category and
/// channel grids. Matches the login card's look: dark fill, thin border
/// in the brand's navy family, soft shadow.
///
/// En modo TV agrega un anillo de foco claro (borde + leve escalado)
/// que aparece al navegar con control remoto/teclado, usando el propio
/// foco de [InkWell] (ya soporta Enter/Select como activación, así que
/// no hace falta un manejo de teclado aparte). En celular el
/// comportamiento táctil queda exactamente igual que antes.
class LogoTile extends StatefulWidget {
  const LogoTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.imageUrl,
    this.color,
    this.onTap,
    this.autofocus = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? imageUrl;
  final Color? color;
  final VoidCallback? onTap;

  /// Marca esta tarjeta para recibir el foco inicial al entrar a la
  /// pantalla en modo TV (por ejemplo, la primera de una grilla).
  final bool autofocus;

  @override
  State<LogoTile> createState() => _LogoTileState();
}

class _LogoTileState extends State<LogoTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tileColor = widget.color ?? AppColors.primary;

    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final isTv = TvUtils.isTv(context);

    final logoSize = isTv ? 92.0 : (isLandscape ? 58.0 : 76.0);
    final borderRadius = isTv ? 20.0 : (isLandscape ? 16.0 : 22.0);
    final titleSize = isTv ? 16.0 : 13.0;
    final iconGlyphSize = isTv ? 36.0 : 30.0;

    return AnimatedScale(
      scale: _focused ? 1.06 : 1.0,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: isTv
            ? TvUtils.focusDecoration(focused: _focused, radius: borderRadius)
            : const BoxDecoration(),
        child: Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(borderRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(borderRadius),
            onTap: widget.onTap,
            autofocus: widget.autofocus,
            focusColor: tileColor.withValues(alpha: .18),
            onFocusChange: isTv
                ? (focused) => setState(() => _focused = focused)
                : null,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(
                  color: tileColor.withValues(alpha: .12),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .18),
                    blurRadius: 12,
                    spreadRadius: 0,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),

              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: logoSize,
                    child: widget.imageUrl != null && widget.imageUrl!.isNotEmpty
                        ? Container(
                            height: logoSize,
                            width: logoSize,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: .10),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Image.network(
                              widget.imageUrl!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) {
                                return Icon(
                                  widget.icon ?? Icons.live_tv_rounded,
                                  color: AppColors.textSecondary,
                                  size: iconGlyphSize,
                                );
                              },
                            ),
                          )
                        : Container(
                            width: isTv ? 76 : 62,
                            height: isTv ? 76 : 62,
                            decoration: BoxDecoration(
                              color: tileColor.withValues(alpha: .12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              widget.icon ?? Icons.live_tv_rounded,
                              color: tileColor,
                              size: iconGlyphSize,
                            ),
                          ),
                  ),

                  const SizedBox(height: 8),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFF22C55E), // Verde
                          shape: BoxShape.circle,
                        ),
                      ),

                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: titleSize,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 6),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: tileColor.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: tileColor,
                              shape: BoxShape.circle,
                            ),
                          ),

                          const SizedBox(width: 4),

                          Text(
                            widget.subtitle!,
                            style: TextStyle(
                              color: tileColor,
                              fontWeight: FontWeight.bold,
                              fontSize: isTv ? 11 : 9,
                              letterSpacing: .4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/// Wide horizontal "quick access" row card — Home shortcuts
/// (Categorías / Mi cuenta / Cerrar sesión), same dark-card language.
///
/// También agrega anillo de foco en TV, igual que [LogoTile].
class HomeMenuCard extends StatefulWidget {
  const HomeMenuCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.onTap,
    this.trailingBadge,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  final Widget? trailingBadge;

  @override
  State<HomeMenuCard> createState() => _HomeMenuCardState();
}

class _HomeMenuCardState extends State<HomeMenuCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final isTv = TvUtils.isTv(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: isTv
          ? TvUtils.focusDecoration(focused: _focused, radius: 14)
          : const BoxDecoration(),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: widget.onTap,
          focusColor: widget.iconColor.withValues(alpha: .18),
          onFocusChange: isTv
              ? (focused) => setState(() => _focused = focused)
              : null,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: widget.iconColor.withValues(alpha: .16),
              ),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: isTv ? 18 : 14,
            ),
            child: Row(
              children: [
                Container(
                  width: isTv ? 54 : 46,
                  height: isTv ? 54 : 46,
                  decoration: BoxDecoration(
                    color: widget.iconColor.withValues(alpha: .14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.icon,
                    color: widget.iconColor,
                    size: isTv ? 26 : 22,
                  ),
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: isTv ? 17 : 15,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: isTv ? 13 : 11.5,
                        ),
                      ),
                    ],
                  ),
                ),

                if (widget.trailingBadge != null) ...[
                  const SizedBox(width: 8),
                  widget.trailingBadge!,
                ],

                const SizedBox(width: 4),

                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                  size: isTv ? 26 : 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
