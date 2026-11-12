// Updating an installed Bible version: knowing the host has a newer file, and
// swapping the installed verses for it without leaving old text behind.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:notify/features/bible/data/bible_database_service.dart';
import 'package:notify/features/bible/data/bible_schema_ddl.dart';
import 'package:notify/features/bible/data/bible_version_updates.dart';
import 'package:notify/features/bible/domain/models/bible_version_info.dart';

BibleVersionInfo _info(String code, [String? url]) => BibleVersionInfo(
      code: code,
      name: 'Version $code',
      downloadUrl: url ?? 'https://host.test/bible/$code.db',
      approximateSizeMb: 8,
      sortOrder: 0,
      isDefault: false,
      isDownloaded: true,
    );

/// A Bible db file holding [verses] ({verse: text}) of one translation.
void _buildDb(String path, String translation, Map<int, String> verses) {
  final db = sqlite3.open(path);
  try {
    for (final ddl in bibleSchemaDDL) {
      db.execute(ddl);
    }
    db.execute(
        "INSERT OR REPLACE INTO _meta(key, value) VALUES ('schema_version', '$bibleSchemaVersion')");
    db.execute(
        "INSERT OR IGNORE INTO bible_books(id, name, short_name, testament, sort_order) VALUES (1, 'Genesis', 'Gen', 0, 1)");
    verses.forEach((v, text) {
      db.execute(
        'INSERT INTO bible_verses(translation, book_id, chapter, verse, text) VALUES (?, 1, 1, ?, ?)',
        [translation, v, text],
      );
    });
  } finally {
    db.dispose();
  }
}

Map<int, String> _read(String path, String translation) {
  final db = sqlite3.open(path);
  try {
    return {
      for (final r in db.select(
          'SELECT verse, text FROM bible_verses WHERE translation = ? ORDER BY verse',
          [translation]))
        r['verse'] as int: r['text'] as String,
    };
  } finally {
    db.dispose();
  }
}

void main() {
  group('deciding whether there is an update', () {
    final newer = DateTime.utc(2026, 11, 20);
    final older = DateTime.utc(2026, 4, 22);

    test('with a saved stamp, a different ETag is an update', () {
      expect(
          bibleVersionNeedsUpdate(
              installedStamp: 'aaa', remote: const RemoteStamp(etag: 'bbb')),
          isTrue);
    });

    test('with a saved stamp, the same ETag is not', () {
      expect(
          bibleVersionNeedsUpdate(
              installedStamp: 'aaa', remote: const RemoteStamp(etag: 'aaa')),
          isFalse);
    });

    test('with a saved stamp, a host that sends no ETag is not an update', () {
      expect(
          bibleVersionNeedsUpdate(
              installedStamp: 'aaa', remote: RemoteStamp(lastModified: newer)),
          isFalse);
    });

    test('an install from before stamps, and a file written since: update', () {
      expect(
          bibleVersionNeedsUpdate(
              installedStamp: null, remote: RemoteStamp(lastModified: newer)),
          isTrue);
    });

    test('the files replaced on 12 Nov 2026 are newer than any old install', () {
      // Last-Modified of the first replaced files on the host.
      final replaced = DateTime.utc(2026, 11, 12, 20, 12, 32);
      expect(
          bibleVersionNeedsUpdate(
              installedStamp: null, remote: RemoteStamp(lastModified: replaced)),
          isTrue);
    });

    test('TEL, the newest file never replaced (June 2026), is not an update',
        () {
      expect(
          bibleVersionNeedsUpdate(
              installedStamp: null,
              remote: RemoteStamp(lastModified: DateTime.utc(2026, 6, 12, 11, 57))),
          isFalse);
    });

    test('an install from before stamps, and a file untouched since: none', () {
      expect(
          bibleVersionNeedsUpdate(
              installedStamp: null, remote: RemoteStamp(lastModified: older)),
          isFalse);
    });

    test('nothing known about the host file is not an update', () {
      expect(
          bibleVersionNeedsUpdate(
              installedStamp: null, remote: const RemoteStamp()),
          isFalse);
    });

    test('ETag quotes are dropped', () {
      expect(bibleStampFromHeaders({'etag': '"abc-2"'}), 'abc-2');
      expect(bibleStampFromHeaders({}), isNull);
    });
  });

  group('checking the host', () {
    late BibleVersionStamps stamps;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      stamps = BibleVersionStamps(await SharedPreferences.getInstance());
    });

    http.Client host(Map<String, Map<String, String>> headersByCode,
        {Set<String> failing = const {}}) {
      return MockClient((req) async {
        final code = p.basenameWithoutExtension(req.url.path);
        if (failing.contains(code)) throw const SocketException('offline');
        expect(req.method, 'HEAD');
        return http.Response('', 200, headers: headersByCode[code] ?? {});
      });
    }

    test('lists the installed versions whose file changed', () async {
      await stamps.write('TLB', 'old');
      await stamps.write('NIV', 'same');
      final checker = BibleVersionUpdateChecker(
        stamps,
        client: host({
          'TLB': {'etag': '"new"'},
          'NIV': {'etag': '"same"'},
        }),
      );

      expect(await checker.check([_info('TLB'), _info('NIV')]), {'TLB'});
    });

    test('an unstamped install is an update once the host file is newer',
        () async {
      final checker = BibleVersionUpdateChecker(
        stamps,
        client: host({
          'ICB': {'last-modified': 'Fri, 20 Nov 2026 10:00:00 GMT'},
          'ESV': {'last-modified': 'Wed, 22 Apr 2026 08:42:00 GMT'},
        }),
      );

      expect(await checker.check([_info('ICB'), _info('ESV')]), {'ICB'});
    });

    test('a host that cannot be reached is not an update', () async {
      await stamps.write('TLB', 'old');
      final checker = BibleVersionUpdateChecker(
        stamps,
        client: host({'TLB': {'etag': '"new"'}}, failing: {'TLB'}),
      );

      expect(await checker.check([_info('TLB')]), isEmpty);
    });
  });

  group('replacing a version', () {
    late Directory tmp;
    late String dbPath;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('bible_update_test');
      dbPath = p.join(tmp.path, 'bible.db');
    });

    tearDown(() => tmp.delete(recursive: true));

    test('the old verses go and the new ones come, in one go', () {
      _buildDb(dbPath, 'TLB', {1: 'one', 3: 'three', 5: 'old text of 4-5'});
      _buildDb(dbPath, 'KJV', {1: 'kjv one'});
      final src = p.join(tmp.path, 'TLB.src');
      _buildDb(src, 'TLB', {1: 'one', 3: 'three', 4: 'new text of 4-5'});

      mergeVersionFile(dbPath, src, 'src_a', replace: true);

      expect(_read(dbPath, 'TLB'),
          {1: 'one', 3: 'three', 4: 'new text of 4-5'},
          reason: 'verse 5 from the old copy must not stay behind');
      expect(_read(dbPath, 'KJV'), {1: 'kjv one'},
          reason: 'other versions are untouched');
    });

    test('the search index follows the replacement', () {
      _buildDb(dbPath, 'TLB', {1: 'apple', 2: 'pear'});
      final src = p.join(tmp.path, 'TLB.src');
      _buildDb(src, 'TLB', {1: 'banana'});

      mergeVersionFile(dbPath, src, 'src_a', replace: true);

      final db = sqlite3.open(dbPath);
      addTearDown(db.dispose);
      int hits(String word) => db
          .select("SELECT COUNT(*) AS n FROM bible_verses_fts WHERE bible_verses_fts MATCH ?",
              [word])
          .first['n'] as int;
      expect(hits('banana'), 1);
      expect(hits('apple'), 0);
      expect(hits('pear'), 0);
    });

    test('a download with no verses keeps what is installed', () {
      _buildDb(dbPath, 'TLB', {1: 'one', 2: 'two'});
      final src = p.join(tmp.path, 'TLB.src');
      _buildDb(src, 'TLB', {});

      expect(() => mergeVersionFile(dbPath, src, 'src_a', replace: true),
          throwsStateError);
      expect(_read(dbPath, 'TLB'), {1: 'one', 2: 'two'});
    });

    test('without replace, an install still only adds what is missing', () {
      _buildDb(dbPath, 'TLB', {1: 'one'});
      final src = p.join(tmp.path, 'TLB.src');
      _buildDb(src, 'TLB', {1: 'different', 2: 'two'});

      mergeVersionFile(dbPath, src, 'src_a');

      expect(_read(dbPath, 'TLB'), {1: 'one', 2: 'two'});
    });
  });

  group('through the service', () {
    late Directory tmp;
    late HttpServer server;
    late BibleDatabaseService service;
    var etag = '"v1"';

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('bible_update_svc');
      _buildDb(p.join(tmp.path, 'KJV.src'), 'KJV', {1: 'kjv'});
      _buildDb(p.join(tmp.path, 'TLB.src'), 'TLB', {1: 'one', 5: 'old'});
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final code = req.uri.pathSegments.last;
        req.response.headers.set('etag', etag);
        req.response.add(await File(p.join(tmp.path, '$code.src')).readAsBytes());
        await req.response.close();
      });
      service = BibleDatabaseService(
          dbPathResolver: () async => p.join(tmp.path, 'bible.db'));
    });

    tearDown(() async {
      service.dispose();
      await server.close(force: true);
      await tmp.delete(recursive: true);
    });

    String url(String code) =>
        'http://${server.address.host}:${server.port}/$code';

    test('an update replaces the installed copy and reports the new stamp',
        () async {
      String? first;
      await service.install('KJV', url('KJV'));
      await service.install('TLB', url('TLB'), onStamp: (s) => first = s);
      expect(first, 'v1', reason: 'the host sent "v1", quotes dropped');
      expect(_read(p.join(tmp.path, 'bible.db'), 'TLB'), {1: 'one', 5: 'old'});

      // The host now has a fuller file with a new ETag.
      File(p.join(tmp.path, 'TLB.src')).deleteSync();
      _buildDb(p.join(tmp.path, 'TLB.src'), 'TLB', {1: 'one', 4: 'new'});
      etag = '"v2"';

      String? second;
      await service.install('TLB', url('TLB'),
          replace: true, onStamp: (s) => second = s);

      expect(second, 'v2');
      expect(_read(p.join(tmp.path, 'bible.db'), 'TLB'), {1: 'one', 4: 'new'});
      expect(_read(p.join(tmp.path, 'bible.db'), 'KJV'), {1: 'kjv'});
    });
  });
}
