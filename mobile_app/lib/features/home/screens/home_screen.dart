import 'package:flutter/material.dart';

import '../../live_tv/screens/player_screen.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ad_slot.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/section_header.dart';
import '../../account/screens/account_screen.dart';
import '../../live_tv/screens/live_tv_home_screen.dart';
import '../../live_tv/services/live_tv_service.dart';
import '../widgets/home_menu_card.dart';
import '../widgets/media_card_row.dart';
import '../widgets/promo_carousel.dart';
import '../../live_tv/models/live_channel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.username,
    required this.password,
  });

  final String username;
  final String password;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final LiveTvService _liveTvService = LiveTvService();


  late Future<List<LiveChannel>> _recommendedChannelsFuture;

  @override
  void initState() {
    super.initState();

    _recommendedChannelsFuture = _loadRecommendedChannels();
  }

  Future<List<LiveChannel>> _loadRecommendedChannels() async {
  final categories = await _liveTvService.getCategories(
    username: widget.username,
    password: widget.password,
  );

  if (categories.isEmpty) {
    return [];
  }

  final firstCategory = categories.first;

  final channels = await _liveTvService.getChannels(
    username: widget.username,
    password: widget.password,
    categoryId: firstCategory.id,
  );

  return channels.take(10).toList();
}

  void _goToLiveTv() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveTvHomeScreen(
          username: widget.username,
          password: widget.password,
        ),
      ),
    );
  }


  void _goToAccount() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AccountScreen(
          username: widget.username,
          password: widget.password,
        ),
      ),
    );
  }

  void _comingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        content: const Text('Función disponible próximamente'),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Top bar: logo + "Suscríbete" + notificaciones + búsqueda + cuenta
  // ---------------------------------------------------------------------
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
      child: Row(
        children: [
          AppTheme.brandmark(fontSize: 15, letterSpacing: 3),
          const Spacer(),
          GestureDetector(
            onTap: _comingSoon,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.liveRed,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Suscríbete',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: _comingSoon,
            icon: const Icon(Icons.notifications_none_rounded,
                color: AppColors.textPrimary),
          ),
          IconButton(
            onPressed: _comingSoon,
            icon:
                const Icon(Icons.search_rounded, color: AppColors.textPrimary),
          ),
          IconButton(
            onPressed: _goToAccount,
            icon: const Icon(Icons.person_outline_rounded,
                color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Continuar viendo (placeholder — conectar a "historial" cuando el
  // backend lo exponga)
  // ---------------------------------------------------------------------
  Widget _buildContinueWatching() {
    final items = [
      MediaCardItem(
        title: 'Más Rápido, Más Furioso',
        subtitle: '1:04:15',
        icon: Icons.local_movies_rounded,
        showPlayOverlay: true,
        progress: 0.35,
        onTap: _comingSoon,
      ),
      MediaCardItem(
        title: 'Los Juegos del Hambre: Balada...',
        subtitle: '2:30:44',
        icon: Icons.local_movies_rounded,
        showPlayOverlay: true,
        progress: 0.6,
        onTap: _comingSoon,
      ),
      MediaCardItem(
        title: 'Constantine',
        subtitle: '1:58:02',
        icon: Icons.local_movies_rounded,
        showPlayOverlay: true,
        progress: 0.15,
        onTap: _comingSoon,
      ),
    ];

    return MediaCardRow(items: items);
  }

  // ---------------------------------------------------------------------
  // Canales recomendados (reales, desde LiveTvService)
  // ---------------------------------------------------------------------
  Widget _buildRecommendedChannels() {
  return FutureBuilder<List<LiveChannel>>(
    future: _recommendedChannelsFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const SizedBox(
          height: 120,
          child: Center(
            child: CircularProgressIndicator(
              color: AppColors.primary,
            ),
          ),
        );
      }

      if (snapshot.hasError ||
          !snapshot.hasData ||
          snapshot.data!.isEmpty) {
        return const SizedBox(
          height: 80,
          child: Center(
            child: Text(
              'No hay canales disponibles.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        );
      }

      final channels = snapshot.data!;

      return SizedBox(
        height: 120,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: channels.length,
          separatorBuilder: (context, index) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final channel = channels[index];

            return SizedBox(
              width: 95,
              child: LogoTile(
                title: channel.name,
                subtitle: 'EN VIVO',
                imageUrl: channel.icon,
                color: AppColors.primary,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlayerScreen(
                        username: widget.username,
                        password: widget.password,
                        streamId: channel.id,
                        channelName: channel.name,
                        channelIcon: channel.icon,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      );
    },
  );
}

  // ---------------------------------------------------------------------
  // Cortesía de la casa (placeholder — reemplazar con el catálogo de
  // películas/series gratuitas cuando exista el endpoint)
  // ---------------------------------------------------------------------
  Widget _buildFreeCourtesy() {
    final items = [
      MediaCardItem(
        title: 'Estreno 1',
        icon: Icons.movie_rounded,
        onTap: _comingSoon,
      ),
      MediaCardItem(
        title: 'Power Rangers',
        icon: Icons.movie_rounded,
        onTap: _comingSoon,
      ),
      MediaCardItem(
        title: 'Polla Millonaria',
        icon: Icons.emoji_events_rounded,
        onTap: _comingSoon,
      ),
    ];

    return MediaCardRow(items: items, cardHeight: 92);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: AppBottomNav(
        currentIndex: 0,
        username: widget.username,
        password: widget.password,
      ),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopBar(),
              const SizedBox(height: 6),
              PromoCarousel(
                banners: [
                  PromoBanner(
                    title: 'DOMINGO 19 · 02:00 PM\nMíralo gratis con datos 5G ilimitados',
                    footerLeft: 'POR: América TV',
                    footerRight: 'EN: TC Play',
                    onTap: _goToLiveTv,
                  ),
                  PromoBanner(
                    title: 'Descubre todos nuestros\ncanales en vivo',
                    tag: 'NUEVO',
                    onTap: _goToLiveTv,
                  ),
                ],
              ),

              // ------------------------------------------------------
              // AD_SLOT_HOME_TOP — banner publicitario debajo del hero
              // ------------------------------------------------------
              const AdSlot(label: 'AD_SLOT_HOME_TOP', height: 80),

              const AppSectionHeader(title: 'Continuar viendo'),
              _buildContinueWatching(),

              AppSectionHeader(
                  title: 'Canales recomendados', onSeeAll: _goToLiveTv),
              _buildRecommendedChannels(),

              const AppSectionHeader(title: '¡Cortesía de la casa!'),
              _buildFreeCourtesy(),

              // ------------------------------------------------------
              // AD_SLOT_HOME_BOTTOM — segundo espacio publicitario,
              // antes del cierre del scroll
              // ------------------------------------------------------
              const AdSlot(label: 'AD_SLOT_HOME_BOTTOM', height: 80),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
