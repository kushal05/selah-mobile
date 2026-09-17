// Per-field update timestamps are what let two devices edit different fields
// of the same record and both keep their change. They are only useful if the
// model actually stamps the field that changed — and only that one — and if
// the value survives the round trip through Drift's JSON string column.
//
// This covers the shared parser and the first model wired to it. The engine's
// merge is tested separately; this is the layer underneath it.

import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/sync/models/field_timestamps.dart';
import 'package:notify/core/sync/models/folder_model.dart';
import 'package:notify/core/sync/models/person_model.dart';
import 'package:notify/core/sync/models/promise_model.dart';
import 'package:notify/core/sync/models/song_model.dart';
import 'package:notify/core/testing/test_clock.dart';

void main() {
  group('parseFieldTimestamps', () {
    test('reads the JSON string Drift stores', () {
      expect(parseFieldTimestamps('{"name":123,"notes":456}'), {
        'name': 123,
        'notes': 456,
      });
    });

    test('reads a decoded map from an API payload', () {
      expect(parseFieldTimestamps({'name': 123}), {'name': 123});
    });

    test('a record written before the column existed reads as empty', () {
      // Which makes the merge fall back to entity-level, rather than throwing.
      expect(parseFieldTimestamps(null), isEmpty);
      expect(parseFieldTimestamps('{}'), isEmpty);
      expect(parseFieldTimestamps(''), isEmpty);
    });

    test('malformed content is empty rather than fatal', () {
      expect(parseFieldTimestamps('not json'), isEmpty);
      expect(parseFieldTimestamps({'name': 'not a number'}), isEmpty);
      expect(parseFieldTimestamps(42), isEmpty);
    });
  });

  group('PersonModel field timestamps', () {
    test('a new person stamps every mergeable field', () {
      final person = PersonModel.create(id: 'p1', userId: 'u1', name: 'Ada');

      expect(
        person.fieldUpdatedAt.keys,
        containsAll(PersonModel.mergeableFields),
      );
    });

    test('an edit stamps only the field that changed', () {
      TestClock.setFixed(1000);
      final person = PersonModel.create(id: 'p1', userId: 'u1', name: 'Ada');
      final before = person.fieldUpdatedAt['name']!;
      addTearDown(TestClock.reset);

      TestClock.advance(5 * 60 * 1000);
      final edited = person.copyWithUpdate(notes: 'met at church');

      expect(
        edited.fieldUpdatedAt['notes'],
        greaterThan(before),
        reason: 'the edited field must carry the new time',
      );
      expect(
        edited.fieldUpdatedAt['name'],
        before,
        reason:
            'an untouched field must keep its old time, or the merge '
            'would think this device changed it too',
      );
    });

    test('timestamps survive the JSON round trip', () {
      final person = PersonModel.create(
        id: 'p1',
        userId: 'u1',
        name: 'Ada',
      ).copyWithUpdate(phone: '555');

      final restored = PersonModel.fromJson(person.toJson());

      expect(restored.fieldUpdatedAt, person.fieldUpdatedAt);
    });

    test('a soft delete does not disturb the timestamps', () {
      final person = PersonModel.create(id: 'p1', userId: 'u1', name: 'Ada');
      expect(person.softDelete().fieldUpdatedAt, person.fieldUpdatedAt);
    });
  });

  // The failure mode that is easy to introduce and invisible once shipped: a
  // constructor that omits the new parameter silently resets it to {}, which
  // erases every field's history and quietly drops the record back to
  // entity-level merge. Each model has several such constructors.
  group('every model keeps its timestamps through a non-field change', () {
    test('folder', () {
      final f = FolderModel.create(id: 'f1', userId: 'u1', name: 'Sermons');
      expect(f.fieldUpdatedAt, isNotEmpty);
      expect(
        f.softDelete().fieldUpdatedAt,
        f.fieldUpdatedAt,
        reason: 'a delete must not erase the merge history',
      );
    });

    test('promise', () {
      final p = PromiseModel.create(
        id: 'p1',
        userId: 'u1',
        reference: 'Rom 8:28',
        content: 'c',
      );
      expect(p.fieldUpdatedAt, isNotEmpty);
      expect(p.softDelete().fieldUpdatedAt, p.fieldUpdatedAt);
    });

    test('song', () {
      final s = SongModel.create(id: 's1', userId: 'u1', title: 'Amazing');
      expect(s.fieldUpdatedAt, isNotEmpty);
      expect(s.softDelete().fieldUpdatedAt, s.fieldUpdatedAt);
    });

    test('person', () {
      final p = PersonModel.create(id: 'p1', userId: 'u1', name: 'Ada');
      expect(p.fieldUpdatedAt, isNotEmpty);
      expect(p.softDelete().fieldUpdatedAt, p.fieldUpdatedAt);
    });
  });

  group('an edit stamps only what changed', () {
    test('song', () {
      TestClock.setFixed(1000);
      addTearDown(TestClock.reset);
      final song = SongModel.create(id: 's1', userId: 'u1', title: 'Amazing');
      final titleAt = song.fieldUpdatedAt['title']!;

      TestClock.advance(60 * 1000);
      final edited = song.copyWithUpdate(lyrics: 'new lyrics');

      expect(edited.fieldUpdatedAt['lyrics'], greaterThan(titleAt));
      expect(
        edited.fieldUpdatedAt['title'],
        titleAt,
        reason:
            'an untouched field must keep its time, or a merge would think '
            'this device changed it too and overwrite the other side',
      );
    });
  });
}
