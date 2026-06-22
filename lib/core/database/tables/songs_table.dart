import 'package:drift/drift.dart';

/// Songs table schema
/// Stores song lyrics and chord annotations with folder organization
///
/// Per spec: Songs are a specialized note type with lyrics/chords modes
/// Soft delete only - no hard deletes
class Songs extends Table {
  /// Primary key - stable UUID (never changes)
  TextColumn get id => text()();

  /// Owner user ID
  TextColumn get userId => text()();

  /// Song title (mandatory)
  TextColumn get title => text()();

  /// Folder ID for organization (references Folders table)
  TextColumn get folderId => text().nullable()();

  /// Clean lyrics content (plain text with line breaks)
  TextColumn get lyrics => text().withDefault(const Constant(''))();

  /// Lyrics with inline chord annotations
  TextColumn get chords => text().withDefault(const Constant(''))();

  /// Primary language of the song
  TextColumn get language => text().withDefault(const Constant('English'))();

  /// Optional songbook/collection identifier
  TextColumn get book => text().nullable()();

  /// Preview text (auto-generated from lyrics, first ~50 chars)
  TextColumn get preview => text().withDefault(const Constant(''))();

  /// User-defined tags (comma-separated)
  TextColumn get tags => text().withDefault(const Constant(''))();

  /// Musical scale/key (e.g. "C", "Dm", "F#", "Bb")
  TextColumn get scale => text().withDefault(const Constant(''))();

  /// Free-form notes or references related to the song
  /// (e.g. author, source URL, performance notes)
  TextColumn get notes => text().withDefault(const Constant(''))();

  /// Structured chord lines as JSON array, stored separately from lyrics.
  /// Each entry: {"lineIndex": int, "rawChords": "G D Em C"}
  /// lineIndex maps to the corresponding lyric line.
  TextColumn get chordLines => text().withDefault(const Constant(''))();

  /// Whether song has chord annotations
  IntColumn get hasChords => integer().withDefault(const Constant(0))();

  /// Favorite flag
  IntColumn get isFavorite => integer().withDefault(const Constant(0))();

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
