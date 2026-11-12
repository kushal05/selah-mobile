import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart'
    show ChangeNotifier, debugPrint, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'bible_schema_ddl.dart';
import 'bible_version_updates.dart';

/// Thrown from a download that was stopped by [BibleDatabaseService.cancelDownload].
class BibleDownloadCancelled implements Exception {
  const BibleDownloadCancelled();
  @override
  String toString() => 'BibleDownloadCancelled';
}

/// Merges the verses of the per-version db at [srcPath] into the db at
/// [dbPath] using its own connection. Runs on a background isolate.
///
/// The FTS5 triggers are part of the main db's schema, so they fire here too.
/// The busy timeout covers a lock held briefly by the app's own connections.
///
/// With [replace], the translation's existing verses are removed first, in the
/// same transaction, so an update never leaves old and new text side by side
/// (verse numbers can move between releases of a file). If the incoming file
/// has no verses the existing ones are kept and this throws.
@visibleForTesting
void mergeVersionFile(String dbPath, String srcPath, String alias,
    {bool replace = false}) {
  final db = sqlite3.open(dbPath);
  try {
    db.execute('PRAGMA busy_timeout = ${BibleDatabaseService._busyTimeoutMs}');
    db.execute('ATTACH DATABASE ? AS $alias', [srcPath]);
    try {
      if (replace) {
        final incoming = db
            .select('SELECT COUNT(*) AS n FROM $alias.bible_verses')
            .first['n'] as int;
        if (incoming == 0) {
          throw StateError('The downloaded Bible file has no verses');
        }
        db.execute('BEGIN');
        try {
          db.execute(
            'DELETE FROM bible_verses WHERE translation IN '
            '(SELECT DISTINCT translation FROM $alias.bible_verses)',
          );
          db.execute(
            'INSERT INTO bible_verses(translation, book_id, chapter, verse, text) '
            'SELECT translation, book_id, chapter, verse, text FROM $alias.bible_verses',
          );
          db.execute('COMMIT');
        } catch (_) {
          db.execute('ROLLBACK');
          rethrow;
        }
      } else {
        db.execute(
          'INSERT OR IGNORE INTO bible_verses(translation, book_id, chapter, verse, text) '
          'SELECT translation, book_id, chapter, verse, text FROM $alias.bible_verses',
        );
      }
    } finally {
      db.execute('DETACH DATABASE $alias');
    }
  } finally {
    db.dispose();
  }
}

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
  BibleDatabaseService({
    @visibleForTesting Future<String> Function()? dbPathResolver,
  }) : _dbPathResolver = dbPathResolver;

  /// Test seam: where bible.db lives. Defaults to the app documents directory.
  final Future<String> Function()? _dbPathResolver;

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

  /// Idle time allowed on the connection, or between chunks, before a download
  /// is abandoned as stalled.
  static const _downloadTimeout = Duration(seconds: 30);

  /// How long a connection waits on a lock held by another connection.
  static const _busyTimeoutMs = 30000;

  /// Downloads queued or running, by cancel key (the version code, or the URL
  /// when no code is given).
  final Set<String> _pending = {};

  /// Keys whose download has been asked to stop.
  final Set<String> _cancelled = {};

  /// The open HTTP client of each running download, closed by [cancelDownload].
  final Map<String, http.Client> _activeClients = {};

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
      // A version merge writes to this file from a background isolate. Wait
      // for its commit instead of failing with SQLITE_BUSY.
      _db!.execute('PRAGMA busy_timeout = $_busyTimeoutMs');
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

  /// Installs the version [code] from [url], choosing the path when the job
  /// actually runs: the first version creates bible.db ([download]); every later
  /// one is merged into the open database ([downloadVersion]).
  ///
  /// The choice must not be made at request time. With nothing installed, two
  /// queued requests would both see a closed database and both take the
  /// first-install path; the second would rename its temp file over the
  /// bible.db the first one just opened.
  ///
  /// With [replace] the version's installed verses are swapped for the
  /// downloaded ones (an update). [onStamp] receives the ETag of the file that
  /// was installed, to compare with the host later.
  Future<void> install(
    String code,
    String url, {
    void Function(double progress)? onProgress,
    bool replace = false,
    void Function(String? stamp)? onStamp,
  }) {
    return _enqueueCancellable(
      code,
      () => _db == null
          ? _downloadImpl(url, code, onProgress: onProgress, onStamp: onStamp)
          : _downloadVersionImpl(code, url,
              onProgress: onProgress, replace: replace, onStamp: onStamp),
    );
  }

  /// Download the Bible database from [url] and open it.
  ///
  /// Prefer [install] unless the caller knows nothing else is queued.
  ///
  /// [onProgress] is called with a value in [0.0, 1.0] as bytes are received.
  /// Throws on network error or non-200 response.
  ///
  /// Pass [code] to make the download cancellable via [cancelDownload].
  Future<void> download(
    String url, {
    String? code,
    void Function(double progress)? onProgress,
  }) {
    final key = code ?? url;
    return _enqueueCancellable(
      key,
      () => _downloadImpl(url, key, onProgress: onProgress),
    );
  }

  Future<void> _downloadImpl(
    String url,
    String key, {
    void Function(double progress)? onProgress,
    void Function(String? stamp)? onStamp,
  }) async {
    assert(url.isNotEmpty, 'download URL must not be empty — provide a URL from the Bible versions API');

    final dbPath = await _localDbPath();
    final tempPath = '$dbPath.tmp';
    // Awaited first: in `onStamp?.call(await ...)` the argument is not even
    // evaluated when there is no callback, so nothing would be downloaded.
    final stamp =
        await _downloadToFile(url, tempPath, key, onProgress: onProgress);

    // Atomically replace any existing file only after a successful download.
    await File(tempPath).rename(dbPath);

    // Open the freshly downloaded database.
    await init();
    onStamp?.call(stamp);
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
    return _enqueueCancellable(
      code,
      () => _downloadVersionImpl(code, url, onProgress: onProgress),
    );
  }

  Future<void> _downloadVersionImpl(
    String code,
    String url, {
    void Function(double progress)? onProgress,
    bool replace = false,
    void Function(String? stamp)? onStamp,
  }) async {
    assert(_db != null, 'BibleDatabaseService must be initialized before downloading additional versions');

    final dbPath = await _localDbPath();
    final tempPath = '$dbPath.$code.tmp';
    final stamp =
        await _downloadToFile(url, tempPath, code, onProgress: onProgress);

    // Merge verses from the downloaded per-version db into the main db.
    // ATTACH + INSERT OR IGNORE handles duplicates gracefully (e.g., existing
    // users who already have this translation in their monolithic bible.db).
    // The FTS5 INSERT trigger auto-syncs new rows into bible_verses_fts.
    //
    // Unique alias per call: a prior failure between ATTACH and DETACH would
    // otherwise leave `src` bound and break every later merge until restart.
    final alias = 'src_${_attachSeq++}';
    try {
      // ~31k rows plus FTS5 maintenance: run on a background isolate with its
      // own connection so the UI isolate keeps painting.
      await Isolate.run(
          () => mergeVersionFile(dbPath, tempPath, alias, replace: replace));
      onStamp?.call(stamp);
    } finally {
      try {
        File(tempPath).deleteSync();
      } catch (e) {
        // Best-effort cleanup of a scratch copy in the temp directory. The
        // import has already succeeded by this point; a leftover file costs
        // disk space and the OS reclaims it.
        debugPrint('Could not delete temp Bible db $tempPath: $e');
      }
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

  /// Queues [task] under cancel [key]. A cancel that lands while the task is
  /// still waiting in the queue makes it fail with [BibleDownloadCancelled]
  /// when its turn comes, without touching the network.
  Future<void> _enqueueCancellable(
    String key,
    Future<void> Function() task,
  ) {
    _cancelled.remove(key);
    _pending.add(key);
    return _enqueue(() async {
      try {
        if (_cancelled.contains(key)) throw const BibleDownloadCancelled();
        await task();
      } finally {
        _pending.remove(key);
        _cancelled.remove(key);
      }
    });
  }

  /// Stops the queued or running download registered under [key]. Its future
  /// completes with [BibleDownloadCancelled]. No-op when nothing is pending.
  void cancelDownload(String key) {
    if (!_pending.contains(key)) return;
    _cancelled.add(key);
    _activeClients[key]?.close();
  }

  /// Streams [url] into [destPath], reporting progress via [onProgress].
  /// Throws [StateError] on a non-200 response, [TimeoutException] when the
  /// connection stalls, and [BibleDownloadCancelled] when cancelled under [key].
  /// The partial file is deleted on any failure.
  ///
  /// Returns the ETag the host sent with the file, or null.
  Future<String?> _downloadToFile(
    String url,
    String destPath,
    String key, {
    void Function(double progress)? onProgress,
  }) async {
    final client = http.Client();
    _activeClients[key] = client;
    var completed = false;
    try {
      final response = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(_downloadTimeout);
      if (response.statusCode != 200) {
        throw StateError('Download failed with HTTP ${response.statusCode}');
      }

      final stamp = bibleStampFromHeaders(response.headers);
      final contentLength = response.contentLength;
      var bytesReceived = 0;
      final sink = File(destPath).openWrite();
      try {
        await for (final chunk in response.stream.timeout(_downloadTimeout)) {
          sink.add(chunk);
          bytesReceived += chunk.length;
          if (contentLength != null && contentLength > 0) {
            onProgress?.call(bytesReceived / contentLength);
          }
        }
      } finally {
        await sink.close();
      }
      completed = true;
      return stamp;
    } catch (_) {
      // Closing the client surfaces as an arbitrary ClientException; report
      // what actually happened.
      if (_cancelled.contains(key)) throw const BibleDownloadCancelled();
      rethrow;
    } finally {
      _activeClients.remove(key);
      client.close();
      if (!completed) {
        try {
          final f = File(destPath);
          if (f.existsSync()) f.deleteSync();
        } catch (e) {
          debugPrint('Could not delete partial Bible download $destPath: $e');
        }
      }
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
    final resolver = _dbPathResolver;
    if (resolver != null) return resolver();
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
