import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../auth/screens/login_screen.dart';
import '../../auth/services/tv_session_service.dart';
import '../../device/screens/device_setup_screen.dart';
import '../../live_tv/models/live_category.dart';
import '../../live_tv/models/live_channel.dart';
import '../../live_tv/services/live_tv_service.dart';
import '../constants/tv_colors.dart';
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

  String? _focusedCategoryId;
  int? _focusedChannelId;
  bool _previewFocused = false;

  bool _loadingCategories = true;
  bool _loadingChannels = false;

  String? _error;

  // Mide en tiempo real dónde queda el hueco del video (mini panel
  // "EN VIVO" o pantalla completa) para posicionar el overlay nativo
  // exactamente ahí, en vez de coordenadas fijas de laboratorio.
  final GlobalKey _videoSlotKey = GlobalKey();

  // URL y canal que el overlay nativo tiene realmente cargados en
  // este momento (puede no coincidir todavía con _selectedChannel
  // mientras el debounce de zapping está en curso).
  String? _currentStreamUrl;
  int? _playingChannelId;

  // Cada llamada a _showNativeOverlay saca un número. Si al terminar
  // de esperar la red este número ya no es el más reciente, significa
  // que el usuario pidió otro canal mientras tanto y esta respuesta
  // llegó tarde: se descarta sin importar a qué canal pertenecía.
  // (Comparar solo por channel.id no bastaba: si el usuario avanzaba
  // dos canales seguidos, una respuesta vieja podía "ganarle" a la
  // más nueva y quedar reproduciendo un canal distinto al que el
  // banner ya mostraba.)
  int _streamRequestSeq = 0;

  bool _isFullscreen = false;
  final FocusNode _fullscreenFocusNode = FocusNode();

  // Evita lanzar varias búsquedas de "categoría siguiente" a la vez
  // si el usuario mantiene presionada la flecha justo al llegar al
  // final de la lista de canales.
  bool _categoryZapInFlight = false;

  @override
  void initState() {
    super.initState();

    WakelockPlus.enable();

    _loadCategories();
  }

  // ============================================================
  // OVERLAY: OCULTAR Y LIMPIAR ESTADO
  // ============================================================

  Future<void> _hideOverlay() async {
    // Envuelto en setState para que el logo de "cargando" reaparezca
    // en el hueco del video (mini panel o pantalla completa)
    // apenas se oculta el canal anterior.
    if (mounted) {
      setState(() {
        _currentStreamUrl = null;
        _playingChannelId = null;
      });
    } else {
      _currentStreamUrl = null;
      _playingChannelId = null;
    }

    await TvOverlayService.hide();
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
        await _hideOverlay();
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

      await _hideOverlay();
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
    await _hideOverlay();

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
        await _hideOverlay();
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingChannels = false;
        _channels = [];
        _selectedChannel = null;
      });

      await _hideOverlay();
    }
  }

  // ============================================================
  // SELECCIÓN MANUAL DE CANAL (mini panel "EN VIVO")
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
  // PANTALLA COMPLETA
  // ============================================================

  // El usuario navega hasta el mini reproductor "EN VIVO" y
  // presiona OK: ese es el gesto que expande el canal que ya se
  // está previsualizando a pantalla completa.
  void _openFullscreen(
    LiveChannel channel,
  ) {
    _channelDebounce?.cancel();
    _channelDebounce = null;

    // Si el canal ya se estaba reproduciendo en el mini panel,
    // no hace falta pedir la URL otra vez: solo re-posicionamos
    // el overlay a pantalla completa.
    final alreadyPlaying = _playingChannelId == channel.id;

    setState(() {
      _selectedChannel = channel;
      _isFullscreen = true;
    });

    if (alreadyPlaying) {
      _pushOverlayGeometry();
    } else {
      _showNativeOverlay(channel);
    }
  }

  void _closeFullscreen() {
    setState(() {
      _isFullscreen = false;
    });

    TvOverlayService.hideChannelBanner();
    _pushOverlayGeometry();
  }

  // ============================================================
  // ZAPPING (avanzar/retroceder canal en pantalla completa)
  // ============================================================

  Future<void> _advanceChannel(int delta) async {
    if (_channels.isEmpty || _selectedChannel == null) return;

    final currentIndex = _channels.indexWhere(
      (c) => c.id == _selectedChannel!.id,
    );

    final baseIndex = currentIndex == -1 ? 0 : currentIndex;
    final nextIndex = baseIndex + delta;

    // Todavía hay canales dentro de la categoría actual: caso normal.
    if (nextIndex >= 0 && nextIndex < _channels.length) {
      _zapToChannel(_channels[nextIndex]);
      return;
    }

    // Se acabaron los canales de esta categoría: seguimos el
    // zapping en la categoría siguiente/anterior, para que el
    // usuario pueda recorrer TODOS los canales sin interrupciones,
    // como en un decodificador real.
    await _zapToAdjacentCategory(delta);
  }

  // Busca, en la dirección del zapping, la próxima categoría que
  // tenga canales, y continúa ahí (primer canal si se avanza,
  // último canal si se retrocede). Salta categorías vacías y da la
  // vuelta completa a la lista si es necesario.
  Future<void> _zapToAdjacentCategory(int delta) async {
    if (_categoryZapInFlight) return;
    if (_categories.isEmpty || _selectedCategory == null) return;

    final categoryIndex = _categories.indexWhere(
      (c) => c.id == _selectedCategory!.id,
    );
    if (categoryIndex == -1) return;

    _categoryZapInFlight = true;

    final categoryCount = _categories.length;
    final step = delta > 0 ? 1 : -1;

    try {
      for (var offset = 1; offset <= categoryCount; offset++) {
        final rawIndex = categoryIndex + (step * offset);
        final normalizedIndex =
            ((rawIndex % categoryCount) + categoryCount) % categoryCount;

        final candidateCategory = _categories[normalizedIndex];

        _showCategoryZapBanner(candidateCategory);

        List<LiveChannel> candidateChannels;
        try {
          candidateChannels = await _service.getChannels(
            username: widget.username,
            password: widget.password,
            categoryId: candidateCategory.id,
          );
        } catch (e) {
          debugPrint('TV ZAP: error cargando ${candidateCategory.name}: $e');
          continue;
        }

        if (!mounted) return;
        if (candidateChannels.isEmpty) continue;

        // El usuario pudo haber salido de pantalla completa (o
        // vuelto a machucar la flecha) mientras esperábamos la red.
        if (!_isFullscreen) return;

        setState(() {
          _selectedCategory = candidateCategory;
          _channels = candidateChannels;
        });

        final target =
            delta > 0 ? candidateChannels.first : candidateChannels.last;

        _zapToChannel(target);
        return;
      }
    } finally {
      _categoryZapInFlight = false;
    }
  }

  void _showCategoryZapBanner(LiveCategory category) {
    final size = MediaQuery.of(context).size;
    final dpr = MediaQuery.of(context).devicePixelRatio;

    const bannerWidthDp = 380.0;
    const bannerHeightDp = 80.0;
    const marginDp = 32.0;

    TvOverlayService.showChannelBanner(
      title: category.name.toUpperCase(),
      subtitle: 'Cargando canales...',
      x: (marginDp * dpr).round(),
      y: ((size.height - bannerHeightDp - marginDp) * dpr).round(),
      width: (bannerWidthDp * dpr).round(),
      height: (bannerHeightDp * dpr).round(),
      autoHideMs: 0,
    );
  }

  void _zapToChannel(LiveChannel channel) {
    setState(() {
      _selectedChannel = channel;
    });

    // El banner se actualiza al instante, pero avisando que todavía
    // no es lo que está en pantalla: el video real tarda el
    // debounce + lo que demore la red, y antes se anunciaba un
    // canal como si ya estuviera al aire cuando en realidad seguía
    // mostrándose el anterior.
    _showZapBanner(channel, tuning: true);

    // Igual que en la navegación por la lista: si el usuario sigue
    // machucando la flecha, solo pedimos el stream del último canal
    // en el que se detuvo, para no saturar al backend de peticiones.
    _channelDebounce?.cancel();
    _channelDebounce = Timer(
      const Duration(milliseconds: 350),
      () {
        if (!mounted) return;

        if (_selectedChannel?.id != channel.id) return;

        _showNativeOverlay(channel);
      },
    );
  }

  void _showZapBanner(
    LiveChannel channel, {
    bool tuning = false,
  }) {
    final index = _channels.indexWhere((c) => c.id == channel.id);
    final position = index == -1 ? '' : '${index + 1}/${_channels.length}  ';
    final category = _selectedCategory?.name.toUpperCase() ?? '';

    final size = MediaQuery.of(context).size;
    final dpr = MediaQuery.of(context).devicePixelRatio;

    const bannerWidthDp = 380.0;
    const bannerHeightDp = 80.0;
    const marginDp = 32.0;

    TvOverlayService.showChannelBanner(
      title: '$position${channel.name}',
      subtitle: tuning ? 'Sintonizando...' : category,
      x: (marginDp * dpr).round(),
      y: ((size.height - bannerHeightDp - marginDp) * dpr).round(),
      width: (bannerWidthDp * dpr).round(),
      height: (bannerHeightDp * dpr).round(),
      // Mientras todavía no confirmamos que el video cambió, no lo
      // ocultamos solo por tiempo: se queda hasta que
      // _showNativeOverlay lo reemplace por la versión confirmada.
      autoHideMs: tuning ? 0 : 4000,
    );
  }

  KeyEventResult _handleFullscreenKey(
    FocusNode node,
    KeyEvent event,
  ) {
    if (!_isFullscreen) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowRight) {
      _advanceChannel(1);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      _advanceChannel(-1);
      return KeyEventResult.handled;
    }

    // El botón "Atrás" NO se maneja aquí a propósito.
    //
    // Antes lo interceptábamos también como tecla normal, además del
    // PopScope de más abajo. El control de la TV puede entregar una
    // sola pulsación por los dos canales casi al mismo tiempo: si
    // este handler la procesaba primero y cambiaba _isFullscreen a
    // false, el PopScope evaluaba la MISMA pulsación con canPop ya
    // en true y dejaba pasar el pop de la única ruta de la app,
    // cerrándola por completo segundos después de "volver bien".
    // PopScope es el mecanismo correcto y único para esto.

    return KeyEventResult.ignored;
  }

  // ============================================================
  // GEOMETRÍA DEL OVERLAY NATIVO
  //
  // El video nativo se posiciona exactamente sobre el hueco que
  // Flutter reserva para él (_videoSlotKey), sea el mini panel
  // "EN VIVO" o la pantalla completa. Así nunca se monta encima
  // del banner de publicidad ni de ningún otro panel.
  // ============================================================

  Rect? _measureVideoSlotRect() {
    final renderObject = _videoSlotKey.currentContext?.findRenderObject();

    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }

    final dpr = MediaQuery.of(context).devicePixelRatio;
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final size = renderObject.size;

    return Rect.fromLTWH(
      topLeft.dx * dpr,
      topLeft.dy * dpr,
      size.width * dpr,
      size.height * dpr,
    );
  }

  // En arranque en frío (justo al abrir la app) el primer frame
  // todavía puede no tener medidas listas para _videoSlotKey
  // (assets, fuentes, animaciones de entrada). Si eso pasa,
  // reintentamos en los siguientes frames en vez de rendirnos: sin
  // este reintento, el video quedaba invisible hasta que el usuario
  // tocaba manualmente un canal.
  static const int _maxGeometryRetries = 10;

  void _pushOverlayGeometry({int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final url = _currentStreamUrl;
      if (url == null) return;

      final rect = _measureVideoSlotRect();
      if (rect == null) {
        if (attempt < _maxGeometryRetries) {
          _pushOverlayGeometry(attempt: attempt + 1);
        }
        return;
      }

      TvOverlayService.showPlayer(
        url: url,
        x: rect.left.round(),
        y: rect.top.round(),
        width: rect.width.round().clamp(1, 1 << 20).toInt(),
        height: rect.height.round().clamp(1, 1 << 20).toInt(),
      );
    });
  }

  // ============================================================
  // OVERLAY NATIVO ANDROID
  // ============================================================

  Future<void> _showNativeOverlay(
    LiveChannel channel,
  ) async {
    final requestSeq = ++_streamRequestSeq;

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

      // Puede ocurrir que la URL tarde y el usuario ya haya pedido
      // otro canal (o dos) mientras tanto. En ese caso esta
      // respuesta quedó obsoleta y no debe pisar la más reciente.
      if (requestSeq != _streamRequestSeq) {
        debugPrint(
          'TV OVERLAY: URL descartada '
          '(canal=${channel.name}) porque ya hay una petición más '
          'reciente en curso.',
        );

        return;
      }

      debugPrint(
        'TV OVERLAY: reproduciendo '
        '${channel.name} (${channel.id})',
      );

      setState(() {
        _currentStreamUrl = url;
        _playingChannelId = channel.id;
      });

      // La geometría real (mini panel "EN VIVO" o pantalla completa)
      // se mide y se envía en _pushOverlayGeometry().
      _pushOverlayGeometry();

      // Recién ahora el canal mostrado en el banner de zapping
      // coincide de verdad con lo que está en pantalla: quitamos el
      // aviso de "Sintonizando..." y dejamos el banner normal.
      if (_isFullscreen && _selectedChannel?.id == channel.id) {
        _showZapBanner(channel, tuning: false);
      }
    } catch (e) {
      debugPrint(
        'TV OVERLAY ERROR: $e',
      );

      // Solo ocultamos si esta sigue siendo la petición más
      // reciente. Así un error atrasado de un canal anterior no
      // apaga accidentalmente el canal nuevo.
      if (mounted && requestSeq == _streamRequestSeq) {
        await _hideOverlay();
      }
    }
  }

  // ============================================================
  // CICLO DE VIDA
  // ============================================================

  @override
  void dispose() {
    _channelDebounce?.cancel();
    _channelDebounce = null;

    _fullscreenFocusNode.dispose();

    TvOverlayService.hideChannelBanner();
    _hideOverlay();

    WakelockPlus.disable();

    super.dispose();
  }

  // ============================================================
  // UI PRINCIPAL
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // El botón/gesto "Atrás" del control de TV no llega a Flutter
      // como una tecla normal: Android lo despacha directo como una
      // navegación de sistema. Sin este PopScope, presionarlo en
      // pantalla completa hacía pop de la única ruta de la app y la
      // cerraba. Aquí lo interceptamos para regresar al mini panel
      // en vez de salir.
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _closeFullscreen();
        }
      },
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_isFullscreen) {
      return _buildFullscreen();
    }

    if (_loadingCategories && _categories.isEmpty && _error == null) {
      return _buildInitialLoading();
    }

    return Scaffold(
      backgroundColor: TvColors.background,
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
  // CARGA INICIAL (splash con logo)
  // ============================================================

  Widget _buildInitialLoading() {
    // Igual que el splash del lado móvil: el logo solo, grande, sin
    // caja ni texto de estado. La imagen trae su propio fondo negro
    // puro, así que el Scaffold usa ESE MISMO negro (TvColors.background)
    // para que no se note el borde de la imagen como una calcomanía
    // pegada.
    return const Scaffold(
      backgroundColor: TvColors.background,
      body: Center(
        child: Image(
          image: AssetImage('assets/images/tc_play_logo.png'),
          height: 260,
        ),
      ),
    );
  }

  // ============================================================
  // PANTALLA COMPLETA
  // ============================================================

  Widget _buildFullscreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _fullscreenFocusNode,
        autofocus: true,
        onKeyEvent: _handleFullscreenKey,
        // El banner de canal y el video se dibujan de forma nativa
        // (ver TvOverlayService.showChannelBanner) porque el
        // SurfaceView del reproductor queda por encima de cualquier
        // widget de Flutter dibujado en esta misma zona. El logo de
        // marca se reserva para el arranque de la app (splash
        // inicial): repetirlo cada vez que se carga un canal se
        // siente repetitivo, así que aquí solo un spinner simple.
        child: Stack(
          children: [
            SizedBox.expand(key: _videoSlotKey),
            if (_currentStreamUrl == null)
              const Center(
                child: CircularProgressIndicator(
                  color: TvColors.accent,
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
              color: TvColors.error,
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
            color: TvColors.textSecondary,
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

        final focused =
            _focusedCategoryId == category.id;

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
              borderRadius: BorderRadius.circular(10),

              focusColor: TvColors.primary.withValues(
                alpha: .30,
              ),

              onFocusChange: (hasFocus) {
                setState(() {
                  _focusedCategoryId =
                      hasFocus ? category.id : null;
                });
              },

              onTap: () {
                _selectCategory(category);
              },

              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: focused
                      ? TvColors.accent.withValues(alpha: .22)
                      : selected
                          ? TvColors.primary.withValues(alpha: .28)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: focused
                        ? TvColors.accent
                        : selected
                            ? TvColors.primary
                            : Colors.transparent,
                    width: focused ? 3 : 2,
                  ),
                  boxShadow: focused
                      ? [
                          BoxShadow(
                            color: TvColors.accent.withValues(alpha: .45),
                            blurRadius: 16,
                            spreadRadius: 1,
                          ),
                        ]
                      : const [],
                ),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.play_arrow_rounded
                          : Icons.folder_outlined,
                      color: focused
                          ? TvColors.textPrimary
                          : selected
                              ? TvColors.accent
                              : TvColors.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        category.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: focused || selected
                              ? TvColors.textPrimary
                              : TvColors.textSecondary,
                          fontSize: 15,
                          fontWeight: focused || selected
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
            color: TvColors.textSecondary,
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
            color: TvColors.textSecondary,
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

        final focused =
            _focusedChannelId == channel.id;

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
                  TvColors.primary.withValues(
                alpha: .30,
              ),

              onFocusChange: (hasFocus) {
                setState(() {
                  _focusedChannelId =
                      hasFocus ? channel.id : null;
                });
              },

              onTap: () {
                _selectChannel(channel);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: focused
                      ? TvColors.accent.withValues(alpha: .22)
                      : selected
                          ? TvColors.primary.withValues(alpha: .28)
                          : Colors.transparent,

                  borderRadius: BorderRadius.circular(10),

                  border: Border.all(
                    color: focused
                        ? TvColors.accent
                        : selected
                            ? TvColors.primary
                            : Colors.transparent,
                    width: focused ? 3 : 2,
                  ),

                  boxShadow: focused
                      ? [
                          BoxShadow(
                            color: TvColors.accent.withValues(alpha: .45),
                            blurRadius: 16,
                            spreadRadius: 1,
                          ),
                        ]
                      : const [],
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
                              color: focused
                                  ? TvColors.textPrimary
                                  : selected
                                      ? TvColors.accent
                                      : TvColors.textSecondary,
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
          color: TvColors.textSecondary,
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
    final category = _selectedCategory;

    if (channel == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.live_tv_rounded,
              size: 70,
              color: TvColors.textSecondary,
            ),
            SizedBox(height: 18),
            Text(
              'Selecciona un canal',
              style: TextStyle(
                color: TvColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        18,
        8,
        18,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Espacio reservado para el SurfaceView nativo.
          //
          // Su posición real se mide con _videoSlotKey y se envía
          // al overlay nativo, así nunca se monta encima del banner
          // de publicidad de más abajo.
          //
          // Es enfocable: el usuario navega hasta aquí con el
          // control y presiona OK para expandir el canal que se
          // está previsualizando a pantalla completa. El borde de
          // foco se dibuja en el padding EXTERNO a _videoSlotKey a
          // propósito: cualquier cosa que Flutter dibuje encima del
          // rectángulo exacto del video queda oculta debajo del
          // SurfaceView nativo.
          Expanded(
            flex: 7,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                focusColor: TvColors.primary.withValues(alpha: .30),
                onFocusChange: (hasFocus) {
                  setState(() {
                    _previewFocused = hasFocus;
                  });
                },
                onTap: _selectedChannel == null
                    ? null
                    : () => _openFullscreen(_selectedChannel!),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _previewFocused
                          ? TvColors.accent
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    // Solo un spinner simple mientras carga: el logo
                    // de marca se reserva para el splash inicial de
                    // la app, no para cada cambio de canal.
                    child: Stack(
                      children: [
                        SizedBox.expand(key: _videoSlotKey),
                        if (_currentStreamUrl == null)
                          const Center(
                            child: CircularProgressIndicator(
                              color: TvColors.accent,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Información del canal actual.
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .22),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: .10),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Color(0xFF22C55E),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: TvColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (category != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          category.name.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: TvColors.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .8,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Text(
                  'EN VIVO',
                  style: TextStyle(
                    color: Color(0xFF22C55E),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          _buildPromoBanner(),
        ],
      ),
    );
  }

  Widget _buildPromoBanner() {
    return Container(
      height: 74,
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        // Degradado oscuro a propósito (no TvColors.primary/accent,
        // que son claros): el texto encima es blanco y necesita un
        // fondo oscuro para seguir siendo legible.
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1C1C1C),
            Color(0xFF3A3A3A),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: TvColors.accent.withValues(alpha: .35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.campaign_rounded,
              color: TvColors.textPrimary,
              size: 25,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nuevos planes disponibles',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: TvColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Conoce las promociones que tenemos para ti.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: TvColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12),
          Icon(
            Icons.arrow_forward_ios_rounded,
            color: TvColors.textPrimary,
            size: 15,
          ),
        ],
      ),
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
      color: TvColors.surface,
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
              color: TvColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          _buildTopBarButton(
            icon: Icons.person_outline_rounded,
            onTap: _showAccountDialog,
          ),
          const SizedBox(width: 20),
          _buildTopBarButton(
            icon: Icons.settings_outlined,
            onTap: _showDeviceSettingsDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildTopBarButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        focusColor: TvColors.primary.withValues(alpha: .35),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            color: TvColors.textSecondary,
            size: 28,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // DIÁLOGO DE CUENTA
  // ============================================================

  Future<void> _showAccountDialog() async {
    // El SurfaceView del video queda por encima de cualquier widget
    // de Flutter en su misma zona (ver setOverlayVisible): sin
    // ocultarlo primero, el diálogo se ve tapado por el mini video.
    await TvOverlayService.setOverlayVisible(false);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: TvColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const CircleAvatar(
                // Blanco sólido con ícono negro: TvColors.primary
                // (gris claro) no da suficiente contraste para un
                // ícono blanco encima.
                backgroundColor: TvColors.accent,
                child: Icon(
                  Icons.person_rounded,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.username,
                      style: const TextStyle(
                        color: TvColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Cuenta activa',
                      style: TextStyle(
                        color: Color(0xFF22C55E),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'CERRAR',
                style: TextStyle(color: TvColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _logout();
              },
              child: const Text(
                'CERRAR SESIÓN',
                style: TextStyle(
                  color: TvColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );

    // Si el diálogo terminó en "Cerrar sesión", la pantalla entera
    // está a punto de reemplazarse por LoginScreen: no hace falta
    // (ni conviene) volver a mostrar el video en ese caso.
    if (mounted && _selectedChannel != null) {
      await TvOverlayService.setOverlayVisible(true);
    }
  }

  Future<void> _logout() async {
    await TvSessionService.clearSession();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
      (route) => false,
    );
  }

  // ============================================================
  // DIÁLOGO DE CONFIGURACIÓN (cambiar tipo de dispositivo)
  // ============================================================

  Future<void> _showDeviceSettingsDialog() async {
    // Igual que en el diálogo de cuenta: el video queda por encima
    // de cualquier widget de Flutter en su misma zona.
    await TvOverlayService.setOverlayVisible(false);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: TvColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Configuración',
            style: TextStyle(color: TvColors.textPrimary),
          ),
          content: const Text(
            '¿Este dispositivo se configuró como el equivocado? '
            'Puedes cambiarlo entre celular/tablet o televisor.',
            style: TextStyle(color: TvColors.textSecondary),
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'CANCELAR',
                style: TextStyle(color: TvColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _changeDeviceProfile();
              },
              child: const Text(
                'CAMBIAR DISPOSITIVO',
                style: TextStyle(
                  color: TvColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );

    // Si se eligió "Cambiar dispositivo", la pantalla ya está siendo
    // reemplazada por DeviceSetupScreen: no hace falta re-mostrar el
    // video en ese caso.
    if (mounted && _selectedChannel != null) {
      await TvOverlayService.setOverlayVisible(true);
    }
  }

  void _changeDeviceProfile() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const DeviceSetupScreen(),
      ),
      (route) => false,
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
        color: TvColors.card,
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
                color: TvColors.textPrimary,
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