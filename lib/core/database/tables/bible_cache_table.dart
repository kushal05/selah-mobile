import 'package:drift/drift.dart';

/// Local cache for Bible verse text
///
/// This is NOT a sync entity - it's a local-only cache table.
/// No oplog, no version/deleted fields.
class BibleCache extends Table {
  /// Unique ID (UUID)
  TextColumn get id => text()();

  /// Book name (e.g., "John")
  TextColumn get book => text()();

  /// Chapter number
  IntColumn get chapter => integer()();

  /// Start verse number
  IntColumn get verseStart => integer()();

  /// End verse number (nullable for single verses)
  IntColumn get verseEnd => integer().nullable()();

  /// Bible version (e.g., "kjv", "web", "asv")
  TextColumn get version => text()();

  /// Full verse text
  TextColumn get verseText => text()();

  /// Display reference string (e.g., "John 3:16")
  TextColumn get reference => text()();

  /// When this verse was fetched/cached (Unix ms)
  IntColumn get fetchedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
