import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/tv_utils.dart';
import '../../home/widgets/home_menu_card.dart';
import '../models/live_channel.dart';
import '../services/live_tv_service.dart';
import 'player_screen.dart';

class ChannelsScreen extends StatefulWidget {
  final String username;
  final String password;
  final String categoryId;
  final String categoryName;

  const ChannelsScreen({
    super.key,
    required this.username,
    required this.password,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  final LiveTvService _service = LiveTvService();
  final TextEditingController _searchController = TextEditingController();

  late Future<List<LiveChannel>> _channels;
  String _search = '';
  
  // Candado para evitar el múltiple tap y el audio fantasma
  bool _isNavigating = false; 

  @override
  void initState() {
    super.initState();
    _channels = _service.getChannels(
      username: widget.username,
      password: widget.password,
      categoryId: widget.categoryId,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _channels = _service.getChannels(
        username: widget.username,
        password: widget.password,
        categoryId: widget.categoryId,
      );
    });
    await _channels;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  InputDecoration _searchDecoration() {
    return InputDecoration(
      hintText: 'Buscar canal...',
      hintStyle: TextStyle(
        color: AppColors.textSecondary.withValues(alpha: .6),
        fontSize: 15,
      ),
      prefixIcon: const Icon(Icons.search_rounded,
          color: AppColors.textSecondary, size: 20),
      filled: true,
      fillColor: Colors.white.withValues(alpha: .05),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: .12)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: .12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(widget.categoryName),
        centerTitle: true,
      ),
      body: FutureBuilder<List<LiveChannel>>(
        future: _channels,
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
                  const Icon(Icons.error_outline,
                      color: AppColors.error, size: 48),
                  const SizedBox(height: 16),
                  const Text('Error al cargar canales',
                      style: TextStyle(color: AppColors.textPrimary)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            );
          }

          final channels = snapshot.data ?? [];
          final filteredChannels = channels
              .where(
                  (c) => c.name.toLowerCase().contains(_search.toLowerCase()))
              .toList();

          final screenWidth = MediaQuery.sizeOf(context).width;

          final isLandscape =
              MediaQuery.orientationOf(context) == Orientation.landscape;
          final isTv = TvUtils.isTv(context);

          final horizontalPadding = isTv ? 40.0 : (isLandscape ? 32.0 : 20.0);
          final spacing = isTv ? 18.0 : (isLandscape ? 12.0 : 14.0);

          final availableWidth =
              screenWidth - (horizontalPadding * 2);

          final crossAxisCount = TvUtils.gridCrossAxisCount(
            context: context,
            availableWidth: availableWidth,
            tileWidth: isLandscape || isTv ? 150 : 105,
            mobileMax: isLandscape ? 6 : 4,
          );

          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.primary,
            child: ListView(
              padding: EdgeInsets.all(horizontalPadding),
              children: [
                TextField(
                  controller: _searchController,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 15),
                  onChanged: (value) => setState(() => _search = value),
                  decoration: _searchDecoration(),
                ),
                const SizedBox(height: 16),
                Text(
                  '${filteredChannels.length} de ${channels.length} canales',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 16),
                if (filteredChannels.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(
                      child: Text(
                        'No se encontraron canales.',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 16),
                      ),
                    ),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredChannels.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                    childAspectRatio:
                        isTv ? 1.0 : (isLandscape ? 1.05 : 0.85),
                  ),
                    itemBuilder: (context, index) {
                      final channel = filteredChannels[index];
                      return LogoTile(
                        title: channel.name,
                        subtitle: channel.streamType,
                        imageUrl: channel.icon,
                        icon: Icons.live_tv_rounded,
                        color: AppColors.primary,
                        // Foco inicial en TV: sin esto el control
                        // remoto no tiene desde dónde empezar a
                        // moverse al entrar a esta pantalla.
                        autofocus: isTv && index == 0,
                        onTap: () async {
                          // Si ya estamos navegando, ignoramos clics adicionales
                          if (_isNavigating) return;
                          
                          setState(() => _isNavigating = true);

                          // Ocultar teclado si buscaron un canal
                          FocusManager.instance.primaryFocus?.unfocus();

                          // Hacemos un await del push. 
                          // La ejecución se pausará aquí hasta que el usuario cierre el PlayerScreen.
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

                          // Cuando el usuario regresa, liberamos el candado
                          if (mounted) {
                            setState(() {
                              _isNavigating = false;
                            });
                          }
                        },
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}