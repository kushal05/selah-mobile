import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Domain model for NoteTag junction (sync-enabled)
///
/// Each note-tag association has its own stable ID for oplog tracking.
class NoteTagModel implements SyncEntity {
  @override
  final String id;

  final String noteId;
  final String tagId;
  final String userId;

  @override
  final int updatedAt;

  @override
  final int version;

  final int deleted;

  @override
  final int? trashedAt;

  final int createdAt;

  const NoteTagModel({
    required this.id,
    required this.noteId,
    required this.tagId,
    required this.userId,
    required this.updatedAt,
    required this.version,
    required this.deleted,
    this.trashedAt,
    required this.createdAt,
  });

  @override
  bool get isDeleted => deleted == 1;

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'noteId': noteId,
      'tagId': tagId,
      'userId': userId,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
    };
  }

  factory NoteTagModel.fromJson(Map<String, dynamic> json) {
    return NoteTagModel(
      id: (json['id'] ?? json['_id']) as String,
      noteId: json['noteId'] as String,
      tagId: json['tagId'] as String,
      userId: json['userId'] as String,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
    );
  }

  factory NoteTagModel.create({
    required String id,
    required String noteId,
    required String tagId,
    required String userId,
  }) {
    final now = TestClock.now();
    return NoteTagModel(
      id: id,
      noteId: noteId,
      tagId: tagId,
      userId: userId,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
    );
  }

  NoteTagModel softDelete() {
    return NoteTagModel(
      id: id,
      noteId: noteId,
      tagId: tagId,
      userId: userId,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 1,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  /// Move to trash (recoverable, cascade from parent)
  NoteTagModel moveToTrash() {
    final now = TestClock.now();
    return NoteTagModel(
      id: id,
      noteId: noteId,
      tagId: tagId,
      userId: userId,
      updatedAt: now,
      version: version + 1,
      deleted: deleted,
      trashedAt: now,
      createdAt: createdAt,
    );
  }

  /// Restore from trash
  NoteTagModel restoreFromTrash() {
    return NoteTagModel(
      id: id,
      noteId: noteId,
      tagId: tagId,
      userId: userId,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: null,
      createdAt: createdAt,
    );
  }

  /// Parses deleted flag that may be bool (from API) or int (from local DB).
  static int _parseDeleted(dynamic value) {
    if (value is bool) return value ? 1 : 0;
    if (value is int) return value;
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteTagModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;
}
