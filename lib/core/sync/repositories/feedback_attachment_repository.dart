import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/sync_database.dart';
import '../models/oplog_entry.dart';
import '../models/feedback_attachment_model.dart';
import 'base_sync_repository.dart';

/// Repository for feedback attachment operations
///
/// Per spec: Every write is transactional with oplog entry
class FeedbackAttachmentRepository
    extends BaseSyncRepository<FeedbackAttachmentModel> {
  final SyncDatabase _db;
  final String _deviceId;

  FeedbackAttachmentRepository(this._db, this._deviceId);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.feedbackAttachment;

  // ==================== READ OPERATIONS ====================

  /// Get all attachments (non-deleted) for a message
  Future<List<FeedbackAttachmentModel>> getMessageAttachments(
      String messageId) async {
    final query = _db.select(_db.feedbackAttachments)
      ..where((a) => a.deleted.equals(0) & a.messageId.equals(messageId))
      ..orderBy([(a) => OrderingTerm.asc(a.createdAt)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Watch all attachments for a message (reactive stream)
  Stream<List<FeedbackAttachmentModel>> watchMessageAttachments(
      String messageId) {
    final query = _db.select(_db.feedbackAttachments)
      ..where((a) => a.deleted.equals(0) & a.messageId.equals(messageId))
      ..orderBy([(a) => OrderingTerm.asc(a.createdAt)]);

    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Get a single attachment by ID
  Future<FeedbackAttachmentModel?> getAttachmentById(String id) async {
    final query = _db.select(_db.feedbackAttachments)
      ..where((a) => a.id.equals(id));

    final row = await query.getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  // ==================== WRITE OPERATIONS ====================

  /// Create a new attachment record
  Future<FeedbackAttachmentModel> createAttachment({
    required String messageId,
    required String url,
    required String type,
    int size = 0,
    String? fileName,
  }) async {
    final attachment = FeedbackAttachmentModel.create(
      id: generateId(),
      messageId: messageId,
      url: url,
      type: type,
      size: size,
      fileName: fileName,
    );

    final oplogEntry = createInsertOp(attachment);

    await _db.transaction(() async {
      await _db
          .into(_db.feedbackAttachments)
          .insert(_toCompanion(attachment));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return attachment;
  }

  /// Soft delete an attachment
  Future<void> deleteAttachment(String id) async {
    final existing = await getAttachmentById(id);
    if (existing == null) {
      throw FeedbackAttachmentNotFoundException(id);
    }

    final deletedAttachment = existing.softDelete();
    final oplogEntry = createDeleteOp(deletedAttachment);

    await _db.transaction(() async {
      await (_db.update(_db.feedbackAttachments)
            ..where((a) => a.id.equals(id)))
          .write(_toCompanion(deletedAttachment));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
  }

  // ==================== HELPER METHODS ====================

  FeedbackAttachmentModel _toModel(FeedbackAttachment row) {
    return FeedbackAttachmentModel(
      id: row.id,
      messageId: row.messageId,
      url: row.url,
      type: row.type,
      size: row.size,
      fileName: row.fileName,
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      createdAt: row.createdAt,
      fieldUpdatedAt: _parseFieldTimestamps(row.fieldUpdatedAt),
    );
  }

  FeedbackAttachmentsCompanion _toCompanion(FeedbackAttachmentModel model) {
    return FeedbackAttachmentsCompanion(
      id: Value(model.id),
      messageId: Value(model.messageId),
      url: Value(model.url),
      type: Value(model.type),
      size: Value(model.size),
      fileName: Value(model.fileName),
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

class FeedbackAttachmentNotFoundException implements Exception {
  final String attachmentId;
  FeedbackAttachmentNotFoundException(this.attachmentId);

  @override
  String toString() => 'Feedback attachment not found: $attachmentId';
}
