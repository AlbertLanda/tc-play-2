class LiveTvService {
  //static const String _baseUrl = 'https://api.telecable.example.com';
 // static const String _categoriesEndpoint = '/api/live-tv/categories';

  Future<List<String>> getCategories() async {
    await Future.delayed(const Duration(milliseconds: 600));

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
    await Future.delayed(const Duration(milliseconds: 600));

    return {
      "currentChannel": {
        "number": "001",
        "name": "TC Noticias HD",
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
          "name": "TC Infantil",
        },
        {
          "number": "005",
          "name": "TC Música",
        },
      ],
    };
  }
}