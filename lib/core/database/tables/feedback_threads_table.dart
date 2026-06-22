import 'package:drift/drift.dart';

/// Feedback threads table schema
/// Stores user feedback/support threads with category, status, priority,
/// and device metadata for debugging.
///
/// Per spec: soft delete only - no hard deletes
class FeedbackThreads extends Table {
  /// Primary key - stable UUID (never changes)
  TextColumn get id => text()();

  /// Owner user ID
  TextColumn get userId => text()();

  /// Feedback category (bug, feature_request, ui_issue, performance, account, content, other)
  TextColumn get category => text()();

  /// Thread subject/title
  TextColumn get subject => text()();

  /// Thread status (open, in_progress, waiting_for_user, resolved, closed)
  TextColumn get status => text().withDefault(const Constant('open'))();

  /// Thread priority (low, medium, high, critical) — set by admin
  TextColumn get priority => text().withDefault(const Constant('medium'))();

  /// Timestamp of the last message in this thread (Unix milliseconds, nullable)
  IntColumn get lastMessageAt => integer().nullable()();

  /// Admin assigned to this thread (nullable)
  TextColumn get adminAssigned => text().nullable()();

  /// Count of unread messages for user (set by admin actions via sync)
  IntColumn get unreadForUser =>
      integer().withDefault(const Constant(0))();

  /// Count of unread messages for admin (incremented on user send)
  IntColumn get unreadForAdmin =>
      integer().withDefault(const Constant(0))();

  /// Device model string captured at thread creation (e.g. "Pixel 7 Pro")
  TextColumn get deviceModel => text().nullable()();

  /// OS version captured at thread creation (e.g. "Android 14", "iOS 17.2")
  TextColumn get osVersion => text().nullable()();

  /// App version captured at thread creation (e.g. "1.2.3+45")
  TextColumn get appVersion => text().nullable()();

  /// Last update timestamp (Unix milliseconds)
  IntColumn get updatedAt => integer()();

  /// Version number for optimistic locking
  IntColumn get version => integer().withDefault(const Constant(1))();

  /// Soft delete flag (0 = active, 1 = deleted)
  IntColumn get deleted => integer().withDefault(const Constant(0))();

  /// Creation timestamp (Unix milliseconds)
  IntColumn get createdAt => integer()();

  /// Per-field update timestamps for field-level merge conflict resolution.
  TextColumn get fieldUpdatedAt =>
      text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};
}
