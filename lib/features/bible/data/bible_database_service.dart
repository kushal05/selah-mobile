import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'bible_schema_ddl.dart';

/// Manages the lifecycle of the read-only Bible SQLite database.
///
/// Architecture decisions:
/// - Uses package:sqlite3 directly (not sqflite) to guarantee FTS5 support
///   via the sqlite3_flutter_libs binary already bundled by the app for Drift.
/// - The Bible DB is a SEPARATE file from the app's sync database. It is never
///   written to at runtime (read-only after initial copy). This isolation means
///   it cannot interfere with notes, songs, or any sync-enabled tables.
/// - On first launch the default translation's .db file is downloaded from
///   the URL provided by GET /v1/bible/versions and written to the application
///   documents directory as bible.db. Subsequent launches re-open in-place.
/// - A `_meta` table stores the schema version for future migration support.
///
/// Extends [ChangeNotifier] so Riverpod's [ChangeNotifierProvider] can
/// reactively rebuild widgets when [isOpen] transitions from false → true
/// after a successful download/init.
///
/// Schema overview (created by the generation script, verified on open):
///   bible_books            — 66 rows, one per canonical book
///   bible_verses           — ~31,000 rows per translation
///   bible_verses_fts       — FTS5 virtual table for full-text search
///   idx_verse_lookup       — composite index (book_id, chapter, verse)
///   idx_books_testament    — index (testament, sort_order)
///   3 triggers             — keep FTS in sync with bible_verses
class BibleDatabaseService extends ChangeNotifier {
  Database? _db;

  static const _dbFileName = 'bible.db';

  /// Serializes concurrent [download] / [downloadVersion] calls so they don't
  /// race on the shared SQLite connection or temp files. The UI lets users tap
  /// several "Download" buttons in quick succession — without this queue, two
  /// in-flight calls share the `src` ATTACH alias (and, on the initial path,
  /// the `bible.db.tmp` filename) and any error in one silently aborts the
  /// other. Per-call unique aliases plus this queue together make each tap
  /// complete independently.
  Future<void> _downloadQueue = Future<void>.value();

  /// Monotonically increasing counter used to build unique ATTACH aliases
  /// (e.g. `src_3`). Guards against leftover attachments from a prior failure.
  int _attachSeq = 0;

  /// Current schema version — delegated to [bibleSchemaVersion] in
  /// `bible_schema_ddl.dart` (the single source of truth).
  static int get schemaVersion => bibleSchemaVersion;

  /// Whether the database is currently open and ready for queries.
  bool get isOpen => _db != null;

  /// The raw database handle. Throws if not yet initialized.
  Database get db {
    assert(_db != null, 'BibleDatabaseService.init() must be called first');
    return _db!;
  }

  /// Initialize the Bible database.
  ///
  /// - If the local file does not exist, returns immediately without opening.
  ///   Call [download] first, then [init] again.
  /// - If the local file exists, opens it and verifies the schema.
  /// - If the on-disk schema_version is older than [bibleSchemaVersion], the
  ///   stale file is deleted so the next download replaces it. Same effect as
  ///   "not yet downloaded" — caller must invoke [download] again.
  Future<void> init() async {
    if (_db != null) return;

    final dbPath = await _localDbPath();
    final dbFile = File(dbPath);

    if (!dbFile.existsSync()) return; // Not yet downloaded — no-op.

    try {
      // Open in read-write mode so triggers and FTS can function.
      // The DB is conceptually read-only from the app layer (BibleRepository
      // never exposes write operations), but SQLite requires write access
      // for FTS queries that use the content-sync mechanism internally.
      _db = sqlite3.open(dbPath);
      _verifySchema();

      // If the file predates the current schema (e.g. before the FTS5
      // prefix index was added), wipe it so the user is prompted to
      // re-download instead of running on a slow legacy DB.
      if (_diskSchemaVersion() < bibleSchemaVersion) {
        debugPrint(
          'Bible DB schema_version is older than $bibleSchemaVersion — '
          'discarding to force re-download.',
        );
        _db!.dispose();
        _db = null;
        try {
          dbFile.deleteSync();
        } catch (e) {
          debugPrint('Failed to delete stale Bible DB: $e');
        }
        return;
      }

      notifyListeners();
    } catch (e, st) {
      debugPrint('BibleDatabaseService.init() failed: $e\n$st');
      _db?.dispose();
      _db = null;
      rethrow;
    }
  }

  /// Read `schema_version` from the `_meta` table, defaulting to 1 if the row
  /// is missing or unparseable (legacy DBs without the row are v1).
  int _diskSchemaVersion() {
    try {
      final rows = _db!.select(
        "SELECT value FROM _meta WHERE key = 'schema_version'",
      );
      if (rows.isEmpty) return 1;
      return int.tryParse(rows.first['value'] as String) ?? 1;
    } catch (_) {
      return 1;
    }
  }

  /// Download the Bible database from [url] and open it.
  ///
  /// [onProgress] is called with a value in [0.0, 1.0] as bytes are received.
  /// Throws on network error or non-200 response.
  Future<void> download(
    String url, {
    void Function(double progress)? onProgress,
  }) {
    return _enqueue(() => _downloadImpl(url, onProgress: onProgress));
  }

  Future<void> _downloadImpl(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    assert(url.isNotEmpty, 'download URL must not be empty — provide a URL from the Bible versions API');

    final dbPath = await _localDbPath();
    final tempPath = '$dbPath.tmp';
    await _downloadToFile(url, tempPath, onProgress: onProgress);

    // Atomically replace any existing file only after a successful download.
    await File(tempPath).rename(dbPath);

    // Open the freshly downloaded database.
    await init();
  }

  /// Download a per-version database file and merge its verses into the main db.
  ///
  /// The per-version file has the same schema as the main `bible.db`. Its
  /// `bible_verses` rows are imported via SQLite `ATTACH + INSERT OR IGNORE`.
  /// The FTS5 INSERT trigger keeps `bible_verses_fts` in sync automatically.
  ///
  /// Throws if the main database is not open yet (call [init] or [download]
  /// first to establish the mandatory base database).
  Future<void> downloadVersion(
    String code,
    String url, {
    void Function(double progress)? onProgress,
  }) {
    return _enqueue(
      () => _downloadVersionImpl(code, url, onProgress: onProgress),
    );
  }

  Future<void> _downloadVersionImpl(
    String code,
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    assert(_db != null, 'BibleDatabaseService must be initialized before downloading additional versions');

    final dbPath = await _localDbPath();
    final tempPath = '$dbPath.$code.tmp';
    await _downloadToFile(url, tempPath, onProgress: onProgress);

    // Merge verses from the downloaded per-version db into the main db.
    // ATTACH + INSERT OR IGNORE handles duplicates gracefully (e.g., existing
    // users who already have this translation in their monolithic bible.db).
    // The FTS5 INSERT trigger auto-syncs new rows into bible_verses_fts.
    //
    // Unique alias per call: a prior failure between ATTACH and DETACH would
    // otherwise leave `src` bound and break every later merge until restart.
    final alias = 'src_${_attachSeq++}';
    try {
      _db!.execute('ATTACH DATABASE ? AS $alias', [tempPath]);
      _db!.execute(
        'INSERT OR IGNORE INTO bible_verses(translation, book_id, chapter, verse, text) '
        'SELECT translation, book_id, chapter, verse, text FROM $alias.bible_verses',
      );
      _db!.execute('DETACH DATABASE $alias');
    } finally {
      try {
        File(tempPath).deleteSync();
      } catch (_) {}
    }

    notifyListeners();
  }

  /// Appends [task] to [_downloadQueue] so it runs after any in-flight
  /// download finishes. Errors are surfaced to the caller but don't poison
  /// the queue for the next task.
  Future<void> _enqueue(Future<void> Function() task) {
    final next = _downloadQueue.then((_) => task());
    _downloadQueue = next.then((_) {}, onError: (_) {});
    return next;
  }

  /// Streams [url] into [destPath], reporting progress via [onProgress].
  /// Throws [StateError] on a non-200 response.
  Future<void> _downloadToFile(
    String url,
    String destPath, {
    void Function(double progress)? onProgress,
  }) async {
    final client = http.Client();
    try {
      final response = await client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) {
        throw StateError('Download failed with HTTP ${response.statusCode}');
      }

      final contentLength = response.contentLength;
      var bytesReceived = 0;
      final sink = File(destPath).openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          bytesReceived += chunk.length;
          if (contentLength != null && contentLength > 0) {
            onProgress?.call(bytesReceived / contentLength);
          }
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }
  }

  /// Delete all verses for [code] from the database and reclaim disk space.
  ///
  /// The FTS5 DELETE trigger keeps `bible_verses_fts` in sync automatically.
  /// After this call, [getAvailableTranslations] will no longer return [code].
  ///
  /// VACUUM runs on a background isolate via a fresh connection so the
  /// main-thread handle is never blocked by the potentially slow compaction.
  Future<void> deleteVersion(String code) async {
    assert(_db != null, 'BibleDatabaseService must be initialized before deleting versions');
    _db!.execute('DELETE FROM bible_verses WHERE translation = ?', [code]);
    notifyListeners();
    // Run VACUUM after notifying so the UI updates immediately. A fresh
    // connection is opened in a background isolate — the main handle is
    // not passed across isolate boundaries (sqlite3 Database isn't sendable).
    final dbPath = await _localDbPath();
    await Isolate.run(() {
      final db = sqlite3.open(dbPath);
      try {
        db.execute('VACUUM');
      } finally {
        db.dispose();
      }
    });
  }

  /// Close the database and release resources.
  @override
  void dispose() {
    _db?.dispose();
    _db = null;
    super.dispose();
  }

  /// Absolute path to the local bible.db in the app documents directory.
  Future<String> _localDbPath() async {
    final docsDir = await getApplicationDocumentsDirectory();
    return p.join(docsDir.path, _dbFileName);
  }

  /// Public accessor for the local Bible DB path. Used by the background
  /// search isolate which opens its own read-only connection to the same file.
  Future<String> dbPath() => _localDbPath();

  /// Verify that the required tables and indexes exist.
  void _verifySchema() {
    final tables = _db!
        .select("SELECT name FROM sqlite_master WHERE type='table'")
        .map((r) => r['name'] as String)
        .toSet();

    const required = {'bible_books', 'bible_verses', 'bible_verses_fts', '_meta'};
    final missing = required.difference(tables);
    if (missing.isNotEmpty) {
      throw StateError(
        'Bible DB schema verification failed. Missing tables: $missing',
      );
    }
  }

  /// SQL statements that create the complete Bible DB schema from scratch.
  /// Delegated to [bibleSchemaDDL] in `bible_schema_ddl.dart`.
  static List<String> get schemaDDL => bibleSchemaDDL;
}
