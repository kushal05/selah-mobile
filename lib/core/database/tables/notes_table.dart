import 'package:drift/drift.dart';

/// Notes table schema
/// Stores note metadata and document content as JSON
class Notes extends Table {
  /// Primary key - UUID
  TextColumn get id => text()();

  /// Note title
  TextColumn get title => text()();

  /// Editor document as JSON
  /// Contains blocks, formatting, and structure
  TextColumn get documentJson => text()();

  /// Creation timestamp
  DateTimeColumn get createdAt => dateTime()();

  /// Last update timestamp
  DateTimeColumn get updatedAt => dateTime()();

  /// Version for conflict resolution
  IntColumn get version => integer().withDefault(const Constant(1))();

  /// Foreign key to preacher (nullable)
  TextColumn get preacherId => text().nullable()();

  /// Foreign key to folder (nullable - null means root level)
  TextColumn get folderId => text().nullable()();

  /// Optional date associated with note (e.g., sermon date)
  DateTimeColumn get noteDate => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
