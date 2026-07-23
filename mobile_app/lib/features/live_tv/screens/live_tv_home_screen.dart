import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/ad_slot.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/section_header.dart';
import '../../home/widgets/home_menu_card.dart';
import '../models/live_category.dart';
import '../models/live_channel.dart';
import '../services/live_tv_service.dart';
import '../widgets/live_player.dart';
import 'channels_screen.dart';
import 'player_screen.dart';

/// Pantalla principal de "TV en Vivo" (pestaña 2 de la barra inferior).
///
/// Reemplaza el flujo anterior Categorías -> Canales como punto de
/// entrada: aquí mismo se ve una vista previa del canal destacado, los
/// filtros rápidos (Todas / categorías) y, debajo, los canales
/// agrupados por sección — igual que en la captura de referencia.
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

  LiveChannel? _selectedChannel;

  late Future<List<LiveCategory>> _categoriesFuture;
  final Map<String, Future<List<LiveChannel>>> _channelsByCategory = {};

  String _selectedTabId = 'all';

  @override
  void initState() {
    super.initState();
    _categoriesFuture = _service.getCategories(
      username: widget.username,
      password: widget.password,
    );
    _loadDefaultChannel();
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
  Future<void> _loadDefaultChannel() async {

  final categories = await _categoriesFuture;

  if (categories.isEmpty) return;

  final channels = await _channelsFor(
    categories.first.id,
  );

  if (channels.isEmpty) return;


  final america = channels.firstWhere(
    (c) => c.name.toLowerCase().contains('america'),
    orElse: () => channels.first,
  );


  if (!mounted) return;

  setState(() {
    _selectedChannel = america;
  });

}

  void _openChannel(LiveChannel channel) {

  setState(() {
    _selectedChannel = channel;
  });

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
      height: 42,
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
                color: selected ? AppColors.liveRed : AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected
                      ? AppColors.liveRed
                      : AppColors.textSecondary.withValues(alpha: .25),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                tab.label,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
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
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }

        final channels = (snapshot.data ?? []).take(8).toList();

        if (channels.isEmpty) return const SizedBox.shrink();

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
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.95,
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
                child: CircularProgressIndicator(color: AppColors.primary),
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
            final sectionCategories = categories.length > 1
                ? [categories.first, categories[1]]
                : categories;

            return ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (_selectedChannel != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal:20),
                  child: LivePlayer(
                    streamId: _selectedChannel!.id,
                    username: widget.username,
                    password: widget.password,
                    channelName: _selectedChannel!.name,
                    channelIcon: _selectedChannel!.icon,
                    onFullscreen: (){
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PlayerScreen(
                            username: widget.username,
                            password: widget.password,
                            streamId: _selectedChannel!.id,
                            channelName: _selectedChannel!.name,
                            channelIcon: _selectedChannel!.icon,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height:16),
                const SizedBox(height: 14),
                _buildTabsBar(categories),
                const SizedBox(height: 6),

                // ----------------------------------------------------
                // AD_SLOT_LIVE_TV — banner debajo de los filtros
                // ----------------------------------------------------
                const AdSlot(label: 'AD_SLOT_LIVE_TV', height: 80),

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
