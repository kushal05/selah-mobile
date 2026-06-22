import 'package:drift/drift.dart';

/// Promise conditions table schema
///
/// Stores structured conditions for Bible promises.
/// Replaces the JSON-encoded conditions that were previously
/// embedded in the promise notes field via `<!-- conditions -->` separator.
///
/// Follows the standard sync entity pattern with soft deletes and versioning.
class PromiseConditions extends Table {
  /// Primary key - stable UUID
  TextColumn get id => text()();

  /// Foreign key to promises table
  TextColumn get promiseId => text()();

  /// Owner user ID
  TextColumn get userId => text()();

  /// Condition description text
  TextColumn get description => text()();

  /// Optional notes about this condition
  TextColumn get notes => text().withDefault(const Constant(''))();

  /// Status: ACTIVE, MET, NOT_MET
  TextColumn get status => text().withDefault(const Constant('ACTIVE'))();

  /// Last update timestamp (Unix milliseconds)
  IntColumn get updatedAt => integer()();

  /// Version number for optimistic locking
  IntColumn get version => integer().withDefault(const Constant(1))();

  /// Soft delete flag (0 = active, 1 = deleted)
  IntColumn get deleted => integer().withDefault(const Constant(0))();

  /// Timestamp when moved to trash (Unix milliseconds, null = not trashed)
  IntColumn get trashedAt => integer().nullable()();

  /// Creation timestamp (Unix milliseconds)
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
