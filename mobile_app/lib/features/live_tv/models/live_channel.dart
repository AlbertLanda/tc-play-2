class LiveChannel {
  final int id;
  final String name;
  final String categoryId;
  final String? icon;
  final String streamType;

  const LiveChannel({
    required this.id,
    required this.name,
    required this.categoryId,
    this.icon,
    required this.streamType,
  });

  factory LiveChannel.fromJson(Map<String, dynamic> json) {
    return LiveChannel(
      id: int.tryParse(json['id'].toString()) ?? 0,
      name: json['name']?.toString() ?? 'Sin nombre',
      categoryId: json['category_id']?.toString() ?? '',
      icon: json['icon']?.toString() ??
            json['stream_icon']?.toString() ??
            json['logo']?.toString(),
      streamType: json['stream_type']?.toString() ?? 'live',
    );
  }
}