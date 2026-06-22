import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Domain model for a daily habit check-in.
///
/// Represents one completed habit for one day. Synced across devices
/// via the oplog system (entity type: 'habit_log').
class HabitLogModel implements SyncEntity {
  @override
  final String id;

  /// Owner user ID
  final String userId;

  /// Habit type key: 'bible' | 'meditation' | 'journal'
  final String habitType;

  /// UTC midnight timestamp (ms) for the day — used for streak calculation
  final int dateDay;

  /// Creation timestamp (ms)
  final int createdAt;

  @override
  final int updatedAt;

  @override
  final int version;

  /// Soft delete flag (0 = active, 1 = deleted)
  final int deleted;

  @override
  final int? trashedAt;

  const HabitLogModel({
    required this.id,
    required this.userId,
    required this.habitType,
    required this.dateDay,
    required this.createdAt,
    required this.updatedAt,
    required this.version,
    required this.deleted,
    this.trashedAt,
  });

  @override
  bool get isDeleted => deleted == 1;

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'habitType': habitType,
      'dateDay': dateDay,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
    };
  }

  factory HabitLogModel.fromJson(Map<String, dynamic> json) {
    return HabitLogModel(
      id: (json['id'] ?? json['_id']) as String,
      userId: json['userId'] as String,
      habitType: json['habitType'] as String,
      dateDay: json['dateDay'] as int,
      createdAt: json['createdAt'] as int,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
    );
  }

  /// Create a new habit log model for insertion.
  factory HabitLogModel.create({
    required String id,
    required String userId,
    required String habitType,
    required int dateDay,
  }) {
    final now = TestClock.now();
    return HabitLogModel(
      id: id,
      userId: userId,
      habitType: habitType,
      dateDay: dateDay,
      createdAt: now,
      updatedAt: now,
      version: 1,
      deleted: 0,
    );
  }

  /// Create soft-deleted copy (increments version).
  HabitLogModel softDelete() {
    return HabitLogModel(
      id: id,
      userId: userId,
      habitType: habitType,
      dateDay: dateDay,
      createdAt: createdAt,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 1,
      trashedAt: trashedAt,
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
      other is HabitLogModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() =>
      'HabitLogModel(id: $id, habitType: $habitType, dateDay: $dateDay, v$version)';
}
