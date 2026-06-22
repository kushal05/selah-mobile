import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/sync_database.dart';
import '../models/oplog_entry.dart';
import '../models/feedback_message_model.dart';
import 'base_sync_repository.dart';

/// Repository for feedback message operations
///
/// Per spec: Every write is transactional with oplog entry
class FeedbackMessageRepository extends BaseSyncRepository<FeedbackMessageModel> {
  final SyncDatabase _db;
  final String _deviceId;

  FeedbackMessageRepository(this._db, this._deviceId);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.feedbackMessage;

  // ==================== READ OPERATIONS ====================

  /// Get all messages (non-deleted) for a thread, ordered by creation time
  Future<List<FeedbackMessageModel>> getThreadMessages(String threadId) async {
    final query = _db.select(_db.feedbackMessages)
      ..where((m) => m.deleted.equals(0) & m.threadId.equals(threadId))
      ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Watch all messages for a thread (reactive stream)
  Stream<List<FeedbackMessageModel>> watchThreadMessages(String threadId) {
    final query = _db.select(_db.feedbackMessages)
      ..where((m) => m.deleted.equals(0) & m.threadId.equals(threadId))
      ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]);

    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Get a single message by ID
  Future<FeedbackMessageModel?> getMessageById(String id) async {
    final query = _db.select(_db.feedbackMessages)
      ..where((m) => m.id.equals(id));

    final row = await query.getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  // ==================== WRITE OPERATIONS ====================

  /// Add a message to a thread
  Future<FeedbackMessageModel> addMessage({
    required String threadId,
    required String userId,
    required String message,
    String senderType = 'user',
    int hasAttachments = 0,
  }) async {
    final msg = FeedbackMessageModel.create(
      id: generateId(),
      threadId: threadId,
      userId: userId,
      message: message,
      senderType: senderType,
      hasAttachments: hasAttachments,
    );

    final oplogEntry = createInsertOp(msg);

    await _db.transaction(() async {
      await _db.into(_db.feedbackMessages).insert(_toCompanion(msg));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return msg;
  }

  /// Soft delete a message
  Future<void> deleteMessage(String id) async {
    final existing = await getMessageById(id);
    if (existing == null) {
      throw FeedbackMessageNotFoundException(id);
    }

    final deletedMsg = existing.softDelete();
    final oplogEntry = createDeleteOp(deletedMsg);

    await _db.transaction(() async {
      await (_db.update(_db.feedbackMessages)..where((m) => m.id.equals(id)))
          .write(_toCompanion(deletedMsg));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
  }

  // ==================== HELPER METHODS ====================

  FeedbackMessageModel _toModel(FeedbackMessage row) {
    return FeedbackMessageModel(
      id: row.id,
      threadId: row.threadId,
      userId: row.userId,
      message: row.message,
      senderType: row.senderType,
      hasAttachments: row.hasAttachments,
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      createdAt: row.createdAt,
      fieldUpdatedAt: _parseFieldTimestamps(row.fieldUpdatedAt),
    );
  }

  FeedbackMessagesCompanion _toCompanion(FeedbackMessageModel model) {
    return FeedbackMessagesCompanion(
      id: Value(model.id),
      threadId: Value(model.threadId),
      userId: Value(model.userId),
      message: Value(model.message),
      senderType: Value(model.senderType),
      hasAttachments: Value(model.hasAttachments),
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

class FeedbackMessageNotFoundException implements Exception {
  final String messageId;
  FeedbackMessageNotFoundException(this.messageId);

  @override
  String toString() => 'Feedback message not found: $messageId';
}
