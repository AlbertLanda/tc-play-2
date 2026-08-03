import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/pip_service.dart';
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

  // Modo mini-reproductor (Picture-in-Picture): true mientras el usuario
  // está en otra app / en el Home y solo se ve la ventanita del video.
  bool _isInPip = PipService.isInPipMode;
  StreamSubscription<bool>? _pipModeSub;

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

    _pipModeSub = PipService.pipModeStream.listen(_onPipModeChanged);
  }

  void _onPipModeChanged(bool isInPip) {
    if (!mounted) return;
    setState(() => _isInPip = isInPip);

    if (!isInPip) {
      // Al volver de la ventanita a pantalla completa, Android puede
      // resetear la barra de estado/navegación: la reponemos.
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
      debugPrint("MEDIA KIT STREAM ERROR: no se pudo abrir el stream");
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

      // El watchdog de salud de la reproducción se detiene al pasar a
      // segundo plano sin PiP (ver _handleAppPaused). Lo reactivamos acá
      // al volver a primer plano, para seguir detectando cortes reales
      // de transmisión mientras el usuario está mirando el canal.
      if (!_isReconnecting && !_playerError && !_isInitializingPlayer) {
        _startPlaybackWatchdog();
      }
      return;
    }

    if (state == AppLifecycleState.paused) {
      _handleAppPaused();
      return;
    }

    if (state == AppLifecycleState.detached) {
      _playbackWatchdog?.cancel();
      _reconnectDelayTimer?.cancel();
      _playerController.player.pause();
    }
  }

  Future<void> _handleAppPaused() async {
    await PipService.enterPictureInPicture();

    // Le damos un pequeño margen para que, si Android sí activó el
    // mini-reproductor (por ejemplo vía onUserLeaveHint nativo), el
    // aviso onPictureInPictureModeChanged llegue a Flutter antes de
    // decidir si pausamos.
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted || _isDisposed) return;

    if (!PipService.isInPipMode) {
      // El mini-reproductor no se activó (no soportado en este equipo,
      // el sistema lo rechazó, etc.): no dejamos el audio sonando de
      // fondo sin que el usuario vea nada. Se reanuda solo al volver
      // a la app gracias al bloque de AppLifecycleState.resumed.
      //
      // IMPORTANTE: también hay que detener el watchdog de reconexión
      // automática. Si se deja corriendo, a los pocos segundos detecta
      // que la posición está "congelada" (justamente porque acabamos de
      // pausar a propósito) y dispara una reconexión automática que
      // vuelve a abrir el stream y llama a play() — eso es lo que hacía
      // que, aunque la app quedara solo en "apps recientes" sin estar
      // visible ni con el mini-reproductor activo, el audio del canal
      // se volviera a escuchar solo unos segundos después.
      _playbackWatchdog?.cancel();
      _reconnectDelayTimer?.cancel();
      await _playerController.player.pause();
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

  // Cancelamos timers inmediatamente
    _playbackWatchdog?.cancel();
    _reconnectDelayTimer?.cancel();
    _hideControlsTimer?.cancel();

    // Restauramos la orientación YA, sin esperar a la limpieza de red
    // (detener el player, cerrar el proxy) que puede tardar. Antes esto
    // se hacía al final, así que la pantalla anterior se veía en
    // horizontal varios segundos hasta que esas llamadas terminaban.
    unawaited(_restoreOrientation());

    if (mounted) {
      Navigator.of(context).pop();
    }

  // 1. LIMPIEZA EN SEGUNDO PLANO (ya no bloquea la salida visual)
    try {
      await _playerController.player.pause();
      await _playerController.player.stop();
    } catch (e) {
      debugPrint('Error deteniendo player: $e');
    }

    try {
      await _service.stopProxy(
        streamId: widget.streamId,
      );
    } catch (e) {
      debugPrint('Error cerrando proxy: $e');
    }
  }

  Future<String> _getPlaybackUrl({required bool preferDirect}) async {
    if (preferDirect) {
      try {
        final directUrl = await _service.getStreamUrl(
          username: widget.username,
          password: widget.password,
          streamId: widget.streamId,
          output: 'ts',
        );

        debugPrint('✅ DIRECT STREAM URL OBTENIDA');
        return directUrl;
      } catch (e) {
        debugPrint('⚠️ No se pudo obtener stream directo. Usando proxy HLS.');
      }
    }

    final proxyUrl = await _service.getProxyStreamUrl(
      username: widget.username,
      password: widget.password,
      streamId: widget.streamId,
    );

    debugPrint('✅ PROXY HLS URL OBTENIDA');
    return proxyUrl;
  }

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
      await _playerController.player.stop();
      // Antes había una espera fija de 500ms "por las dudas" antes de
      // siquiera pedir la URL del canal. player.stop() ya se espera
      // (await) arriba, así que ese tiempo era puro tiempo muerto. Se
      // deja un margen chico (no cero) solo por seguridad.
      await Future.delayed(const Duration(milliseconds: 100));

      String streamUrl = '';
      bool urlObtained = false;
      int retries = 0;

      // 2. Bucle de persistencia
      while (!urlObtained && retries < _maxReconnectAttempts) {
        try {
          streamUrl = await _getPlaybackUrl(preferDirect: true);
          urlObtained = true; 
        } catch (e) {
          if (_isTransientStartupError(e)) {
            retries++;
            debugPrint("⚠️ INICIO NO LISTO AÚN (${_transientErrorReason(e)}). Reintento $retries de $_maxReconnectAttempts...");
            if (retries >= _maxReconnectAttempts) rethrow;
            await Future.delayed(const Duration(seconds: 2));
          } else {
            rethrow; 
          }
        }
      }

      debugPrint("✅ STREAM URL OBTENIDA");
      if (!mounted || _isDisposed) return;

      await _playerController.initializePlayer(streamUrl);

      if (_playerController.hasError) {
        _showPlayerError();
        return;
      }

      await _waitUntilVideoReady();
      if (!mounted || _isDisposed) return;

      _reconnectAttempts = 0;
      _startPlaybackWatchdog();

      if (mounted) {
        setState(() {
          _isInitializingPlayer = false;
          _playerError = false;
        });
      }
    } catch (e) {
      debugPrint('❌ ERROR FATAL PLAYER');
      if (!mounted || _isDisposed) return;
      _showPlayerError();
    }
  }

  // Espera a que el player realmente termine el buffering inicial y
  // tenga video listo para mostrar, en vez de solo esperar a que se
  // haya enviado el comando de reproducir. Sin esto, el spinner
  // desaparecía antes de que llegara el primer frame real, dejando un
  // instante de pantalla negra "vacía" (sin spinner y sin canal).
  // Tiene un tope de tiempo para no dejar el spinner pegado si el
  // aviso de "listo" nunca llega.
  Future<void> _waitUntilVideoReady() async {
    if (_playerController.player.state.buffering == false) return;

    final completer = Completer<void>();
    late final StreamSubscription<bool> sub;

    sub = _playerController.player.stream.buffering.listen((buffering) {
      if (!buffering && !completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      await completer.future.timeout(const Duration(seconds: 8));
    } catch (_) {
      // Tardó demasiado en avisar: mostramos el canal igual, es mejor
      // eso a dejar el "Cargando canal..." pegado indefinidamente.
    } finally {
      await sub.cancel();
    }
  }

  // Algunos errores del backend son transitorios (el proxy/transcoder
  // todavía está arrancando o generando los primeros segmentos HLS) y se
  // resuelven solos si se reintenta a los pocos segundos. Los detectamos
  // por el texto del mensaje para no tener que tocar el backend.
  bool _isTransientStartupError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('transcoder') ||
        msg.contains('segmento') ||
        msg.contains('segment') ||
        msg.contains('hls');
  }

  String _transientErrorReason(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('transcoder')) return 'transcoder ocupado';
    if (msg.contains('segmento') || msg.contains('segment') || msg.contains('hls')) {
      return 'segmentos HLS aún no listos';
    }
    return 'inicio no listo';
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
          newStreamUrl = await _getPlaybackUrl(preferDirect: false);
          urlObtained = true;
        } catch (e) {
          if (_isTransientStartupError(e)) {
            retries++;
            debugPrint("⚠️ RECONEXIÓN: ${_transientErrorReason(e)}. Reintento $retries...");
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

      await _waitUntilVideoReady();
      if (_isDisposed) return;

      _reconnectAttempts = 0;
      _startPlaybackWatchdog();
      if (mounted) {
        setState(() {
          _playerError = false;
          // El canal ya está reproduciendo con normalidad: había quedado
          // pegado en "Cargando canal..." porque este flag no se
          // reseteaba aquí (solo se reseteaba en la carga inicial).
          _isInitializingPlayer = false;
        });
      }
    } catch (e) {
      debugPrint('AUTOMATIC RECONNECT ERROR');
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
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.black.withValues(alpha: 0.75),
          elevation: 0,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          duration: const Duration(seconds: 2),
          content: const Row(
            children: [
              Icon(
                Icons.heart_broken_rounded,
                color: Colors.white70,
                size: 20,
              ),
              SizedBox(width: 10),
              Text(
                'Canal eliminado de favoritos',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          duration: const Duration(seconds: 2),
          content: const Row(
            children: [
              Icon(
                Icons.favorite_rounded,
                color: Colors.redAccent,
                size: 20,
              ),
              SizedBox(width: 10),
              Text(
                'Canal agregado a favoritos',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
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
    _playingSub?.cancel();
    _errorSub?.cancel();
    _playbackWatchdog?.cancel();
    _reconnectDelayTimer?.cancel();
    _hideControlsTimer?.cancel();
    _volumeHideTimer?.cancel();
    _brightnessHideTimer?.cancel();
    _pipModeSub?.cancel();
    WakelockPlus.disable();

    // Devolvemos el brillo del dispositivo a su valor original al salir.
    ScreenBrightness().resetApplicationScreenBrightness();

    _playerController.dispose();

    if (!_isClosingPlayer) {
      // Salida "no limpia": el sistema cerró la app o el mini-reproductor
      // (X del PiP, quitar la app de recientes, Android matando la
      // Activity) en vez de usar el botón de volver. El reproductor es
      // una instancia global compartida, así que si no se detiene aquí
      // explícitamente sigue sonando con lo que ya tenía en buffer
      // aunque la pantalla ya no exista.
      unawaited(_playerController.player.pause());
      unawaited(_playerController.player.stop());
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

        await _closePlayerAndExit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: (_locked || _isInPip) ? null : _toggleControls,
          onVerticalDragStart: (_locked || _isInPip) ? null : _handleVerticalDragStart,
          onVerticalDragUpdate: (_locked || _isInPip) ? null : _handleVerticalDragUpdate,
          onVerticalDragEnd: (_locked || _isInPip) ? null : _handleVerticalDragEnd,
          child: Stack(
            children: [
              // En modo mini-reproductor solo se ve el video, sin overlays.
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
              onPressed: _closePlayerAndExit,
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: AppColors.textPrimary,
              ),
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
                _isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: Colors.redAccent,
                size: 22,
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
  if (_isInitializingPlayer || _playerError) {
    return const SizedBox.shrink();
  }

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
  // correspondiente, y se oculta sola. El tamaño y el margen se calculan
  // según el tamaño real de la pantalla para que se vea bien en cualquier
  // equipo (teléfono chico, grande, tablet) y en landscape/portrait.
  // Diseño tipo "glass" con degradado de marca y porcentaje, en vez de
  // la barra plana anterior.
  // ---------------------------------------------------------------------
  Widget _buildVerticalIndicator({
    required Alignment alignment,
    required bool visible,
    required double value,
    required IconData icon,
  }) {
    final screenSize = MediaQuery.of(context).size;
    final safePadding = MediaQuery.of(context).padding;

    // Alto proporcional a la pantalla, con tope mínimo y máximo para que
    // no se vea gigante en tablets ni diminuta en teléfonos chicos.
    final barHeight = (screenSize.height * 0.36).clamp(140.0, 235.0);
    final barWidth = (screenSize.width * 0.05).clamp(36.0, 48.0);

    // Separación del borde: respeta el notch/cámara del lado
    // correspondiente (importante en landscape) más un margen mínimo.
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
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .14),
                    ),
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
                                      colors: [
                                        AppColors.accent,
                                        AppColors.primary,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: barHeight * 0.045),
                      Icon(
                        icon,
                        color: AppColors.textPrimary,
                        size: barWidth * 0.4,
                      ),
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
