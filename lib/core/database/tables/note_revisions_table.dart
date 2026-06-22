import 'package:drift/drift.dart';

/// Local-only table for note revision snapshots.
///
/// This is NOT a sync entity - revisions stay on-device only.
/// No oplog, no version/deleted/userId fields.
class NoteRevisions extends Table {
  /// Unique ID (UUID)
  TextColumn get id => text()();

  /// Parent note ID
  TextColumn get noteId => text()();

  /// Full JSON snapshot of note + blocks at this point in time
  TextColumn get snapshotJson => text()();

  /// When this revision was created (Unix ms)
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
