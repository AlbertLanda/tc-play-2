import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// Dark rounded tile with a colored icon/logo — used for category and
/// channel grids. Matches the login card's look: dark fill, thin border
/// in the brand's navy family, soft shadow.
class LogoTile extends StatelessWidget {
  const LogoTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.imageUrl,
    this.color,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? imageUrl;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tileColor = color ?? AppColors.primary;

    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    final logoSize = isLandscape ? 58.0 : 76.0;
    final borderRadius = isLandscape ? 16.0 : 22.0;

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(borderRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(borderRadius),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(22),
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
                child: imageUrl != null && imageUrl!.isNotEmpty
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
                          imageUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) {
                            return Icon(
                              icon ?? Icons.live_tv_rounded,
                              color: AppColors.textSecondary,
                              size: 28,
                            );
                          },
                        ),
                      )
                    : Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          color: tileColor.withValues(alpha: .12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icon ?? Icons.live_tv_rounded,
                          color: tileColor,
                          size: 30,
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
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              ),

              if (subtitle != null) ...[
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
                        subtitle!,
                        style: TextStyle(
                          color: tileColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 9,
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
    );
  }
}


/// Wide horizontal "quick access" row card — Home shortcuts
/// (Categorías / Mi cuenta / Cerrar sesión), same dark-card language.
class HomeMenuCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: iconColor.withValues(alpha: .16),
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: .14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 22,
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),

              if (trailingBadge != null) ...[
                const SizedBox(width: 8),
                trailingBadge!,
              ],

              const SizedBox(width: 4),

              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}