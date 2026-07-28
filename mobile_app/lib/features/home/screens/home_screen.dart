import 'package:flutter/material.dart';

import '../../live_tv/models/recent_channel.dart';
import '../../live_tv/services/recent_channel_service.dart';
import '../../live_tv/models/favorite_channel.dart';
import '../../live_tv/services/favorite_channel_service.dart';
import '../../live_tv/screens/search_screen.dart';
import '../../live_tv/screens/player_screen.dart';
import '../../../core/constants/app_colors.dart';
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
import 'package:google_fonts/google_fonts.dart';

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
  final RecentChannelService _recentChannelService =
    RecentChannelService();

  final FavoriteChannelService _favoriteService =
    FavoriteChannelService();


  late Future<List<LiveChannel>> _recommendedChannelsFuture;
  late Future<List<RecentChannel>> _recentChannelsFuture;
  late Future<List<FavoriteChannel>> _favoriteChannelsFuture;

  @override
  void initState() {
    super.initState();

    _recommendedChannelsFuture = _loadRecommendedChannels();
    _recentChannelsFuture = _recentChannelService.getRecentChannels();
    _favoriteChannelsFuture = _favoriteService.getFavoriteChannels();

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

Future<void> _reloadRecentChannels() async {
  setState(() {
    _recentChannelsFuture = _recentChannelService.getRecentChannels();
  });
}

void _reloadFavorites() {
  setState(() {
    _favoriteChannelsFuture =
        _favoriteService.getFavoriteChannels();
  });
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

  void _openSearch() {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => SearchScreen(
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
  // Top bar: logo + notificaciones + búsqueda + cuenta
  // ---------------------------------------------------------------------
 Widget _buildTopBar() {
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
    child: Row(
      children: [
        Image.asset(
          'assets/images/tc_play_logo.png',
          height: 34,
          fit: BoxFit.contain,
        ),

        const SizedBox(width: 10),

        Text(
          'TC PLAY',
          style: GoogleFonts.sora(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Spacer(),

        IconButton(
          onPressed: _comingSoon,
          icon: const Icon(
            Icons.notifications_none_rounded,
            color: AppColors.textPrimary,
          ),
        ),

        IconButton(
          onPressed: _openSearch,
          icon: const Icon(
            Icons.search_rounded,
            color: AppColors.textPrimary,
          ),
        ),

        IconButton(
          onPressed: _goToAccount,
          icon: const Icon(
            Icons.person_outline_rounded,
            color: AppColors.textPrimary,
          ),
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
  return FutureBuilder<List<RecentChannel>>(
    future: _recentChannelsFuture,
    builder: (context, snapshot) {
      if (!snapshot.hasData || snapshot.data!.isEmpty) {
        return const SizedBox(
          height: 110,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.live_tv_outlined,
                  size: 34,
                  color: AppColors.textSecondary,
                ),
                SizedBox(height: 10),
                Text(
                  'Aún no has visto ningún canal.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Empieza a ver TV en vivo y aparecerá aquí.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      final items = snapshot.data!
          .map(
            (channel) => MediaCardItem(
              title: channel.name,
              imageUrl: channel.icon,
              showPlayOverlay: true,
              progress: 1,
              onTap: () async {
                await Navigator.push(
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

                _reloadRecentChannels();
              },
            ),
          )
          .toList();

      return MediaCardRow(items: items);
    },
  );
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  color: AppColors.primary,
                ),
                SizedBox(height: 14),
                Text(
                  'Cargando canales...',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
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
        height: 155,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: channels.length,
          separatorBuilder: (context, index) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final channel = channels[index];

            return SizedBox(
              width: 110,
              child: LogoTile(
                title: channel.name,
                subtitle: 'EN VIVO',
                imageUrl: channel.icon,
                color: AppColors.primary,
                onTap: () async {
                  await Navigator.push(
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
                  
                  _reloadRecentChannels();
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
  Widget _buildFavoriteChannels() {
  return FutureBuilder<List<FavoriteChannel>>(
    future: _favoriteChannelsFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const SizedBox(
          height: 120,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  color: AppColors.primary,
                ),
                SizedBox(height: 14),
                Text(
                  'Cargando canales...',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      final favorites = snapshot.data ?? [];

      if (favorites.isEmpty) {
        return const SizedBox(
          height: 120,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.favorite_border_rounded,
                  size: 34,
                  color: AppColors.textSecondary,
                ),
                SizedBox(height: 10),
                Text(
                  'Aún no tienes canales favoritos.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Toca el corazón de un canal para guardarlo aquí.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return SizedBox(
        height: 155,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: favorites.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final channel = favorites[index];

            return SizedBox(
              width: 110,
              child: LogoTile(
                title: channel.name,
                subtitle: 'FAVORITO',
                imageUrl: channel.icon,
                color: AppColors.favoriteGold,
                onTap: () async {
                  await Navigator.push(
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
                  
                  _reloadFavorites();
                },
              ),
            );
          },
        ),
      );
    },
  );
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

              const AppSectionHeader(title: 'Tus Canales Favoritos'),
              _buildFavoriteChannels(),

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