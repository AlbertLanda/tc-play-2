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
/// Por qué existe: antes esta lógica (player, watchdog de salud,
/// reconexión automática, manejo del ciclo de vida de la app) vivía
/// dentro del State de PlayerScreen. Eso significaba que se destruía por
/// completo cada vez que esa pantalla se cerraba, así que no había forma
/// de mantener un canal sonando/visible en un mini-reproductor mientras
/// el usuario navegaba por el resto de la app: al hacer "volver", todo
/// se cortaba junto con la pantalla.
///
/// Ahora todo eso vive acá, en un singleton que existe durante toda la
/// vida de la app. PlayerScreen (pantalla completa) y MiniPlayerOverlay
/// (mini-reproductor flotante dentro de la app) son solo "vistas": leen
/// el estado de este manager y controlan el mismo Player real, en vez de
/// tener cada una su propia instancia.
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

  static const int _maxAttempts = 3;

  LiveChannelInfo? _channel;
  LiveChannelInfo? get channel => _channel;

  PlaybackStatus _status = PlaybackStatus.idle;
  PlaybackStatus get status => _status;

  /// true mientras PlayerScreen está abierta a pantalla completa. El
  /// mini-reproductor flotante debe permanecer oculto en ese caso, para
  /// no mostrar el mismo video duplicado.
  bool _isFullScreenOpen = false;
  bool get isFullScreenOpen => _isFullScreenOpen;

  /// true cuando corresponde MOSTRAR el mini-reproductor flotante: hay
  /// un canal cargado y la pantalla completa no está abierta.
  bool get showMiniPlayer => _channel != null && !_isFullScreenOpen;

  /// Cast/TV: solo debe habilitarse cuando exista una integración real
  /// (Chromecast, AirPlay, DLNA, etc.) con un flujo funcional. Hasta que
  /// eso exista, se deja en false para no mostrar un botón que en
  /// realidad no hace nada.
  bool get castAvailable => false;

  /// Selector de "TV" (por ejemplo, cambiar de canal sin salir del
  /// player). Mismo criterio que castAvailable: false hasta que haya
  /// una función real detrás.
  bool get tvChannelSwitcherAvailable => false;

  /// Menú de opciones adicionales del player (calidad, audio, etc.).
  /// Mismo criterio: false hasta que haya una función real detrás.
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

  /// Lo llama PlayerScreen en initState/dispose para avisar si está
  /// montada a pantalla completa o no. Esto solo decide si se muestra
  /// el mini-reproductor PROPIO (Flutter) en el resto de la app; el
  /// permiso de PiP nativo se maneja aparte (ver [loadChannel] /
  /// [closePlayback]), porque gracias a `PipOverlayRoot` ya es seguro
  /// activarlo sin importar en qué pantalla esté el usuario.
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
      // Cambio de canal real (por ejemplo, se eligió otro canal desde la
      // lista mientras el mini-reproductor mostraba uno distinto):
      // cerramos el proxy del canal anterior en segundo plano para no
      // dejarlo abierto sin uso.
      unawaited(
        _service.stopProxy(streamId: previous.streamId).catchError((_) {}),
      );
    }

    _channel = info;
    _closing = false;
    _status = PlaybackStatus.loading;
    notifyListeners();
    WakelockPlus.enable();

    // Habilita el PiP nativo apenas hay un canal cargado, sin importar
    // en qué pantalla de la app esté el usuario: si más adelante se va
    // a Home o cambia de app, `PipOverlayRoot` se encarga de que el PiP
    // muestre solo el video. Si NO hay ningún canal cargado (usuario
    // navegando la app sin haber abierto nada), esto nunca se llama, y
    // por lo tanto `onUserLeaveHint` en el lado nativo no hace nada.
    unawaited(PipService.setEnabled(true));

    if (sameChannel && player.state.playing) {
      // Ya está reproduciendo este mismo canal — por ejemplo, se volvió
      // a abrir PlayerScreen a pantalla completa desde el
      // mini-reproductor. No hace falta pedir la URL de nuevo ni
      // reiniciar el stream, solo seguir mostrando lo que ya hay.
      _status = PlaybackStatus.playing;
      notifyListeners();
      _startWatchdog();
      return;
    }

    await _openStream(info, preferDirect: true);
  }

  Future<void> _openStream(
    LiveChannelInfo info, {
    required bool preferDirect,
  }) async {
    try {
      await player.stop();
      await Future.delayed(const Duration(milliseconds: 100));

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
      if (_channel?.streamId == info.streamId) {
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
        if (preferDirect) {
          try {
            return await _service.getStreamUrl(
              username: info.username,
              password: info.password,
              streamId: info.streamId,
              output: 'ts',
            );
          } catch (_) {
            // Sin stream directo disponible: se sigue con el proxy HLS.
          }
        }
        return await _service.getProxyStreamUrl(
          username: info.username,
          password: info.password,
          streamId: info.streamId,
        );
      } catch (e) {
        if (_isTransientStartupError(e) && retries < _maxAttempts - 1) {
          retries++;
          debugPrint(
            'LivePlaybackManager: inicio no listo aún, reintento $retries',
          );
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        rethrow;
      }
    }
  }

  bool _isTransientStartupError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('transcoder') ||
        msg.contains('segmento') ||
        msg.contains('segment') ||
        msg.contains('hls');
  }

  // Espera a que el player realmente termine el buffering inicial, en
  // vez de solo esperar a que se haya mandado el comando de reproducir.
  // Tiene un tope de tiempo para no dejar el estado "cargando" pegado si
  // el aviso de "listo" nunca llega.
  Future<void> _waitUntilReady() async {
    if (player.state.buffering == false) return;
    final completer = Completer<void>();
    late final StreamSubscription<bool> sub;
    sub = player.stream.buffering.listen((buffering) {
      if (!buffering && !completer.isCompleted) completer.complete();
    });
    try {
      await completer.future.timeout(const Duration(seconds: 8));
    } catch (_) {
      // Tardó demasiado: se muestra el canal igual.
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
      debugPrint('LivePlaybackManager: reproducción congelada 30s, reconectando');
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
      try {
        await _service.stopProxy(streamId: info.streamId);
      } catch (_) {}

      await Future.delayed(const Duration(seconds: 1));
      if (_closing || _channel?.streamId != info.streamId) return;

      await _openStream(info, preferDirect: false);
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
      _reconnectDelayTimer = Timer(const Duration(seconds: 2), _startReconnect);
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
  /// reproduciéndose, ahora en el mini-reproductor flotante (dentro de
  /// la app). No detiene nada.
  void minimizeToMiniPlayer() {
    setFullScreenOpen(false);
  }

  /// Cierra por completo la reproducción, mini-reproductor incluido.
  /// Se usa cuando el usuario cierra explícitamente el mini-reproductor,
  /// o cuando se agotó la reconexión automática y elige salir.
  Future<void> closePlayback() async {
    _closing = true;
    _watchdog?.cancel();
    _reconnectDelayTimer?.cancel();
    final info = _channel;
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
    if (info != null) {
      try {
        await _service.stopProxy(streamId: info.streamId);
      } catch (e) {
        debugPrint(
          'LivePlaybackManager: error cerrando el proxy (${sanitizeForLog(e)})',
        );
      }
    }
    _closing = false;
  }

  // -------------------------------------------------------------------
  // Ciclo de vida de la app: decide cuándo pedir PiP nativo o pausar de
  // forma controlada. Vive acá (y no en PlayerScreen) porque tiene que
  // seguir funcionando aunque el usuario ya haya salido de esa pantalla
  // y solo quede el mini-reproductor flotante activo.
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

    // Se pide PiP nativo sin importar en qué pantalla de la app esté el
    // usuario (PlayerScreen a pantalla completa, u otra sección con el
    // mini-reproductor propio flotando): `PipOverlayRoot` se encarga de
    // que, mientras el PiP esté activo, Flutter solo dibuje el video,
    // así que ya no importa qué hubiera debajo en el momento de entrar.
    await PipService.enterPictureInPicture();

    // Margen para que, si Android sí activó el PiP nativo (por ejemplo
    // vía onUserLeaveHint), el aviso llegue antes de decidir si pausamos.
    await Future.delayed(const Duration(milliseconds: 300));

    if (_channel == null) return;

    if (!PipService.isInPipMode) {
      // El PiP nativo no se activó (no soportado, rechazado por el
      // sistema, etc.): no dejamos audio sonando de fondo sin nada
      // visible. Se reanuda solo al volver a la app (bloque "resumed").
      //
      // También se detiene el watchdog: si sigue corriendo, a los pocos
      // segundos detecta la posición "congelada" (porque acabamos de
      // pausar a propósito) y dispara una reconexión automática que
      // vuelve a poner audio sin que el usuario vea nada.
      _watchdog?.cancel();
      _reconnectDelayTimer?.cancel();
      await player.pause();
    }
  }
}