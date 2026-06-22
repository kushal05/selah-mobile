import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/sync_database.dart';
import '../models/oplog_entry.dart';
import '../models/feedback_thread_model.dart';
import 'base_sync_repository.dart';

/// Repository for feedback thread operations
///
/// Per spec: Every write is transactional with oplog entry
class FeedbackThreadRepository extends BaseSyncRepository<FeedbackThreadModel> {
  final SyncDatabase _db;
  final String _deviceId;

  FeedbackThreadRepository(this._db, this._deviceId);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.feedbackThread;

  // ==================== READ OPERATIONS ====================

  /// Get all feedback threads (non-deleted) for a user, ordered by most recent
  Future<List<FeedbackThreadModel>> getUserThreads(String userId) async {
    final query = _db.select(_db.feedbackThreads)
      ..where((t) => t.deleted.equals(0) & t.userId.equals(userId))
      ..orderBy([(t) => OrderingTerm.desc(t.lastMessageAt)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Watch all feedback threads (reactive stream) for a user
  Stream<List<FeedbackThreadModel>> watchUserThreads(String userId) {
    final query = _db.select(_db.feedbackThreads)
      ..where((t) => t.deleted.equals(0) & t.userId.equals(userId))
      ..orderBy([(t) => OrderingTerm.desc(t.lastMessageAt)]);

    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Get a single thread by ID
  Future<FeedbackThreadModel?> getThreadById(String id) async {
    final query = _db.select(_db.feedbackThreads)
      ..where((t) => t.id.equals(id));

    final row = await query.getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  /// Watch a single thread by ID (reactive)
  Stream<FeedbackThreadModel?> watchThreadById(String id) {
    final query = _db.select(_db.feedbackThreads)
      ..where((t) => t.id.equals(id));

    return query.watchSingleOrNull().map((row) => row != null ? _toModel(row) : null);
  }

  // ==================== WRITE OPERATIONS ====================

  /// Create a new feedback thread
  Future<FeedbackThreadModel> createThread({
    required String userId,
    required String category,
    required String subject,
    String? deviceModel,
    String? osVersion,
    String? appVersion,
  }) async {
    final thread = FeedbackThreadModel.create(
      id: generateId(),
      userId: userId,
      category: category,
      subject: subject,
      deviceModel: deviceModel,
      osVersion: osVersion,
      appVersion: appVersion,
    );

    final oplogEntry = createInsertOp(thread);

    await _db.transaction(() async {
      await _db.into(_db.feedbackThreads).insert(_toCompanion(thread));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return thread;
  }

  /// Update thread status or metadata
  Future<FeedbackThreadModel> updateThread({
    required String id,
    String? status,
    String? priority,
    int? lastMessageAt,
    String? adminAssigned,
    int? unreadForUser,
    int? unreadForAdmin,
  }) async {
    final existing = await getThreadById(id);
    if (existing == null) {
      throw FeedbackThreadNotFoundException(id);
    }

    final updated = existing.copyWithUpdate(
      status: status,
      priority: priority,
      lastMessageAt: lastMessageAt,
      adminAssigned: adminAssigned,
      unreadForUser: unreadForUser,
      unreadForAdmin: unreadForAdmin,
    );

    final oplogEntry = createUpdateOp(updated);

    await _db.transaction(() async {
      await (_db.update(_db.feedbackThreads)..where((t) => t.id.equals(id)))
          .write(_toCompanion(updated));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return updated;
  }

  /// Soft delete a thread
  Future<void> deleteThread(String id) async {
    final existing = await getThreadById(id);
    if (existing == null) {
      throw FeedbackThreadNotFoundException(id);
    }

    final deletedThread = existing.softDelete();
    final oplogEntry = createDeleteOp(deletedThread);

    await _db.transaction(() async {
      await (_db.update(_db.feedbackThreads)..where((t) => t.id.equals(id)))
          .write(_toCompanion(deletedThread));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
  }

  // ==================== HELPER METHODS ====================

  FeedbackThreadModel _toModel(FeedbackThread row) {
    return FeedbackThreadModel(
      id: row.id,
      userId: row.userId,
      category: row.category,
      subject: row.subject,
      status: row.status,
      priority: row.priority,
      lastMessageAt: row.lastMessageAt,
      adminAssigned: row.adminAssigned,
      unreadForUser: row.unreadForUser,
      unreadForAdmin: row.unreadForAdmin,
      deviceModel: row.deviceModel,
      osVersion: row.osVersion,
      appVersion: row.appVersion,
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      createdAt: row.createdAt,
      fieldUpdatedAt: _parseFieldTimestamps(row.fieldUpdatedAt),
    );
  }

  FeedbackThreadsCompanion _toCompanion(FeedbackThreadModel model) {
    return FeedbackThreadsCompanion(
      id: Value(model.id),
      userId: Value(model.userId),
      category: Value(model.category),
      subject: Value(model.subject),
      status: Value(model.status),
      priority: Value(model.priority),
      lastMessageAt: Value(model.lastMessageAt),
      adminAssigned: Value(model.adminAssigned),
      unreadForUser: Value(model.unreadForUser),
      unreadForAdmin: Value(model.unreadForAdmin),
      deviceModel: Value(model.deviceModel),
      osVersion: Value(model.osVersion),
      appVersion: Value(model.appVersion),
      updatedAt: Value(model.updatedAt),
      version: Value(model.version),
      deleted: Value(model.deleted),
      createdAt: Value(model.createdAt),
      fieldUpdatedAt: Value(jsonEncode(model.fieldUpdatedAt)),
    );
  }

  static Map<String, dynamic> _parseFieldTimestamps(String raw) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
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

class FeedbackThreadNotFoundException implements Exception {
  final String threadId;
  FeedbackThreadNotFoundException(this.threadId);

  @override
  String toString() => 'Feedback thread not found: $threadId';
}
