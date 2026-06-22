import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Domain model for Tag (sync-enabled)
class TagModel implements SyncEntity {
  @override
  final String id;

  final String userId;
  final String name;

  @override
  final int updatedAt;

  @override
  final int version;

  final int deleted;

  @override
  final int? trashedAt;

  final int createdAt;

  const TagModel({
    required this.id,
    required this.userId,
    required this.name,
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
      'userId': userId,
      'name': name,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
    };
  }

  factory TagModel.fromJson(Map<String, dynamic> json) {
    return TagModel(
      id: (json['id'] ?? json['_id']) as String,
      userId: json['userId'] as String,
      name: json['name'] as String,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
    );
  }

  factory TagModel.create({
    required String id,
    required String userId,
    required String name,
  }) {
    final now = TestClock.now();
    return TagModel(
      id: id,
      userId: userId,
      name: name,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
    );
  }

  TagModel copyWithUpdate({String? name}) {
    return TagModel(
      id: id,
      userId: userId,
      name: name ?? this.name,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  TagModel softDelete() {
    return TagModel(
      id: id,
      userId: userId,
      name: name,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 1,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  /// Move to trash (recoverable)
  TagModel moveToTrash() {
    final now = TestClock.now();
    return TagModel(
      id: id,
      userId: userId,
      name: name,
      updatedAt: now,
      version: version + 1,
      deleted: deleted,
      trashedAt: now,
      createdAt: createdAt,
    );
  }

  /// Restore from trash
  TagModel restoreFromTrash() {
    return TagModel(
      id: id,
      userId: userId,
      name: name,
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
      other is TagModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;
}
