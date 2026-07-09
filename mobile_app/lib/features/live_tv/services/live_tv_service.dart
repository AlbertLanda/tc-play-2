class LiveTvService {
  Future<List<String>> getCategories() async {
    await Future.delayed(const Duration(milliseconds: 600));

//Categorías temporales, por el momento no hay un endpoint para obtenerlas desde el backend, 
//por lo que se retornan de manera local.
    return const [
      'Noticias',
      'Deportes',
      'Entretenimiento',
      'Películas',
      'Infantil',
      'Música',
      'Documentales',
      'Internacional',
    ];
  }

  Future<Map<String, dynamic>> getLiveTvData() async {
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
      ],
    };
  }
}