class FavoriteChannel {
  final int id;
  final String name;
  final String? icon;
  final String streamType;

  const FavoriteChannel({
    required this.id,
    required this.name,
    this.icon,
    required this.streamType,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'streamType': streamType,
    };
  }

  factory FavoriteChannel.fromJson(Map<String, dynamic> json) {
    return FavoriteChannel(
      id: json['id'],
      name: json['name'],
      icon: json['icon'],
      streamType: json['streamType'],
    );
  }
}