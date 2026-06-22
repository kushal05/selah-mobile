import 'dart:convert';

import 'sync_entity.dart';
import '../../domain/enums/prayer_enums.dart';
import '../../testing/test_clock.dart';

/// Domain model for Prayer
///
/// Stores prayer requests with tracking for frequency and status
class PrayerModel implements SyncEntity {
  @override
  final String id;

  /// Owner user ID
  final String userId;

  /// Prayer title/subject
  final String title;

  /// Full prayer content/description
  final String content;

  /// Prayer frequency for reminders
  final PrayerFrequency frequency;

  /// Prayer status (active, answered, archived)
  final PrayerStatus status;

  /// Optional category/tag
  final String? category;

  /// Reminder datetime (Unix milliseconds, nullable)
  final int? reminderAt;

  /// When the prayer was answered (null if not answered)
  final int? answeredAt;

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

  /// Per-field update timestamps for field-level merge.
  final Map<String, int> fieldUpdatedAt;

  /// Fields eligible for field-level merge.
  static const mergeableFields = [
    'title',
    'content',
    'frequency',
    'status',
    'category',
    'reminderAt',
    'answeredAt',
  ];

  const PrayerModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.content,
    required this.frequency,
    required this.status,
    this.category,
    this.reminderAt,
    this.answeredAt,
    required this.updatedAt,
    required this.version,
    required this.deleted,
    this.trashedAt,
    required this.createdAt,
    this.fieldUpdatedAt = const {},
  });

  @override
  bool get isDeleted => deleted == 1;

  /// Check if prayer is answered
  bool get isAnswered => status == PrayerStatus.answered;

  /// Check if prayer is active
  bool get isActive => status == PrayerStatus.active;

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'title': title,
      'content': content,
      'frequency': frequency.name,
      'status': status.name,
      'category': category,
      'reminderAt': reminderAt,
      'answeredAt': answeredAt,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
      'fieldUpdatedAt': fieldUpdatedAt,
    };
  }

  factory PrayerModel.fromJson(Map<String, dynamic> json) {
    return PrayerModel(
      id: (json['id'] ?? json['_id']) as String,
      userId: json['userId'] as String,
      title: json['title'] as String,
      content: json['content'] as String? ?? '',
      frequency: PrayerFrequency.values.firstWhere(
        (f) => f.name == json['frequency'],
        orElse: () => PrayerFrequency.daily,
      ),
      status: PrayerStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => PrayerStatus.active,
      ),
      category: json['category'] as String?,
      reminderAt: json['reminderAt'] as int?,
      answeredAt: json['answeredAt'] as int?,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
      fieldUpdatedAt: _parseFieldTimestamps(json['fieldUpdatedAt']),
    );
  }

  /// Create a new prayer
  factory PrayerModel.create({
    required String id,
    required String userId,
    required String title,
    String content = '',
    PrayerFrequency frequency = PrayerFrequency.asNeeded,
    PrayerStatus status = PrayerStatus.active,
    String? category,
    int? reminderAt,
  }) {
    final now = TestClock.now();
    return PrayerModel(
      id: id,
      userId: userId,
      title: title,
      content: content,
      frequency: frequency,
      status: status,
      category: category,
      reminderAt: reminderAt,
      answeredAt: null,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
      fieldUpdatedAt: {for (final f in mergeableFields) f: now},
    );
  }

  /// Create updated copy with incremented version
  PrayerModel copyWithUpdate({
    String? title,
    String? content,
    PrayerFrequency? frequency,
    PrayerStatus? status,
    String? category,
    bool clearCategory = false,
    int? reminderAt,
    bool clearReminderAt = false,
    int? answeredAt,
    bool clearAnsweredAt = false,
  }) {
    final now = TestClock.now();
    final newFieldTimestamps = Map<String, int>.from(fieldUpdatedAt);
    if (title != null) newFieldTimestamps['title'] = now;
    if (content != null) newFieldTimestamps['content'] = now;
    if (frequency != null) newFieldTimestamps['frequency'] = now;
    if (status != null) newFieldTimestamps['status'] = now;
    if (category != null || clearCategory) {
      newFieldTimestamps['category'] = now;
    }
    if (reminderAt != null || clearReminderAt) {
      newFieldTimestamps['reminderAt'] = now;
    }
    if (answeredAt != null || clearAnsweredAt) {
      newFieldTimestamps['answeredAt'] = now;
    }

    return PrayerModel(
      id: id,
      userId: userId,
      title: title ?? this.title,
      content: content ?? this.content,
      frequency: frequency ?? this.frequency,
      status: status ?? this.status,
      category: clearCategory ? null : (category ?? this.category),
      reminderAt: clearReminderAt ? null : (reminderAt ?? this.reminderAt),
      answeredAt: clearAnsweredAt ? null : (answeredAt ?? this.answeredAt),
      updatedAt: now,
      version: version + 1,
      deleted: deleted,
      trashedAt: trashedAt,
      createdAt: createdAt,
      fieldUpdatedAt: newFieldTimestamps,
    );
  }

  /// Mark prayer as answered
  PrayerModel markAnswered() {
    return copyWithUpdate(
      status: PrayerStatus.answered,
      answeredAt: TestClock.now(),
    );
  }

  /// Archive the prayer
  PrayerModel archive() {
    return copyWithUpdate(status: PrayerStatus.archived);
  }

  /// Create soft-deleted copy
  PrayerModel softDelete() {
    return PrayerModel(
      id: id,
      userId: userId,
      title: title,
      content: content,
      frequency: frequency,
      status: status,
      category: category,
      reminderAt: reminderAt,
      answeredAt: answeredAt,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 1,
      trashedAt: trashedAt,
      createdAt: createdAt,
      fieldUpdatedAt: fieldUpdatedAt,
    );
  }

  /// Move to trash (recoverable)
  PrayerModel moveToTrash() {
    final now = TestClock.now();
    return PrayerModel(
      id: id,
      userId: userId,
      title: title,
      content: content,
      frequency: frequency,
      status: status,
      category: category,
      reminderAt: reminderAt,
      answeredAt: answeredAt,
      updatedAt: now,
      version: version + 1,
      deleted: deleted,
      trashedAt: now,
      createdAt: createdAt,
      fieldUpdatedAt: fieldUpdatedAt,
    );
  }

  /// Restore from trash
  PrayerModel restoreFromTrash() {
    return PrayerModel(
      id: id,
      userId: userId,
      title: title,
      content: content,
      frequency: frequency,
      status: status,
      category: category,
      reminderAt: reminderAt,
      answeredAt: answeredAt,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: null,
      createdAt: createdAt,
      fieldUpdatedAt: fieldUpdatedAt,
    );
  }

  static Map<String, int> _parseFieldTimestamps(dynamic value) {
    if (value == null) return {};
    if (value is Map<String, dynamic>) {
      try {
        return value.map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {
        return {};
      }
    }
    if (value is String) {
      try {
        final decoded = jsonDecode(value) as Map<String, dynamic>;
        return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {
        return {};
      }
    }
    return {};
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
      other is PrayerModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() {
    return 'PrayerModel(id: $id, title: $title, status: $status, v$version)';
  }
}
