import 'package:drift/drift.dart';

import '../../database/sync_database.dart';
import '../models/oplog_entry.dart';
import '../models/person_model.dart';
import 'base_sync_repository.dart';

/// Repository for person operations
///
/// Per spec: Every write is transactional with oplog entry
class PersonRepository extends BaseSyncRepository<PersonModel> {
  final SyncDatabase _db;
  final String _deviceId;

  PersonRepository(this._db, this._deviceId);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.person;

  // ==================== READ OPERATIONS ====================

  /// Get all people (non-deleted) for a user
  Future<List<PersonModel>> getAllPeople(String userId) async {
    final query = _db.select(_db.people)
      ..where((p) => p.deleted.equals(0) & p.trashedAt.isNull() & p.userId.equals(userId))
      ..orderBy([(p) => OrderingTerm.asc(p.name)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Get people by relation/group for a user
  Future<List<PersonModel>> getPeopleByRelation(String relation, String userId) async {
    final query = _db.select(_db.people)
      ..where((p) => p.deleted.equals(0) & p.trashedAt.isNull() & p.userId.equals(userId) & p.relation.equals(relation))
      ..orderBy([(p) => OrderingTerm.asc(p.name)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Get person by ID
  Future<PersonModel?> getPersonById(String id) async {
    final query = _db.select(_db.people)..where((p) => p.id.equals(id));

    final row = await query.getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  /// Watch all people (reactive stream) for a user
  Stream<List<PersonModel>> watchAllPeople(String userId) {
    final query = _db.select(_db.people)
      ..where((p) => p.deleted.equals(0) & p.trashedAt.isNull() & p.userId.equals(userId))
      ..orderBy([(p) => OrderingTerm.asc(p.name)]);

    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Watch people by relation for a user
  Stream<List<PersonModel>> watchPeopleByRelation(String relation, String userId) {
    final query = _db.select(_db.people)
      ..where((p) => p.deleted.equals(0) & p.trashedAt.isNull() & p.userId.equals(userId) & p.relation.equals(relation))
      ..orderBy([(p) => OrderingTerm.asc(p.name)]);

    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Search people by name for a user
  Future<List<PersonModel>> searchPeople(String searchQuery, String userId) async {
    final searchPattern = '%$searchQuery%';
    final query = _db.select(_db.people)
      ..where((p) =>
          p.deleted.equals(0) & p.trashedAt.isNull() & p.userId.equals(userId) &
          (p.name.like(searchPattern) | p.relation.like(searchPattern)))
      ..orderBy([(p) => OrderingTerm.asc(p.name)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Get unique relations/groups for a user
  Future<List<String>> getUniqueRelations(String userId) async {
    final result = await _db.customSelect(
      'SELECT DISTINCT relation FROM people WHERE user_id = ? AND deleted = 0 AND trashed_at IS NULL AND relation != "" ORDER BY relation',
      variables: [Variable.withString(userId)],
    ).get();
    return result.map((row) => row.read<String>('relation')).toList();
  }

  /// Get person count for a user
  Future<int> getPersonCount(String userId) async {
    final result = await _db.customSelect(
      'SELECT COUNT(*) as count FROM people WHERE user_id = ? AND deleted = 0 AND trashed_at IS NULL',
      variables: [Variable.withString(userId)],
    ).getSingle();
    return result.read<int>('count');
  }

  // ==================== WRITE OPERATIONS ====================

  /// Create a new person
  Future<PersonModel> createPerson({
    required String userId,
    required String name,
    String relation = '',
    String? church,
    String? email,
    String? phone,
    String notes = '',
    String? imageUrl,
  }) async {
    final person = PersonModel.create(
      id: generateId(),
      userId: userId,
      name: name,
      relation: relation,
      church: church,
      email: email,
      phone: phone,
      notes: notes,
      imageUrl: imageUrl,
    );

    final oplogEntry = createInsertOp(person);

    await _db.transaction(() async {
      await _db.into(_db.people).insert(_toCompanion(person));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return person;
  }

  /// Update a person
  Future<PersonModel> updatePerson({
    required String id,
    String? name,
    String? relation,
    String? church,
    String? email,
    String? phone,
    String? notes,
    String? imageUrl,
  }) async {
    final existing = await getPersonById(id);
    if (existing == null) {
      throw PersonNotFoundException(id);
    }

    final updated = existing.copyWithUpdate(
      name: name,
      relation: relation,
      church: church,
      email: email,
      phone: phone,
      notes: notes,
      imageUrl: imageUrl,
    );

    final oplogEntry = createUpdateOp(updated);

    await _db.transaction(() async {
      await (_db.update(_db.people)..where((p) => p.id.equals(id)))
          .write(_toCompanion(updated));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return updated;
  }

  /// Move a person to the trash
  Future<PersonModel> trashPerson(String id) async {
    final existing = await getPersonById(id);
    if (existing == null) throw PersonNotFoundException(id);
    final trashed = existing.moveToTrash();
    final oplogEntry = createUpdateOp(trashed);
    await _db.transaction(() async {
      await (_db.update(_db.people)..where((p) => p.id.equals(id)))
          .write(_toCompanion(trashed));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
    return trashed;
  }

  /// Restore a person from the trash
  Future<PersonModel> restorePerson(String id) async {
    final existing = await getPersonById(id);
    if (existing == null) throw PersonNotFoundException(id);
    final restored = existing.restoreFromTrash();
    final oplogEntry = createUpdateOp(restored);
    await _db.transaction(() async {
      await (_db.update(_db.people)..where((p) => p.id.equals(id)))
          .write(_toCompanion(restored));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
    return restored;
  }

  /// Get all trashed people for a user
  Future<List<PersonModel>> getTrashedPeople(String userId) async {
    final query = _db.select(_db.people)
      ..where((p) => p.userId.equals(userId) & p.deleted.equals(0) & p.trashedAt.isNotNull())
      ..orderBy([(p) => OrderingTerm.desc(p.trashedAt)]);
    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Watch all trashed people for a user
  Stream<List<PersonModel>> watchTrashedPeople(String userId) {
    final query = _db.select(_db.people)
      ..where((p) => p.userId.equals(userId) & p.deleted.equals(0) & p.trashedAt.isNotNull())
      ..orderBy([(p) => OrderingTerm.desc(p.trashedAt)]);
    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Soft delete a person
  Future<void> deletePerson(String id) async {
    final existing = await getPersonById(id);
    if (existing == null) {
      throw PersonNotFoundException(id);
    }

    final deletedPerson = existing.softDelete();
    final oplogEntry = createDeleteOp(deletedPerson);

    await _db.transaction(() async {
      await (_db.update(_db.people)..where((p) => p.id.equals(id)))
          .write(_toCompanion(deletedPerson));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
  }

  // ==================== HELPER METHODS ====================

  /// Convert database row to domain model
  PersonModel _toModel(PeopleData row) {
    return PersonModel(
      id: row.id,
      userId: row.userId,
      name: row.name,
      relation: row.relation,
      church: row.church,
      email: row.email,
      phone: row.phone,
      notes: row.notes,
      imageUrl: row.imageUrl,
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      trashedAt: row.trashedAt,
      createdAt: row.createdAt,
    );
  }

  /// Convert domain model to database companion
  PeopleCompanion _toCompanion(PersonModel model) {
    return PeopleCompanion(
      id: Value(model.id),
      userId: Value(model.userId),
      name: Value(model.name),
      relation: Value(model.relation),
      church: Value(model.church),
      email: Value(model.email),
      phone: Value(model.phone),
      notes: Value(model.notes),
      imageUrl: Value(model.imageUrl),
      updatedAt: Value(model.updatedAt),
      version: Value(model.version),
      deleted: Value(model.deleted),
      trashedAt: Value(model.trashedAt),
      createdAt: Value(model.createdAt),
    );
  }

  /// Convert oplog entry to database companion
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

// ==================== EXCEPTIONS ====================

class PersonNotFoundException implements Exception {
  final String personId;
  PersonNotFoundException(this.personId);

  @override
  String toString() => 'Person not found: $personId';
}
