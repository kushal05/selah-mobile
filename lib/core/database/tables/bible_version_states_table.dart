import 'package:drift/drift.dart';

/// Local registry of Bible translations available for download.
///
/// Populated by fetching GET /v1/bible/versions from the backend and cached
/// here so the versions screen works offline after the first load.
///
/// [isDefault] — the user's chosen default translation, used in the Bible
///   reader, notes, and search.  Exactly one row should have isDefault = true
///   at any time; the repository enforces this invariant.
///
/// "Downloaded" state is NOT stored here — it is derived at runtime by
/// querying `SELECT DISTINCT translation FROM bible_verses` on the separate
/// bible.db file ([BibleRepository.getAvailableTranslations]). This avoids
/// the two sources of truth diverging after an app reinstall or bible.db swap.
///
/// Local-only — never synced.
class BibleVersionStates extends Table {
  /// Translation code, e.g. 'NKJV'. Also the primary key.
  TextColumn get code => text()();

  /// Full display name, e.g. 'New King James Version'.
  TextColumn get name => text()();

  /// S3 URL for the per-translation SQLite database file.
  TextColumn get downloadUrl => text()();

  /// Approximate download size in MB (for UI display only).
  IntColumn get approximateSizeMb => integer()();

  /// Display order from the server (lower = shown first).
  IntColumn get sortOrder => integer()();

  /// Whether this is the user's active default translation.
  /// Exactly one row should be true at a time.
  BoolColumn get isDefault =>
      boolean().withDefault(const Constant(false))();

  /// Unix ms when this row was last refreshed from the server.
  IntColumn get fetchedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {code};
}
