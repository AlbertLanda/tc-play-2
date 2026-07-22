import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../services/live_tv_service.dart';
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

class _PlayerScreenState extends State<PlayerScreen> {
  final LiveTvService _service = LiveTvService();

  final FavoriteChannelService _favoriteService = FavoriteChannelService();

  bool _isFavorite = false;

  final RecentChannelService _recentChannelService =
    RecentChannelService();

  VideoPlayerController? _videoPlayerController;

  Timer? _playbackWatchdog;
  Timer? _reconnectDelayTimer;
  Timer? _hideControlsTimer;

  bool _isInitializingPlayer = false;
  bool _playerError = false;
  bool _isReconnecting = false;
  bool _isDisposed = false;
  bool _isLandscape = false;
  bool _controlsVisible = true;
  bool _locked = false;

  int _reconnectAttempts = 0;

  static const int _maxReconnectAttempts = 2;

  Duration _lastPosition = Duration.zero;
  DateTime _lastPositionChange = DateTime.now();

  @override
  void initState() {
    super.initState();

    _checkFavorite(); 

    WakelockPlus.enable();

    _saveRecentChannel();

    _loadInitialPlayer();

    _scheduleHideControls();
  }

  

  // ---------------------------------------------------------------------
  // Orientación: portrait <-> landscape (pantalla completa horizontal)
  // ---------------------------------------------------------------------
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

  // ---------------------------------------------------------------------
  // Controles: mostrar/ocultar con auto-hide
  // ---------------------------------------------------------------------
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
  // Carga / reconexión del stream (misma lógica que la versión original)
  // ---------------------------------------------------------------------
  Future<void> _loadInitialPlayer() async {
    if (_isDisposed) return;

    if (mounted) {
      setState(() {
        _isInitializingPlayer = true;
        _playerError = false;
      });
    }

    try {
      final streamUrl = await _service.getProxyStreamUrl(
        username: widget.username,
        password: widget.password,
        streamId: widget.streamId,
      );

      if (!mounted || _isDisposed) return;

      final controller = await _createAndInitializeController(streamUrl);

      if (!mounted || _isDisposed) {
        await controller?.dispose();
        return;
      }

      if (controller == null) {
        _showPlayerError();
        return;
      }

      _videoPlayerController = controller;
      await controller.play();

      _reconnectAttempts = 0;
      _startPlaybackWatchdog();

      setState(() {
        _isInitializingPlayer = false;
        _playerError = false;
      });
    } catch (e) {
      debugPrint('INITIAL PLAYER ERROR: $e');
      if (!mounted || _isDisposed) return;
      _showPlayerError();
    }
  }

  Future<VideoPlayerController?> _createAndInitializeController(
    String url,
  ) async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );

    try {
      await controller.initialize();

      if (!controller.value.isInitialized) {
        await controller.dispose();
        return null;
      }

      controller.addListener(() {
        if (_isDisposed) return;
        if (mounted) setState(() {});

        if (controller.value.hasError &&
            identical(controller, _videoPlayerController)) {
          debugPrint('VIDEO ERROR: ${controller.value.errorDescription}');
          _startAutomaticReconnect();
        }
      });

      return controller;
    } catch (e) {
      debugPrint('CONTROLLER INITIALIZATION ERROR: $e');
      await controller.dispose();
      return null;
    }
  }

  void _startPlaybackWatchdog() {
    _playbackWatchdog?.cancel();

    _lastPosition = _videoPlayerController?.value.position ?? Duration.zero;
    _lastPositionChange = DateTime.now();

    _playbackWatchdog = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkPlaybackHealth(),
    );
  }

  void _checkPlaybackHealth() {
    if (_isDisposed || _isReconnecting || _videoPlayerController == null) {
      return;
    }

    final controller = _videoPlayerController!;
    if (!controller.value.isInitialized) return;

    if (controller.value.hasError) {
      _startAutomaticReconnect();
      return;
    }

    final currentPosition = controller.value.position;

    if (currentPosition != _lastPosition) {
      _lastPosition = currentPosition;
      _lastPositionChange = DateTime.now();
      return;
    }

    final frozenDuration = DateTime.now().difference(_lastPositionChange);

    if (frozenDuration >= const Duration(seconds: 10)) {
      debugPrint('PLAYBACK FROZEN FOR 10 SECONDS - STARTING AUTOMATIC RECOVERY');
      _startAutomaticReconnect();
    }
  }

  Future<void> _startAutomaticReconnect() async {
    if (_isReconnecting || _isDisposed) return;

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('MAXIMUM AUTOMATIC RECONNECT ATTEMPTS REACHED');
      _showPlayerError();
      return;
    }

    _isReconnecting = true;
    _reconnectAttempts++;

    _playbackWatchdog?.cancel();

    final oldController = _videoPlayerController;

    try {
      await _service.stopProxy(streamId: widget.streamId);
      if (_isDisposed) return;

      final newStreamUrl = await _service.getProxyStreamUrl(
        username: widget.username,
        password: widget.password,
        streamId: widget.streamId,
      );

      if (_isDisposed) return;

      final newController = await _createAndInitializeController(newStreamUrl);

      if (newController == null) {
        _handleReconnectFailure();
        return;
      }

      if (_isDisposed || !mounted) {
        await newController.dispose();
        return;
      }

      await newController.play();

      _videoPlayerController = newController;
      await oldController?.dispose();

      _reconnectAttempts = 0;
      _startPlaybackWatchdog();

      if (mounted) setState(() => _playerError = false);
    } catch (e) {
      debugPrint('AUTOMATIC RECONNECT ERROR: $e');
      _handleReconnectFailure();
    } finally {
      _isReconnecting = false;
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
    _reconnectAttempts = 0;
    _playerError = false;
    await _startAutomaticReconnect();
  }

  void _seekRelative(Duration offset) {
    final controller = _videoPlayerController;
    if (controller == null || !controller.value.isInitialized) return;
    final target = controller.value.position + offset;
    controller.seekTo(
      target < Duration.zero ? Duration.zero : target,
    );
    _scheduleHideControls();
  }

  void _togglePlayPause() {
    final controller = _videoPlayerController;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
    _scheduleHideControls();
    setState(() {});
  }

  Future<void> _checkFavorite() async {
      final favorite =
          await _favoriteService.isFavorite(widget.streamId);
      
      if (!mounted) return;
      
      setState(() {
        _isFavorite = favorite;
      });
    }

    Future<void> _toggleFavorite() async {
      if (_isFavorite) {
        await _favoriteService.removeChannel(widget.streamId);

        if (!mounted) return;

        setState(() {
          _isFavorite = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Canal eliminado de favoritos'),
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

        setState(() {
          _isFavorite = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Canal agregado a favoritos'),
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
    _playbackWatchdog?.cancel();
    _reconnectDelayTimer?.cancel();
    _hideControlsTimer?.cancel();
    WakelockPlus.disable();
    _videoPlayerController?.dispose();
    _service.stopProxy(streamId: widget.streamId);
    _restoreOrientation();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isLandscape,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isLandscape) _toggleOrientation();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _locked ? null : _toggleControls,
          child: Stack(
            children: [
              Positioned.fill(child: _buildPlayerContent()),
              if (_controlsVisible) ...[
                Positioned(
                    top: 0, left: 0, right: 0, child: _buildTopOverlay()),
                if (!_locked)
                  Positioned.fill(child: Center(child: _buildCenterControls())),
                Positioned(
                    left: 0, right: 0, bottom: 0, child: _buildBottomOverlay()),
              ],
              if (_controlsVisible)
                Positioned(
                  left: 12,
                  bottom: _isLandscape ? 70 : 90,
                  child: _buildLockButton(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerContent() {
    final controller = _videoPlayerController;

    if (controller != null && controller.value.isInitialized && !_playerError) {
      return Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      );
    }

    if (_isInitializingPlayer) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_playerError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 50),
            const SizedBox(height: 16),
            const Text(
              'No se pudo reproducir el canal.',
              style: TextStyle(color: AppColors.textPrimary),
            ),
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

    return const Center(
      child: CircularProgressIndicator(color: AppColors.primary),
    );
  }

  // ---------------------------------------------------------------------
  // Overlay superior: volver, ícono + nombre del canal, cast, me gusta,
  // tv, más opciones — como en la captura 3
  // ---------------------------------------------------------------------
  Widget _buildTopOverlay() {
    return Container(
      padding: EdgeInsets.fromLTRB(4, _isLandscape ? 6 : 6, 8, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.65),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              onPressed: () {
                if (_isLandscape) {
                  _toggleOrientation();
                } else {
                  Navigator.of(context).pop();
                }
              },
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: AppColors.textPrimary),
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
                    Icons.public_rounded,
                    color: AppColors.textPrimary,
                    size: 20,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.channelName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            IconButton(
              onPressed: _comingSoon,
              icon: const Icon(Icons.cast_connected_rounded,
                  color: AppColors.textPrimary, size: 20),
            ),
            IconButton(
              onPressed: _toggleFavorite,
              icon: Icon(
                _isFavorite
                  ? Icons.star_rounded
                  : Icons.star_border_rounded,
                color: Colors.amber,
                size: 22,
              ),
            ),
            IconButton(
              onPressed: _comingSoon,
              icon: const Icon(Icons.tv_rounded,
                  color: AppColors.textPrimary, size: 20),
            ),
            IconButton(
              onPressed: _comingSoon,
              icon: const Icon(Icons.more_vert_rounded,
                  color: AppColors.textPrimary, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Controles centrales: retroceder 10s, play/pause, adelantar 10s
  // ---------------------------------------------------------------------
  Widget _buildCenterControls() {
    final controller = _videoPlayerController;
    final isPlaying = controller?.value.isPlaying ?? false;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _circleIconButton(
          icon: Icons.replay_10_rounded,
          onTap: () => _seekRelative(const Duration(seconds: -10)),
        ),
        const SizedBox(width: 34),
        _circleIconButton(
          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 34,
          padding: 14,
          onTap: _togglePlayPause,
        ),
        const SizedBox(width: 34),
        _circleIconButton(
          icon: Icons.forward_10_rounded,
          onTap: () => _seekRelative(const Duration(seconds: 10)),
        ),
      ],
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
          color: Colors.black.withValues(alpha: .35),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: size),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Overlay inferior: barra de progreso roja + fila con Cerrar,
  // COMENTAR, expandir/contraer pantalla
  // ---------------------------------------------------------------------
  Widget _buildBottomOverlay() {
    final controller = _videoPlayerController;
    final duration = controller?.value.duration ?? Duration.zero;
    final position = controller?.value.position ?? Duration.zero;
    final hasFiniteDuration = duration.inMilliseconds > 0;
    final progress = hasFiniteDuration
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 1.0; // stream en vivo: barra llena en rojo

    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, _isLandscape ? 10 : 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                activeTrackColor: AppColors.liveRed,
                inactiveTrackColor: Colors.white.withValues(alpha: .3),
                thumbColor: AppColors.liveRed,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: progress,
                onChanged: hasFiniteDuration
                    ? (value) {
                        final target = duration * value;
                        controller?.seekTo(target);
                      }
                    : null,
              ),
            ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    if (_isLandscape) _toggleOrientation();
                    Navigator.of(context).pop();
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  icon: const Icon(Icons.lock_outline_rounded, size: 18),
                  label: const Text('Cerrar', style: TextStyle(fontSize: 12)),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _comingSoon,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  icon: const Icon(Icons.mode_comment_outlined, size: 18),
                  label:
                      const Text('COMENTAR', style: TextStyle(fontSize: 12)),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _toggleOrientation,
                  icon: Icon(
                    _isLandscape
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
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
          color: Colors.black.withValues(alpha: .45),
          shape: BoxShape.circle,
        ),
        child: Icon(
          _locked ? Icons.lock_rounded : Icons.lock_open_rounded,
          color: Colors.white,
          size: 18,
        ),
      ),
    );
  }
}
