import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../live_tv/models/live_category.dart';
import '../../live_tv/models/live_channel.dart';
import '../../live_tv/services/live_tv_service.dart';
import '../services/tv_overlay_service.dart';

class TvHomeScreen extends StatefulWidget {
  const TvHomeScreen({
    super.key,
    required this.username,
    required this.password,
  });

  final String username;
  final String password;

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen> {
  final LiveTvService _service = LiveTvService();

  // Evita abrir varios streams seguidos cuando el usuario
  // navega rápidamente por la lista de canales.
  Timer? _channelDebounce;

  List<LiveCategory> _categories = [];
  List<LiveChannel> _channels = [];

  LiveCategory? _selectedCategory;
  LiveChannel? _selectedChannel;

  bool _loadingCategories = true;
  bool _loadingChannels = false;

  String? _error;

  @override
  void initState() {
    super.initState();

    _loadCategories();
  }

  // ============================================================
  // CARGA DE CATEGORÍAS
  // ============================================================

  Future<void> _loadCategories() async {
    try {
      final categories = await _service.getCategories(
        username: widget.username,
        password: widget.password,
      );

      if (!mounted) return;

      setState(() {
        _categories = categories;
        _loadingCategories = false;
        _error = null;
      });

      if (categories.isNotEmpty) {
        await _selectCategory(categories.first);
      } else {
        await TvOverlayService.hide();
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingCategories = false;
        _error = e.toString().replaceFirst(
          'Exception: ',
          '',
        );
      });

      await TvOverlayService.hide();
    }
  }

  // ============================================================
  // SELECCIÓN DE CATEGORÍA
  // ============================================================

  Future<void> _selectCategory(
    LiveCategory category,
  ) async {
    // Si había un cambio de canal pendiente, lo cancelamos.
    _channelDebounce?.cancel();
    _channelDebounce = null;

    // Ocultamos temporalmente el video mientras se carga
    // la nueva categoría.
    await TvOverlayService.hide();

    if (!mounted) return;

    setState(() {
      _selectedCategory = category;
      _selectedChannel = null;
      _channels = [];
      _loadingChannels = true;
      _error = null;
    });

    try {
      final channels = await _service.getChannels(
        username: widget.username,
        password: widget.password,
        categoryId: category.id,
      );

      if (!mounted) return;

      // Protección contra respuestas atrasadas.
      //
      // Si mientras esperábamos al backend el usuario cambió
      // nuevamente de categoría, descartamos esta respuesta.
      if (_selectedCategory?.id != category.id) {
        return;
      }

      LiveChannel? firstChannel;

      setState(() {
        _channels = channels;
        _loadingChannels = false;

        if (channels.isNotEmpty) {
          firstChannel = channels.first;
          _selectedChannel = firstChannel;
        }
      });

      // El primer canal de una categoría sí se reproduce
      // inmediatamente. Aquí no necesitamos debounce.
      if (firstChannel != null) {
        await _showNativeOverlay(
          firstChannel!,
        );
      } else {
        await TvOverlayService.hide();
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingChannels = false;
        _channels = [];
        _selectedChannel = null;
      });

      await TvOverlayService.hide();
    }
  }

  // ============================================================
  // SELECCIÓN MANUAL DE CANAL
  // ============================================================

  void _selectChannel(
    LiveChannel channel,
  ) {
    if (_selectedChannel?.id == channel.id) {
      return;
    }

    setState(() {
      _selectedChannel = channel;
    });

    // Si todavía estaba esperando otro canal, lo cancelamos.
    _channelDebounce?.cancel();

    // Esperamos 500 ms.
    //
    // Si el usuario sigue navegando por la lista, este Timer
    // será reemplazado y solamente se reproducirá finalmente
    // el último canal seleccionado.
    _channelDebounce = Timer(
      const Duration(milliseconds: 500),
      () {
        if (!mounted) return;

        // Segunda protección:
        // verificamos que el canal siga siendo el seleccionado.
        if (_selectedChannel?.id != channel.id) {
          return;
        }

        _showNativeOverlay(channel);
      },
    );
  }

  // ============================================================
  // OVERLAY NATIVO ANDROID
  // ============================================================

  Future<void> _showNativeOverlay(
    LiveChannel channel,
  ) async {
    try {
      debugPrint(
        'TV OVERLAY: solicitando URL '
        'canal=${channel.name} id=${channel.id}',
      );

      final url = await _service.getStreamUrl(
        username: widget.username,
        password: widget.password,
        streamId: channel.id,
        output: 'm3u8',
      );

      if (!mounted) return;

      // Puede ocurrir que la URL tarde y el usuario ya haya
      // seleccionado otro canal.
      //
      // En ese caso no enviamos esta URL antigua a ExoPlayer.
      if (_selectedChannel?.id != channel.id) {
        debugPrint(
          'TV OVERLAY: URL descartada '
          'porque cambió el canal seleccionado.',
        );

        return;
      }

      debugPrint(
        'TV OVERLAY: reproduciendo '
        '${channel.name} (${channel.id})',
      );

      await TvOverlayService.showPlayer(
        url: url,

        // TEMPORAL:
        // estas coordenadas pertenecen al laboratorio que ya
        // comprobamos físicamente en las TVs.
        //
        // Más adelante las calcularemos automáticamente según
        // la posición real del panel EN VIVO.
        x: 700,
        y: 220,
        width: 500,
        height: 350,
      );
    } catch (e) {
      debugPrint(
        'TV OVERLAY ERROR: $e',
      );

      // Solo ocultamos si este sigue siendo el canal seleccionado.
      //
      // Así un error atrasado de un canal anterior no apaga
      // accidentalmente el canal nuevo.
      if (mounted &&
          _selectedChannel?.id == channel.id) {
        await TvOverlayService.hide();
      }
    }
  }

  // ============================================================
  // CICLO DE VIDA
  // ============================================================

  @override
  void dispose() {
    // Evita que un Timer intente abrir un canal después
    // de haber abandonado TvHomeScreen.
    _channelDebounce?.cancel();
    _channelDebounce = null;

    // No usamos await dentro de dispose().
    TvOverlayService.hide();

    super.dispose();
  }

  // ============================================================
  // UI PRINCIPAL
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _buildPanel(
                        title: 'CATEGORÍAS',
                        child: _buildCategories(),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      flex: 3,
                      child: _buildPanel(
                        title: 'CANALES',
                        child: _buildChannels(),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      flex: 5,
                      child: _buildPanel(
                        title: 'EN VIVO',
                        child: _buildPreview(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CATEGORÍAS
  // ============================================================

  Widget _buildCategories() {
    if (_loadingCategories) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.error,
            ),
          ),
        ),
      );
    }

    if (_categories.isEmpty) {
      return const Center(
        child: Text(
          'No hay categorías disponibles.',
          style: TextStyle(
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        vertical: 10,
      ),
      itemCount: _categories.length,
      itemBuilder: (context, index) {
        final category = _categories[index];

        final selected =
            _selectedCategory?.id == category.id;

        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 3,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius:
                BorderRadius.circular(10),
            child: InkWell(
              autofocus: index == 0,
              borderRadius:
                  BorderRadius.circular(10),
              focusColor:
                  AppColors.primary.withValues(
                alpha: .30,
              ),
              onTap: () {
                _selectCategory(category);
              },
              child: AnimatedContainer(
                duration:
                    const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary
                          .withValues(alpha: .22)
                      : Colors.transparent,
                  borderRadius:
                      BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.play_arrow_rounded
                          : Icons.folder_outlined,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        category.name,
                        maxLines: 1,
                        overflow:
                            TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected
                              ? AppColors.textPrimary
                              : AppColors
                                  .textSecondary,
                          fontSize: 15,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // CANALES
  // ============================================================

  Widget _buildChannels() {
    if (_selectedCategory == null) {
      return const Center(
        child: Text(
          'Selecciona una categoría.',
          style: TextStyle(
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    if (_loadingChannels) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_channels.isEmpty) {
      return const Center(
        child: Text(
          'No hay canales disponibles.',
          style: TextStyle(
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        vertical: 10,
      ),
      itemCount: _channels.length,
      itemBuilder: (context, index) {
        final channel = _channels[index];

        final selected =
            _selectedChannel?.id == channel.id;

        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 3,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius:
                BorderRadius.circular(10),
            child: InkWell(
              borderRadius:
                  BorderRadius.circular(10),
              focusColor:
                  AppColors.primary.withValues(
                alpha: .30,
              ),
              onTap: () {
                _selectChannel(channel);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white
                          .withValues(alpha: .08)
                      : Colors.transparent,
                  borderRadius:
                      BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    _channelLogo(channel),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            channel.name,
                            maxLines: 1,
                            overflow:
                                TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected
                                  ? AppColors
                                      .textPrimary
                                  : AppColors
                                      .textSecondary,
                              fontSize: 15,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'EN VIVO',
                            style: TextStyle(
                              color:
                                  Color(0xFF22C55E),
                              fontSize: 10,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _channelLogo(
    LiveChannel channel,
  ) {
    if (channel.icon == null ||
        channel.icon!.isEmpty) {
      return Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.white
              .withValues(alpha: .08),
          borderRadius:
              BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.live_tv_rounded,
          color: AppColors.textSecondary,
        ),
      );
    }

    return Container(
      width: 46,
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(8),
      ),
      child: Image.network(
        channel.icon!,
        fit: BoxFit.contain,
        errorBuilder: (
          context,
          error,
          stackTrace,
        ) {
          return const Icon(
            Icons.live_tv_rounded,
            color: Colors.black54,
          );
        },
      ),
    );
  }

  // ============================================================
  // PREVIEW
  // ============================================================

  Widget _buildPreview() {
    final channel = _selectedChannel;

    if (channel == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.live_tv_rounded,
              size: 70,
              color: AppColors.textSecondary,
            ),
            SizedBox(height: 18),
            Text(
              'Selecciona un canal',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    // El área queda vacía deliberadamente.
    //
    // Flutter dibuja el panel, pero el video real está siendo
    // colocado encima por Android mediante:
    //
    // TvOverlayController
    //      ↓
    // TextureView
    //      ↓
    // ExoPlayer
    //
    // Así evitamos el problema de PlatformView/SurfaceProducer
    // que causaba audio sin imagen en estas TVs.
    return const Padding(
      padding: EdgeInsets.all(18),
      child: SizedBox.expand(),
    );
  }

  // ============================================================
  // TOP BAR
  // ============================================================

  Widget _buildTopBar() {
    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(
        horizontal: 32,
      ),
      color: AppColors.surface,
      child: Row(
        children: [
          Image.asset(
            'assets/images/tc_play_logo.png',
            height: 46,
          ),
          const SizedBox(width: 14),
          const Text(
            'TC PLAY',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          const Icon(
            Icons.search_rounded,
            color: AppColors.textSecondary,
            size: 28,
          ),
          const SizedBox(width: 28),
          const Icon(
            Icons.person_outline_rounded,
            color: AppColors.textSecondary,
            size: 28,
          ),
          const SizedBox(width: 28),
          const Icon(
            Icons.settings_outlined,
            color: AppColors.textSecondary,
            size: 28,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PANEL
  // ============================================================

  Widget _buildPanel({
    required String title,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius:
            BorderRadius.circular(18),
        border: Border.all(
          color:
              Colors.white.withValues(alpha: .08),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding:
                const EdgeInsets.fromLTRB(
              20,
              18,
              20,
              14,
            ),
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
          Divider(
            height: 1,
            color:
                Colors.white.withValues(alpha: .08),
          ),
          Expanded(
            child: child,
          ),
        ],
      ),
    );
  }
}