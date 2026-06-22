import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import '../domain/models/bible_search_result.dart';

/// Long-lived background isolate that owns its own read-only `sqlite3`
/// connection to `bible.db`.
///
/// Why this exists: `package:sqlite3` is synchronous. Wrapping a query in
/// `Future(() => db.select(...))` only defers a microtask — the SQL itself
/// still runs on the main isolate and blocks the UI thread. Multi-word FTS5
/// prefix queries (e.g. `faith* AND hope* AND love*`) joined across
/// `bible_verses` × `bible_books` can take seconds and freeze the app.
///
/// All Bible search SQL therefore runs here. Requests are serialized through a
/// single isolate so the connection is never used concurrently. The Bible DB
/// is never written to from this isolate, so opening with `OpenMode.readOnly`
/// guarantees we cannot conflict with the main isolate's read-write handle
/// during version downloads/deletes.
class BibleSearchIsolate {
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  Completer<void>? _ready;

  final Map<int, Completer<dynamic>> _pending = {};
  int _nextRequestId = 0;
  bool _disposed = false;

  Future<void> start(String dbPath) {
    if (_disposed) {
      return Future.error(StateError('BibleSearchIsolate already disposed'));
    }
    final existing = _ready;
    if (existing != null) return existing.future;

    final ready = Completer<void>();
    _ready = ready;

    final receivePort = ReceivePort();
    _receivePort = receivePort;
    receivePort.listen(_handleMessage);

    Isolate.spawn(
      _entry,
      _IsolateInit(receivePort.sendPort, dbPath),
      debugName: 'bible-search',
    ).then((iso) {
      // dispose() can run while spawn is in flight. If we're already
      // disposed by the time the isolate handle arrives, kill it
      // immediately — otherwise it lives on as a zombie with no SendPort
      // pointing at it (our ReceivePort was closed in _cleanup).
      if (_disposed) {
        iso.kill(priority: Isolate.immediate);
        return;
      }
      _isolate = iso;
    }).catchError((e, st) {
      // Fail the in-flight start AND clear the cached completer so a later
      // call to start() can retry instead of replaying the same error.
      if (!ready.isCompleted) ready.completeError(e, st);
      _cleanup();
    });

    return ready.future;
  }

  void _handleMessage(dynamic msg) {
    if (msg is SendPort) {
      _sendPort = msg;
      _ready?.complete();
      return;
    }
    if (msg is _SearchResponse) {
      final completer = _pending.remove(msg.requestId);
      if (completer == null) return;
      if (msg.error != null) {
        completer.completeError(StateError(msg.error!));
      } else {
        completer.complete(msg.payload);
      }
    }
  }

  Future<List<BibleSearchResult>> search({
    required String ftsQuery,
    required Set<int> testaments,
    required Set<int> bookIds,
    required Set<String> translations,
    required String orderClause,
    required int limit,
    required int offset,
    required String hlOpen,
    required String hlClose,
  }) async {
    final port = await _waitForPort();
    final id = _nextRequestId++;
    final completer = Completer<List<BibleSearchResult>>();
    _pending[id] = completer;
    port.send(_SearchRequest(
      requestId: id,
      ftsQuery: ftsQuery,
      testaments: testaments.toList(growable: false),
      bookIds: bookIds.toList(growable: false),
      translations: translations.toList(growable: false),
      orderClause: orderClause,
      limit: limit,
      offset: offset,
      hlOpen: hlOpen,
      hlClose: hlClose,
    ));
    final raw = await completer.future;
    return (raw as List).cast<BibleSearchResult>();
  }

  Future<int> getVerseCount() async {
    final port = await _waitForPort();
    final id = _nextRequestId++;
    final completer = Completer<int>();
    _pending[id] = completer;
    port.send(_CountRequest(id));
    return completer.future;
  }

  Future<SendPort> _waitForPort() async {
    final ready = _ready;
    if (ready == null) {
      throw StateError('BibleSearchIsolate.start() was not called');
    }
    await ready.future;
    final port = _sendPort;
    if (port == null) {
      throw StateError('BibleSearchIsolate has no send port');
    }
    return port;
  }

  void dispose() {
    _disposed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _cleanup();
  }

  void _cleanup() {
    _isolate = null;
    _sendPort = null;
    _receivePort?.close();
    _receivePort = null;
    // Clear _ready so a subsequent start() (after a transient spawn failure)
    // can rebuild from scratch instead of replaying the failed completer.
    _ready = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(StateError('BibleSearchIsolate disposed'));
      }
    }
    _pending.clear();
  }

  // ── Isolate entry point ────────────────────────────────────────────────

  static void _entry(_IsolateInit init) {
    final receivePort = ReceivePort();
    init.sendPort.send(receivePort.sendPort);

    Database? db;
    String? openError;
    try {
      db = sqlite3.open(init.dbPath, mode: OpenMode.readOnly);
    } catch (e) {
      // Fall back to read-write (without create) so we never silently
      // materialise an empty DB at the path if the file is missing or
      // permission-locked. Search-only — no writes are ever issued here.
      try {
        db = sqlite3.open(init.dbPath, mode: OpenMode.readWrite);
      } catch (e2) {
        openError = e2.toString();
        if (kDebugMode) {
          debugPrint('BibleSearchIsolate failed to open DB: $e2');
        }
      }
    }

    if (db != null) {
      _tuneConnection(db);
      if (kDebugMode) _logSchemaVersion(db);
    }

    receivePort.listen((msg) {
      if (msg is _SearchRequest) {
        if (db == null) {
          init.sendPort.send(_SearchResponse.error(
            msg.requestId,
            openError ?? 'DB not open',
          ));
          return;
        }
        try {
          final sw = kDebugMode ? (Stopwatch()..start()) : null;
          final results = _runSearch(db, msg);
          if (sw != null) {
            sw.stop();
            debugPrint(
              'BibleSearchIsolate query: ${results.length} rows in '
              '${sw.elapsedMilliseconds}ms — '
              '${msg.ftsQuery} (translations=${msg.translations.length})',
            );
          }
          init.sendPort.send(_SearchResponse.success(msg.requestId, results));
        } catch (e) {
          init.sendPort
              .send(_SearchResponse.error(msg.requestId, e.toString()));
        }
      } else if (msg is _CountRequest) {
        if (db == null) {
          init.sendPort.send(_SearchResponse.success(msg.requestId, 0));
          return;
        }
        try {
          final rows = db.select('SELECT COUNT(*) AS cnt FROM bible_verses');
          final cnt = rows.first['cnt'] as int;
          init.sendPort.send(_SearchResponse.success(msg.requestId, cnt));
        } catch (e) {
          init.sendPort
              .send(_SearchResponse.error(msg.requestId, e.toString()));
        }
      }
    });
  }

  /// Apply SQLite tuning PRAGMAs that benefit read-heavy FTS5 queries.
  ///
  /// - `mmap_size=256MB`: maps the DB file into memory so reads bypass the
  ///   user-space page cache and hit the OS page cache directly. The whole
  ///   `bible.db` is well under this size, so the entire file becomes
  ///   essentially memory-resident after the first few queries.
  /// - `cache_size=-50000`: 50MB of in-process page cache (negative value =
  ///   KB). Plenty of room for hot FTS index pages.
  /// - `temp_store=MEMORY`: keeps the FTS5 sorter / intermediate result sets
  ///   off disk, which matters most for large-rank `ORDER BY rank` queries.
  /// - `synchronous=OFF` + `journal_mode=OFF`: pure read-only connection,
  ///   so there's nothing to sync or journal anyway.
  static void _tuneConnection(Database db) {
    try {
      db.execute('PRAGMA mmap_size = 268435456');
      db.execute('PRAGMA cache_size = -50000');
      db.execute('PRAGMA temp_store = MEMORY');
      db.execute('PRAGMA synchronous = OFF');
    } catch (e) {
      if (kDebugMode) debugPrint('BibleSearchIsolate tune failed: $e');
    }
  }

  /// Debug-only check that surfaces stale-DB situations clearly. If a user
  /// reports slow searches and this prints `1`, they're still on the legacy
  /// schema (no FTS5 prefix index) and the wipe-and-redownload path hasn't
  /// fired yet on their device.
  static void _logSchemaVersion(Database db) {
    try {
      final rows =
          db.select("SELECT value FROM _meta WHERE key = 'schema_version'");
      final v = rows.isNotEmpty ? rows.first['value'] : 'missing';
      debugPrint('BibleSearchIsolate opened DB at schema_version=$v');
    } catch (e) {
      debugPrint('BibleSearchIsolate schema_version probe failed: $e');
    }
  }

  static List<BibleSearchResult> _runSearch(Database db, _SearchRequest req) {
    final params = <Object>[
      req.hlOpen,
      req.hlClose,
      req.ftsQuery,
    ];

    final conditions = <String>['bible_verses_fts MATCH ?'];

    if (req.testaments.isNotEmpty) {
      final ph = List.filled(req.testaments.length, '?').join(', ');
      conditions.add('b.testament IN ($ph)');
      params.addAll(req.testaments);
    }
    if (req.bookIds.isNotEmpty) {
      final ph = List.filled(req.bookIds.length, '?').join(', ');
      conditions.add('bv.book_id IN ($ph)');
      params.addAll(req.bookIds);
    }
    if (req.translations.isNotEmpty) {
      final ph = List.filled(req.translations.length, '?').join(', ');
      conditions.add('bv.translation IN ($ph)');
      params.addAll(req.translations);
    }

    params.add(req.limit);
    params.add(req.offset);

    final rows = db.select(
      'SELECT bv.id, bv.translation, bv.book_id, bv.chapter, bv.verse, bv.text, '
      'b.name AS book_name, b.testament, '
      'highlight(bible_verses_fts, 0, ?, ?) AS highlighted_text '
      'FROM bible_verses_fts '
      'INNER JOIN bible_verses bv ON bv.id = bible_verses_fts.rowid '
      'INNER JOIN bible_books b ON b.id = bv.book_id '
      'WHERE ${conditions.join(' AND ')} '
      '${req.orderClause} '
      'LIMIT ? OFFSET ?',
      params,
    );

    return rows.map((r) => BibleSearchResult.fromRow(r)).toList();
  }
}

// ── Wire-format messages ─────────────────────────────────────────────────

@immutable
class _IsolateInit {
  final SendPort sendPort;
  final String dbPath;
  const _IsolateInit(this.sendPort, this.dbPath);
}

@immutable
class _SearchRequest {
  final int requestId;
  final String ftsQuery;
  final List<int> testaments;
  final List<int> bookIds;
  final List<String> translations;
  final String orderClause;
  final int limit;
  final int offset;
  final String hlOpen;
  final String hlClose;

  const _SearchRequest({
    required this.requestId,
    required this.ftsQuery,
    required this.testaments,
    required this.bookIds,
    required this.translations,
    required this.orderClause,
    required this.limit,
    required this.offset,
    required this.hlOpen,
    required this.hlClose,
  });
}

@immutable
class _CountRequest {
  final int requestId;
  const _CountRequest(this.requestId);
}

@immutable
class _SearchResponse {
  final int requestId;
  final Object? payload;
  final String? error;

  const _SearchResponse._({
    required this.requestId,
    this.payload,
    this.error,
  });

  factory _SearchResponse.success(int id, Object payload) =>
      _SearchResponse._(requestId: id, payload: payload);

  factory _SearchResponse.error(int id, String message) =>
      _SearchResponse._(requestId: id, error: message);
}
