// Ruta en el proyecto: lib/features/live_tv/screens/player_screen.dart

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/pip_service.dart';
import '../../../core/services/live_playback_manager.dart';
import '../../../core/utils/tv_utils.dart';
import '../models/recent_channel.dart';
import '../services/recent_channel_service.dart';
import '../models/favorite_channel.dart';
import '../services/favorite_channel_service.dart';

class PlayerScreen extends StatefulWidget {
  final String username;
  final String password;
  final int streamId;
  final String channelName;
  final String? channelIcon;

  const PlayerScreen({
    super.key,
    required this.username,
    required this.password,
    required this.streamId,
    required this.channelName,
    this.channelIcon,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  final LivePlaybackManager _manager = LivePlaybackManager.instance;
  final FavoriteChannelService _favoriteService = FavoriteChannelService();
  final RecentChannelService _recentChannelService = RecentChannelService();

  bool _isFavorite = false;

  Timer? _hideControlsTimer;

  bool _isDisposed = false;
  bool _isClosingPlayer = false;
  bool _isLandscape = false;
  bool _controlsVisible = true;
  bool _locked = false;

  // Modo mini-reproductor NATIVO (Picture-in-Picture del sistema): true
  // mientras el usuario está en otra app / en el Home. Distinto del
  // mini-reproductor propio dentro de la app (ver MiniPlayerOverlay),
  // que se activa al volver de PlayerScreen sin salir de TC Play.
  bool _isInPip = PipService.isInPipMode;
  StreamSubscription<bool>? _pipModeSub;

  // ---------------------------------------------------------------------
  // Volumen (deslizar en la mitad izquierda) y brillo (mitad derecha)
  // ---------------------------------------------------------------------
  double _volume = 0.5;
  double _brightness = 0.5;
  bool _showVolumeIndicator = false;
  bool _showBrightnessIndicator = false;
  Timer? _volumeHideTimer;
  Timer? _brightnessHideTimer;

  double? _dragStartY;
  double? _dragStartValue;
  bool? _isDraggingLeftSide;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _manager.addListener(_onManagerChanged);
    _manager.setFullScreenOpen(true);

    _enterFullscreenLandscape();

    _checkFavorite();
    _saveRecentChannel();
    _scheduleHideControls();
    _initMediaControls();

    _pipModeSub = PipService.pipModeStream.listen(_onPipModeChanged);

    _manager.loadChannel(
      LiveChannelInfo(
        username: widget.username,
        password: widget.password,
        streamId: widget.streamId,
        channelName: widget.channelName,
        channelIcon: widget.channelIcon,
      ),
    );
  }

  void _onManagerChanged() {
    if (mounted) setState(() {});
  }

  void _onPipModeChanged(bool isInPip) {
    if (!mounted) return;
    setState(() => _isInPip = isInPip);

    if (!isInPip) {
      // Al volver de la ventanita nativa a pantalla completa, Android
      // puede resetear la barra de estado/navegación: la reponemos.
      if (_isLandscape) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        );
      }
      _scheduleHideControls();
    }
  }

  Future<void> _initMediaControls() async {
    try {
      final brightness = await ScreenBrightness().application;
      if (mounted) setState(() => _brightness = brightness);
    } catch (e) {
      debugPrint('No se pudo leer el brillo actual');
    }

    try {
      VolumeController.instance.showSystemUI = false;
      final volume = await VolumeController.instance.getVolume();
      if (mounted) setState(() => _volume = volume);
    } catch (e) {
      debugPrint('No se pudo leer el volumen actual');
    }
  }

  // Ya no maneja play/pause/reconexión: eso vive en LivePlaybackManager
  // y sigue funcionando aunque esta pantalla no esté montada. Acá solo
  // queda lo que es puramente de esta pantalla (UI del sistema).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed) return;
    if (state == AppLifecycleState.resumed && !_isInPip) {
      if (_isLandscape) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    }
  }

  Future<void> _toggleOrientation() async {
    _isLandscape = !_isLandscape;

    if (_isLandscape) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _enterFullscreenLandscape() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    _isLandscape = true;

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (mounted) setState(() {});
  }

  Future<void> _restoreOrientation() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_locked) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHideControls();
  }

  // ---------------------------------------------------------------------
  // Gestos verticales: izquierda = volumen, derecha = brillo
  // ---------------------------------------------------------------------
  void _handleVerticalDragStart(DragStartDetails details) {
    if (_locked) return;
    final width = MediaQuery.of(context).size.width;
    _isDraggingLeftSide = details.globalPosition.dx < width / 2;
    _dragStartY = details.globalPosition.dy;
    _dragStartValue = _isDraggingLeftSide! ? _volume : _brightness;
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (_locked ||
        _dragStartY == null ||
        _dragStartValue == null ||
        _isDraggingLeftSide == null) {
      return;
    }

    final height = MediaQuery.of(context).size.height;
    final delta = (_dragStartY! - details.globalPosition.dy) / height;
    final newValue = (_dragStartValue! + delta).clamp(0.0, 1.0);

    if (_isDraggingLeftSide!) {
      setState(() {
        _volume = newValue;
        _showVolumeIndicator = true;
      });
      VolumeController.instance.setVolume(newValue);
      _volumeHideTimer?.cancel();
    } else {
      setState(() {
        _brightness = newValue;
        _showBrightnessIndicator = true;
      });
      ScreenBrightness().setApplicationScreenBrightness(newValue);
      _brightnessHideTimer?.cancel();
    }
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    _dragStartY = null;
    _dragStartValue = null;

    if (_isDraggingLeftSide == true) {
      _volumeHideTimer = Timer(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => _showVolumeIndicator = false);
      });
    } else if (_isDraggingLeftSide == false) {
      _brightnessHideTimer = Timer(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => _showBrightnessIndicator = false);
      });
    }

    _isDraggingLeftSide = null;
  }

  // ---------------------------------------------------------------------
  // Salida de la pantalla: "volver" ahora MINIMIZA (el canal sigue
  // reproduciéndose en el mini-reproductor flotante), no detiene nada.
  // Solo se detiene todo explícitamente (ver _closePlaybackAndExit).
  // ---------------------------------------------------------------------
  Future<void> _minimizeAndExit() async {
    if (_isClosingPlayer || _isDisposed) return;
    _isClosingPlayer = true;

    _hideControlsTimer?.cancel();

    // Restauramos la orientación ya, sin esperar nada más, para que la
    // pantalla anterior no quede en horizontal unos segundos de más.
    unawaited(_restoreOrientation());

    _manager.minimizeToMiniPlayer();

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  // Cierre explícito y total (por ejemplo desde la pantalla de error):
  // acá sí se detiene la reproducción y se cierra el proxy.
  Future<void> _closePlaybackAndExit() async {
    if (_isClosingPlayer || _isDisposed) return;
    _isClosingPlayer = true;

    _hideControlsTimer?.cancel();
    unawaited(_restoreOrientation());

    if (mounted) {
      Navigator.of(context).pop();
    }

    await _manager.closePlayback();
  }

  Future<void> _checkFavorite() async {
    final favorite = await _favoriteService.isFavorite(widget.streamId);
    if (!mounted) return;
    setState(() => _isFavorite = favorite);
  }

  Future<void> _toggleFavorite() async {
    if (_isFavorite) {
      await _favoriteService.removeChannel(widget.streamId);
      if (!mounted) return;
      setState(() => _isFavorite = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.black.withValues(alpha: 0.75),
          elevation: 0,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          duration: const Duration(seconds: 2),
          content: const Row(
            children: [
              Icon(Icons.heart_broken_rounded, color: Colors.white70, size: 20),
              SizedBox(width: 10),
              Text(
                'Canal eliminado de favoritos',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    } else {
      await _favoriteService.saveChannel(
        FavoriteChannel(
          id: widget.streamId,
          name: widget.channelName,
          icon: widget.channelIcon,
          streamType: 'live',
        ),
      );
      if (!mounted) return;
      setState(() => _isFavorite = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.black.withValues(alpha: 0.75),
          elevation: 0,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          duration: const Duration(seconds: 2),
          content: const Row(
            children: [
              Icon(Icons.favorite_rounded, color: Colors.redAccent, size: 20),
              SizedBox(width: 10),
              Text(
                'Canal agregado a favoritos',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _saveRecentChannel() async {
    await _recentChannelService.saveChannel(
      RecentChannel(
        id: widget.streamId,
        name: widget.channelName,
        icon: widget.channelIcon,
        streamType: 'live',
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

  @override
  void dispose() {
    _isDisposed = true;
    _hideControlsTimer?.cancel();
    _volumeHideTimer?.cancel();
    _brightnessHideTimer?.cancel();
    _pipModeSub?.cancel();
    _manager.removeListener(_onManagerChanged);

    // Devolvemos el brillo del dispositivo a su valor original al salir
    // de esta pantalla (el gesto de brillo es propio de PlayerScreen).
    ScreenBrightness().resetApplicationScreenBrightness();

    if (!_isClosingPlayer) {
      // Salida "no limpia": el sistema cerró/recreó esta pantalla sin
      // pasar por el botón de volver (por ejemplo, Android recicló la
      // ruta). Minimizamos al mini-reproductor en vez de dejar el
      // estado indefinido — el canal sigue vivo en LivePlaybackManager
      // de cualquier forma, ya que es un singleton independiente de
      // esta pantalla.
      _manager.minimizeToMiniPlayer();
      unawaited(_restoreOrientation());
    }

    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _minimizeAndExit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          // En TV los controles se ocultan solos tras unos segundos, y
          // sin esto no había forma de volver a mostrarlos con el
          // control remoto (el GestureDetector de abajo solo reacciona
          // a toques de pantalla táctil). Cualquier tecla del control
          // remoto (flechas, OK, atrás) los vuelve a mostrar; si ya
          // estaban visibles, dejamos pasar la tecla normalmente para
          // que la navegación entre botones siga funcionando.
          onKeyEvent: (node, event) {
            if (_locked || _isInPip) return KeyEventResult.ignored;
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (!_controlsVisible) {
              setState(() => _controlsVisible = true);
              _scheduleHideControls();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: (_locked || _isInPip) ? null : _toggleControls,
            onVerticalDragStart: (_locked || _isInPip) ? null : _handleVerticalDragStart,
            onVerticalDragUpdate: (_locked || _isInPip) ? null : _handleVerticalDragUpdate,
            onVerticalDragEnd: (_locked || _isInPip) ? null : _handleVerticalDragEnd,
            child: Stack(
            children: [
              // En PiP nativo solo se ve el video, sin overlays.
              Positioned.fill(child: _buildPlayerContent()),
              if (!_isInPip) ...[
                if (_controlsVisible) ...[
                  Positioned(top: 0, left: 0, right: 0, child: _buildTopOverlay()),
                  if (!_locked) Positioned.fill(child: Center(child: _buildCenterControls())),
                ],
                if (_controlsVisible)
                  Positioned(
                    left: 12,
                    bottom: _isLandscape ? 70 : 90,
                    child: _buildLockButton(),
                  ),
                _buildVerticalIndicator(
                  alignment: Alignment.centerLeft,
                  visible: _showVolumeIndicator,
                  value: _volume,
                  icon: _volume <= 0
                      ? Icons.volume_off_rounded
                      : (_volume < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
                ),
                _buildVerticalIndicator(
                  alignment: Alignment.centerRight,
                  visible: _showBrightnessIndicator,
                  value: _brightness,
                  icon: _brightness < 0.5
                      ? Icons.brightness_low_rounded
                      : Icons.brightness_high_rounded,
                ),
              ],
            ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerContent() {
    final status = _manager.status;

    return Stack(
      children: [
        Positioned.fill(
          child: Video(
            controller: _manager.videoController,
            controls: NoVideoControls,
            // Por defecto el Video widget usa BoxFit.contain, que
            // respeta la proporción original del stream y deja barras
            // negras arriba/abajo o a los costados cuando esa
            // proporción no coincide exacto con la pantalla del
            // celular. En pantalla completa queremos que ocupe todo el
            // espacio disponible, recortando el sobrante si hace falta
            // en vez de dejar barras.
            fit: BoxFit.contain,
          ),
        ),

        if (status == PlaybackStatus.loading || status == PlaybackStatus.reconnecting)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: AppColors.primary),
                const SizedBox(height: 14),
                Text(
                  status == PlaybackStatus.reconnecting
                      ? 'Reconectando...'
                      : 'Cargando canal...',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

        if (status == PlaybackStatus.error)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: AppColors.error, size: 50),
                const SizedBox(height: 16),
                const Text(
                  'No se pudo reproducir este canal.',
                  style: TextStyle(color: AppColors.textPrimary),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _manager.refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: _closePlaybackAndExit,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Volver'),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTopOverlay() {
    final castEnabled = _manager.castAvailable;
    final tvEnabled = _manager.tvChannelSwitcherAvailable;
    final moreEnabled = _manager.moreOptionsAvailable;
    final isTv = TvUtils.isTv(context);
    final iconSize = isTv ? 26.0 : 20.0;

    return Container(
      padding: EdgeInsets.fromLTRB(4, _isLandscape ? 6 : 6, 8, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.65), Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              onPressed: _minimizeAndExit,
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: AppColors.textPrimary,
                size: iconSize,
              ),
            ),
            if (widget.channelIcon != null && widget.channelIcon!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  widget.channelIcon!,
                  width: isTv ? 28 : 22,
                  height: isTv ? 28 : 22,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.public_rounded, color: AppColors.textPrimary, size: iconSize,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.channelName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: isTv ? 19 : 15,
                ),
              ),
            ),
            // Cast solo se muestra si hay una integración real detrás.
            // Mostrar un ícono de cast "activo" que en realidad no
            // conecta a nada confunde más de lo que ayuda.
            if (castEnabled)
              IconButton(
                onPressed: _comingSoon,
                icon: Icon(Icons.cast_connected_rounded, color: AppColors.textPrimary, size: iconSize),
              ),
            IconButton(
              onPressed: _toggleFavorite,
              icon: Icon(
                _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: Colors.redAccent,
                size: isTv ? 28 : 22,
              ),
            ),
            if (tvEnabled)
              IconButton(
                onPressed: _comingSoon,
                icon: Icon(Icons.tv_rounded, color: AppColors.textPrimary, size: iconSize),
              ),
            IconButton(
              onPressed: _toggleOrientation,
              icon: Icon(
                _isLandscape ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                color: AppColors.textPrimary, size: isTv ? 28 : 22,
              ),
            ),
            if (moreEnabled)
              IconButton(
                onPressed: _comingSoon,
                icon: Icon(Icons.more_vert_rounded, color: AppColors.textPrimary, size: iconSize),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterControls() {
    final status = _manager.status;
    if (status == PlaybackStatus.loading ||
        status == PlaybackStatus.reconnecting ||
        status == PlaybackStatus.error) {
      return const SizedBox.shrink();
    }

    final isPlaying = _manager.isPlaying;
    final isTv = TvUtils.isTv(context);

    return _circleIconButton(
      icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
      size: isTv ? 46 : 34,
      padding: isTv ? 20 : 14,
      // En TV este botón recibe el foco inicial al abrir el reproductor:
      // así el OK/Enter del control remoto pausa/reanuda de inmediato,
      // sin que el usuario tenga que navegar primero hasta él.
      autofocus: isTv,
      onTap: () {
        _manager.togglePlayPause();
        _scheduleHideControls();
      },
    );
  }

  Widget _circleIconButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 26,
    double padding = 10,
    bool autofocus = false,
  }) {
    // Material + InkWell en vez de GestureDetector: mismo aspecto y
    // mismo comportamiento táctil, pero además navegable y activable
    // con Enter/OK/D-Pad center en TV (foco nativo de InkWell).
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        autofocus: autofocus,
        customBorder: const CircleBorder(),
        focusColor: Colors.white.withValues(alpha: .25),
        child: Container(
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .35), shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: size),
        ),
      ),
    );
  }

  Widget _buildLockButton() {
    final isTv = TvUtils.isTv(context);

    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: () {
          setState(() => _locked = !_locked);
          _scheduleHideControls();
        },
        customBorder: const CircleBorder(),
        focusColor: Colors.white.withValues(alpha: .25),
        child: Container(
          padding: EdgeInsets.all(isTv ? 12 : 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .45), shape: BoxShape.circle,
          ),
          child: Icon(
            _locked ? Icons.lock_rounded : Icons.lock_open_rounded,
            color: Colors.white, size: isTv ? 26 : 18,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Barra vertical de volumen / brillo — sin cambios respecto al
  // original salvo por vivir en esta versión reorganizada del archivo.
  // ---------------------------------------------------------------------
  Widget _buildVerticalIndicator({
    required Alignment alignment,
    required bool visible,
    required double value,
    required IconData icon,
  }) {
    final screenSize = MediaQuery.of(context).size;
    final safePadding = MediaQuery.of(context).padding;

    final barHeight = (screenSize.height * 0.36).clamp(140.0, 235.0);
    final barWidth = (screenSize.width * 0.05).clamp(36.0, 48.0);

    final edgeInset =
        alignment == Alignment.centerLeft ? safePadding.left : safePadding.right;
    final baseMargin = (screenSize.width * 0.035).clamp(16.0, 28.0);
    final horizontalMargin = edgeInset + baseMargin;

    final clampedValue = value.clamp(0.0, 1.0);
    final percent = (clampedValue * 100).round();
    final trackWidth = barWidth * 0.32;

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: Align(
          alignment: alignment,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalMargin),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(barWidth / 2),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  width: barWidth,
                  height: barHeight,
                  padding: EdgeInsets.symmetric(vertical: barHeight * 0.06),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.surface.withValues(alpha: .8),
                        AppColors.background.withValues(alpha: .88),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(barWidth / 2),
                    border: Border.all(color: Colors.white.withValues(alpha: .14)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .4),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$percent%',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: barWidth * 0.26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      SizedBox(height: barHeight * 0.045),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(trackWidth / 2),
                          child: Container(
                            width: trackWidth,
                            color: Colors.white.withValues(alpha: .12),
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor: clampedValue,
                                widthFactor: 1,
                                child: Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [AppColors.accent, AppColors.primary],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: barHeight * 0.045),
                      Icon(icon, color: AppColors.textPrimary, size: barWidth * 0.4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}