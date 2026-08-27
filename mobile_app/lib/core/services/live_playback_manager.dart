// Ruta sugerida en el proyecto: lib/core/services/live_playback_manager.dart
//
// Ajustar los imports de abajo (LiveTvService, PipService, log_sanitizer)
// a la ubicación real de esos archivos en tu proyecto.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../features/live_tv/services/live_tv_service.dart';
import '../utils/log_sanitizer.dart';
import 'pip_service.dart';

/// Datos del canal actualmente cargado.
///
/// Se mantienen SOLO en memoria (nunca se imprimen ni se persisten acá)
/// porque incluyen usuario y contraseña, necesarios para reconstruir la
/// URL de streaming al reconectar o al cambiar de canal.
class LiveChannelInfo {
  final String username;
  final String password;
  final int streamId;
  final String channelName;
  final String? channelIcon;

  const LiveChannelInfo({
    required this.username,
    required this.password,
    required this.streamId,
    required this.channelName,
    this.channelIcon,
  });
}

enum PlaybackStatus { idle, loading, playing, reconnecting, error }

/// Motor de reproducción de TV en vivo, único para toda la app.
///
/// Importante para costos:
/// - Azure solo debe entregar datos ligeros y la URL directa.
/// - La reproducción pesada debe ir directo desde Xtream/NOC.
/// - Este manager NO debe caer automáticamente al proxy HLS de Azure.
class LivePlaybackManager extends ChangeNotifier with WidgetsBindingObserver {
  LivePlaybackManager._internal() {
    WidgetsBinding.instance.addObserver(this);
  }

  static final LivePlaybackManager instance = LivePlaybackManager._internal();

  final LiveTvService _service = LiveTvService();

  final Player player = Player(
    configuration: const PlayerConfiguration(
      bufferSize: 1024 * 1024 * 32, // 32MB de buffer
    ),
  );

  late final VideoController videoController = VideoController(player);

  static const int _maxAttempts = 5;

  LiveChannelInfo? _channel;
  LiveChannelInfo? get channel => _channel;

  PlaybackStatus _status = PlaybackStatus.idle;
  PlaybackStatus get status => _status;

  /// true mientras PlayerScreen está abierta a pantalla completa.
  bool _isFullScreenOpen = false;
  bool get isFullScreenOpen => _isFullScreenOpen;

  /// true cuando corresponde mostrar el mini-reproductor flotante.
  bool get showMiniPlayer => _channel != null && !_isFullScreenOpen;

  /// Cast/TV: oculto hasta que exista integración real.
  bool get castAvailable => false;

  /// Selector TV: oculto hasta que exista flujo real.
  bool get tvChannelSwitcherAvailable => false;

  /// Menú extra: oculto hasta que exista flujo real.
  bool get moreOptionsAvailable => false;

  StreamSubscription? _errorSub;
  Timer? _watchdog;
  Timer? _reconnectDelayTimer;

  int _attempts = 0;
  Duration _lastPosition = Duration.zero;
  DateTime _lastPositionChange = DateTime.now();

  bool _reconnecting = false;
  bool _closing = false;

  bool get isPlaying => player.state.playing;

  void _listenErrorsOnce() {
    _errorSub ??= player.stream.error.listen((_) {
      if (!_reconnecting && _channel != null) {
        _startReconnect();
      }
    });
  }

  void setFullScreenOpen(bool open) {
    if (_isFullScreenOpen == open) return;
    _isFullScreenOpen = open;
    notifyListeners();
  }

  Future<void> loadChannel(LiveChannelInfo info) async {
    _listenErrorsOnce();

    final previous = _channel;
    final sameChannel = previous?.streamId == info.streamId;

    if (!sameChannel && previous != null) {
      // Como ahora el flujo principal es DIRECTO a Xtream, no cerramos
      // proxy HLS automáticamente. Esto evita llamadas innecesarias a Azure.
      //
      // Si en el futuro se habilita un modo proxy manual, ahí sí convendría
      // guardar un flag para saber si el canal anterior usaba proxy o directo.
    }

    _channel = info;
    _closing = false;
    _status = PlaybackStatus.loading;
    notifyListeners();

    WakelockPlus.enable();

    // Habilita PiP nativo cuando hay un canal cargado.
    unawaited(PipService.setEnabled(true));

    if (sameChannel && player.state.playing) {
      _status = PlaybackStatus.playing;
      notifyListeners();
      _startWatchdog();
      return;
    }

    // IMPORTANTE:
    // Debe ir directo a Xtream. No usar proxy HLS de Azure por defecto.
    await _openStream(info, preferDirect: true);
  }

  Future<void> _openStream(
    LiveChannelInfo info, {
    required bool preferDirect,
  }) async {
    try {
      await player.stop();
      await Future.delayed(const Duration(milliseconds: 150));

      final url = await _resolveUrl(info, preferDirect: preferDirect);

      if (_channel?.streamId != info.streamId || _closing) return;

      await player.open(
        Media(
          url,
          httpHeaders: const {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36',
            'Accept': '*/*',
            'Connection': 'keep-alive',
          },
        ),
      );

      await player.play();
      await _waitUntilReady();

      if (_channel?.streamId != info.streamId || _closing) return;

      _attempts = 0;
      _status = PlaybackStatus.playing;
      notifyListeners();

      _startWatchdog();
    } catch (e) {
      debugPrint(
        'LivePlaybackManager: fallo al abrir el stream (${sanitizeForLog(e)})',
      );

      if (_channel?.streamId == info.streamId && !_closing) {
        _status = PlaybackStatus.error;
        notifyListeners();
      }
    }
  }

  Future<String> _resolveUrl(
    LiveChannelInfo info, {
    required bool preferDirect,
  }) async {
    int retries = 0;

    while (true) {
      try {
        // IMPORTANTE:
        // Solo pedimos al backend la URL directa.
        // El backend Azure responde una URL de Xtream.
        // La app reproduce el video directo desde Xtream/NOC.
        return await _service.getStreamUrl(
          username: info.username,
          password: info.password,
          streamId: info.streamId,
          output: 'ts',
        );
      } catch (e) {
        if (_isTransientStartupError(e) && retries < _maxAttempts - 1) {
          retries++;

          debugPrint(
            'LivePlaybackManager: stream directo no listo aún, reintento $retries',
          );

          await Future.delayed(const Duration(seconds: 4));
          continue;
        }

        rethrow;
      }
    }
  }

  bool _isTransientStartupError(Object e) {
    final msg = e.toString().toLowerCase();

    return msg.contains('timeout') ||
        msg.contains('connection') ||
        msg.contains('socket') ||
        msg.contains('network') ||
        msg.contains('abort') ||
        msg.contains('reset') ||
        msg.contains('failed host lookup') ||
        msg.contains('temporarily') ||
        msg.contains('no se pudo') ||
        msg.contains('no pudo');
  }

  // Espera a que el player realmente termine el buffering inicial.
  Future<void> _waitUntilReady() async {
    if (player.state.buffering == false) return;

    final completer = Completer<void>();
    late final StreamSubscription<bool> sub;

    sub = player.stream.buffering.listen((buffering) {
      if (!buffering && !completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      await completer.future.timeout(const Duration(seconds: 20));
    } catch (_) {
      // Tardó demasiado: se deja que el watchdog supervise.
    } finally {
      await sub.cancel();
    }
  }

  void _startWatchdog() {
    _watchdog?.cancel();
    _lastPosition = player.state.position;
    _lastPositionChange = DateTime.now();

    _watchdog = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkHealth(),
    );
  }

  void _checkHealth() {
    if (_closing || _reconnecting || _channel == null) return;

    final pos = player.state.position;

    if (pos != _lastPosition) {
      _lastPosition = pos;
      _lastPositionChange = DateTime.now();
      return;
    }

    if (DateTime.now().difference(_lastPositionChange) >=
        const Duration(seconds: 30)) {
      debugPrint(
        'LivePlaybackManager: reproducción congelada 30s, reconectando directo',
      );

      _startReconnect();
    }
  }

  Future<void> _startReconnect() async {
    if (_reconnecting || _closing || _channel == null) return;

    if (_attempts >= _maxAttempts) {
      _status = PlaybackStatus.error;
      notifyListeners();
      return;
    }

    _reconnecting = true;
    _attempts++;
    _watchdog?.cancel();
    _status = PlaybackStatus.reconnecting;
    notifyListeners();

    final info = _channel!;

    try {
      await player.stop();

      // No cerramos proxy porque el flujo principal ya no debe usar proxy Azure.
      await Future.delayed(const Duration(seconds: 2));

      if (_closing || _channel?.streamId != info.streamId) return;

      // Reconexión también directa a Xtream.
      await _openStream(info, preferDirect: true);
    } catch (e) {
      debugPrint(
        'LivePlaybackManager: fallo al reconectar (${sanitizeForLog(e)})',
      );

      _scheduleReconnectRetry();
    } finally {
      _reconnecting = false;
    }
  }

  void _scheduleReconnectRetry() {
    if (_closing) return;

    if (_attempts < _maxAttempts) {
      _reconnectDelayTimer?.cancel();
      _reconnectDelayTimer = Timer(
        const Duration(seconds: 4),
        _startReconnect,
      );
    } else {
      _status = PlaybackStatus.error;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (_channel == null) return;

    _attempts = 0;
    _status = PlaybackStatus.loading;
    notifyListeners();

    await _startReconnect();
  }

  void togglePlayPause() {
    player.playOrPause();
    notifyListeners();
  }

  /// El usuario salió de PlayerScreen con "volver": el canal sigue
  /// reproduciéndose en el mini-reproductor flotante.
  void minimizeToMiniPlayer() {
    setFullScreenOpen(false);
  }

  /// Cierra por completo la reproducción, mini-reproductor incluido.
  Future<void> closePlayback() async {
    _closing = true;
    _watchdog?.cancel();
    _reconnectDelayTimer?.cancel();

    _channel = null;
    _isFullScreenOpen = false;
    _status = PlaybackStatus.idle;
    notifyListeners();

    WakelockPlus.disable();
    unawaited(PipService.setEnabled(false));

    try {
      await player.pause();
      await player.stop();
    } catch (e) {
      debugPrint(
        'LivePlaybackManager: error deteniendo el player (${sanitizeForLog(e)})',
      );
    }

    // No llamamos stopProxy por defecto porque este flujo debe ser directo.
    _closing = false;
  }

  // -------------------------------------------------------------------
  // Ciclo de vida de la app
  // -------------------------------------------------------------------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_channel == null) return;

    if (state == AppLifecycleState.resumed) {
      if (_status != PlaybackStatus.error && !player.state.playing) {
        player.play();
      }

      if (!_reconnecting && _status != PlaybackStatus.error) {
        _startWatchdog();
      }

      return;
    }

    if (state == AppLifecycleState.paused) {
      _handleAppPaused();
      return;
    }

    if (state == AppLifecycleState.detached) {
      _watchdog?.cancel();
      _reconnectDelayTimer?.cancel();
      player.pause();
    }
  }

  Future<void> _handleAppPaused() async {
    if (_channel == null) return;

    await PipService.enterPictureInPicture();

    // Margen para que Android active PiP nativo si está disponible.
    await Future.delayed(const Duration(milliseconds: 300));

    if (_channel == null) return;

    if (!PipService.isInPipMode) {
      // Si PiP no se activó, no dejamos audio corriendo en segundo plano
      // sin video visible.
      _watchdog?.cancel();
      _reconnectDelayTimer?.cancel();
      await player.pause();
    }
  }
}