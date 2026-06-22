import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Attachment type for feedback messages
enum FeedbackAttachmentType {
  image,
  video,
  file;

  String toDbValue() {
    switch (this) {
      case FeedbackAttachmentType.image:
        return 'image';
      case FeedbackAttachmentType.video:
        return 'video';
      case FeedbackAttachmentType.file:
        return 'file';
    }
  }

  static FeedbackAttachmentType fromDbValue(String value) {
    switch (value) {
      case 'image':
        return FeedbackAttachmentType.image;
      case 'video':
        return FeedbackAttachmentType.video;
      case 'file':
      default:
        return FeedbackAttachmentType.file;
    }
  }
}

/// Domain model for a feedback attachment
class FeedbackAttachmentModel implements SyncEntity {
  @override
  final String id;

  final String messageId;

  final String url;

  final String type;

  final int size;

  final String? fileName;

  @override
  final int updatedAt;

  @override
  final int version;

  final int deleted;

  @override
  final int? trashedAt;

  final int createdAt;

  final Map<String, dynamic> fieldUpdatedAt;

  const FeedbackAttachmentModel({
    required this.id,
    required this.messageId,
    required this.url,
    required this.type,
    this.size = 0,
    this.fileName,
    required this.updatedAt,
    required this.version,
    required this.deleted,
    this.trashedAt,
    required this.createdAt,
    this.fieldUpdatedAt = const {},
  });

  @override
  bool get isDeleted => deleted == 1;

  FeedbackAttachmentType get typeEnum =>
      FeedbackAttachmentType.fromDbValue(type);

  bool get isImage => typeEnum == FeedbackAttachmentType.image;

  bool get isVideo => typeEnum == FeedbackAttachmentType.video;

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'messageId': messageId,
      'url': url,
      'type': type,
      'size': size,
      'fileName': fileName,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
      'fieldUpdatedAt': fieldUpdatedAt,
    };
  }

  factory FeedbackAttachmentModel.fromJson(Map<String, dynamic> json) {
    return FeedbackAttachmentModel(
      id: (json['id'] ?? json['_id']) as String,
      messageId: json['messageId'] as String,
      url: json['url'] as String,
      type: json['type'] as String? ?? 'file',
      size: json['size'] as int? ?? 0,
      fileName: json['fileName'] as String?,
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

  factory FeedbackAttachmentModel.create({
    required String id,
    required String messageId,
    required String url,
    required String type,
    int size = 0,
    String? fileName,
  }) {
    final now = TestClock.now();
    return FeedbackAttachmentModel(
      id: id,
      messageId: messageId,
      url: url,
      type: type,
      size: size,
      fileName: fileName,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
    );
  }

  FeedbackAttachmentModel softDelete() {
    return FeedbackAttachmentModel(
      id: id,
      messageId: messageId,
      url: url,
      type: type,
      size: size,
      fileName: fileName,
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
      other is FeedbackAttachmentModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() {
    return 'FeedbackAttachmentModel(id: $id, messageId: $messageId, type: $type, v$version)';
  }
}
