import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/sync/models/oplog_entry.dart';
import 'package:notify/core/sync/models/promise_prayer_link_model.dart';

void main() {
  group('PromisePrayerLinkModel', () {
    test('create() sets correct defaults', () {
      final link = PromisePrayerLinkModel.create(
        id: 'link-1',
        promiseId: 'promise-1',
        prayerId: 'prayer-1',
        userId: 'user-1',
      );

      expect(link.id, 'link-1');
      expect(link.promiseId, 'promise-1');
      expect(link.prayerId, 'prayer-1');
      expect(link.userId, 'user-1');
      expect(link.version, 1);
      expect(link.deleted, 0);
      expect(link.isDeleted, false);
      expect(link.updatedAt, link.createdAt);
    });

    test('softDelete() increments version and sets deleted', () {
      final link = PromisePrayerLinkModel.create(
        id: 'link-1',
        promiseId: 'promise-1',
        prayerId: 'prayer-1',
        userId: 'user-1',
      );

      final deleted = link.softDelete();

      expect(deleted.id, link.id);
      expect(deleted.promiseId, link.promiseId);
      expect(deleted.prayerId, link.prayerId);
      expect(deleted.version, 2);
      expect(deleted.deleted, 1);
      expect(deleted.isDeleted, true);
      expect(deleted.createdAt, link.createdAt);
      expect(deleted.updatedAt, greaterThanOrEqualTo(link.updatedAt));
    });

    test('toJson() produces correct map', () {
      final link = PromisePrayerLinkModel(
        id: 'link-1',
        promiseId: 'promise-1',
        prayerId: 'prayer-1',
        userId: 'user-1',
        updatedAt: 1000,
        version: 1,
        deleted: 0,
        createdAt: 1000,
      );

      final json = link.toJson();

      expect(json['id'], 'link-1');
      expect(json['promiseId'], 'promise-1');
      expect(json['prayerId'], 'prayer-1');
      expect(json['userId'], 'user-1');
      expect(json['updatedAt'], 1000);
      expect(json['version'], 1);
      expect(json['deleted'], 0);
      expect(json['createdAt'], 1000);
    });

    test('fromJson() reconstructs model', () {
      final json = {
        'id': 'link-1',
        'promiseId': 'promise-1',
        'prayerId': 'prayer-1',
        'userId': 'user-1',
        'updatedAt': 2000,
        'version': 3,
        'deleted': 1,
        'createdAt': 1000,
      };

      final link = PromisePrayerLinkModel.fromJson(json);

      expect(link.id, 'link-1');
      expect(link.promiseId, 'promise-1');
      expect(link.prayerId, 'prayer-1');
      expect(link.userId, 'user-1');
      expect(link.updatedAt, 2000);
      expect(link.version, 3);
      expect(link.deleted, 1);
      expect(link.isDeleted, true);
      expect(link.createdAt, 1000);
    });

    test('fromJson() defaults deleted to 0 when null', () {
      final json = {
        'id': 'link-1',
        'promiseId': 'promise-1',
        'prayerId': 'prayer-1',
        'userId': 'user-1',
        'updatedAt': 1000,
        'version': 1,
        'createdAt': 1000,
      };

      final link = PromisePrayerLinkModel.fromJson(json);
      expect(link.deleted, 0);
      expect(link.isDeleted, false);
    });

    test('equality based on id and version', () {
      final a = PromisePrayerLinkModel(
        id: 'link-1',
        promiseId: 'promise-1',
        prayerId: 'prayer-1',
        userId: 'user-1',
        updatedAt: 1000,
        version: 1,
        deleted: 0,
        createdAt: 1000,
      );
      final b = PromisePrayerLinkModel(
        id: 'link-1',
        promiseId: 'promise-2',
        prayerId: 'prayer-2',
        userId: 'user-2',
        updatedAt: 2000,
        version: 1,
        deleted: 0,
        createdAt: 2000,
      );
      final c = PromisePrayerLinkModel(
        id: 'link-1',
        promiseId: 'promise-1',
        prayerId: 'prayer-1',
        userId: 'user-1',
        updatedAt: 1000,
        version: 2,
        deleted: 0,
        createdAt: 1000,
      );

      expect(a, equals(b)); // same id + version
      expect(a, isNot(equals(c))); // different version
    });

    test('implements SyncEntity interface', () {
      final link = PromisePrayerLinkModel.create(
        id: 'link-1',
        promiseId: 'promise-1',
        prayerId: 'prayer-1',
        userId: 'user-1',
      );

      expect(link.id, isNotEmpty);
      expect(link.updatedAt, isPositive);
      expect(link.version, 1);
      expect(link.isDeleted, false);
      expect(link.toJson(), isA<Map<String, dynamic>>());
    });
  });

  group('OplogEntityType.promisePrayerLink', () {
    test('toDbValue returns promise_prayer_link', () {
      expect(
        OplogEntityType.promisePrayerLink.toDbValue(),
        'promise_prayer_link',
      );
    });

    test('fromDbValue returns promisePrayerLink', () {
      expect(
        OplogEntityType.fromDbValue('promise_prayer_link'),
        OplogEntityType.promisePrayerLink,
      );
    });
  });
}
