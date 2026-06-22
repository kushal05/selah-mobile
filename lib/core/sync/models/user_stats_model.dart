/// Read-only model for user statistics fetched from the server.
class UserStatsModel {
  final String userId;
  final int noteCount;
  final int prayerCount;
  final int totalStorageBytes;
  final int lastCalculatedAt;

  const UserStatsModel({
    required this.userId,
    required this.noteCount,
    required this.prayerCount,
    required this.totalStorageBytes,
    required this.lastCalculatedAt,
  });

  factory UserStatsModel.fromJson(Map<String, dynamic> json) {
    return UserStatsModel(
      userId: json['userId'] as String,
      noteCount: json['noteCount'] as int? ?? 0,
      prayerCount: json['prayerCount'] as int? ?? 0,
      totalStorageBytes: json['totalStorageBytes'] as int? ?? 0,
      lastCalculatedAt: json['lastCalculatedAt'] as int? ?? 0,
    );
  }

  /// Format totalStorageBytes as a human-readable string.
  String get formattedStorage {
    if (totalStorageBytes < 1024) return '$totalStorageBytes B';
    if (totalStorageBytes < 1024 * 1024) {
      return '${(totalStorageBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(totalStorageBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
