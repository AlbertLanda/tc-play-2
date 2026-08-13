import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/tv_utils.dart';

class PromoBanner {
  const PromoBanner({
    required this.title,
    this.tag = 'EN VIVO',
    this.subtitle,
    this.footerLeft,
    this.footerRight,
    this.gradient = AppColors.heroGradient,
    this.onTap,
  });

  final String title;
  final String tag;
  final String? subtitle;
  final String? footerLeft;
  final String? footerRight;
  final Gradient gradient;
  final VoidCallback? onTap;
}

/// Carrusel principal de promociones (equivalente al banner
/// "ESPAÑA VS ARGENTINA · MÍRALO GRATIS" de la pantalla de inicio).
///
/// Recibe una lista de [PromoBanner]; cuando el backend exponga un
/// endpoint de banners/promos, basta con mapear su respuesta a esta
/// lista — el widget ya soporta auto-rotación e indicadores.
class PromoCarousel extends StatefulWidget {
  const PromoCarousel({super.key, required this.banners, this.height = 190});

  final List<PromoBanner> banners;
  final double height;

  @override
  State<PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<PromoCarousel> {
  final PageController _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    if (widget.banners.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!mounted) return;
        _page = (_page + 1) % widget.banners.length;
        _controller.animateToPage(
          _page,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.banners.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: widget.height,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.banners.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, index) => _BannerCard(
              banner: widget.banners[index],
            ),
          ),
        ),
        if (widget.banners.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.banners.length, (i) {
              final active = i == _page;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.primary
                      : AppColors.textSecondary.withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

class _BannerCard extends StatefulWidget {
  const _BannerCard({required this.banner});

  final PromoBanner banner;

  @override
  State<_BannerCard> createState() => _BannerCardState();
}

class _BannerCardState extends State<_BannerCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final banner = widget.banner;
    final isTv = TvUtils.isTv(context);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: banner.onTap,
        focusColor: Colors.white.withValues(alpha: .1),
        onFocusChange:
            isTv ? (focused) => setState(() => _focused = focused) : null,
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: banner.gradient,
          borderRadius: BorderRadius.circular(16),
          border: isTv
              ? Border.all(
                  color: _focused ? AppColors.accent : Colors.transparent,
                  width: 3,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .35),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -14,
              bottom: -24,
              child: Icon(
                Icons.sports_soccer_rounded,
                size: 130,
                color: Colors.black.withValues(alpha: .12),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.liveRed,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    banner.tag,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Text(
                  banner.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                ),
                if (banner.subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      banner.subtitle!,
                      style: TextStyle(
                        color: AppColors.textPrimary.withValues(alpha: .8),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (banner.footerLeft != null || banner.footerRight != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (banner.footerLeft != null)
                        Text(
                          banner.footerLeft!,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (banner.footerRight != null)
                          Text(
                            banner.footerRight!,
                            style: TextStyle(
                            color: AppColors.textPrimary.withValues(alpha: .8),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}
