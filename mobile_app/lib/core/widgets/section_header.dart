import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    this.onSeeAll,
    this.trailingIcon,
  });

  final String title;
  final VoidCallback? onSeeAll;

  /// Ícono opcional a la derecha del título (ej: ⚽ para "Fútbol").
  final Widget? trailingIcon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: 6),
            trailingIcon!,
          ],
          const Spacer(),
          if (onSeeAll != null)
            // InkWell en vez de GestureDetector: mismo aspecto, pero
            // navegable y activable con Enter/OK del control remoto.
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: onSeeAll,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                  child: Row(
                    children: [
                      Text('Ver todas',
                          style:
                              TextStyle(color: AppColors.accent, fontSize: 13)),
                      Icon(Icons.chevron_right_rounded,
                          color: AppColors.accent, size: 18),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
