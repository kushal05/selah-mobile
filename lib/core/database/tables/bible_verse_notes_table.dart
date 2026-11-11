import 'package:drift/drift.dart';

/// A note the user wrote on a Bible verse, from the verse sheet's "Your notes".
///
/// Separate from [BibleHighlights.note], which is a single string that belongs
/// to a highlight and its colour: a verse can have any number of these, with or
/// without a highlight. Not a normal note either: it has no title, blocks or
/// folder, only the text.
///
/// Sync-enabled like highlights. Flutter-only entity type (bibleVerseNote)
/// pending Worker support, same pattern as bibleHighlight.
class BibleVerseNotes extends Table {
  /// Unique ID (UUID)
  TextColumn get id => text()();

  /// Owner user ID
  TextColumn get userId => text().withDefault(const Constant(''))();

  /// Book ID (1..66, matches bible_books.id in bible.db)
  IntColumn get bookId => integer()();

  /// Chapter number
  IntColumn get chapter => integer()();

  /// Start verse number (inclusive)
  IntColumn get verseStart => integer()();

  /// End verse number (inclusive, same as verseStart for a single verse)
  IntColumn get verseEnd => integer()();

  /// The note text
  TextColumn get content => text()();

  /// Version for optimistic concurrency (starts at 1, increments on each update)
  IntColumn get version => integer().withDefault(const Constant(1))();

  /// Soft delete flag (0 = active, 1 = deleted)
  IntColumn get deleted => integer().withDefault(const Constant(0))();

  /// When this note was created (Unix ms)
  IntColumn get createdAt => integer()();

  /// When this note was last modified (Unix ms)
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
