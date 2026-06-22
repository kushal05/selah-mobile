import 'package:drift/drift.dart';

/// CRDT foundation: records editing operations for future collaborative editing.
///
/// Phase A (current): local-only, not synced via oplog.
/// Phase B (future): add to OplogEntityType, sync across devices, merge ops.
///
/// Supports: notes, songs, prayers, future documents.
/// Operation types: insert, delete, update (text-level editing operations).
class DocumentOperations extends Table {
  /// Primary key — stable UUID
  TextColumn get id => text()();

  /// Type of entity being edited: note, song, prayer
  TextColumn get entityType => text()();

  /// ID of the entity being edited
  TextColumn get entityId => text()();

  /// Editing operation type: insert, delete, update
  TextColumn get operationType => text()();

  /// JSON payload describing the operation (position, length, text, attributes)
  TextColumn get payload => text()();

  /// User who performed the operation
  TextColumn get userId => text()();

  /// Device that created this operation
  TextColumn get deviceId => text()();

  /// Operation timestamp (Unix milliseconds)
  IntColumn get timestamp => integer()();

  /// Version counter for ordering
  IntColumn get version => integer().withDefault(const Constant(1))();

  /// Local monotonic sequence number per entity for ordering
  IntColumn get sequenceNumber => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
