import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/testing/test_clock.dart';
import 'package:notify/core/testing/test_db_utils.dart';
import 'package:notify/core/testing/test_seeder.dart';

import 'test_config.dart';

/// Harness that spins up an in-memory Drift database and Riverpod container
/// for headless integration tests (no UI, no real network).
///
/// Usage:
/// ```dart
/// final harness = TestHarness();
/// await harness.setUp();
/// // ... run assertions ...
/// await harness.tearDown();
/// ```
class TestHarness {
  late SyncDatabase db;
  late ProviderContainer container;
  late TestDbUtils dbUtils;
  late TestSeeder seeder;

  /// Set up an in-memory database and provider container.
  Future<void> setUp() async {
    // Each test creates a fresh in-memory DB, which triggers a harmless
    // Drift warning about multiple instances. Suppress it.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

    // Freeze clock for deterministic tests
    TestClock.setFixed(TestConfig.baseTimestamp);

    // In-memory SQLite via Drift's NativeDatabase.memory()
    db = SyncDatabase.forTesting(NativeDatabase.memory());

    // Wait for Drift to create all tables
    await db.customSelect('SELECT 1').get();

    container = ProviderContainer(
      overrides: [
        syncDatabaseProvider.overrideWithValue(db),
        deviceIdProvider.overrideWith((ref) => TestConfig.testDeviceId),
        currentUserIdProvider.overrideWith((ref) => TestConfig.testUserId),
      ],
    );

    final folderRepo = container.read(folderRepositoryProvider);
    final noteRepo = container.read(noteRepositoryProvider);
    final prayerRepo = container.read(prayerRepositoryProvider);

    dbUtils = TestDbUtils(db);
    seeder = TestSeeder(
      db: db,
      folderRepo: folderRepo,
      noteRepo: noteRepo,
      prayerRepo: prayerRepo,
    );
  }

  /// Tear down the database and container.
  Future<void> tearDown() async {
    TestClock.reset();
    container.dispose();
    await db.close();
  }
}

/// Poll [condition] every [interval] until it returns true, or throw after [timeout].
///
/// Replaces arbitrary `sleep()` calls with deterministic polling.
Future<void> waitForCondition(
  Future<bool> Function() condition, {
  Duration timeout = TestConfig.defaultTimeout,
  Duration interval = TestConfig.pollInterval,
  String? description,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await Future<void>.delayed(interval);
  }
  throw TimeoutException(
    description ?? 'Condition not met within $timeout',
  );
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => 'TimeoutException: $message';
}
