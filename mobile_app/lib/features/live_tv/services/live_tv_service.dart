class LiveTvService {
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