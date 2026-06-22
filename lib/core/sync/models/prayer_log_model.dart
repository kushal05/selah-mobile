import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Domain model for PrayerLog
///
/// Records each time a user prays for a prayer item.
/// Logs are append-only in practice (never conflicted).
class PrayerLogModel implements SyncEntity {
  @override
  final String id;

  /// Reference to the prayer that was logged
  final String prayerId;

  /// Owner user ID
  final String userId;

  /// Optional note added when logging
  final String note;

  /// Timestamp when the prayer was logged (Unix milliseconds)
  final int loggedAt;

  /// Date string for the session (YYYY-MM-DD)
  final String sessionDate;

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

  const PrayerLogModel({
    required this.id,
    required this.prayerId,
    required this.userId,
    required this.note,
    required this.loggedAt,
    required this.sessionDate,
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
      'note': note,
      'loggedAt': loggedAt,
      'sessionDate': sessionDate,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
    };
  }

  factory PrayerLogModel.fromJson(Map<String, dynamic> json) {
    return PrayerLogModel(
      id: (json['id'] ?? json['_id']) as String,
      prayerId: json['prayerId'] as String,
      userId: json['userId'] as String,
      note: json['note'] as String? ?? '',
      loggedAt: json['loggedAt'] as int,
      sessionDate: json['sessionDate'] as String,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
    );
  }

  /// Create a new prayer log
  factory PrayerLogModel.create({
    required String id,
    required String prayerId,
    required String userId,
    String note = '',
    String? sessionDate,
  }) {
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final date = sessionDate ??
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return PrayerLogModel(
      id: id,
      prayerId: prayerId,
      userId: userId,
      note: note,
      loggedAt: nowMs,
      sessionDate: date,
      updatedAt: nowMs,
      version: 1,
      deleted: 0,
      createdAt: nowMs,
    );
  }

  /// Create updated copy with incremented version
  PrayerLogModel copyWithUpdate({
    String? note,
  }) {
    return PrayerLogModel(
      id: id,
      prayerId: prayerId,
      userId: userId,
      note: note ?? this.note,
      loggedAt: loggedAt,
      sessionDate: sessionDate,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  /// Create soft-deleted copy
  PrayerLogModel softDelete() {
    return PrayerLogModel(
      id: id,
      prayerId: prayerId,
      userId: userId,
      note: note,
      loggedAt: loggedAt,
      sessionDate: sessionDate,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 1,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  /// Move to trash (recoverable, cascade from parent)
  PrayerLogModel moveToTrash() {
    final now = TestClock.now();
    return PrayerLogModel(
      id: id,
      prayerId: prayerId,
      userId: userId,
      note: note,
      loggedAt: loggedAt,
      sessionDate: sessionDate,
      updatedAt: now,
      version: version + 1,
      deleted: deleted,
      trashedAt: now,
      createdAt: createdAt,
    );
  }

  /// Restore from trash
  PrayerLogModel restoreFromTrash() {
    return PrayerLogModel(
      id: id,
      prayerId: prayerId,
      userId: userId,
      note: note,
      loggedAt: loggedAt,
      sessionDate: sessionDate,
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
      other is PrayerLogModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() {
    return 'PrayerLogModel(id: $id, prayerId: $prayerId, sessionDate: $sessionDate, v$version)';
  }
}
