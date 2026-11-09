import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notify/features/bible/data/bible_database_service.dart';
import 'package:notify/features/bible/data/bible_schema_ddl.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Builds a Bible db file holding one translation with [verses] verses.
void _buildDb(String path, String translation, int verses,
    {String word = 'grace'}) {
  final db = sqlite3.open(path);
  try {
    for (final ddl in bibleSchemaDDL) {
      db.execute(ddl);
    }
    db.execute(
        "INSERT OR REPLACE INTO _meta(key, value) VALUES ('schema_version', '$bibleSchemaVersion')");
    db.execute(
        "INSERT OR IGNORE INTO bible_books(id, name, short_name, testament, sort_order) VALUES (1, 'Genesis', 'Gen', 0, 1)");
    for (var v = 1; v <= verses; v++) {
      db.execute(
        'INSERT INTO bible_verses(translation, book_id, chapter, verse, text) VALUES (?, 1, 1, ?, ?)',
        [translation, v, '$translation $word verse $v'],
      );
    }
  } finally {
    db.dispose();
  }
}

void main() {
  late Directory tmp;
  late HttpServer server;
  final hits = <String>[];
  final gates = <String, Completer<void>>{};

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('bible_svc_test');
    hits.clear();
    gates.clear();
    for (final c in ['AAA', 'BBB']) {
      _buildDb(p.join(tmp.path, '$c.src'), c, 5, word: c == 'AAA' ? 'grace' : 'mercy');
    }
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final code = req.uri.pathSegments.last;
      hits.add(code);
      await gates[code]?.future;
      req.response.add(await File(p.join(tmp.path, '$code.src')).readAsBytes());
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await tmp.delete(recursive: true);
  });

  String url(String code) => 'http://127.0.0.1:${server.port}/$code';

  BibleDatabaseService makeService() => BibleDatabaseService(
        dbPathResolver: () async => p.join(tmp.path, 'bible.db'),
      );

  test('two installs queued from an empty state: first-install then merge',
      () async {
    final svc = makeService();
    addTearDown(svc.dispose);
    expect(svc.isOpen, isFalse);

    gates['AAA'] = Completer<void>();
    // Both are requested while nothing is installed.
    final a = svc.install('AAA', url('AAA'));
    final b = svc.install('BBB', url('BBB'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    // The second has not even started its download (serialized).
    expect(hits, ['AAA']);
    gates['AAA']!.complete();
    await Future.wait([a, b]);

    expect(svc.isOpen, isTrue);
    final rows = svc.db.select(
        'SELECT translation, COUNT(*) AS n FROM bible_verses GROUP BY translation ORDER BY translation');
    expect(rows.map((r) => [r['translation'], r['n']]).toList(), [
      ['AAA', 5],
      ['BBB', 5],
    ]);
    // Merge ran on another connection; FTS triggers fired for merged rows.
    final fts = svc.db.select(
        "SELECT rowid FROM bible_verses_fts WHERE bible_verses_fts MATCH 'mercy'");
    expect(fts.length, 5);
    final fts2 = svc.db.select(
        "SELECT rowid FROM bible_verses_fts WHERE bible_verses_fts MATCH 'grace'");
    expect(fts2.length, 5);
    // Scratch files are gone.
    expect(File(p.join(tmp.path, 'bible.db.BBB.tmp')).existsSync(), isFalse);
    expect(File(p.join(tmp.path, 'bible.db.tmp')).existsSync(), isFalse);
  });

  test('cancelling a queued install leaves the other to first-install',
      () async {
    final svc = makeService();
    addTearDown(svc.dispose);
    gates['AAA'] = Completer<void>();
    final a = svc.install('AAA', url('AAA'));
    final b = svc.install('BBB', url('BBB'));
    final bResult = expectLater(b, throwsA(isA<BibleDownloadCancelled>()));
    svc.cancelDownload('BBB');
    gates['AAA']!.complete();
    await a;
    await bResult;
    expect(hits, ['AAA']);
    expect(svc.db.select('SELECT DISTINCT translation FROM bible_verses').length, 1);
  });

  test('mergeVersionFile merges rows and keeps FTS in sync', () {
    final main = p.join(tmp.path, 'main.db');
    _buildDb(main, 'AAA', 3);
    mergeVersionFile(main, p.join(tmp.path, 'BBB.src'), 'src_0');
    // Merging again is idempotent (INSERT OR IGNORE).
    mergeVersionFile(main, p.join(tmp.path, 'BBB.src'), 'src_1');
    final db = sqlite3.open(main);
    addTearDown(db.dispose);
    expect(db.select('SELECT COUNT(*) AS n FROM bible_verses').first['n'], 8);
    expect(
        db
            .select(
                "SELECT rowid FROM bible_verses_fts WHERE bible_verses_fts MATCH 'mercy'")
            .length,
        5);
  });
}
