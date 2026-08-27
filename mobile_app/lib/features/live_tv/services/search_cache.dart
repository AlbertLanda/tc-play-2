import '../models/live_category.dart';
import '../models/live_channel.dart';
import 'live_tv_service.dart';

class SearchCache {
  static List<LiveCategory>? categories;
  static List<LiveChannel>? channels;

  // Carga en curso (si la hay), para no disparar la misma consulta de
  // red dos veces si dos pantallas la piden casi al mismo tiempo (por
  // ejemplo la precarga de Inicio y que el usuario abra Buscar antes de
  // que esa precarga termine).
  static Future<void>? _loadingFuture;

  static bool get hasData => categories != null && channels != null;

  static void clear() {
    categories = null;
    channels = null;
    _loadingFuture = null;
  }

  /// Se puede llamar apenas se entra a Inicio (antes de que el usuario
  /// toque la lupa) para dejar precargados los canales y categorías que
  /// usa la búsqueda. Así, cuando la pantalla de Buscar se abre, ya no
  /// tiene que esperar la primera consulta al servidor y el filtrado se
  /// siente instantáneo desde la primera letra, igual que en búsquedas
  /// posteriores.
  static Future<void> ensureLoaded(
    LiveTvService service, {
    required String username,
    required String password,
  }) {
    if (hasData) return Future.value();

    return _loadingFuture ??= _load(
      service,
      username: username,
      password: password,
    );
  }

  static Future<void> _load(
    LiveTvService service, {
    required String username,
    required String password,
  }) async {
    try {
      final loadedCategories = await service.getCategories(
        username: username,
        password: password,
      );

      // Se piden los canales de todas las categorías en paralelo (en
      // vez de uno por uno) para no acumular la latencia de cada
      // petición una tras otra.
      final channelLists = await Future.wait(
        loadedCategories.map(
          (category) => service.getChannels(
            username: username,
            password: password,
            categoryId: category.id,
          ),
        ),
      );

      categories = loadedCategories;
      channels = channelLists.expand((result) => result).toList();
    } catch (_) {
      // Si falló, no dejamos la caché "ocupada" para siempre: se
      // permite reintentar en el próximo llamado (por ejemplo cuando el
      // usuario efectivamente abra la pantalla de Buscar).
      _loadingFuture = null;
      rethrow;
    }
  }
}