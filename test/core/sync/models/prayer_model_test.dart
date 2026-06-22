import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/database/tables/prayers_table.dart';
import 'package:notify/core/sync/models/prayer_model.dart';

void main() {
  group('PrayerModel', () {
    test('constructor sets all fields', () {
      final prayer = PrayerModel(
        id: 'p-1',
        userId: 'test-user',
        title: 'Test Prayer',
        content: 'Lord, help me...',
        frequency: PrayerFrequency.daily,
        status: PrayerStatus.active,
        category: 'personal',
        answeredAt: null,
        updatedAt: 1000,
        version: 1,
        deleted: 0,
        createdAt: 1000,
      );

      expect(prayer.id, 'p-1');
      expect(prayer.title, 'Test Prayer');
      expect(prayer.content, 'Lord, help me...');
      expect(prayer.frequency, PrayerFrequency.daily);
      expect(prayer.status, PrayerStatus.active);
      expect(prayer.category, 'personal');
      expect(prayer.answeredAt, isNull);
      expect(prayer.version, 1);
      expect(prayer.deleted, 0);
    });

    test('isDeleted returns correct values', () {
      final active = PrayerModel(
        id: 'p-1', userId: 'test-user', title: 'T', content: '',
        frequency: PrayerFrequency.daily, status: PrayerStatus.active,
        updatedAt: 1000, version: 1, deleted: 0, createdAt: 1000,
      );
      final deleted = PrayerModel(
        id: 'p-2', userId: 'test-user', title: 'T', content: '',
        frequency: PrayerFrequency.daily, status: PrayerStatus.active,
        updatedAt: 1000, version: 1, deleted: 1, createdAt: 1000,
      );

      expect(active.isDeleted, false);
      expect(deleted.isDeleted, true);
    });

    test('isAnswered returns true only for answered status', () {
      final active = PrayerModel(
        id: 'p-1', userId: 'test-user', title: 'T', content: '',
        frequency: PrayerFrequency.daily, status: PrayerStatus.active,
        updatedAt: 1000, version: 1, deleted: 0, createdAt: 1000,
      );
      final answered = PrayerModel(
        id: 'p-2', userId: 'test-user', title: 'T', content: '',
        frequency: PrayerFrequency.daily, status: PrayerStatus.answered,
        updatedAt: 1000, version: 1, deleted: 0, createdAt: 1000,
      );

      expect(active.isAnswered, false);
      expect(answered.isAnswered, true);
    });

    test('isActive returns true only for active status', () {
      final active = PrayerModel(
        id: 'p-1', userId: 'test-user', title: 'T', content: '',
        frequency: PrayerFrequency.daily, status: PrayerStatus.active,
        updatedAt: 1000, version: 1, deleted: 0, createdAt: 1000,
      );
      final archived = PrayerModel(
        id: 'p-2', userId: 'test-user', title: 'T', content: '',
        frequency: PrayerFrequency.daily, status: PrayerStatus.archived,
        updatedAt: 1000, version: 1, deleted: 0, createdAt: 1000,
      );

      expect(active.isActive, true);
      expect(archived.isActive, false);
    });

    group('create factory', () {
      test('defaults are correct', () {
        final prayer = PrayerModel.create(
          id: 'p-new',
          userId: 'test-user',
          title: 'New Prayer',
        );

        expect(prayer.id, 'p-new');
        expect(prayer.title, 'New Prayer');
        expect(prayer.content, '');
        expect(prayer.frequency, PrayerFrequency.daily);
        expect(prayer.status, PrayerStatus.active);
        expect(prayer.category, isNull);
        expect(prayer.answeredAt, isNull);
        expect(prayer.version, 1);
        expect(prayer.deleted, 0);
        expect(prayer.createdAt, prayer.updatedAt);
      });

      test('accepts all parameters', () {
        final prayer = PrayerModel.create(
          id: 'p-full',
          userId: 'test-user',
          title: 'Full Prayer',
          content: 'Detailed description',
          frequency: PrayerFrequency.weekly,
          status: PrayerStatus.active,
          category: 'family',
        );

        expect(prayer.content, 'Detailed description');
        expect(prayer.frequency, PrayerFrequency.weekly);
        expect(prayer.category, 'family');
      });
    });

    group('toJson / fromJson round-trip', () {
      test('round-trip preserves all fields', () {
        final original = PrayerModel(
          id: 'p-rt',
          userId: 'test-user',
          title: 'Round Trip',
          content: 'Testing...',
          frequency: PrayerFrequency.weekdays,
          status: PrayerStatus.answered,
          category: 'test',
          answeredAt: 2000,
          updatedAt: 1500,
          version: 3,
          deleted: 0,
          createdAt: 1000,
        );

        final json = original.toJson();
        final restored = PrayerModel.fromJson(json);

        expect(restored.id, original.id);
        expect(restored.title, original.title);
        expect(restored.content, original.content);
        expect(restored.frequency, original.frequency);
        expect(restored.status, original.status);
        expect(restored.category, original.category);
        expect(restored.answeredAt, original.answeredAt);
        expect(restored.updatedAt, original.updatedAt);
        expect(restored.version, original.version);
        expect(restored.deleted, original.deleted);
        expect(restored.createdAt, original.createdAt);
      });

      test('fromJson defaults content to empty string', () {
        final json = {
          'id': 'p-1',
          'userId': 'test-user',
          'title': 'T',
          'frequency': 'daily',
          'status': 'active',
          'updatedAt': 1000,
          'version': 1,
          'createdAt': 1000,
        };

        final prayer = PrayerModel.fromJson(json);
        expect(prayer.content, '');
      });

      test('fromJson defaults deleted to 0', () {
        final json = {
          'id': 'p-1',
          'userId': 'test-user',
          'title': 'T',
          'content': '',
          'frequency': 'daily',
          'status': 'active',
          'updatedAt': 1000,
          'version': 1,
          'createdAt': 1000,
        };

        final prayer = PrayerModel.fromJson(json);
        expect(prayer.deleted, 0);
      });

      test('fromJson handles unknown frequency gracefully', () {
        final json = {
          'id': 'p-1',
          'userId': 'test-user',
          'title': 'T',
          'content': '',
          'frequency': 'hourly',
          'status': 'active',
          'updatedAt': 1000,
          'version': 1,
          'createdAt': 1000,
        };

        final prayer = PrayerModel.fromJson(json);
        expect(prayer.frequency, PrayerFrequency.daily);
      });

      test('fromJson handles unknown status gracefully', () {
        final json = {
          'id': 'p-1',
          'userId': 'test-user',
          'title': 'T',
          'content': '',
          'frequency': 'daily',
          'status': 'unknown',
          'updatedAt': 1000,
          'version': 1,
          'createdAt': 1000,
        };

        final prayer = PrayerModel.fromJson(json);
        expect(prayer.status, PrayerStatus.active);
      });
    });

    group('copyWithUpdate', () {
      final original = PrayerModel(
        id: 'p-1',
        userId: 'test-user',
        title: 'Original',
        content: 'Content',
        frequency: PrayerFrequency.daily,
        status: PrayerStatus.active,
        category: 'test',
        answeredAt: null,
        updatedAt: 1000,
        version: 1,
        deleted: 0,
        createdAt: 1000,
      );

      test('updates title and increments version', () {
        final updated = original.copyWithUpdate(title: 'Updated Title');
        expect(updated.title, 'Updated Title');
        expect(updated.version, 2);
        expect(updated.content, original.content);
      });

      test('updates multiple fields', () {
        final updated = original.copyWithUpdate(
          title: 'New',
          content: 'New Content',
          frequency: PrayerFrequency.monthly,
        );
        expect(updated.title, 'New');
        expect(updated.content, 'New Content');
        expect(updated.frequency, PrayerFrequency.monthly);
        expect(updated.version, 2);
      });

      test('preserves all fields when nothing specified', () {
        final updated = original.copyWithUpdate();
        expect(updated.title, original.title);
        expect(updated.content, original.content);
        expect(updated.frequency, original.frequency);
        expect(updated.status, original.status);
        expect(updated.category, original.category);
        expect(updated.version, 2);
      });
    });

    group('markAnswered', () {
      test('sets status to answered and records answeredAt', () {
        final prayer = PrayerModel.create(
          id: 'p-1',
          userId: 'test-user',
          title: 'Test',
        );

        final answered = prayer.markAnswered();
        expect(answered.status, PrayerStatus.answered);
        expect(answered.answeredAt, isNotNull);
        expect(answered.answeredAt, greaterThan(0));
        expect(answered.isAnswered, true);
        expect(answered.version, 2);
      });
    });

    group('archive', () {
      test('sets status to archived', () {
        final prayer = PrayerModel.create(
          id: 'p-1',
          userId: 'test-user',
          title: 'Test',
        );

        final archived = prayer.archive();
        expect(archived.status, PrayerStatus.archived);
        expect(archived.isActive, false);
        expect(archived.version, 2);
      });
    });

    group('softDelete', () {
      test('sets deleted to 1 and increments version', () {
        final prayer = PrayerModel.create(
          id: 'p-1',
          userId: 'test-user',
          title: 'Test',
        );

        final deleted = prayer.softDelete();
        expect(deleted.isDeleted, true);
        expect(deleted.deleted, 1);
        expect(deleted.version, 2);
        expect(deleted.id, prayer.id);
        expect(deleted.title, prayer.title);
      });
    });

    group('equality', () {
      test('equal when same id and version', () {
        final a = PrayerModel(
          id: 'p-1', userId: 'test-user', title: 'A', content: '',
          frequency: PrayerFrequency.daily, status: PrayerStatus.active,
          updatedAt: 1000, version: 1, deleted: 0, createdAt: 1000,
        );
        final b = PrayerModel(
          id: 'p-1', userId: 'test-user', title: 'B', content: 'different',
          frequency: PrayerFrequency.weekly, status: PrayerStatus.answered,
          updatedAt: 2000, version: 1, deleted: 0, createdAt: 500,
        );

        expect(a, equals(b));
      });

      test('not equal when different version', () {
        final a = PrayerModel(
          id: 'p-1', userId: 'test-user', title: 'A', content: '',
          frequency: PrayerFrequency.daily, status: PrayerStatus.active,
          updatedAt: 1000, version: 1, deleted: 0, createdAt: 1000,
        );
        final b = PrayerModel(
          id: 'p-1', userId: 'test-user', title: 'A', content: '',
          frequency: PrayerFrequency.daily, status: PrayerStatus.active,
          updatedAt: 1000, version: 2, deleted: 0, createdAt: 1000,
        );

        expect(a, isNot(equals(b)));
      });
    });

    test('toString contains key info', () {
      final prayer = PrayerModel(
        id: 'p-ts', userId: 'test-user', title: 'Test Prayer', content: '',
        frequency: PrayerFrequency.daily, status: PrayerStatus.active,
        updatedAt: 1000, version: 2, deleted: 0, createdAt: 1000,
      );

      final str = prayer.toString();
      expect(str, contains('p-ts'));
      expect(str, contains('Test Prayer'));
      expect(str, contains('active'));
      expect(str, contains('v2'));
    });
  });

  group('PrayerFrequency', () {
    test('displayName returns correct values', () {
      expect(PrayerFrequency.daily.displayName, 'Daily');
      expect(PrayerFrequency.weekdays.displayName, 'Weekdays');
      expect(PrayerFrequency.weekly.displayName, 'Weekly');
      expect(PrayerFrequency.monthly.displayName, 'Monthly');
      expect(PrayerFrequency.asNeeded.displayName, 'As Needed');
    });
  });

  group('PrayerStatus', () {
    test('displayName returns correct values', () {
      expect(PrayerStatus.active.displayName, 'Active');
      expect(PrayerStatus.answered.displayName, 'Answered');
      expect(PrayerStatus.archived.displayName, 'Archived');
    });
  });
}
