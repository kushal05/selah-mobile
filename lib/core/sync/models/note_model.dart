import 'dart:convert';

import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Domain model for Note (metadata only)
///
/// Per spec section 3.4:
/// - No content stored here
/// - Keeps note list fast
/// - Prevents massive row updates during typing
/// - Content is stored in NoteBlockModel
class NoteModel implements SyncEntity {
  @override
  final String id;

  /// Folder this note belongs to
  final String folderId;

  /// Owner user ID
  final String userId;

  /// Note title
  final String title;

  @override
  final int updatedAt;

  @override
  final int version;

  /// Soft delete flag
  final int deleted;

  @override
  final int? trashedAt;

  /// Creation timestamp
  final int createdAt;

  /// Optional preacher reference (for sermon notes)
  final String? preacherId;

  /// Optional date associated with note
  final int? noteDate;

  /// Per-field update timestamps for field-level merge.
  /// Keys are field names, values are Unix millisecond timestamps.
  final Map<String, int> fieldUpdatedAt;

  /// JSON snapshot of the full block list for fast single-read access.
  final String? documentJson;

  /// Fields eligible for field-level merge.
  static const mergeableFields = [
    'title',
    'folderId',
    'preacherId',
    'noteDate',
    'documentJson',
  ];

  const NoteModel({
    required this.id,
    required this.folderId,
    required this.userId,
    required this.title,
    required this.updatedAt,
    required this.version,
    required this.deleted,
    this.trashedAt,
    required this.createdAt,
    this.preacherId,
    this.noteDate,
    this.fieldUpdatedAt = const {},
    this.documentJson,
  });

  @override
  bool get isDeleted => deleted == 1;

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      // Serialize the 'root' sentinel as null so the server receives a valid
      // nullable UUID (null) instead of the string 'root', which PostgreSQL
      // would reject as an invalid UUID format.
      'folderId': folderId == 'root' ? null : folderId,
      'userId': userId,
      'title': title,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
      if (preacherId != null) 'preacherId': preacherId,
      if (noteDate != null) 'noteDate': noteDate,
      'fieldUpdatedAt': fieldUpdatedAt,
      if (documentJson != null) 'documentJson': documentJson,
    };
  }

  factory NoteModel.fromJson(Map<String, dynamic> json) {
    return NoteModel(
      id: (json['id'] ?? json['_id']) as String,
      // Server returns null for root-level notes (folder_id is a nullable UUID).
      // Convert null back to the 'root' sentinel used internally.
      folderId: (json['folderId'] as String?) ?? 'root',
      userId: json['userId'] as String,
      title: json['title'] as String,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
      preacherId: json['preacherId'] as String?,
      noteDate: json['noteDate'] as int?,
      fieldUpdatedAt: _parseFieldTimestamps(json['fieldUpdatedAt']),
      documentJson: json['documentJson'] as String?,
    );
  }

  /// Create a new note
  factory NoteModel.create({
    required String id,
    required String folderId,
    required String userId,
    required String title,
    String? preacherId,
    int? noteDate,
  }) {
    final now = TestClock.now();
    return NoteModel(
      id: id,
      folderId: folderId,
      userId: userId,
      title: title,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
      preacherId: preacherId,
      noteDate: noteDate,
      fieldUpdatedAt: {for (final f in mergeableFields) f: now},
    );
  }

  /// Create updated copy with incremented version
  NoteModel copyWithUpdate({
    String? folderId,
    String? title,
    String? preacherId,
    int? noteDate,
    bool clearPreacher = false,
    bool clearNoteDate = false,
    String? documentJson,
  }) {
    final now = TestClock.now();
    final newFieldTimestamps = Map<String, int>.from(fieldUpdatedAt);
    if (title != null) newFieldTimestamps['title'] = now;
    if (folderId != null) newFieldTimestamps['folderId'] = now;
    if (preacherId != null || clearPreacher) {
      newFieldTimestamps['preacherId'] = now;
    }
    if (noteDate != null || clearNoteDate) {
      newFieldTimestamps['noteDate'] = now;
    }
    if (documentJson != null) newFieldTimestamps['documentJson'] = now;

    return NoteModel(
      id: id,
      folderId: folderId ?? this.folderId,
      userId: userId,
      title: title ?? this.title,
      updatedAt: now,
      version: version + 1,
      deleted: deleted,
      trashedAt: trashedAt,
      createdAt: createdAt,
      preacherId: clearPreacher ? null : (preacherId ?? this.preacherId),
      noteDate: clearNoteDate ? null : (noteDate ?? this.noteDate),
      fieldUpdatedAt: newFieldTimestamps,
      documentJson: documentJson ?? this.documentJson,
    );
  }

  /// Create soft-deleted copy
  NoteModel softDelete() {
    return NoteModel(
      id: id,
      folderId: folderId,
      userId: userId,
      title: title,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 1,
      trashedAt: trashedAt,
      createdAt: createdAt,
      preacherId: preacherId,
      noteDate: noteDate,
      fieldUpdatedAt: fieldUpdatedAt,
      documentJson: documentJson,
    );
  }

  /// Move to trash (recoverable)
  NoteModel moveToTrash() {
    final now = TestClock.now();
    return NoteModel(
      id: id,
      folderId: folderId,
      userId: userId,
      title: title,
      updatedAt: now,
      version: version + 1,
      deleted: deleted,
      trashedAt: now,
      createdAt: createdAt,
      preacherId: preacherId,
      noteDate: noteDate,
      fieldUpdatedAt: fieldUpdatedAt,
      documentJson: documentJson,
    );
  }

  /// Restore from trash
  NoteModel restoreFromTrash() {
    return NoteModel(
      id: id,
      folderId: folderId,
      userId: userId,
      title: title,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: null,
      createdAt: createdAt,
      preacherId: preacherId,
      noteDate: noteDate,
      fieldUpdatedAt: fieldUpdatedAt,
      documentJson: documentJson,
    );
  }

  /// Parse fieldUpdatedAt from various JSON representations.
  static Map<String, int> _parseFieldTimestamps(dynamic value) {
    if (value == null) return {};
    if (value is Map<String, dynamic>) {
      try {
        return value.map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {
        return {};
      }
    }
    if (value is String) {
      try {
        final decoded = jsonDecode(value) as Map<String, dynamic>;
        return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {
        return {};
      }
    }
    return {};
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
      other is NoteModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() {
    return 'NoteModel(id: $id, title: $title, v$version, deleted: $isDeleted)';
  }
}
