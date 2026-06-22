import 'package:drift/drift.dart';

/// Feedback messages table schema
/// Stores individual messages within a feedback thread (chat-style)
///
/// Per spec: soft delete only - no hard deletes
class FeedbackMessages extends Table {
  /// Primary key - stable UUID (never changes)
  TextColumn get id => text()();

  /// Parent thread ID (FK to feedback_threads)
  TextColumn get threadId => text()();

  /// Author user ID (user or admin)
  TextColumn get userId => text()();

  /// Message content
  TextColumn get message => text()();

  /// Sender type: 'user', 'admin', or 'system'
  TextColumn get senderType => text()();

  /// Whether this message has attachments (0 = no, 1 = yes)
  IntColumn get hasAttachments =>
      integer().withDefault(const Constant(0))();

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
