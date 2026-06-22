class DeviceModel {
  final String id;
  final String name;
  final String platform;
  final String? appVersion;
  final DateTime createdAt;
  final DateTime lastActiveAt;

  const DeviceModel({
    required this.id,
    required this.name,
    required this.platform,
    this.appVersion,
    required this.createdAt,
    required this.lastActiveAt,
  });

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Unknown Device',
      platform: json['platform'] as String? ?? 'unknown',
      appVersion: json['appVersion'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      lastActiveAt:
          DateTime.fromMillisecondsSinceEpoch(json['lastActiveAt'] as int),
    );
  }
}
