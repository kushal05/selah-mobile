import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Domain model for PrayerTag junction (sync-enabled)
///
/// Each prayer-tag association has its own stable ID for oplog tracking.
class PrayerTagModel implements SyncEntity {
  @override
  final String id;

  final String prayerId;
  final String tagId;
  final String userId;

  @override
  final int updatedAt;

  @override
  final int version;

  final int deleted;

  @override
  final int? trashedAt;

  final int createdAt;

  const PrayerTagModel({
    required this.id,
    required this.prayerId,
    required this.tagId,
    required this.userId,
    required this.updatedAt,
    required this.version,
    required this.deleted,
    this.trashedAt,
    required this.createdAt,
  });

  @override
  bool get isDeleted => deleted == 1;

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'prayerId': prayerId,
      'tagId': tagId,
      'userId': userId,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
    };
  }

  factory PrayerTagModel.fromJson(Map<String, dynamic> json) {
    return PrayerTagModel(
      id: (json['id'] ?? json['_id']) as String,
      prayerId: json['prayerId'] as String,
      tagId: json['tagId'] as String,
      userId: json['userId'] as String,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
    );
  }

  factory PrayerTagModel.create({
    required String id,
    required String prayerId,
    required String tagId,
    required String userId,
  }) {
    final now = TestClock.now();
    return PrayerTagModel(
      id: id,
      prayerId: prayerId,
      tagId: tagId,
      userId: userId,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
    );
  }

  PrayerTagModel softDelete() {
    return PrayerTagModel(
      id: id,
      prayerId: prayerId,
      tagId: tagId,
      userId: userId,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 1,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  /// Move to trash (recoverable, cascade from parent)
  PrayerTagModel moveToTrash() {
    final now = TestClock.now();
    return PrayerTagModel(
      id: id,
      prayerId: prayerId,
      tagId: tagId,
      userId: userId,
      updatedAt: now,
      version: version + 1,
      deleted: deleted,
      trashedAt: now,
      createdAt: createdAt,
    );
  }

  /// Restore from trash
  PrayerTagModel restoreFromTrash() {
    return PrayerTagModel(
      id: id,
      prayerId: prayerId,
      tagId: tagId,
      userId: userId,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: null,
      createdAt: createdAt,
    );
  }

  /// Parses deleted flag that may be bool (from API) or int (from local DB).
  static int _parseDeleted(dynamic value) {
    if (value is bool) return value ? 1 : 0;
    if (value is int) return value;
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrayerTagModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;
}
