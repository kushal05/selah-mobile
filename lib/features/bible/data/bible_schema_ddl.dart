/// Authoritative SQL DDL for the Bible SQLite database schema.
///
/// This file is intentionally free of Flutter dependencies so it can be
/// imported by both:
///   - `BibleDatabaseService` (Flutter app)
///   - `tools/generate_bible_db.dart` (standalone Dart CLI)
///
/// Any schema changes MUST be made here. Bump [bibleSchemaVersion] when
/// the CDN database is regenerated (e.g., new translation added).
library;

/// Current schema version. When a new `bible.db` is published to the CDN,
/// bump this so devices re-download the updated database.
///
/// v2 (2026-04-22): added `prefix='2 3 4'` to the FTS5 virtual table for
/// fast multi-word prefix searches. Devices on v1 will see a stale-DB
/// detection in [BibleDatabaseService.init] and need to re-download.
const int bibleSchemaVersion = 2;

/// SQL statements that create the complete Bible DB schema from scratch.
const List<String> bibleSchemaDDL = [
  // Metadata table for version tracking
  '''
  CREATE TABLE IF NOT EXISTS _meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  )
  ''',

  // Bible books — 66 rows, one per canonical book
  '''
  CREATE TABLE IF NOT EXISTS bible_books (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    short_name TEXT NOT NULL,
    testament INTEGER NOT NULL,
    sort_order INTEGER NOT NULL
  )
  ''',

  // Bible verses — one row per (translation, book, chapter, verse)
  '''
  CREATE TABLE IF NOT EXISTS bible_verses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    translation TEXT NOT NULL,
    book_id INTEGER NOT NULL REFERENCES bible_books(id),
    chapter INTEGER NOT NULL,
    verse INTEGER NOT NULL,
    text TEXT NOT NULL,
    UNIQUE(translation, book_id, chapter, verse)
  )
  ''',

  // FTS5 virtual table for full-text search on verse text.
  // content= and content_rowid= make this a "content-synced" external
  // content table backed by bible_verses. The triggers below keep them
  // in sync automatically.
  //
  // prefix='2 3 4' builds dedicated indexes for 2/3/4-character prefixes
  // so multi-word queries like `faith* AND hope*` resolve via direct
  // index seeks instead of linear term-index scans.
  '''
  CREATE VIRTUAL TABLE IF NOT EXISTS bible_verses_fts USING fts5(
    text,
    content='bible_verses',
    content_rowid='id',
    prefix='2 3 4'
  )
  ''',

  // Index for fast verse lookup by coordinates
  'CREATE INDEX IF NOT EXISTS idx_verse_lookup ON bible_verses(book_id, chapter, verse)',

  // Index for testament-based filtering and sort ordering
  'CREATE INDEX IF NOT EXISTS idx_books_testament ON bible_books(testament, sort_order)',

  // Trigger: AFTER INSERT → sync new row into FTS
  '''
  CREATE TRIGGER IF NOT EXISTS bible_verses_ai AFTER INSERT ON bible_verses BEGIN
    INSERT INTO bible_verses_fts(rowid, text) VALUES (new.id, new.text);
  END
  ''',

  // Trigger: AFTER DELETE → remove deleted row from FTS
  '''
  CREATE TRIGGER IF NOT EXISTS bible_verses_ad AFTER DELETE ON bible_verses BEGIN
    INSERT INTO bible_verses_fts(bible_verses_fts, rowid, text)
      VALUES ('delete', old.id, old.text);
  END
  ''',

  // Trigger: AFTER UPDATE → re-sync changed row in FTS
  '''
  CREATE TRIGGER IF NOT EXISTS bible_verses_au AFTER UPDATE ON bible_verses BEGIN
    INSERT INTO bible_verses_fts(bible_verses_fts, rowid, text)
      VALUES ('delete', old.id, old.text);
    INSERT INTO bible_verses_fts(rowid, text) VALUES (new.id, new.text);
  END
  ''',
];
