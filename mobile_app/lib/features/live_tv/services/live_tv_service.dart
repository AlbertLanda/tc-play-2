class LiveTvService {
  static const String _baseUrl = 'https://api.telecable.example.com';
  static const String _categoriesEndpoint = '/api/live-tv/categories';

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
}
