import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/sync/models/folder_model.dart';

void main() {
  group('FolderModel', () {
    test('constructor sets all fields', () {
      final folder = FolderModel(
        id: 'f-1',
        parentId: 'f-0',
        name: 'My Folder',
        userId: 'user-1',
        updatedAt: 1000,
        version: 1,
        deleted: 0,
        createdAt: 1000,
      );

      expect(folder.id, 'f-1');
      expect(folder.parentId, 'f-0');
      expect(folder.name, 'My Folder');
      expect(folder.userId, 'user-1');
      expect(folder.updatedAt, 1000);
      expect(folder.version, 1);
      expect(folder.deleted, 0);
      expect(folder.createdAt, 1000);
    });

    test('isDeleted returns true when deleted == 1', () {
      final folder = FolderModel(
        id: 'f-1',
        name: 'Deleted',
        userId: 'u-1',
        updatedAt: 1000,
        version: 1,
        deleted: 1,
        createdAt: 1000,
      );
      expect(folder.isDeleted, true);
    });

    test('isDeleted returns false when deleted == 0', () {
      final folder = FolderModel(
        id: 'f-1',
        name: 'Active',
        userId: 'u-1',
        updatedAt: 1000,
        version: 1,
        deleted: 0,
        createdAt: 1000,
      );
      expect(folder.isDeleted, false);
    });

    test('isRoot returns true when parentId is null', () {
      final folder = FolderModel(
        id: 'f-1',
        parentId: null,
        name: 'Root',
        userId: 'u-1',
        updatedAt: 1000,
        version: 1,
        deleted: 0,
        createdAt: 1000,
      );
      expect(folder.isRoot, true);
    });

    test('isRoot returns false when parentId is set', () {
      final folder = FolderModel(
        id: 'f-1',
        parentId: 'f-0',
        name: 'Child',
        userId: 'u-1',
        updatedAt: 1000,
        version: 1,
        deleted: 0,
        createdAt: 1000,
      );
      expect(folder.isRoot, false);
    });

    group('create factory', () {
      test('creates folder with version 1 and deleted 0', () {
        final folder = FolderModel.create(
          id: 'f-new',
          name: 'New Folder',
          userId: 'u-1',
        );

        expect(folder.id, 'f-new');
        expect(folder.name, 'New Folder');
        expect(folder.userId, 'u-1');
        expect(folder.version, 1);
        expect(folder.deleted, 0);
        expect(folder.parentId, isNull);
        expect(folder.createdAt, folder.updatedAt);
        expect(folder.createdAt, greaterThan(0));
      });

      test('create with parentId', () {
        final folder = FolderModel.create(
          id: 'f-child',
          parentId: 'f-parent',
          name: 'Child',
          userId: 'u-1',
        );

        expect(folder.parentId, 'f-parent');
        expect(folder.isRoot, false);
      });
    });

    group('toJson / fromJson round-trip', () {
      test('round-trip preserves all fields including null parentId', () {
        final original = FolderModel(
          id: 'f-rt',
          parentId: null,
          name: 'Root Folder',
          userId: 'user-1',
          updatedAt: 1700000000000,
          version: 3,
          deleted: 0,
          createdAt: 1699000000000,
        );

        final json = original.toJson();
        final restored = FolderModel.fromJson(json);

        expect(restored.id, original.id);
        expect(restored.parentId, original.parentId);
        expect(restored.name, original.name);
        expect(restored.userId, original.userId);
        expect(restored.updatedAt, original.updatedAt);
        expect(restored.version, original.version);
        expect(restored.deleted, original.deleted);
        expect(restored.createdAt, original.createdAt);
      });

      test('round-trip preserves non-null parentId', () {
        final original = FolderModel(
          id: 'f-child',
          parentId: 'f-parent',
          name: 'Child',
          userId: 'user-1',
          updatedAt: 1000,
          version: 1,
          deleted: 0,
          createdAt: 1000,
        );

        final json = original.toJson();
        final restored = FolderModel.fromJson(json);

        expect(restored.parentId, 'f-parent');
      });

      test('fromJson defaults deleted to 0 when missing', () {
        final json = {
          'id': 'f-1',
          'parentId': null,
          'name': 'Test',
          'userId': 'u-1',
          'updatedAt': 1000,
          'version': 1,
          'createdAt': 1000,
        };

        final folder = FolderModel.fromJson(json);
        expect(folder.deleted, 0);
        expect(folder.isDeleted, false);
      });
    });

    group('copyWithUpdate', () {
      test('updates name and increments version', () {
        final original = FolderModel(
          id: 'f-1',
          name: 'Old Name',
          userId: 'u-1',
          updatedAt: 1000,
          version: 1,
          deleted: 0,
          createdAt: 1000,
        );

        final updated = original.copyWithUpdate(name: 'New Name');

        expect(updated.id, original.id);
        expect(updated.name, 'New Name');
        expect(updated.version, 2);
        expect(updated.updatedAt, greaterThan(original.updatedAt));
        expect(updated.createdAt, original.createdAt);
      });

      test('updates parentId', () {
        final original = FolderModel(
          id: 'f-1',
          parentId: null,
          name: 'Folder',
          userId: 'u-1',
          updatedAt: 1000,
          version: 1,
          deleted: 0,
          createdAt: 1000,
        );

        final updated = original.copyWithUpdate(parentId: 'f-parent');
        expect(updated.parentId, 'f-parent');
        expect(updated.version, 2);
      });

      test('preserves fields when not specified', () {
        final original = FolderModel(
          id: 'f-1',
          parentId: 'f-0',
          name: 'Folder',
          userId: 'u-1',
          updatedAt: 1000,
          version: 3,
          deleted: 0,
          createdAt: 500,
        );

        final updated = original.copyWithUpdate();
        expect(updated.name, original.name);
        expect(updated.parentId, original.parentId);
        expect(updated.userId, original.userId);
        expect(updated.version, 4);
      });
    });

    group('softDelete', () {
      test('sets deleted to 1 and increments version', () {
        final original = FolderModel(
          id: 'f-1',
          name: 'Folder',
          userId: 'u-1',
          updatedAt: 1000,
          version: 2,
          deleted: 0,
          createdAt: 1000,
        );

        final deleted = original.softDelete();

        expect(deleted.isDeleted, true);
        expect(deleted.deleted, 1);
        expect(deleted.version, 3);
        expect(deleted.id, original.id);
        expect(deleted.name, original.name);
        expect(deleted.updatedAt, greaterThan(original.updatedAt));
      });
    });

    group('equality', () {
      test('equal when same id and version', () {
        final a = FolderModel(
          id: 'f-1',
          name: 'A',
          userId: 'u-1',
          updatedAt: 1000,
          version: 1,
          deleted: 0,
          createdAt: 1000,
        );
        final b = FolderModel(
          id: 'f-1',
          name: 'B',
          userId: 'u-2',
          updatedAt: 2000,
          version: 1,
          deleted: 0,
          createdAt: 500,
        );

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('not equal when different version', () {
        final a = FolderModel(
          id: 'f-1',
          name: 'A',
          userId: 'u-1',
          updatedAt: 1000,
          version: 1,
          deleted: 0,
          createdAt: 1000,
        );
        final b = FolderModel(
          id: 'f-1',
          name: 'A',
          userId: 'u-1',
          updatedAt: 1000,
          version: 2,
          deleted: 0,
          createdAt: 1000,
        );

        expect(a, isNot(equals(b)));
      });

      test('not equal when different id', () {
        final a = FolderModel(
          id: 'f-1',
          name: 'Same',
          userId: 'u-1',
          updatedAt: 1000,
          version: 1,
          deleted: 0,
          createdAt: 1000,
        );
        final b = FolderModel(
          id: 'f-2',
          name: 'Same',
          userId: 'u-1',
          updatedAt: 1000,
          version: 1,
          deleted: 0,
          createdAt: 1000,
        );

        expect(a, isNot(equals(b)));
      });
    });

    test('toString contains key info', () {
      final folder = FolderModel(
        id: 'f-ts',
        name: 'Test Folder',
        userId: 'u-1',
        updatedAt: 1000,
        version: 2,
        deleted: 0,
        createdAt: 1000,
      );

      final str = folder.toString();
      expect(str, contains('f-ts'));
      expect(str, contains('Test Folder'));
      expect(str, contains('v2'));
    });
  });
}
