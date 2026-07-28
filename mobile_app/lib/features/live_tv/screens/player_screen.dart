import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

import '../../../core/constants/app_colors.dart';
import '../services/live_tv_service.dart';
import '../controllers/live_tv_player_controller.dart';
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
  final LiveTvService _service = LiveTvService();
  final LiveTvPlayerController _playerController = LiveTvPlayerController();
  final FavoriteChannelService _favoriteService = FavoriteChannelService();
  final RecentChannelService _recentChannelService = RecentChannelService();

  bool _isFavorite = false;

  Timer? _playbackWatchdog;
  Timer? _reconnectDelayTimer;
  Timer? _hideControlsTimer;

  StreamSubscription? _playingSub;
  StreamSubscription? _errorSub;

  bool _isInitializingPlayer = false;
  bool _playerError = false;
  bool _isReconnecting = false;
  bool _isDisposed = false;
  bool _isClosingPlayer = false;
  bool _isLandscape = false;
  bool _controlsVisible = true;
  bool _locked = false;

  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;

  Duration _lastPosition = Duration.zero;
  DateTime _lastPositionChange = DateTime.now();

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

    _enterFullscreenLandscape();

    _checkFavorite();
    WakelockPlus.enable();
    _saveRecentChannel();
    _setupMediaKitListeners();
    _loadInitialPlayer();
    _scheduleHideControls();
    _initMediaControls();
  }

  Future<void> _initMediaControls() async {
    try {
      final brightness = await ScreenBrightness().application;
      if (mounted) setState(() => _brightness = brightness);
    } catch (e) {
      debugPrint('No se pudo leer el brillo actual: $e');
    }

    try {
      VolumeController.instance.showSystemUI = false;
      final volume = await VolumeController.instance.getVolume();
      if (mounted) setState(() => _volume = volume);
    } catch (e) {
      debugPrint('No se pudo leer el volumen actual: $e');
    }
  }

  void _setupMediaKitListeners() {
    _playingSub = _playerController.player.stream.playing.listen((isPlaying) {
      if (mounted) setState(() {});
    });

    _errorSub = _playerController.player.stream.error.listen((error) {
      debugPrint("MEDIA KIT STREAM ERROR: $error");
      if (!_isReconnecting && !_isDisposed) {
        _playerController.hasError = true;
        _startAutomaticReconnect();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed || _isClosingPlayer) return;

    if (state == AppLifecycleState.resumed) {
      if (!_playerError &&
          !_isInitializingPlayer &&
          !_playerController.player.state.playing) {
        _playerController.player.play();
      }
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _playerController.player.pause();
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

    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    );

    if (mounted) {
      setState(() {});
    }
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
    // Recorrer toda la pantalla de arriba a abajo mueve el valor de 0 a 1.
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

  // MÉTODO PARA SALIDA LIMPIA Y SEGURA
  Future<void> _closePlayerAndExit() async {
    if (_isClosingPlayer || _isDisposed) return;

    _isClosingPlayer = true;

    _playbackWatchdog?.cancel();
    _reconnectDelayTimer?.cancel();
    _hideControlsTimer?.cancel();

    try {
      await _playerController.player.pause();
      await _playerController.player.stop();
    } catch (e) {
      debugPrint('Error al detener el player: $e');
    }

    try {
      await _service.stopProxy(streamId: widget.streamId);
    } catch (e) {
      debugPrint('Error al detener proxy: $e');
    }

    try {
      await _restoreOrientation();
    } catch (e) {
      debugPrint('Error al restaurar orientación: $e');
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  // EL CARGADOR DEFINITIVO CON REINTENTOS
  // EL CARGADOR CORREGIDO
  Future<void> _loadInitialPlayer() async {
    debugPrint("===== LOAD INITIAL PLAYER =====");
    if (_isDisposed) return;

    if (mounted) {
      setState(() {
        _isInitializingPlayer = true;
        _playerError = false;
      });
    }

    try {
      // 1. SOLO detenemos el motor de video. 
      // ELIMINAMOS el stopProxy erróneo de aquí.
      await _playerController.player.stop();
      await Future.delayed(const Duration(milliseconds: 500));

      String streamUrl = '';
      bool urlObtained = false;
      int retries = 0;

      // 2. Bucle de persistencia
      while (!urlObtained && retries < _maxReconnectAttempts) {
        try {
          streamUrl = await _service.getProxyStreamUrl(
            username: widget.username,
            password: widget.password,
            streamId: widget.streamId, // Ahora sí pedimos el canal sin haberlo matado
          );
          urlObtained = true; 
        } catch (e) {
          final errorText = e.toString().toLowerCase();

          if (
            errorText.contains('transcoder') ||
            errorText.contains('segmentos hls') ||
            errorText.contains('hls_not_ready') ||
            errorText.contains('no generó segmentos')
          ) {
            retries++;
            debugPrint("⚠️ HLS aún no listo. Reintento $retries de $_maxReconnectAttempts...");
            if (retries >= _maxReconnectAttempts) rethrow;
            await Future.delayed(const Duration(seconds: 2));
          } else {
            rethrow;
          }
        }
      }

      debugPrint("✅ STREAM URL OBTENIDA: $streamUrl");
      if (!mounted || _isDisposed) return;

      await _playerController.initializePlayer(streamUrl);

      if (_playerController.hasError) {
        _showPlayerError();
        return;
      }

      _reconnectAttempts = 0;
      _startPlaybackWatchdog();

      if (mounted) {
        setState(() {
          _isInitializingPlayer = false;
          _playerError = false;
        });
      }
    } catch (e) {
      debugPrint('❌ ERROR FATAL PLAYER: $e');
      if (!mounted || _isDisposed) return;
      _showPlayerError();
    }
  }

  // RECONEXIÓN AUTOMÁTICA CORREGIDA
  Future<void> _startAutomaticReconnect() async {
    debugPrint("START AUTOMATIC RECONNECT");
    if (_isReconnecting || _isDisposed) return;

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('MAXIMUM AUTOMATIC RECONNECT ATTEMPTS REACHED');
      _showPlayerError();
      return;
    }

    _isReconnecting = true;
    _reconnectAttempts++;
    _playbackWatchdog?.cancel();

    if (mounted) {
      setState(() {
        _isInitializingPlayer = true;
        _playerError = false;
      });
    }

    try {
      await _playerController.player.stop();
      
      // Aquí sí está bien detener el proxy porque es el mismo canal que se cayó
      try {
        await _service.stopProxy(streamId: widget.streamId);
      } catch (_) {}
      
      await Future.delayed(const Duration(seconds: 1)); // Damos un poco más de tiempo
      if (_isDisposed) return;

      String newStreamUrl = '';
      bool urlObtained = false;
      int retries = 0;

      while (!urlObtained && retries < _maxReconnectAttempts) {
        try {
          newStreamUrl = await _service.getProxyStreamUrl(
            username: widget.username,
            password: widget.password,
            streamId: widget.streamId,
          );
          urlObtained = true;
        } catch (e) {
          final errorText = e.toString().toLowerCase();

          if (
            errorText.contains('transcoder') ||
            errorText.contains('segmentos hls') ||
            errorText.contains('hls_not_ready') ||
            errorText.contains('no generó segmentos')
          ) {
            retries++;
            debugPrint("⚠️ RECONEXIÓN: HLS aún no listo. Reintento $retries...");
            if (retries >= _maxReconnectAttempts) rethrow;
            await Future.delayed(const Duration(seconds: 2));
          } else {
            rethrow;
          }
        }
      }

      if (_isDisposed) return;
      await _playerController.initializePlayer(newStreamUrl);

      if (_playerController.hasError) {
        _handleReconnectFailure();
        return;
      }

      _reconnectAttempts = 0;
      _startPlaybackWatchdog();
      if (mounted) {
        setState(() {
          _isInitializingPlayer = false;
          _playerError = false;
        });
      }
    } catch (e) {
      debugPrint('AUTOMATIC RECONNECT ERROR: $e');
      _handleReconnectFailure();
    } finally {
      _isReconnecting = false;
    }
  }

  void _startPlaybackWatchdog() {
    _playbackWatchdog?.cancel();
    _lastPosition = _playerController.player.state.position;
    _lastPositionChange = DateTime.now();
    _playbackWatchdog = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkPlaybackHealth(),
    );
  }

  void _checkPlaybackHealth() {
    if (_isDisposed || _isReconnecting) return;

    if (_playerController.hasError) {
      _startAutomaticReconnect();
      return;
    }

    final currentPosition = _playerController.player.state.position;
    if (currentPosition != _lastPosition) {
      _lastPosition = currentPosition;
      _lastPositionChange = DateTime.now();
      return;
    }

    final frozenDuration = DateTime.now().difference(_lastPositionChange);
    if (frozenDuration >= const Duration(seconds: 30)) {
      debugPrint('PLAYBACK FROZEN FOR 30 SECONDS - STARTING AUTOMATIC RECOVERY');
      _startAutomaticReconnect();
    }
  }

  void _handleReconnectFailure() {
    if (_isDisposed) return;
    if (_reconnectAttempts < _maxReconnectAttempts) {
      _reconnectDelayTimer?.cancel();
      _reconnectDelayTimer = Timer(const Duration(seconds: 2), () {
        if (!_isDisposed && !_isReconnecting) {
          _startAutomaticReconnect();
        }
      });
      return;
    }
    _showPlayerError();
  }

  void _showPlayerError() {
    if (!mounted || _isDisposed) return;
    setState(() {
      _isInitializingPlayer = false;
      _playerError = true;
    });
  }

  Future<void> _refresh() async {
    if (_isDisposed) return;
    setState(() {
      _playerError = false;
      _isInitializingPlayer = true;
    });
    _reconnectAttempts = 0;
    await _startAutomaticReconnect();
  }

  void _togglePlayPause() {
    _playerController.player.playOrPause();
    _scheduleHideControls();
    setState(() {});
  }

  Future<void> _checkFavorite() async {
    final favorite = await _favoriteService.isFavorite(widget.streamId);
    if (!mounted) return;
    setState(() {
      _isFavorite = favorite;
    });
  }

  Future<void> _toggleFavorite() async {
    if (_isFavorite) {
      await _favoriteService.removeChannel(widget.streamId);
      if (!mounted) return;
      setState(() => _isFavorite = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Canal eliminado de favoritos')),
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
        const SnackBar(content: Text('Canal agregado a favoritos')),
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
    _playingSub?.cancel();
    _errorSub?.cancel();
    _playbackWatchdog?.cancel();
    _reconnectDelayTimer?.cancel();
    _hideControlsTimer?.cancel();
    _volumeHideTimer?.cancel();
    _brightnessHideTimer?.cancel();
    WakelockPlus.disable();

    // Devolvemos el brillo del dispositivo a su valor original al salir.
    ScreenBrightness().resetApplicationScreenBrightness();

    _playerController.dispose();

    if (!_isClosingPlayer) {
      unawaited(_service.stopProxy(streamId: widget.streamId));
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
        if (_isLandscape) {
          _toggleOrientation();
        } else {
          await _closePlayerAndExit();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _locked ? null : _toggleControls,
          onVerticalDragStart: _locked ? null : _handleVerticalDragStart,
          onVerticalDragUpdate: _locked ? null : _handleVerticalDragUpdate,
          onVerticalDragEnd: _locked ? null : _handleVerticalDragEnd,
          child: Stack(
            children: [
              Positioned.fill(child: _buildPlayerContent()),
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
                    : (_volume < 0.5
                        ? Icons.volume_down_rounded
                        : Icons.volume_up_rounded),
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
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerContent() {
    return Stack(
      children: [
        Positioned.fill(
          child: Video(
            controller: _playerController.videoController,
            controls: NoVideoControls,
          ),
        ),

        if (_isInitializingPlayer)
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  color: AppColors.primary,
                ),
                SizedBox(height: 14),
                Text(
                  'Cargando canal...',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

        if (_playerError)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.error,
                  size: 50,
                ),
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
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: _closePlayerAndExit,
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
              onPressed: () async {
                if (_isLandscape) {
                  _toggleOrientation();
                } else {
                  await _closePlayerAndExit();
                }
              },
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
            ),
            if (widget.channelIcon != null && widget.channelIcon!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  widget.channelIcon!,
                  width: 22,
                  height: 22,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.public_rounded, color: AppColors.textPrimary, size: 20,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.channelName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15,
                ),
              ),
            ),
            IconButton(
              onPressed: _comingSoon,
              icon: const Icon(Icons.cast_connected_rounded, color: AppColors.textPrimary, size: 20),
            ),
            IconButton(
              onPressed: _toggleFavorite,
              icon: Icon(
                _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                color: AppColors.favoriteGold, size: 22,
              ),
            ),
            IconButton(
              onPressed: _comingSoon,
              icon: const Icon(Icons.tv_rounded, color: AppColors.textPrimary, size: 20),
            ),
            IconButton(
              onPressed: _toggleOrientation,
              icon: Icon(
                _isLandscape ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                color: AppColors.textPrimary, size: 22,
              ),
            ),
            IconButton(
              onPressed: _comingSoon,
              icon: const Icon(Icons.more_vert_rounded, color: AppColors.textPrimary, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterControls() {
    final isPlaying = _playerController.player.state.playing;

    return _circleIconButton(
      icon: isPlaying
          ? Icons.pause_rounded
          : Icons.play_arrow_rounded,
      size: 34,
      padding: 14,
      onTap: _togglePlayPause,
    );
  }

  Widget _circleIconButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 26,
    double padding = 10,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .35), shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: size),
      ),
    );
  }

  Widget _buildLockButton() {
    return GestureDetector(
      onTap: () {
        setState(() => _locked = !_locked);
        _scheduleHideControls();
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .45), shape: BoxShape.circle,
        ),
        child: Icon(
          _locked ? Icons.lock_rounded : Icons.lock_open_rounded,
          color: Colors.white, size: 18,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Barra vertical de volumen / brillo — aparece al deslizar, del lado
  // correspondiente, y se oculta sola.
  // ---------------------------------------------------------------------
  Widget _buildVerticalIndicator({
    required Alignment alignment,
    required bool visible,
    required double value,
    required IconData icon,
  }) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: Align(
          alignment: alignment,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Container(
              width: 36,
              height: 150,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: .08)),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: value.clamp(0.0, 1.0),
                        widthFactor: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Icon(icon, color: Colors.white, size: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
