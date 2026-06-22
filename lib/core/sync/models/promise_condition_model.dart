import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Status of a promise condition
enum PromiseConditionStatus {
  active,
  met,
  notMet;

  String toDbValue() {
    switch (this) {
      case PromiseConditionStatus.active:
        return 'ACTIVE';
      case PromiseConditionStatus.met:
        return 'MET';
      case PromiseConditionStatus.notMet:
        return 'NOT_MET';
    }
  }

  static PromiseConditionStatus fromDbValue(String value) {
    switch (value.toUpperCase()) {
      case 'ACTIVE':
        return PromiseConditionStatus.active;
      case 'MET':
        return PromiseConditionStatus.met;
      case 'NOT_MET':
        return PromiseConditionStatus.notMet;
      default:
        return PromiseConditionStatus.active;
    }
  }
}

/// Domain model for a structured promise condition
class PromiseConditionModel implements SyncEntity {
  @override
  final String id;

  /// Foreign key to promises table
  final String promiseId;

  /// Owner user ID
  final String userId;

  /// Condition description text
  final String description;

  /// Optional notes about this condition
  final String notes;

  /// Status: ACTIVE, MET, NOT_MET
  final PromiseConditionStatus status;

  @override
  final int updatedAt;

  @override
  final int version;

  final int deleted;

  @override
  final int? trashedAt;

  final int createdAt;

  const PromiseConditionModel({
    required this.id,
    required this.promiseId,
    required this.userId,
    required this.description,
    required this.notes,
    required this.status,
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
      'promiseId': promiseId,
      'userId': userId,
      'description': description,
      'notes': notes,
      'status': status.toDbValue(),
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
    };
  }

  factory PromiseConditionModel.fromJson(Map<String, dynamic> json) {
    return PromiseConditionModel(
      id: (json['id'] ?? json['_id']) as String,
      promiseId: json['promiseId'] as String,
      userId: json['userId'] as String,
      description: json['description'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      status: PromiseConditionStatus.fromDbValue(
        json['status'] as String? ?? 'ACTIVE',
      ),
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
    );
  }

  factory PromiseConditionModel.create({
    required String id,
    required String promiseId,
    required String userId,
    required String description,
    String notes = '',
    PromiseConditionStatus status = PromiseConditionStatus.active,
  }) {
    final now = TestClock.now();
    return PromiseConditionModel(
      id: id,
      promiseId: promiseId,
      userId: userId,
      description: description,
      notes: notes,
      status: status,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
    );
  }

  PromiseConditionModel copyWithUpdate({
    String? description,
    String? notes,
    PromiseConditionStatus? status,
  }) {
    return PromiseConditionModel(
      id: id,
      promiseId: promiseId,
      userId: userId,
      description: description ?? this.description,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  PromiseConditionModel softDelete() {
    return PromiseConditionModel(
      id: id,
      promiseId: promiseId,
      userId: userId,
      description: description,
      notes: notes,
      status: status,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 1,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  /// Move to trash (recoverable, cascade from parent)
  PromiseConditionModel moveToTrash() {
    final now = TestClock.now();
    return PromiseConditionModel(
      id: id,
      promiseId: promiseId,
      userId: userId,
      description: description,
      notes: notes,
      status: status,
      updatedAt: now,
      version: version + 1,
      deleted: deleted,
      trashedAt: now,
      createdAt: createdAt,
    );
  }

  /// Restore from trash
  PromiseConditionModel restoreFromTrash() {
    return PromiseConditionModel(
      id: id,
      promiseId: promiseId,
      userId: userId,
      description: description,
      notes: notes,
      status: status,
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
      other is PromiseConditionModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() {
    return 'PromiseConditionModel(id: $id, promiseId: $promiseId, '
        'status: ${status.toDbValue()}, v$version)';
  }
}
