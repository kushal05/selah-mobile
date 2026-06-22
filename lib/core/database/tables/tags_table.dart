import 'package:drift/drift.dart';

/// Tags table schema
/// Stores available tags
class Tags extends Table {
  /// Primary key - UUID
  TextColumn get id => text()();

  /// Tag name
  TextColumn get name => text()();

  /// Creation timestamp
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {name}
      ];
}

/// Junction table for note-tag many-to-many relationship
class NoteTags extends Table {
  /// Foreign key to note
  TextColumn get noteId => text()();

  /// Foreign key to tag
  TextColumn get tagId => text()();

  /// Creation timestamp
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {noteId, tagId};
}
