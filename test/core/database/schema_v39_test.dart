// v39: sync_song_tags.weight, for ranked song search.

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/database/sync_database.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test('upgrading adds the weight column (2 for existing links) and resyncs once',
      () async {
    final dir = await Directory.systemTemp.createTemp('selah_v39_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/sync.sqlite');

    // A v38 phone: the table without the column, one link, a cursor.
    final phone = SyncDatabase.forTesting(NativeDatabase(file));
    await phone.customSelect('SELECT 1').get();
    await phone.customStatement('DROP TABLE sync_song_tags');
    await phone.customStatement(
      'CREATE TABLE sync_song_tags (id TEXT NOT NULL PRIMARY KEY, song_id TEXT NOT NULL, '
      'tag_id TEXT NOT NULL, user_id TEXT NOT NULL, updated_at INTEGER NOT NULL, '
      'version INTEGER NOT NULL DEFAULT 1, deleted INTEGER NOT NULL DEFAULT 0, '
      'trashed_at INTEGER, created_at INTEGER NOT NULL)',
    );
    await phone.customStatement(
        "INSERT INTO sync_song_tags VALUES ('l1','s1','t1','u1',1,1,0,NULL,1)");
    await phone.customStatement(
        "UPDATE sync_state SET last_remote_cursor = '1700000000000_op9'");
    await phone.customStatement('PRAGMA user_version = 38');
    await phone.close();

    final updated = SyncDatabase.forTesting(NativeDatabase(file));
    addTearDown(updated.close);
    final row = await updated.select(updated.syncSongTags).getSingle();
    expect(row.weight, 2);
    final cursor = await updated
        .customSelect('SELECT last_remote_cursor FROM sync_state WHERE id = 1')
        .map((r) => r.readNullable<String>('last_remote_cursor'))
        .getSingle();
    expect(cursor, isNull,
        reason: 'builds without the column applied the weight updates and had '
            'nowhere to keep them; one full pull brings them');
  });
}
