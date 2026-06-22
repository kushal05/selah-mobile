import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Domain model for PrayerUpdate
///
/// Stores a single update entry for a prayer item.
class PrayerUpdateModel implements SyncEntity {
  @override
  final String id;

  /// Reference to the parent prayer
  final String prayerId;

  /// User who created this update
  final String userId;

  /// Update text content
  final String content;

  @override
  final int updatedAt;

  @override
  final int version;

  /// Soft delete flag
  final int deleted;

  @override
  final int? trashedAt;

  /// Creation timestamp
  final int createdAt;

  const PrayerUpdateModel({
    required this.id,
    required this.prayerId,
    required this.userId,
    required this.content,
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
      'userId': userId,
      'content': content,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
    };
  }

  factory PrayerUpdateModel.fromJson(Map<String, dynamic> json) {
    return PrayerUpdateModel(
      id: (json['id'] ?? json['_id']) as String,
      prayerId: json['prayerId'] as String,
      userId: json['userId'] as String,
      content: json['content'] as String? ?? '',
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
    );
  }

  /// Create a new prayer update
  factory PrayerUpdateModel.create({
    required String id,
    required String prayerId,
    required String userId,
    required String content,
  }) {
    final now = TestClock.now();
    return PrayerUpdateModel(
      id: id,
      prayerId: prayerId,
      userId: userId,
      content: content,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
    );
  }

  /// Create updated copy with incremented version
  PrayerUpdateModel copyWithUpdate({
    String? content,
  }) {
    return PrayerUpdateModel(
      id: id,
      prayerId: prayerId,
      userId: userId,
      content: content ?? this.content,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  /// Create soft-deleted copy
  PrayerUpdateModel softDelete() {
    return PrayerUpdateModel(
      id: id,
      prayerId: prayerId,
      userId: userId,
      content: content,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 1,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  /// Move to trash (recoverable, cascade from parent)
  PrayerUpdateModel moveToTrash() {
    final now = TestClock.now();
    return PrayerUpdateModel(
      id: id,
      prayerId: prayerId,
      userId: userId,
      content: content,
      updatedAt: now,
      version: version + 1,
      deleted: deleted,
      trashedAt: now,
      createdAt: createdAt,
    );
  }

  /// Restore from trash
  PrayerUpdateModel restoreFromTrash() {
    return PrayerUpdateModel(
      id: id,
      prayerId: prayerId,
      userId: userId,
      content: content,
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
      other is PrayerUpdateModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() {
    return 'PrayerUpdateModel(id: $id, prayerId: $prayerId, v$version)';
  }
}
