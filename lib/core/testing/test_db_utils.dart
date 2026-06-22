import '../database/sync_database.dart';

/// Database utilities for integration tests.
///
/// Provides clean-slate reset and table-level inspection without
/// exposing raw SQL to test code.
class TestDbUtils {
  final SyncDatabase db;

  TestDbUtils(this.db);

  /// Delete all user data and reset sync state.
  ///
  /// Delegates to [SyncDatabase.clearAllUserData] which handles
  /// all tables and re-initializes the sync_state row.
  Future<void> clearAll() async {
    await db.clearAllUserData();
  }

  /// Return the count of unsynced oplog entries.
  Future<int> pendingOplogCount() => db.getPendingOpsCount();

  /// Return all unsynced oplog entries as raw Drift data objects.
  Future<List<OplogData>> pendingOplogs() => db.getUnsyncedOps();

  /// Assert that no unsynced operations remain.
  Future<bool> isOplogEmpty() async => (await pendingOplogCount()) == 0;
}
