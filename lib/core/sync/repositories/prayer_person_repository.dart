import 'package:drift/drift.dart';

import '../../database/sync_database.dart';
import '../models/oplog_entry.dart';
import '../models/person_model.dart';
import '../models/prayer_person_model.dart';
import 'base_sync_repository.dart';

/// Repository for prayer-person junction operations (sync-enabled)
///
/// Manages which people are linked to which prayers.
class PrayerPersonRepository extends BaseSyncRepository<PrayerPersonModel> {
  final SyncDatabase _db;
  final String _deviceId;

  PrayerPersonRepository(this._db, this._deviceId);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.prayerPerson;

  // ==================== READ OPERATIONS ====================

  /// Get all person IDs linked to a prayer
  Future<List<String>> getPersonIdsForPrayer(String prayerId) async {
    final query = _db.select(_db.syncPrayerPeople)
      ..where(
          (pp) => pp.prayerId.equals(prayerId) & pp.deleted.equals(0) & pp.trashedAt.isNull());

    final rows = await query.get();
    return rows.map((r) => r.personId).toList();
  }

  /// Get all prayer-person associations for a prayer
  Future<List<PrayerPersonModel>> getPeopleForPrayer(
      String prayerId) async {
    final query = _db.select(_db.syncPrayerPeople)
      ..where(
          (pp) => pp.prayerId.equals(prayerId) & pp.deleted.equals(0) & pp.trashedAt.isNull());

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Watch person IDs for a prayer (reactive)
  Stream<List<String>> watchPersonIdsForPrayer(String prayerId) {
    final query = _db.select(_db.syncPrayerPeople)
      ..where(
          (pp) => pp.prayerId.equals(prayerId) & pp.deleted.equals(0) & pp.trashedAt.isNull());

    return query
        .watch()
        .map((rows) => rows.map((r) => r.personId).toList());
  }

  /// Get all prayer IDs linked to a specific person
  Future<List<String>> getPrayerIdsForPerson(String personId) async {
    final query = _db.select(_db.syncPrayerPeople)
      ..where(
          (pp) => pp.personId.equals(personId) & pp.deleted.equals(0) & pp.trashedAt.isNull());

    final rows = await query.get();
    return rows.map((r) => r.prayerId).toList();
  }

  /// Get unique people linked to any active prayer, with a single JOIN query.
  /// Used by dashboard to avoid N+1 queries.
  Future<List<PersonModel>> getPeopleLinkedToActivePrayers(
    String userId, {
    int limit = 10,
  }) async {
    final results = await _db.customSelect(
      '''
      SELECT DISTINCT p.*
      FROM people p
      INNER JOIN sync_prayer_people spp
        ON spp.person_id = p.id AND spp.deleted = 0 AND spp.trashed_at IS NULL
      INNER JOIN prayers pr
        ON pr.id = spp.prayer_id AND pr.deleted = 0 AND pr.trashed_at IS NULL
        AND pr.status = 'active' AND pr.user_id = ?
      WHERE p.deleted = 0 AND p.trashed_at IS NULL
      LIMIT ?
      ''',
      variables: [Variable.withString(userId), Variable.withInt(limit)],
      readsFrom: {_db.people, _db.syncPrayerPeople, _db.prayers},
    ).get();

    return results
        .map((row) => PersonModel(
              id: row.read<String>('id'),
              userId: row.read<String>('user_id'),
              name: row.read<String>('name'),
              relation: row.read<String>('relation'),
              church: row.readNullable<String>('church'),
              email: row.readNullable<String>('email'),
              phone: row.readNullable<String>('phone'),
              notes: row.read<String>('notes'),
              imageUrl: row.readNullable<String>('image_url'),
              updatedAt: row.read<int>('updated_at'),
              version: row.read<int>('version'),
              deleted: row.read<int>('deleted'),
              createdAt: row.read<int>('created_at'),
            ))
        .toList();
  }

  // ==================== WRITE OPERATIONS ====================

  Future<PrayerPersonModel> addPersonToPrayer({
    required String prayerId,
    required String personId,
    required String userId,
  }) async {
    // Check for existing (including soft-deleted) to prevent duplicates
    final existing = await (_db.select(_db.syncPrayerPeople)
          ..where((pp) =>
              pp.prayerId.equals(prayerId) &
              pp.personId.equals(personId)))
        .getSingleOrNull();

    if (existing != null && existing.deleted == 0) {
      return _toModel(existing);
    }

    final prayerPerson = PrayerPersonModel.create(
      id: existing?.id ?? generateId(),
      prayerId: prayerId,
      personId: personId,
      userId: userId,
    );

    final oplogEntry = createInsertOp(prayerPerson);

    await _db.transaction(() async {
      await _db
          .into(_db.syncPrayerPeople)
          .insertOnConflictUpdate(_toCompanion(prayerPerson));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return prayerPerson;
  }

  Future<void> removePersonFromPrayer(
      String prayerId, String personId) async {
    final query = _db.select(_db.syncPrayerPeople)
      ..where((pp) =>
          pp.prayerId.equals(prayerId) &
          pp.personId.equals(personId) &
          pp.deleted.equals(0));

    final row = await query.getSingleOrNull();
    if (row == null) return;

    final model = _toModel(row);
    final deleted = model.softDelete();
    final oplogEntry = createDeleteOp(deleted);

    await _db.transaction(() async {
      await (_db.update(_db.syncPrayerPeople)
            ..where((pp) => pp.id.equals(model.id)))
          .write(_toCompanion(deleted));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
  }

  /// Replace all people for a prayer with the given set.
  Future<void> setPeopleForPrayer(
    String prayerId,
    List<String> personIds,
    String userId,
  ) async {
    final current = await getPeopleForPrayer(prayerId);
    final currentPersonIds = current.map((pp) => pp.personId).toSet();
    final desiredPersonIds = personIds.toSet();

    final toAdd = desiredPersonIds.difference(currentPersonIds);
    final toRemove = currentPersonIds.difference(desiredPersonIds);

    for (final personId in toAdd) {
      await addPersonToPrayer(
          prayerId: prayerId, personId: personId, userId: userId);
    }
    for (final personId in toRemove) {
      await removePersonFromPrayer(prayerId, personId);
    }
  }

  // ==================== HELPERS ====================

  PrayerPersonModel _toModel(SyncPrayerPeopleData row) {
    return PrayerPersonModel(
      id: row.id,
      prayerId: row.prayerId,
      personId: row.personId,
      userId: row.userId,
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      trashedAt: row.trashedAt,
      createdAt: row.createdAt,
    );
  }

  SyncPrayerPeopleCompanion _toCompanion(PrayerPersonModel model) {
    return SyncPrayerPeopleCompanion(
      id: Value(model.id),
      prayerId: Value(model.prayerId),
      personId: Value(model.personId),
      userId: Value(model.userId),
      updatedAt: Value(model.updatedAt),
      version: Value(model.version),
      deleted: Value(model.deleted),
      trashedAt: Value(model.trashedAt),
      createdAt: Value(model.createdAt),
    );
  }

  OplogCompanion _oplogToCompanion(OplogEntry entry) {
    return OplogCompanion(
      opId: Value(entry.opId),
      entityType: Value(entry.entityType.toDbValue()),
      entityId: Value(entry.entityId),
      operation: Value(entry.operation.toDbValue()),
      payloadJson: Value(entry.payloadJson),
      timestamp: Value(entry.timestamp),
      deviceId: Value(entry.deviceId),
      synced: Value(entry.synced ? 1 : 0),
      entityVersion: Value(entry.entityVersion),
      serverTimestamp: Value(entry.serverTimestamp),
    );
  }
}
