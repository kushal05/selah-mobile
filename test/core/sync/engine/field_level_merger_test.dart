import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/sync/engine/field_level_merger.dart';

void main() {
  late FieldLevelMerger merger;

  setUp(() {
    merger = FieldLevelMerger();
  });

  group('FieldLevelMerger', () {
    group('different fields edited on different devices', () {
      test('both field changes are preserved', () {
        // Base entity created at T=1000.
        // Device1 changes title at T=2000.
        // Device2 changes folderId at T=3000.
        final result = merger.merge(
          localFields: {'title': 'B', 'folderId': 'f1'},
          localFieldTimestamps: {'title': 2000, 'folderId': 1000},
          localUpdatedAt: 2000,
          localVersion: 2,
          remoteFields: {'title': 'A', 'folderId': 'f2'},
          remoteFieldTimestamps: {'title': 1000, 'folderId': 3000},
          remoteUpdatedAt: 3000,
          remoteVersion: 2,
          localDeviceId: 'device1',
          remoteDeviceId: 'device2',
          mergeableFieldNames: ['title', 'folderId'],
        );

        expect(result.mergedFields['title'], 'B');
        expect(result.mergedFields['folderId'], 'f2');
        expect(result.fieldResolutions['title'], 'local');
        expect(result.fieldResolutions['folderId'], 'remote');
      });

      test('note: title on device A, folderId on device B', () {
        // Created at T=1000.
        // DeviceA edits title at T=2000.
        // DeviceB moves to folder2 at T=3000.
        final result = merger.merge(
          localFields: {
            'title': 'Updated Title',
            'folderId': 'folder1',
            'preacherId': null,
            'noteDate': null,
            'documentJson': null,
          },
          localFieldTimestamps: {
            'title': 2000,
            'folderId': 1000,
            'preacherId': 1000,
            'noteDate': 1000,
            'documentJson': 1000,
          },
          localUpdatedAt: 2000,
          localVersion: 2,
          remoteFields: {
            'title': 'Original Title',
            'folderId': 'folder2',
            'preacherId': null,
            'noteDate': null,
            'documentJson': null,
          },
          remoteFieldTimestamps: {
            'title': 1000,
            'folderId': 3000,
            'preacherId': 1000,
            'noteDate': 1000,
            'documentJson': 1000,
          },
          remoteUpdatedAt: 3000,
          remoteVersion: 2,
          localDeviceId: 'deviceA',
          remoteDeviceId: 'deviceB',
          mergeableFieldNames: [
            'title',
            'folderId',
            'preacherId',
            'noteDate',
            'documentJson',
          ],
        );

        expect(result.mergedFields['title'], 'Updated Title');
        expect(result.mergedFields['folderId'], 'folder2');
        expect(result.mergedVersion, 2);
        expect(result.mergedUpdatedAt, 3000);
      });
    });

    group('same field edited on both devices', () {
      test('higher timestamp wins', () {
        final result = merger.merge(
          localFields: {'title': 'Local Title'},
          localFieldTimestamps: {'title': 1000},
          localUpdatedAt: 1000,
          localVersion: 2,
          remoteFields: {'title': 'Remote Title'},
          remoteFieldTimestamps: {'title': 2000},
          remoteUpdatedAt: 2000,
          remoteVersion: 2,
          localDeviceId: 'device1',
          remoteDeviceId: 'device2',
          mergeableFieldNames: ['title'],
        );

        expect(result.mergedFields['title'], 'Remote Title');
        expect(result.fieldResolutions['title'], 'remote');
      });

      test('local wins when local timestamp is higher', () {
        final result = merger.merge(
          localFields: {'title': 'Local Title'},
          localFieldTimestamps: {'title': 3000},
          localUpdatedAt: 3000,
          localVersion: 2,
          remoteFields: {'title': 'Remote Title'},
          remoteFieldTimestamps: {'title': 2000},
          remoteUpdatedAt: 2000,
          remoteVersion: 2,
          localDeviceId: 'device1',
          remoteDeviceId: 'device2',
          mergeableFieldNames: ['title'],
        );

        expect(result.mergedFields['title'], 'Local Title');
        expect(result.fieldResolutions['title'], 'local');
      });
    });

    group('timestamp tie — device ID tiebreaker', () {
      test('higher device ID wins on tie', () {
        final result = merger.merge(
          localFields: {'title': 'Local'},
          localFieldTimestamps: {'title': 5000},
          localUpdatedAt: 5000,
          localVersion: 2,
          remoteFields: {'title': 'Remote'},
          remoteFieldTimestamps: {'title': 5000},
          remoteUpdatedAt: 5000,
          remoteVersion: 2,
          localDeviceId: 'aaa',
          remoteDeviceId: 'zzz',
          mergeableFieldNames: ['title'],
        );

        // 'zzz' > 'aaa' → remote wins
        expect(result.mergedFields['title'], 'Remote');
        expect(result.fieldResolutions['title'], 'remote');
      });

      test('local wins when local device ID is higher', () {
        final result = merger.merge(
          localFields: {'title': 'Local'},
          localFieldTimestamps: {'title': 5000},
          localUpdatedAt: 5000,
          localVersion: 2,
          remoteFields: {'title': 'Remote'},
          remoteFieldTimestamps: {'title': 5000},
          remoteUpdatedAt: 5000,
          remoteVersion: 2,
          localDeviceId: 'zzz',
          remoteDeviceId: 'aaa',
          mergeableFieldNames: ['title'],
        );

        // 'aaa' < 'zzz' → local wins
        expect(result.mergedFields['title'], 'Local');
        expect(result.fieldResolutions['title'], 'local');
      });
    });

    group('fallback to entity-level updatedAt', () {
      test(
          'uses entity updatedAt when fieldUpdatedAt is empty (backward compat)',
          () {
        // Simulate pre-migration entity with no fieldUpdatedAt
        final result = merger.merge(
          localFields: {'title': 'Local', 'content': 'local content'},
          localFieldTimestamps: {}, // empty — pre-migration
          localUpdatedAt: 1000,
          localVersion: 2,
          remoteFields: {'title': 'Remote', 'content': 'remote content'},
          remoteFieldTimestamps: {'title': 2000, 'content': 2000},
          remoteUpdatedAt: 2000,
          remoteVersion: 2,
          localDeviceId: 'device1',
          remoteDeviceId: 'device2',
          mergeableFieldNames: ['title', 'content'],
        );

        // local falls back to updatedAt=1000, remote has 2000 → remote wins
        expect(result.mergedFields['title'], 'Remote');
        expect(result.mergedFields['content'], 'remote content');
      });

      test('both sides missing field timestamps — degrades to entity LWW', () {
        final result = merger.merge(
          localFields: {'title': 'Local'},
          localFieldTimestamps: {},
          localUpdatedAt: 3000,
          localVersion: 2,
          remoteFields: {'title': 'Remote'},
          remoteFieldTimestamps: {},
          remoteUpdatedAt: 2000,
          remoteVersion: 2,
          localDeviceId: 'device1',
          remoteDeviceId: 'device2',
          mergeableFieldNames: ['title'],
        );

        // Both fall back to updatedAt: local=3000 > remote=2000 → local wins
        expect(result.mergedFields['title'], 'Local');
        expect(result.fieldResolutions['title'], 'local');
      });
    });

    group('metadata merging', () {
      test('version is max of both sides', () {
        final result = merger.merge(
          localFields: {'title': 'A'},
          localFieldTimestamps: {'title': 5000},
          localUpdatedAt: 5000,
          localVersion: 3,
          remoteFields: {'title': 'B'},
          remoteFieldTimestamps: {'title': 6000},
          remoteUpdatedAt: 6000,
          remoteVersion: 7,
          localDeviceId: 'device1',
          remoteDeviceId: 'device2',
          mergeableFieldNames: ['title'],
        );

        expect(result.mergedVersion, 7);
      });

      test('updatedAt is max of both sides', () {
        final result = merger.merge(
          localFields: {'title': 'A'},
          localFieldTimestamps: {'title': 5000},
          localUpdatedAt: 8000,
          localVersion: 2,
          remoteFields: {'title': 'B'},
          remoteFieldTimestamps: {'title': 6000},
          remoteUpdatedAt: 6000,
          remoteVersion: 2,
          localDeviceId: 'device1',
          remoteDeviceId: 'device2',
          mergeableFieldNames: ['title'],
        );

        expect(result.mergedUpdatedAt, 8000);
      });

      test('mergedFieldTimestamps takes max per field', () {
        final result = merger.merge(
          localFields: {'title': 'A', 'folderId': 'f1'},
          localFieldTimestamps: {'title': 5000, 'folderId': 3000},
          localUpdatedAt: 5000,
          localVersion: 2,
          remoteFields: {'title': 'B', 'folderId': 'f2'},
          remoteFieldTimestamps: {'title': 2000, 'folderId': 7000},
          remoteUpdatedAt: 7000,
          remoteVersion: 2,
          localDeviceId: 'device1',
          remoteDeviceId: 'device2',
          mergeableFieldNames: ['title', 'folderId'],
        );

        expect(result.mergedFieldTimestamps['title'], 5000);
        expect(result.mergedFieldTimestamps['folderId'], 7000);
      });
    });

    group('prayer field-level merge', () {
      test('title on device A, status on device B — both preserved', () {
        // Created at T=1000.
        // DeviceA changes title at T=4000.
        // DeviceB changes status+answeredAt at T=5000.
        final result = merger.merge(
          localFields: {
            'title': 'Pray for Y',
            'content': 'details',
            'frequency': 'daily',
            'status': 'active',
            'category': null,
            'reminderAt': null,
            'answeredAt': null,
          },
          localFieldTimestamps: {
            'title': 4000,
            'content': 1000,
            'frequency': 1000,
            'status': 1000,
            'category': 1000,
            'reminderAt': 1000,
            'answeredAt': 1000,
          },
          localUpdatedAt: 4000,
          localVersion: 2,
          remoteFields: {
            'title': 'Pray for X',
            'content': 'details',
            'frequency': 'daily',
            'status': 'answered',
            'category': null,
            'reminderAt': null,
            'answeredAt': 5000,
          },
          remoteFieldTimestamps: {
            'title': 1000,
            'content': 1000,
            'frequency': 1000,
            'status': 5000,
            'category': 1000,
            'reminderAt': 1000,
            'answeredAt': 5000,
          },
          remoteUpdatedAt: 5000,
          remoteVersion: 2,
          localDeviceId: 'deviceA',
          remoteDeviceId: 'deviceB',
          mergeableFieldNames: [
            'title',
            'content',
            'frequency',
            'status',
            'category',
            'reminderAt',
            'answeredAt',
          ],
        );

        expect(result.mergedFields['title'], 'Pray for Y');
        expect(result.mergedFields['status'], 'answered');
        expect(result.mergedFields['answeredAt'], 5000);
      });
    });

    group('user profile field-level merge', () {
      test('displayName on device A, bio on device B — both preserved', () {
        // Created at T=1000.
        // DeviceA changes displayName at T=3000.
        // DeviceB changes bio at T=4000.
        final result = merger.merge(
          localFields: {
            'username': 'john',
            'displayName': 'Johnny',
            'bio': 'Hello',
            'imageUrl': null,
            'friendRequestsEnabled': 1,
          },
          localFieldTimestamps: {
            'username': 1000,
            'displayName': 3000,
            'bio': 1000,
            'imageUrl': 1000,
            'friendRequestsEnabled': 1000,
          },
          localUpdatedAt: 3000,
          localVersion: 2,
          remoteFields: {
            'username': 'john',
            'displayName': 'John',
            'bio': 'Hi there',
            'imageUrl': null,
            'friendRequestsEnabled': 1,
          },
          remoteFieldTimestamps: {
            'username': 1000,
            'displayName': 1000,
            'bio': 4000,
            'imageUrl': 1000,
            'friendRequestsEnabled': 1000,
          },
          remoteUpdatedAt: 4000,
          remoteVersion: 2,
          localDeviceId: 'deviceA',
          remoteDeviceId: 'deviceB',
          mergeableFieldNames: [
            'username',
            'displayName',
            'bio',
            'imageUrl',
            'friendRequestsEnabled',
          ],
        );

        expect(result.mergedFields['displayName'], 'Johnny');
        expect(result.mergedFields['bio'], 'Hi there');
      });
    });

    group('group field-level merge', () {
      test('only mergeable fields are resolved', () {
        // Created at T=1000.
        // DeviceA changes description at T=3000.
        // DeviceB changes name + joinPolicy at T=4000.
        final result = merger.merge(
          localFields: {
            'name': 'My Church',
            'description': 'Updated desc',
            'groupType': 'church',
            'imageUrl': null,
            'joinPolicy': 'codeOnly',
          },
          localFieldTimestamps: {
            'name': 1000,
            'description': 3000,
            'groupType': 1000,
            'imageUrl': 1000,
            'joinPolicy': 1000,
          },
          localUpdatedAt: 3000,
          localVersion: 2,
          remoteFields: {
            'name': 'Our Church',
            'description': 'Old desc',
            'groupType': 'church',
            'imageUrl': null,
            'joinPolicy': 'open',
          },
          remoteFieldTimestamps: {
            'name': 4000,
            'description': 1000,
            'groupType': 1000,
            'imageUrl': 1000,
            'joinPolicy': 4000,
          },
          remoteUpdatedAt: 4000,
          remoteVersion: 2,
          localDeviceId: 'deviceA',
          remoteDeviceId: 'deviceB',
          mergeableFieldNames: [
            'name',
            'description',
            'groupType',
            'imageUrl',
            'joinPolicy',
          ],
        );

        expect(result.mergedFields['name'], 'Our Church');
        expect(result.mergedFields['description'], 'Updated desc');
        expect(result.mergedFields['joinPolicy'], 'open');
      });
    });

    group('determinism', () {
      test('merge is commutative — same result regardless of which is local',
          () {
        final mergeableFields = ['title', 'folderId'];

        final resultAB = merger.merge(
          localFields: {'title': 'A', 'folderId': 'f1'},
          localFieldTimestamps: {'title': 2000, 'folderId': 1000},
          localUpdatedAt: 2000,
          localVersion: 2,
          remoteFields: {'title': 'B', 'folderId': 'f2'},
          remoteFieldTimestamps: {'title': 1000, 'folderId': 3000},
          remoteUpdatedAt: 3000,
          remoteVersion: 2,
          localDeviceId: 'device1',
          remoteDeviceId: 'device2',
          mergeableFieldNames: mergeableFields,
        );

        // Swap local/remote
        final resultBA = merger.merge(
          localFields: {'title': 'B', 'folderId': 'f2'},
          localFieldTimestamps: {'title': 1000, 'folderId': 3000},
          localUpdatedAt: 3000,
          localVersion: 2,
          remoteFields: {'title': 'A', 'folderId': 'f1'},
          remoteFieldTimestamps: {'title': 2000, 'folderId': 1000},
          remoteUpdatedAt: 2000,
          remoteVersion: 2,
          localDeviceId: 'device2',
          remoteDeviceId: 'device1',
          mergeableFieldNames: mergeableFields,
        );

        expect(resultAB.mergedFields['title'], resultBA.mergedFields['title']);
        expect(resultAB.mergedFields['folderId'],
            resultBA.mergedFields['folderId']);
        expect(resultAB.mergedVersion, resultBA.mergedVersion);
        expect(resultAB.mergedUpdatedAt, resultBA.mergedUpdatedAt);
      });
    });

    group('nullable fields', () {
      test('null value is preserved when it wins', () {
        final result = merger.merge(
          localFields: {'preacherId': null},
          localFieldTimestamps: {'preacherId': 5000},
          localUpdatedAt: 5000,
          localVersion: 2,
          remoteFields: {'preacherId': 'preacher123'},
          remoteFieldTimestamps: {'preacherId': 3000},
          remoteUpdatedAt: 3000,
          remoteVersion: 2,
          localDeviceId: 'device1',
          remoteDeviceId: 'device2',
          mergeableFieldNames: ['preacherId'],
        );

        expect(result.mergedFields['preacherId'], isNull);
        expect(result.fieldResolutions['preacherId'], 'local');
      });
    });
  });
}
