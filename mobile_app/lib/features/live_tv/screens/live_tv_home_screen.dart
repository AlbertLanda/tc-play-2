import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
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

    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: tabs.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final selected = tab.id == _selectedTabId;
          return GestureDetector(
            onTap: () => setState(() => _selectedTabId = tab.id),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                  fontSize: 13,
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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSectionHeader(
              title: category.name,
              onSeeAll: () => _seeAll(category),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: channels.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 18,
                  crossAxisSpacing: 18,
                  childAspectRatio: .82,
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

                const SizedBox(height:20),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: SizedBox(
                    height: 56,
                    child: TextField(
                      readOnly: true,
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
                      decoration: InputDecoration(
                        hintText: 'Buscar canal...',
                        hintStyle: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 15,
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: AppColors.textSecondary,
                        ),
                        suffixIcon: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 18,
                          color: AppColors.textSecondary,
                          ),
                        filled: true,
                        fillColor: AppColors.card,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: .08),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
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
