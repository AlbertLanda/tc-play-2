class RecentChannel {
  final int id;
  final String name;
  final String? icon;
  final String streamType;

  const RecentChannel({
    required this.id,
    required this.name,
    this.icon,
    required this.streamType,
  });

  factory RecentChannel.fromJson(Map<String, dynamic> json) {
    return RecentChannel(
      id: json['id'] as int,
      name: json['name'] as String,
      icon: json['icon'] as String?,
      streamType: json['streamType'] as String? ?? 'live',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'streamType': streamType,
    };
  }
}