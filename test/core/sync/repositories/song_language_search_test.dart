// Song search narrows by language, against a real database.
//
// The screen tests use a fake repository, so they prove the language reaches
// the search — not that the SQL then honours it. This does, and checks the
// language list the filter offers is the one the search will match.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/repositories/entity_access_repository.dart';
import 'package:notify/core/sync/repositories/song_repository.dart';

const _user = 'u1';
const _device = 'device-1';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late SyncDatabase db;
  late SongRepository songs;

  setUp(() async {
    db = SyncDatabase.forTesting(NativeDatabase.memory());
    songs = SongRepository(db, _device, EntityAccessRepository(db, _device));
    for (final (title, language, scale) in [
      ('Amazing Grace', 'English', 'G'),
      ('How Great Thou Art', 'English', 'C'),
      ('Yesu Raja', 'Telugu', 'G'),
      ('Stuti Aradhana', 'Telugu', 'D'),
      ('Nandri', 'Tamil', 'G'),
    ]) {
      await songs.createSong(
          userId: _user, title: title, language: language, scale: scale);
    }
    // Someone else's Telugu song, which must never be found.
    await songs.createSong(userId: 'u2', title: 'Other', language: 'Telugu');
  });
  tearDown(() => db.close());

  Future<List<String>> titles({String? language, String? scale}) async =>
      (await songs.searchSongsFiltered(
        userId: _user,
        language: language,
        scale: scale,
      ))
          .map((s) => s.title)
          .toList();

  test('a language narrows the results to it', () async {
    expect(await titles(language: 'Telugu'), ['Stuti Aradhana', 'Yesu Raja']);
  });

  test('and combines with the other filters rather than replacing them',
      () async {
    expect(await titles(language: 'Telugu', scale: 'G'), ['Yesu Raja']);
  });

  test('no language means every language', () async {
    expect(await titles(), hasLength(5));
  });

  test('the languages offered are exactly the ones the search will match',
      () async {
    // The filter lists getUniqueLanguages and the search matches the value
    // exactly, so every language offered must find something.
    final offered = await songs.getUniqueLanguages(_user);
    expect(offered, ['English', 'Tamil', 'Telugu']);
    for (final language in offered) {
      expect(await titles(language: language), isNotEmpty,
          reason: '"$language" is offered but finds nothing');
    }
  });

  test('a blank language is never offered, but its songs are not lost',
      () async {
    // The server's language column defaults to '', and the app substitutes
    // "English" only when the field is missing, so a song created without a
    // language arrives with an empty one. Offered, it would be a blank chip.
    // Tabs and newlines too: SQLite's TRIM strips only spaces unless told
    // otherwise, and the first version of this guard let them through.
    final blanks = {
      'No language': '',
      'Spaces': '   ',
      'Tab': '\t',
      'Newline': '\n',
      'Mixed': ' \t\r\n ',
    };
    for (final MapEntry(key: title, value: language) in blanks.entries) {
      await songs.createSong(userId: _user, title: title, language: language);
    }

    expect(await songs.getUniqueLanguages(_user), ['English', 'Tamil', 'Telugu'],
        reason: 'no blank or whitespace-only option');
    expect(await titles(), containsAll(blanks.keys),
        reason: 'they still show when no language is chosen');
  });

  test('the language column is indexed, so filtering by it seeks', () async {
    final plan = await db
        .customSelect("EXPLAIN QUERY PLAN SELECT s.* FROM songs s WHERE "
            "s.deleted = 0 AND s.trashed_at IS NULL AND s.user_id = 'u1' "
            "AND s.language = 'Telugu'")
        .get();
    final detail = plan.map((r) => r.read<String>('detail')).join(' | ');
    expect(detail, contains('USING INDEX idx_songs_language'), reason: detail);
  });
}
