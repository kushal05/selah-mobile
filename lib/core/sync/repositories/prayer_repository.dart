import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/sync_database.dart';
import '../../database/tables/prayers_table.dart';
import '../models/oplog_entry.dart';
import '../models/prayer_model.dart';
import 'base_sync_repository.dart';
import 'entity_access_repository.dart';
import 'promise_prayer_link_repository.dart';

/// Repository for prayer operations
///
/// Per spec: Every write is transactional with oplog entry
class PrayerRepository extends BaseSyncRepository<PrayerModel> {
  final SyncDatabase _db;
  final String _deviceId;
  final EntityAccessRepository _entityAccessRepo;
  PromisePrayerLinkRepository? _linkRepository;

  PrayerRepository(this._db, this._deviceId, this._entityAccessRepo);

  /// Set the link repository for cascade deletes.
  /// Injected after construction to avoid circular dependencies.
  set linkRepository(PromisePrayerLinkRepository repo) =>
      _linkRepository = repo;

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.prayer;

  // ==================== READ OPERATIONS ====================

  /// Get all prayers (non-deleted, non-trashed) for a user
  Future<List<PrayerModel>> getAllPrayers(String userId) async {
    final query = _db.select(_db.prayers)
      ..where((p) => p.deleted.equals(0) & p.userId.equals(userId) & p.trashedAt.isNull())
      ..orderBy([(p) => OrderingTerm.desc(p.updatedAt)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Get prayers by status for a user
  Future<List<PrayerModel>> getPrayersByStatus(PrayerStatus status, String userId) async {
    final query = _db.select(_db.prayers)
      ..where((p) => p.deleted.equals(0) & p.userId.equals(userId) & p.trashedAt.isNull() & p.status.equals(status.name))
      ..orderBy([(p) => OrderingTerm.desc(p.updatedAt)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Get active prayers for a user
  Future<List<PrayerModel>> getActivePrayers(String userId) async {
    return getPrayersByStatus(PrayerStatus.active, userId);
  }

  /// Get answered prayers for a user
  Future<List<PrayerModel>> getAnsweredPrayers(String userId) async {
    return getPrayersByStatus(PrayerStatus.answered, userId);
  }

  /// Get archived prayers for a user
  Future<List<PrayerModel>> getArchivedPrayers(String userId) async {
    return getPrayersByStatus(PrayerStatus.archived, userId);
  }

  /// Get prayer by ID
  Future<PrayerModel?> getPrayerById(String id) async {
    final query = _db.select(_db.prayers)..where((p) => p.id.equals(id));

    final row = await query.getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  /// Watch all prayers (reactive stream) for a user
  Stream<List<PrayerModel>> watchAllPrayers(String userId) {
    final query = _db.select(_db.prayers)
      ..where((p) => p.deleted.equals(0) & p.userId.equals(userId) & p.trashedAt.isNull())
      ..orderBy([(p) => OrderingTerm.desc(p.updatedAt)]);

    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Watch prayers by status for a user
  Stream<List<PrayerModel>> watchPrayersByStatus(PrayerStatus status, String userId) {
    final query = _db.select(_db.prayers)
      ..where((p) => p.deleted.equals(0) & p.userId.equals(userId) & p.trashedAt.isNull() & p.status.equals(status.name))
      ..orderBy([(p) => OrderingTerm.desc(p.updatedAt)]);

    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Watch active prayers for a user
  Stream<List<PrayerModel>> watchActivePrayers(String userId) {
    return watchPrayersByStatus(PrayerStatus.active, userId);
  }

  /// Search prayers by title or content for a user
  Future<List<PrayerModel>> searchPrayers(String query, String userId) async {
    final searchPattern = '%$query%';
    final rows = await _db.customSelect(
      'SELECT * FROM prayers '
      'WHERE deleted = 0 AND trashed_at IS NULL AND user_id = ? '
      'AND (title LIKE ? OR content LIKE ? OR category LIKE ?) '
      'ORDER BY updated_at DESC',
      variables: [
        Variable.withString(userId),
        Variable.withString(searchPattern),
        Variable.withString(searchPattern),
        Variable.withString(searchPattern),
      ],
    ).get();
    return rows.map((row) {
      return PrayerModel(
        id: row.read<String>('id'),
        userId: row.read<String>('user_id'),
        title: row.read<String>('title'),
        content: row.read<String>('content'),
        frequency: PrayerFrequency.values.firstWhere(
          (f) => f.name == row.read<String>('frequency'),
          orElse: () => PrayerFrequency.daily,
        ),
        status: PrayerStatus.values.firstWhere(
          (s) => s.name == row.read<String>('status'),
          orElse: () => PrayerStatus.active,
        ),
        category: row.readNullable<String>('category'),
        reminderAt: row.readNullable<int>('reminder_at'),
        answeredAt: row.readNullable<int>('answered_at'),
        updatedAt: row.read<int>('updated_at'),
        version: row.read<int>('version'),
        deleted: row.read<int>('deleted'),
        trashedAt: row.readNullable<int>('trashed_at'),
        createdAt: row.read<int>('created_at'),
        fieldUpdatedAt: _parseFieldTimestamps(
          row.read<String>('field_updated_at'),
        ),
      );
    }).toList();
  }

  /// Get prayer count by status for a user
  Future<int> getPrayerCount(PrayerStatus status, String userId) async {
    final result = await _db.customSelect(
      'SELECT COUNT(*) as count FROM prayers WHERE status = ? AND user_id = ? AND deleted = 0 AND trashed_at IS NULL',
      variables: [Variable.withString(status.name), Variable.withString(userId)],
    ).getSingle();
    return result.read<int>('count');
  }

  // ==================== WRITE OPERATIONS ====================

  /// Create a new prayer
  Future<PrayerModel> createPrayer({
    required String userId,
    required String title,
    String content = '',
    PrayerFrequency frequency = PrayerFrequency.daily,
    String? category,
    int? reminderAt,
  }) async {
    final prayer = PrayerModel.create(
      id: generateId(),
      userId: userId,
      title: title,
      content: content,
      frequency: frequency,
      category: category,
      reminderAt: reminderAt,
    );

    final oplogEntry = createInsertOp(prayer);

    await _db.transaction(() async {
      await _db.into(_db.prayers).insert(_toCompanion(prayer));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return prayer;
  }

  /// Update a prayer
  Future<PrayerModel> updatePrayer({
    required String id,
    String? title,
    String? content,
    PrayerFrequency? frequency,
    PrayerStatus? status,
    String? category,
    bool clearCategory = false,
    int? reminderAt,
    bool clearReminderAt = false,
    int? answeredAt,
    bool clearAnsweredAt = false,
  }) async {
    final existing = await getPrayerById(id);
    if (existing == null) {
      throw PrayerNotFoundException(id);
    }

    final updated = existing.copyWithUpdate(
      title: title,
      content: content,
      frequency: frequency,
      status: status,
      category: category,
      clearCategory: clearCategory,
      reminderAt: reminderAt,
      clearReminderAt: clearReminderAt,
      answeredAt: answeredAt,
      clearAnsweredAt: clearAnsweredAt,
    );

    final oplogEntry = createUpdateOp(updated);

    await _db.transaction(() async {
      await (_db.update(_db.prayers)..where((p) => p.id.equals(id)))
          .write(_toCompanion(updated));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return updated;
  }

  /// Mark prayer as answered
  Future<PrayerModel> markAsAnswered(String id) async {
    final existing = await getPrayerById(id);
    if (existing == null) {
      throw PrayerNotFoundException(id);
    }

    final updated = existing.markAnswered();
    final oplogEntry = createUpdateOp(updated);

    await _db.transaction(() async {
      await (_db.update(_db.prayers)..where((p) => p.id.equals(id)))
          .write(_toCompanion(updated));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return updated;
  }

  /// Archive a prayer
  Future<PrayerModel> archivePrayer(String id) async {
    final existing = await getPrayerById(id);
    if (existing == null) {
      throw PrayerNotFoundException(id);
    }

    final updated = existing.archive();
    final oplogEntry = createUpdateOp(updated);

    await _db.transaction(() async {
      await (_db.update(_db.prayers)..where((p) => p.id.equals(id)))
          .write(_toCompanion(updated));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return updated;
  }

  /// Soft delete a prayer
  Future<void> deletePrayer(String id) async {
    final existing = await getPrayerById(id);
    if (existing == null) {
      throw PrayerNotFoundException(id);
    }

    final deletedPrayer = existing.softDelete();
    final oplogEntry = createDeleteOp(deletedPrayer);

    await _db.transaction(() async {
      await (_db.update(_db.prayers)..where((p) => p.id.equals(id)))
          .write(_toCompanion(deletedPrayer));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    // Cascade: soft-delete all promise-prayer links
    await _linkRepository?.softDeleteLinksForPrayer(id);

    // Cascade: revoke entity_access grants for this prayer so recipients'
    // local DBs drop their stale access rows on next sync.
    await _entityAccessRepo.deleteAllAccessForEntity('prayer', id);
  }

  // ==================== TRASH OPERATIONS ====================

  /// Move prayer to trash
  Future<PrayerModel> trashPrayer(String id) async {
    final existing = await getPrayerById(id);
    if (existing == null) throw PrayerNotFoundException(id);

    final trashed = existing.moveToTrash();
    final oplogEntry = createUpdateOp(trashed);

    await _db.transaction(() async {
      await (_db.update(_db.prayers)..where((p) => p.id.equals(id)))
          .write(_toCompanion(trashed));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return trashed;
  }

  /// Restore prayer from trash
  Future<PrayerModel> restorePrayer(String id) async {
    final existing = await getPrayerById(id);
    if (existing == null) throw PrayerNotFoundException(id);

    final restored = existing.restoreFromTrash();
    final oplogEntry = createUpdateOp(restored);

    await _db.transaction(() async {
      await (_db.update(_db.prayers)..where((p) => p.id.equals(id)))
          .write(_toCompanion(restored));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return restored;
  }

  /// Get all trashed prayers for a user
  Future<List<PrayerModel>> getTrashedPrayers(String userId) async {
    final query = _db.select(_db.prayers)
      ..where((p) => p.userId.equals(userId) & p.deleted.equals(0) & p.trashedAt.isNotNull())
      ..orderBy([(p) => OrderingTerm.desc(p.trashedAt)]);
    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Watch trashed prayers for a user
  Stream<List<PrayerModel>> watchTrashedPrayers(String userId) {
    final query = _db.select(_db.prayers)
      ..where((p) => p.userId.equals(userId) & p.deleted.equals(0) & p.trashedAt.isNotNull())
      ..orderBy([(p) => OrderingTerm.desc(p.trashedAt)]);
    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  // ==================== HELPER METHODS ====================

  /// Convert database row to domain model
  PrayerModel _toModel(Prayer row) {
    return PrayerModel(
      id: row.id,
      userId: row.userId,
      title: row.title,
      content: row.content,
      frequency: PrayerFrequency.values.firstWhere(
        (f) => f.name == row.frequency,
        orElse: () => PrayerFrequency.daily,
      ),
      status: PrayerStatus.values.firstWhere(
        (s) => s.name == row.status,
        orElse: () => PrayerStatus.active,
      ),
      category: row.category,
      reminderAt: row.reminderAt,
      answeredAt: row.answeredAt,
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      trashedAt: row.trashedAt,
      createdAt: row.createdAt,
      fieldUpdatedAt: _parseFieldTimestamps(row.fieldUpdatedAt),
    );
  }

  /// Convert domain model to database companion
  PrayersCompanion _toCompanion(PrayerModel model) {
    return PrayersCompanion(
      id: Value(model.id),
      userId: Value(model.userId),
      title: Value(model.title),
      content: Value(model.content),
      frequency: Value(model.frequency.name),
      status: Value(model.status.name),
      category: Value(model.category),
      reminderAt: Value(model.reminderAt),
      answeredAt: Value(model.answeredAt),
      updatedAt: Value(model.updatedAt),
      version: Value(model.version),
      deleted: Value(model.deleted),
      trashedAt: Value(model.trashedAt),
      createdAt: Value(model.createdAt),
      fieldUpdatedAt: Value(jsonEncode(model.fieldUpdatedAt)),
    );
  }

  static Map<String, int> _parseFieldTimestamps(String raw) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
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

class PrayerNotFoundException implements Exception {
  final String prayerId;
  PrayerNotFoundException(this.prayerId);

  @override
  String toString() => 'Prayer not found: $prayerId';
}
