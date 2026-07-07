class LiveTvService {
  Future<List<String>> getCategories() async {
    await Future.delayed(const Duration(milliseconds: 500));

    return [
      'Deportes',
      'Noticias',
      'Películas',
      'Series',
      'Infantil',
      'Música',
      'Documentales',
    ];
  }
}