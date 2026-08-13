import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/tv_utils.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/section_header.dart';
import '../../home/widgets/home_menu_card.dart';
import '../models/live_category.dart';
import '../models/live_channel.dart';
import '../services/live_tv_service.dart';
import 'channels_screen.dart';
import 'player_screen.dart';
import 'search_screen.dart';

/// Pantalla principal de "TV en Vivo".
///
/// Muestra buscador, categorías y canales disponibles.
/// No reproduce automáticamente ningún canal: el usuario debe tocar
/// una tarjeta para abrir el reproductor.
class LiveTvHomeScreen extends StatefulWidget {
  const LiveTvHomeScreen({
    super.key,
    required this.username,
    required this.password,
  });

  final String username;
  final String password;

  @override
  State<LiveTvHomeScreen> createState() => _LiveTvHomeScreenState();
}

class _LiveTvHomeScreenState extends State<LiveTvHomeScreen> {
  final LiveTvService _service = LiveTvService();

  late Future<List<LiveCategory>> _categoriesFuture;
  final Map<String, Future<List<LiveChannel>>> _channelsByCategory = {};

  String _selectedTabId = 'all';
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _categoriesFuture = _service.getCategories(
      username: widget.username,
      password: widget.password,
    );
  }

  Future<List<LiveChannel>> _channelsFor(String categoryId) {
    return _channelsByCategory.putIfAbsent(
      categoryId,
      () => _service.getChannels(
        username: widget.username,
        password: widget.password,
        categoryId: categoryId,
      ),
    );
  }

  Future<void> _openChannel(LiveChannel channel) async {
    if (_isNavigating) return;

    setState(() {
      _isNavigating = true;
    });

    try {
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
    } finally {
      if (mounted) {
        setState(() {
          _isNavigating = false;
        });
      }
    }
  }

  void _seeAll(LiveCategory category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChannelsScreen(
          username: widget.username,
          password: widget.password,
          categoryId: category.id,
          categoryName: category.name,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Barra de filtros rápidos: "Todas" + categorías reales
  // ---------------------------------------------------------------------
  Widget _buildTabsBar(List<LiveCategory> categories) {
    final tabs = <_TabItem>[
      const _TabItem(id: 'all', label: 'Todas'),
      ...categories.map((c) => _TabItem(id: c.id, label: c.name)),
    ];

    final isLandscape =
    MediaQuery.orientationOf(context) == Orientation.landscape;
    final isTv = TvUtils.isTv(context);

    return SizedBox(
      height: isTv ? 56 : (isLandscape ? 40 : 46),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: tabs.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final selected = tab.id == _selectedTabId;
          // Material + InkWell en vez de GestureDetector: así cada
          // pestaña recibe foco navegable y se activa con Enter/OK del
          // control remoto de forma nativa, además del toque normal.
          return Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              focusColor: AppColors.primary.withValues(alpha: .25),
              onTap: () => setState(() => _selectedTabId = tab.id),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isTv ? 20 : 16,
                  vertical: isTv ? 12 : 8,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary
                      : AppColors.card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : Colors.white.withValues(alpha: .08),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  tab.label,
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: isTv ? 15 : 13,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Grilla de canales de una categoría (sección)
  // ---------------------------------------------------------------------
  Widget _buildChannelSection(LiveCategory category) {
    return FutureBuilder<List<LiveChannel>>(
      future: _channelsFor(category.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: AppColors.primary,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Cargando canales...',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final channels = (snapshot.data ?? []).take(8).toList();

        if (channels.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                'No hay canales disponibles en esta categoría.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          );
        }

        final screenWidth = MediaQuery.sizeOf(context).width;

        final isLandscape =
            MediaQuery.orientationOf(context) == Orientation.landscape;
        final isTv = TvUtils.isTv(context);

        final horizontalPadding = isTv ? 40.0 : (isLandscape ? 32.0 : 20.0);
        final spacing = isTv ? 20.0 : (isLandscape ? 12.0 : 18.0);

        final availableWidth =
            screenWidth - (horizontalPadding * 2);

        final crossAxisCount = isTv
            ? TvUtils.gridCrossAxisCount(
                context: context,
                availableWidth: availableWidth,
                tileWidth: 190,
              )
            : (isLandscape ? (availableWidth / 150).floor().clamp(3, 6) : 3);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSectionHeader(
              title: category.name,
              onSeeAll: () => _seeAll(category),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: channels.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: spacing,
                  crossAxisSpacing: spacing,
                  childAspectRatio: isTv ? 1.0 : (isLandscape ? 1.05 : .82),
                ),
                itemBuilder: (context, index) {
                  final channel = channels[index];
                  return LogoTile(
                    title: channel.name,
                    imageUrl: channel.icon,
                    icon: Icons.live_tv_rounded,
                    color: AppColors.primary,
                    onTap: () => _openChannel(channel),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: AppBottomNav(
        currentIndex: 1,
        username: widget.username,
        password: widget.password,
      ),
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<List<LiveCategory>>(
          future: _categoriesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: AppColors.primary,
                    ),
                    SizedBox(height:20),
                    Text(
                      'Preparando TV en vivo...',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppColors.error, size: 42),
                    const SizedBox(height: 12),
                    const Text('Error al cargar canales',
                        style: TextStyle(color: AppColors.textPrimary)),
                  ],
                ),
              );
            }

            final categories = snapshot.data ?? [];
            // "Los favoritos de muchos" toma la 2ª categoría disponible
            // (o la primera si solo hay una) como segunda sección.
            final sectionCategories = categories;

            return ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [

                const SizedBox(height:8),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  // Antes era un TextField de solo lectura: funcionaba
                  // al tacto pero un campo de texto no se "activa" con
                  // Enter/OK de un control remoto (el sistema espera
                  // que ahí se escriba, no que dispare una acción). Un
                  // botón real (Material + InkWell) se ve idéntico y
                  // sigue abriendo Buscar al tocar, pero además queda
                  // navegable y activable por teclado/control en TV.
                  child: SizedBox(
                    height: 56,
                    child: Material(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(30),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(30),
                        focusColor: AppColors.primary.withValues(alpha: .25),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SearchScreen(
                                username: widget.username,
                                password: widget.password,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .08),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.search_rounded,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Buscar canal...',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _buildTabsBar(categories),
                const SizedBox(height: 4),

                // ----------------------------------------------------
                // AD_SLOT_LIVE_TV — banner debajo de los filtros
                // ----------------------------------------------------
                //const AdSlot(label: 'AD_SLOT_LIVE_TV', height: 80),

                if (_selectedTabId == 'all')
                  ...sectionCategories.map(_buildChannelSection)
                else
                  _buildChannelSection(
                    categories.firstWhere((c) => c.id == _selectedTabId),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TabItem {
  const _TabItem({required this.id, required this.label});
  final String id;
  final String label;
}
