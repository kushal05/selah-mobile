import 'package:drift/drift.dart';

import '../../database/sync_database.dart';
import '../../testing/test_clock.dart';

/// Repository for document editing operations (CRDT foundation).
///
/// Phase A (current): local-only, no oplog entries.
/// Phase B (future): will extend BaseSyncRepository for cross-device sync.
///
/// Records editing operations for future collaborative editing support.
class DocumentOperationsRepository {
  final SyncDatabase _db;

  DocumentOperationsRepository(this._db);

  /// Record a new editing operation.
  Future<void> insertOperation({
    required String id,
    required String entityType,
    required String entityId,
    required String operationType,
    required String payload,
    required String userId,
    required String deviceId,
    required int sequenceNumber,
  }) async {
    await _db.into(_db.documentOperations).insert(
          DocumentOperationsCompanion.insert(
            id: id,
            entityType: entityType,
            entityId: entityId,
            operationType: operationType,
            payload: payload,
            userId: userId,
            deviceId: deviceId,
            timestamp: TestClock.now(),
            sequenceNumber: sequenceNumber,
          ),
        );
  }

  /// Get all operations for an entity, ordered by sequence number.
  Future<List<DocumentOperation>> getOperationsForEntity(
    String entityId,
  ) async {
    final query = _db.select(_db.documentOperations)
      ..where((d) => d.entityId.equals(entityId))
      ..orderBy([(d) => OrderingTerm.asc(d.sequenceNumber)]);
    return query.get();
  }

  /// Get operations after a given sequence number (for replay/merge).
  Future<List<DocumentOperation>> getOperationsAfter(
    String entityId,
    int afterSequence,
  ) async {
    final query = _db.select(_db.documentOperations)
      ..where((d) =>
          d.entityId.equals(entityId) &
          d.sequenceNumber.isBiggerThanValue(afterSequence))
      ..orderBy([(d) => OrderingTerm.asc(d.sequenceNumber)]);
    return query.get();
  }

  /// Get the next sequence number for an entity.
  Future<int> getNextSequenceNumber(String entityId) async {
    final result = await _db.customSelect(
      'SELECT MAX(sequence_number) as max_seq FROM document_operations '
      'WHERE entity_id = ?',
      variables: [Variable.withString(entityId)],
    ).getSingleOrNull();
    final maxSeq = result?.read<int?>('max_seq');
    return (maxSeq ?? 0) + 1;
  }

  /// Delete all operations for an entity (cleanup).
  Future<void> deleteOperationsForEntity(String entityId) async {
    await (_db.delete(_db.documentOperations)
          ..where((d) => d.entityId.equals(entityId)))
        .go();
  }
}
