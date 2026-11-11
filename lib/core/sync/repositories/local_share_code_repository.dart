import 'package:drift/drift.dart';

import '../../database/sync_database.dart';

/// Device-local memory of which prayer a share code belongs to.
///
/// Lets the author open their own share link with no network: the app looks
/// the code up here first. Backed by the `ShareCodes` table, which is local
/// only and not synced (no oplog entries), so this deliberately does not go
/// through `BaseSyncRepository`.
class LocalShareCodeRepository {
  LocalShareCodeRepository(this._db);

  final SyncDatabase _db;

  static const _prayer = 'prayer';

  /// Record (or refresh) the code for a prayer, replacing any older code.
  Future<void> remember({
    required String code,
    required String prayerId,
    required String sharedPrayerId,
  }) async {
    if (code.isEmpty) return;
    await _db.transaction(() async {
      await forgetPrayer(prayerId);
      await _db.into(_db.shareCodes).insertOnConflictUpdate(
            ShareCodesCompanion.insert(
              code: code.toUpperCase(),
              entityAccessId: sharedPrayerId,
              entityType: _prayer,
              entityId: prayerId,
            ),
          );
    });
  }

  /// Drop whatever code a prayer had (after it is un-shared).
  Future<void> forgetPrayer(String prayerId) {
    return (_db.delete(_db.shareCodes)
          ..where((c) =>
              c.entityType.equals(_prayer) & c.entityId.equals(prayerId)))
        .go();
  }

  /// The prayer this code was recorded for, or null.
  Future<String?> prayerIdFor(String code) async {
    final row = await (_db.select(_db.shareCodes)
          ..where((c) =>
              c.code.equals(code.toUpperCase()) &
              c.entityType.equals(_prayer)))
        .getSingleOrNull();
    return row?.entityId;
  }
}
