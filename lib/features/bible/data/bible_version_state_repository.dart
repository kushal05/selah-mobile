import 'package:drift/drift.dart';

import '../../../core/database/sync_database.dart';
import 'bible_version_api_service.dart';

/// Read/write access to the local [BibleVersionStates] Drift table.
///
/// Responsibilities:
///   - Cache the server version list locally (upsert server fields, preserve
///     the user's [isDefault] choice).
///   - Expose a reactive stream for the versions screen.
///   - Manage the default translation (exactly one row has isDefault = true).
class BibleVersionStateRepository {
  final SyncDatabase _db;

  BibleVersionStateRepository(this._db);

  // ── Streams ────────────────────────────────────────────────────────────────

  /// All available versions ordered by [sortOrder].
  Stream<List<BibleVersionState>> watchAll() =>
      (_db.select(_db.bibleVersionStates)
            ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
          .watch();

  // ── Queries ────────────────────────────────────────────────────────────────

  Future<List<BibleVersionState>> getAll() =>
      (_db.select(_db.bibleVersionStates)
            ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
          .get();

  /// Returns the code of the current default translation, or null if the
  /// table is empty (first launch before server data has been fetched).
  Future<String?> getDefaultCode() async {
    final row = await (_db.select(_db.bibleVersionStates)
          ..where((t) => t.isDefault.equals(true))
          ..limit(1))
        .getSingleOrNull();
    return row?.code;
  }

  /// Returns true if the cached version list was fetched within the last hour.
  Future<bool> isCacheFresh() async {
    final row = await (_db.select(_db.bibleVersionStates)
          ..orderBy([(t) => OrderingTerm.desc(t.fetchedAt)])
          ..limit(1))
        .getSingleOrNull();
    if (row?.fetchedAt == null) return false;
    final age = DateTime.now().millisecondsSinceEpoch - row!.fetchedAt!;
    return age < const Duration(hours: 1).inMilliseconds;
  }

  // ── Writes ────────────────────────────────────────────────────────────────

  /// Upsert versions received from the server.
  ///
  /// Server-side fields (name, downloadUrl, approximateSizeMb, sortOrder) are
  /// always updated.  [isDefault] is preserved from the existing row so the
  /// user's preference is never overwritten by a server refresh.
  ///
  /// If the table is currently empty, [isDefault] from the server response
  /// (i.e. NKJV) is honoured as the initial default.
  Future<void> upsertFromServer(List<BibleVersionDto> versions) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await _db.transaction(() async {
      // Check emptiness inside the transaction so concurrent calls can't both
      // see an empty table and both set isDefault = true.
      final tableEmpty = await _db.bibleVersionStates.count().getSingle() == 0;
      for (final v in versions) {
        await _db.into(_db.bibleVersionStates).insert(
          BibleVersionStatesCompanion.insert(
            code: v.code,
            name: v.name,
            downloadUrl: v.downloadUrl,
            approximateSizeMb: v.approximateSizeMb,
            sortOrder: v.sortOrder,
            // On first load: honour the server's isDefault flag.
            // On refresh: preserve the user's existing choice.
            isDefault: Value(tableEmpty ? v.isDefault : false),
            fetchedAt: Value(now),
          ),
          onConflict: DoUpdate(
            (old) => BibleVersionStatesCompanion(
              name: Value(v.name),
              downloadUrl: Value(v.downloadUrl),
              approximateSizeMb: Value(v.approximateSizeMb),
              sortOrder: Value(v.sortOrder),
              fetchedAt: Value(now),
              // isDefault is intentionally excluded — preserve user's choice.
            ),
          ),
        );
      }
    });
  }

  /// Sets [code] as the default translation, clearing the flag on all others.
  Future<void> setDefault(String code) async {
    await _db.transaction(() async {
      // Clear all
      await (_db.update(_db.bibleVersionStates))
          .write(const BibleVersionStatesCompanion(isDefault: Value(false)));
      // Set the chosen one
      await (_db.update(_db.bibleVersionStates)
            ..where((t) => t.code.equals(code)))
          .write(const BibleVersionStatesCompanion(isDefault: Value(true)));
    });
  }

  /// Seeds the table from a server response and marks [defaultCode] as the
  /// default.  Used by the onboarding screen after the user makes their choice.
  Future<void> initWithDefault(
    List<BibleVersionDto> versions,
    String defaultCode,
  ) async {
    await upsertFromServer(versions);
    await setDefault(defaultCode);
  }
}
