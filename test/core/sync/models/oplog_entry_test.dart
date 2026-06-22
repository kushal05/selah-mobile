import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/sync/models/oplog_entry.dart';

void main() {
  group('OplogOperation', () {
    test('toDbValue returns correct strings', () {
      expect(OplogOperation.insert.toDbValue(), 'INSERT');
      expect(OplogOperation.update.toDbValue(), 'UPDATE');
      expect(OplogOperation.delete.toDbValue(), 'DELETE');
    });

    test('fromDbValue returns correct enum values', () {
      expect(OplogOperation.fromDbValue('INSERT'), OplogOperation.insert);
      expect(OplogOperation.fromDbValue('UPDATE'), OplogOperation.update);
      expect(OplogOperation.fromDbValue('DELETE'), OplogOperation.delete);
    });

    test('fromDbValue throws on unknown value', () {
      expect(
        () => OplogOperation.fromDbValue('UNKNOWN'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('OplogEntityType', () {
    test('toDbValue returns correct strings', () {
      expect(OplogEntityType.folder.toDbValue(), 'folder');
      expect(OplogEntityType.note.toDbValue(), 'note');
      expect(OplogEntityType.noteBlock.toDbValue(), 'note_block');
      expect(OplogEntityType.prayer.toDbValue(), 'prayer');
      expect(OplogEntityType.promise.toDbValue(), 'promise');
      expect(OplogEntityType.person.toDbValue(), 'person');
      expect(OplogEntityType.song.toDbValue(), 'song');
    });

    test('fromDbValue returns correct enum values', () {
      expect(OplogEntityType.fromDbValue('folder'), OplogEntityType.folder);
      expect(OplogEntityType.fromDbValue('note'), OplogEntityType.note);
      expect(OplogEntityType.fromDbValue('note_block'), OplogEntityType.noteBlock);
      expect(OplogEntityType.fromDbValue('prayer'), OplogEntityType.prayer);
      expect(OplogEntityType.fromDbValue('promise'), OplogEntityType.promise);
      expect(OplogEntityType.fromDbValue('person'), OplogEntityType.person);
      expect(OplogEntityType.fromDbValue('song'), OplogEntityType.song);
    });

    test('fromDbValue throws on unknown value', () {
      expect(
        () => OplogEntityType.fromDbValue('unknown'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('OplogEntry', () {
    final payload = {'title': 'Test', 'content': 'Hello'};

    test('constructor sets all fields', () {
      final entry = OplogEntry(
        opId: 'op-1',
        entityType: OplogEntityType.note,
        entityId: 'note-1',
        operation: OplogOperation.insert,
        payload: payload,
        timestamp: 1000,
        deviceId: 'device-1',
        entityVersion: 1,
      );

      expect(entry.opId, 'op-1');
      expect(entry.entityType, OplogEntityType.note);
      expect(entry.entityId, 'note-1');
      expect(entry.operation, OplogOperation.insert);
      expect(entry.payload, payload);
      expect(entry.timestamp, 1000);
      expect(entry.deviceId, 'device-1');
      expect(entry.entityVersion, 1);
      expect(entry.synced, false);
      expect(entry.serverTimestamp, isNull);
    });

    group('factory constructors', () {
      test('insert sets operation to insert', () {
        final entry = OplogEntry.insert(
          opId: 'op-1',
          entityType: OplogEntityType.folder,
          entityId: 'folder-1',
          payload: payload,
          deviceId: 'device-1',
          entityVersion: 1,
        );
        expect(entry.operation, OplogOperation.insert);
        expect(entry.synced, false);
        expect(entry.timestamp, greaterThan(0));
      });

      test('update sets operation to update', () {
        final entry = OplogEntry.update(
          opId: 'op-2',
          entityType: OplogEntityType.prayer,
          entityId: 'prayer-1',
          payload: payload,
          deviceId: 'device-1',
          entityVersion: 2,
        );
        expect(entry.operation, OplogOperation.update);
        expect(entry.entityVersion, 2);
      });

      test('delete sets operation to delete', () {
        final entry = OplogEntry.delete(
          opId: 'op-3',
          entityType: OplogEntityType.song,
          entityId: 'song-1',
          payload: payload,
          deviceId: 'device-1',
          entityVersion: 3,
        );
        expect(entry.operation, OplogOperation.delete);
        expect(entry.entityVersion, 3);
      });
    });

    group('toJson / fromJson round-trip', () {
      test('round-trip preserves all fields', () {
        final original = OplogEntry(
          opId: 'op-rt',
          entityType: OplogEntityType.promise,
          entityId: 'promise-1',
          operation: OplogOperation.update,
          payload: {'reference': 'John 3:16', 'content': 'For God so loved...'},
          timestamp: 1700000000000,
          deviceId: 'device-abc',
          entityVersion: 5,
          synced: true,
          serverTimestamp: 1700000001000,
        );

        final json = original.toJson();
        final restored = OplogEntry.fromJson(json);

        expect(restored.opId, original.opId);
        expect(restored.entityType, original.entityType);
        expect(restored.entityId, original.entityId);
        expect(restored.operation, original.operation);
        expect(restored.payload, original.payload);
        expect(restored.timestamp, original.timestamp);
        expect(restored.deviceId, original.deviceId);
        expect(restored.entityVersion, original.entityVersion);
        expect(restored.synced, original.synced);
        expect(restored.serverTimestamp, original.serverTimestamp);
      });

      test('fromJson handles payload as String', () {
        final json = {
          'opId': 'op-str',
          'entityType': 'note',
          'entityId': 'note-1',
          'operation': 'INSERT',
          'payload': '{"title":"Test"}',
          'timestamp': 1000,
          'deviceId': 'dev-1',
          'entityVersion': 1,
          'synced': false,
        };

        final entry = OplogEntry.fromJson(json);
        expect(entry.payload, {'title': 'Test'});
      });

      test('fromJson handles synced as int (1)', () {
        final json = {
          'opId': 'op-int',
          'entityType': 'folder',
          'entityId': 'folder-1',
          'operation': 'UPDATE',
          'payload': <String, dynamic>{},
          'timestamp': 1000,
          'deviceId': 'dev-1',
          'entityVersion': 1,
          'synced': 1,
        };

        final entry = OplogEntry.fromJson(json);
        expect(entry.synced, true);
      });

      test('toJson omits serverTimestamp when null', () {
        final entry = OplogEntry(
          opId: 'op-null',
          entityType: OplogEntityType.person,
          entityId: 'person-1',
          operation: OplogOperation.insert,
          payload: {},
          timestamp: 1000,
          deviceId: 'dev-1',
          entityVersion: 1,
        );

        final json = entry.toJson();
        expect(json.containsKey('serverTimestamp'), false);
      });
    });

    test('payloadJson returns JSON string', () {
      final entry = OplogEntry(
        opId: 'op-pj',
        entityType: OplogEntityType.note,
        entityId: 'note-1',
        operation: OplogOperation.insert,
        payload: {'key': 'value'},
        timestamp: 1000,
        deviceId: 'dev-1',
        entityVersion: 1,
      );

      expect(entry.payloadJson, '{"key":"value"}');
    });

    test('markSynced returns copy with synced = true', () {
      final entry = OplogEntry(
        opId: 'op-ms',
        entityType: OplogEntityType.folder,
        entityId: 'folder-1',
        operation: OplogOperation.update,
        payload: {'name': 'New Folder'},
        timestamp: 1000,
        deviceId: 'dev-1',
        entityVersion: 2,
      );

      expect(entry.synced, false);

      final synced = entry.markSynced(serverTs: 2000);
      expect(synced.synced, true);
      expect(synced.serverTimestamp, 2000);
      // Original unchanged
      expect(entry.synced, false);
      // All other fields preserved
      expect(synced.opId, entry.opId);
      expect(synced.entityType, entry.entityType);
      expect(synced.entityId, entry.entityId);
      expect(synced.operation, entry.operation);
      expect(synced.payload, entry.payload);
      expect(synced.deviceId, entry.deviceId);
      expect(synced.entityVersion, entry.entityVersion);
    });

    test('markSynced without serverTs uses current time', () {
      final entry = OplogEntry(
        opId: 'op-ms2',
        entityType: OplogEntityType.song,
        entityId: 'song-1',
        operation: OplogOperation.insert,
        payload: {},
        timestamp: 1000,
        deviceId: 'dev-1',
        entityVersion: 1,
      );

      final synced = entry.markSynced();
      expect(synced.synced, true);
      expect(synced.serverTimestamp, isNotNull);
      expect(synced.serverTimestamp, greaterThan(0));
    });

    test('toString contains key info', () {
      final entry = OplogEntry(
        opId: 'op-ts',
        entityType: OplogEntityType.prayer,
        entityId: 'prayer-1',
        operation: OplogOperation.delete,
        payload: {},
        timestamp: 1000,
        deviceId: 'dev-1',
        entityVersion: 3,
      );

      final str = entry.toString();
      expect(str, contains('op-ts'));
      expect(str, contains('prayer'));
      expect(str, contains('prayer-1'));
      expect(str, contains('delete'));
      expect(str, contains('v3'));
    });
  });
}
