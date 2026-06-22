import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/sync/engine/conflict_resolver.dart';

void main() {
  late ConflictResolver resolver;

  setUp(() {
    resolver = ConflictResolver();
  });

  group('ConflictResolver._resolve (via resolveFolder)', () {
    group('no conflict scenarios', () {
      test('remote version strictly higher → no conflict, use remote', () {
        final result = resolver.resolveFolder(
          entityId: 'test',
          localVersion: 1,
          localUpdatedAt: 1000,
          remoteVersion: 2,
          remoteUpdatedAt: 2000,
          remoteIsDelete: false,
          localIsDelete: false,
        );
        expect(result.hadConflict, false);
        expect(result.useRemote, true);
      });

      test('remote version much higher → no conflict', () {
        final result = resolver.resolveFolder(
          entityId: 'test',
          localVersion: 3,
          localUpdatedAt: 5000,
          remoteVersion: 10,
          remoteUpdatedAt: 6000,
          remoteIsDelete: false,
          localIsDelete: false,
        );
        expect(result.hadConflict, false);
        expect(result.useRemote, true);
      });
    });

    group('delete wins rule', () {
      test('remote delete with same version → delete wins', () {
        final result = resolver.resolveFolder(
          entityId: 'test',
          localVersion: 2,
          localUpdatedAt: 2000,
          remoteVersion: 2,
          remoteUpdatedAt: 2000,
          remoteIsDelete: true,
          localIsDelete: false,
        );
        expect(result.hadConflict, true);
        expect(result.useRemote, true);
        expect(result.reason, contains('Delete'));
      });

      test('remote delete with lower version → delete wins', () {
        final result = resolver.resolveFolder(
          entityId: 'test',
          localVersion: 5,
          localUpdatedAt: 5000,
          remoteVersion: 3,
          remoteUpdatedAt: 3000,
          remoteIsDelete: true,
          localIsDelete: false,
        );
        expect(result.hadConflict, true);
        expect(result.useRemote, true);
      });

      test('remote delete with equal version and older timestamp → delete wins', () {
        final result = resolver.resolveFolder(
          entityId: 'test',
          localVersion: 3,
          localUpdatedAt: 5000,
          remoteVersion: 3,
          remoteUpdatedAt: 3000,
          remoteIsDelete: true,
          localIsDelete: false,
        );
        expect(result.hadConflict, true);
        expect(result.useRemote, true);
      });
    });

    group('higher updatedAt wins', () {
      test('remote has higher updatedAt → use remote', () {
        final result = resolver.resolveFolder(
          entityId: 'test',
          localVersion: 3,
          localUpdatedAt: 1000,
          remoteVersion: 3,
          remoteUpdatedAt: 2000,
          remoteIsDelete: false,
          localIsDelete: false,
        );
        expect(result.hadConflict, true);
        expect(result.useRemote, true);
        expect(result.reason, contains('Remote has higher updatedAt'));
      });

      test('local has higher updatedAt → use local', () {
        final result = resolver.resolveFolder(
          entityId: 'test',
          localVersion: 3,
          localUpdatedAt: 3000,
          remoteVersion: 3,
          remoteUpdatedAt: 2000,
          remoteIsDelete: false,
          localIsDelete: false,
        );
        expect(result.hadConflict, true);
        expect(result.useRemote, false);
        expect(result.reason, contains('Local has higher updatedAt'));
      });
    });

    group('same timestamp, higher version wins', () {
      test('remote has higher version with same timestamp → use remote', () {
        final result = resolver.resolveFolder(
          entityId: 'test',
          localVersion: 2,
          localUpdatedAt: 1000,
          remoteVersion: 2,
          remoteUpdatedAt: 1000,
          remoteIsDelete: false,
          localIsDelete: false,
        );
        // Same version and same timestamp → local default
        expect(result.hadConflict, true);
        expect(result.useRemote, false);
      });

      test('local has higher version with same timestamp → use local', () {
        final result = resolver.resolveFolder(
          entityId: 'test',
          localVersion: 5,
          localUpdatedAt: 1000,
          remoteVersion: 3,
          remoteUpdatedAt: 1000,
          remoteIsDelete: false,
          localIsDelete: false,
        );
        expect(result.hadConflict, true);
        expect(result.useRemote, false);
        expect(result.reason, contains('Local has higher version'));
      });
    });

    group('tie-breaker', () {
      test('same timestamp and same version → local wins by default', () {
        final result = resolver.resolveFolder(
          entityId: 'test',
          localVersion: 3,
          localUpdatedAt: 1000,
          remoteVersion: 3,
          remoteUpdatedAt: 1000,
          remoteIsDelete: false,
          localIsDelete: false,
        );
        expect(result.hadConflict, true);
        expect(result.useRemote, false);
        expect(result.reason, contains('Local wins by default'));
      });
    });
  });

  group('entity-specific resolvers all use same algorithm', () {
    test('resolveNote behaves same as resolveFolder', () {
      final noteResult = resolver.resolveNote(
        entityId: 'test-note',
        localVersion: 1,
        localUpdatedAt: 1000,
        remoteVersion: 1,
        remoteUpdatedAt: 2000,
        remoteIsDelete: false,
        localIsDelete: false,
      );
      final folderResult = resolver.resolveFolder(
        entityId: 'test-folder',
        localVersion: 1,
        localUpdatedAt: 1000,
        remoteVersion: 1,
        remoteUpdatedAt: 2000,
        remoteIsDelete: false,
        localIsDelete: false,
      );
      expect(noteResult.useRemote, folderResult.useRemote);
      expect(noteResult.hadConflict, folderResult.hadConflict);
    });

    test('resolveBlock behaves same as resolveFolder', () {
      final blockResult = resolver.resolveBlock(
        entityId: 'test-block',
        localVersion: 2,
        localUpdatedAt: 3000,
        remoteVersion: 1,
        remoteUpdatedAt: 2000,
        remoteIsDelete: false,
        localIsDelete: false,
      );
      expect(blockResult.hadConflict, true);
      expect(blockResult.useRemote, false);
    });

    test('resolvePrayer behaves same as resolveFolder', () {
      final result = resolver.resolvePrayer(
        entityId: 'test-prayer',
        localVersion: 1,
        localUpdatedAt: 1000,
        remoteVersion: 1,
        remoteUpdatedAt: 1000,
        remoteIsDelete: true,
        localIsDelete: false,
      );
      expect(result.useRemote, true);
      expect(result.reason, contains('Delete'));
    });

    test('resolvePromise behaves same as resolveFolder', () {
      final result = resolver.resolvePromise(
        entityId: 'test-promise',
        localVersion: 5,
        localUpdatedAt: 5000,
        remoteVersion: 5,
        remoteUpdatedAt: 5000,
        remoteIsDelete: false,
        localIsDelete: false,
      );
      expect(result.useRemote, false);
    });

    test('resolvePerson behaves same as resolveFolder', () {
      final result = resolver.resolvePerson(
        entityId: 'test-person',
        localVersion: 1,
        localUpdatedAt: 1000,
        remoteVersion: 5,
        remoteUpdatedAt: 5000,
        remoteIsDelete: false,
        localIsDelete: false,
      );
      expect(result.hadConflict, false);
      expect(result.useRemote, true);
    });

    test('resolveSong behaves same as resolveFolder', () {
      final result = resolver.resolveSong(
        entityId: 'test-song',
        localVersion: 3,
        localUpdatedAt: 2000,
        remoteVersion: 3,
        remoteUpdatedAt: 3000,
        remoteIsDelete: false,
        localIsDelete: false,
      );
      expect(result.hadConflict, true);
      expect(result.useRemote, true);
    });
  });

  group('ConflictResolutionResult', () {
    test('noConflict factory', () {
      final result = ConflictResolutionResult.noConflict(useRemote: true);
      expect(result.hadConflict, false);
      expect(result.useRemote, true);
    });

    test('toString includes all fields', () {
      final result = ConflictResolutionResult.remoteNewer();
      final str = result.toString();
      expect(str, contains('useRemote: true'));
      expect(str, contains('hadConflict: true'));
      expect(str, contains('Remote has higher updatedAt'));
    });
  });

  group('ConflictLog', () {
    test('toJson includes all fields', () {
      final resolution = ConflictResolutionResult.remoteNewer();
      final log = ConflictLog(
        entityType: 'folder',
        entityId: 'folder-123',
        localVersion: 1,
        remoteVersion: 2,
        localUpdatedAt: 1000,
        remoteUpdatedAt: 2000,
        resolution: resolution,
      );

      final json = log.toJson();
      expect(json['entityType'], 'folder');
      expect(json['entityId'], 'folder-123');
      expect(json['localVersion'], 1);
      expect(json['remoteVersion'], 2);
      expect(json['useRemote'], true);
      expect(json['reason'], contains('Remote'));
      expect(json['timestamp'], isNotNull);
    });

    test('toString is descriptive', () {
      final resolution = ConflictResolutionResult.localNewer();
      final log = ConflictLog(
        entityType: 'note',
        entityId: 'note-456',
        localVersion: 3,
        remoteVersion: 2,
        localUpdatedAt: 3000,
        remoteUpdatedAt: 2000,
        resolution: resolution,
      );

      final str = log.toString();
      expect(str, contains('note/note-456'));
      expect(str, contains('LOCAL wins'));
    });
  });
}
