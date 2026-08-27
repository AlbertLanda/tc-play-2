class LiveCategory {
  final String id;
  final String name;

  const LiveCategory({
    required this.id,
    required this.name,
  });

  factory LiveCategory.fromJson(Map<String, dynamic> json) {
    return LiveCategory(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? 'Sin nombre',
    );
  }
}