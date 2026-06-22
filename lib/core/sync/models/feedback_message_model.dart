import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Sender type for feedback messages
enum FeedbackSenderType {
  user,
  admin,
  system;

  String toDbValue() {
    switch (this) {
      case FeedbackSenderType.user:
        return 'user';
      case FeedbackSenderType.admin:
        return 'admin';
      case FeedbackSenderType.system:
        return 'system';
    }
  }

  static FeedbackSenderType fromDbValue(String value) {
    switch (value) {
      case 'admin':
        return FeedbackSenderType.admin;
      case 'system':
        return FeedbackSenderType.system;
      case 'user':
      default:
        return FeedbackSenderType.user;
    }
  }
}

/// Domain model for a feedback message within a thread
class FeedbackMessageModel implements SyncEntity {
  @override
  final String id;

  final String threadId;

  final String userId;

  final String message;

  final String senderType;

  final int hasAttachments;

  @override
  final int updatedAt;

  @override
  final int version;

  final int deleted;

  @override
  final int? trashedAt;

  final int createdAt;

  final Map<String, dynamic> fieldUpdatedAt;

  const FeedbackMessageModel({
    required this.id,
    required this.threadId,
    required this.userId,
    required this.message,
    required this.senderType,
    this.hasAttachments = 0,
    required this.updatedAt,
    required this.version,
    required this.deleted,
    this.trashedAt,
    required this.createdAt,
    this.fieldUpdatedAt = const {},
  });

  @override
  bool get isDeleted => deleted == 1;

  FeedbackSenderType get senderTypeEnum =>
      FeedbackSenderType.fromDbValue(senderType);

  bool get isFromAdmin => senderTypeEnum == FeedbackSenderType.admin;

  bool get isSystemMessage => senderTypeEnum == FeedbackSenderType.system;

  bool get hasFiles => hasAttachments == 1;

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'threadId': threadId,
      'userId': userId,
      'message': message,
      'senderType': senderType,
      'hasAttachments': hasAttachments,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
      'fieldUpdatedAt': fieldUpdatedAt,
    };
  }

  factory FeedbackMessageModel.fromJson(Map<String, dynamic> json) {
    return FeedbackMessageModel(
      id: (json['id'] ?? json['_id']) as String,
      threadId: json['threadId'] as String,
      userId: json['userId'] as String,
      message: json['message'] as String,
      senderType: json['senderType'] as String? ?? 'user',
      hasAttachments: json['hasAttachments'] as int? ?? 0,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
      fieldUpdatedAt: json['fieldUpdatedAt'] is Map
          ? Map<String, dynamic>.from(json['fieldUpdatedAt'] as Map)
          : const {},
    );
  }

  factory FeedbackMessageModel.create({
    required String id,
    required String threadId,
    required String userId,
    required String message,
    String senderType = 'user',
    int hasAttachments = 0,
  }) {
    final now = TestClock.now();
    return FeedbackMessageModel(
      id: id,
      threadId: threadId,
      userId: userId,
      message: message,
      senderType: senderType,
      hasAttachments: hasAttachments,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
    );
  }

  FeedbackMessageModel copyWithUpdate({
    String? message,
    int? hasAttachments,
  }) {
    return FeedbackMessageModel(
      id: id,
      threadId: threadId,
      userId: userId,
      message: message ?? this.message,
      senderType: senderType,
      hasAttachments: hasAttachments ?? this.hasAttachments,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: trashedAt,
      createdAt: createdAt,
      fieldUpdatedAt: fieldUpdatedAt,
    );
  }

  FeedbackMessageModel softDelete() {
    return FeedbackMessageModel(
      id: id,
      threadId: threadId,
      userId: userId,
      message: message,
      senderType: senderType,
      hasAttachments: hasAttachments,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 1,
      trashedAt: trashedAt,
      createdAt: createdAt,
      fieldUpdatedAt: fieldUpdatedAt,
    );
  }

  static int _parseDeleted(dynamic value) {
    if (value is bool) return value ? 1 : 0;
    if (value is int) return value;
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeedbackMessageModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() {
    return 'FeedbackMessageModel(id: $id, threadId: $threadId, sender: $senderType, v$version)';
  }
}
