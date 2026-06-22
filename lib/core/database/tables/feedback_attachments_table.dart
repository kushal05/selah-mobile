import 'package:drift/drift.dart';

/// Feedback attachments table schema
/// Stores file/image/video attachments linked to feedback messages.
/// Actual files are stored in Cloudflare R2; this table stores metadata + URL.
///
/// Per spec: soft delete only - no hard deletes
class FeedbackAttachments extends Table {
  /// Primary key - stable UUID (never changes)
  TextColumn get id => text()();

  /// Parent message ID (FK to feedback_messages)
  TextColumn get messageId => text()();

  /// R2/CDN URL of the uploaded file
  TextColumn get url => text()();

  /// Attachment type: 'image', 'video', 'file'
  TextColumn get type => text()();

  /// File size in bytes
  IntColumn get size => integer().withDefault(const Constant(0))();

  /// Original file name (for display)
  TextColumn get fileName => text().nullable()();

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
