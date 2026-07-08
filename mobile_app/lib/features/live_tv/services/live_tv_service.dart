class LiveTvService {
  // ============================================================
  // TODO:
  // Consumir el endpoint real del backend cuando esté disponible.
  // GET /api/live-tv/current
  // GET /api/live-tv/channels
  // ============================================================

  Future<Map<String, dynamic>> getLiveTvData() async {
    // Simula la carga del servidor.
    await Future.delayed(const Duration(seconds: 2));

    return {
      "currentChannel": {
        "number": "001",
        "name": "TC Noticias HD",
        "isLive": true,
      },
      "channels": [
        {
          "number": "001",
          "name": "TC Noticias HD",
        },
        {
          "number": "002",
          "name": "TC Deportes HD",
        },
        {
          "number": "003",
          "name": "TC Películas",
        },
        {
          "number": "004",
          "name": "TC Música",
        },
        {
          "number": "005",
          "name": "TC Infantil",
        },
      ]
    };
  }
}