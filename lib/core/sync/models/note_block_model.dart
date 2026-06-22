import 'dart:convert';

import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Block types supported in notes
///
/// Maps to block_type column in note_blocks table
enum BlockType {
  paragraph,
  heading1,
  heading2,
  heading3,
  bulletList,
  numberedList,
  checkbox,
  quote,
  code,
  divider,
  image,
  bibleReference;

  String toDbValue() => name;

  static BlockType fromDbValue(String value) {
    return BlockType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => BlockType.paragraph,
    );
  }
}

/// Domain model for NoteBlock (content layer)
///
/// Per spec section 3.5:
/// - Enables partial updates
/// - Smaller sync payloads
/// - Better conflict isolation
///
/// Each block syncs independently, so typing in one block
/// doesn't create conflicts with other blocks.
class NoteBlockModel implements SyncEntity {
  @override
  final String id;

  /// Parent note ID
  final String noteId;

  /// Block type (paragraph, heading, bullet, etc.)
  final BlockType blockType;

  /// Block content as JSON map
  /// Contains formatted text spans, checked state, etc.
  final Map<String, dynamic> content;

  /// Position within the note (0-indexed)
  final int orderIndex;

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

  /// Note section this block belongs to ('main', 'personalApplication', 'prayer')
  final String section;

  const NoteBlockModel({
    required this.id,
    required this.noteId,
    required this.blockType,
    required this.content,
    required this.orderIndex,
    required this.updatedAt,
    required this.version,
    required this.deleted,
    this.trashedAt,
    required this.createdAt,
    this.section = 'main',
  });

  @override
  bool get isDeleted => deleted == 1;

  /// Get content as JSON string (for database storage)
  String get contentJson => jsonEncode(content);

  /// Get plain text from content (for search)
  String get plainText {
    if (content.containsKey('text')) {
      return content['text'] as String? ?? '';
    }
    if (content.containsKey('spans')) {
      final spans = content['spans'] as List?;
      if (spans != null) {
        return spans
            .map((s) => (s as Map<String, dynamic>)['text'] ?? '')
            .join();
      }
    }
    return '';
  }

  /// Check if this is a checkbox block and if it's checked
  bool get isChecked {
    if (blockType != BlockType.checkbox) return false;
    return content['checked'] == true;
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'noteId': noteId,
      'blockType': blockType.toDbValue(),
      'content': content,
      'orderIndex': orderIndex,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
      'section': section,
    };
  }

  factory NoteBlockModel.fromJson(Map<String, dynamic> json) {
    final contentValue = json['content'];
    Map<String, dynamic> content;

    if (contentValue is String) {
      content = jsonDecode(contentValue) as Map<String, dynamic>;
    } else if (contentValue is Map<String, dynamic>) {
      content = contentValue;
    } else {
      content = {};
    }

    return NoteBlockModel(
      id: (json['id'] ?? json['_id']) as String,
      noteId: json['noteId'] as String,
      blockType: BlockType.fromDbValue(json['blockType'] as String),
      content: content,
      orderIndex: json['orderIndex'] as int,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
      section: json['section'] as String? ?? 'main',
    );
  }

  /// Create a new block
  factory NoteBlockModel.create({
    required String id,
    required String noteId,
    required BlockType blockType,
    required Map<String, dynamic> content,
    required int orderIndex,
    String section = 'main',
  }) {
    final now = TestClock.now();
    return NoteBlockModel(
      id: id,
      noteId: noteId,
      blockType: blockType,
      content: content,
      orderIndex: orderIndex,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
      section: section,
    );
  }

  /// Create a simple paragraph block
  factory NoteBlockModel.paragraph({
    required String id,
    required String noteId,
    required int orderIndex,
    String text = '',
  }) {
    return NoteBlockModel.create(
      id: id,
      noteId: noteId,
      blockType: BlockType.paragraph,
      content: {'text': text},
      orderIndex: orderIndex,
    );
  }

  /// Create updated copy with incremented version
  NoteBlockModel copyWithUpdate({
    BlockType? blockType,
    Map<String, dynamic>? content,
    int? orderIndex,
    String? section,
  }) {
    return NoteBlockModel(
      id: id,
      noteId: noteId,
      blockType: blockType ?? this.blockType,
      content: content ?? this.content,
      orderIndex: orderIndex ?? this.orderIndex,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: trashedAt,
      createdAt: createdAt,
      section: section ?? this.section,
    );
  }

  /// Create soft-deleted copy
  NoteBlockModel softDelete() {
    return NoteBlockModel(
      id: id,
      noteId: noteId,
      blockType: blockType,
      content: content,
      orderIndex: orderIndex,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 1,
      trashedAt: trashedAt,
      createdAt: createdAt,
      section: section,
    );
  }

  /// Move to trash (recoverable, cascade from parent)
  NoteBlockModel moveToTrash() {
    final now = TestClock.now();
    return NoteBlockModel(
      id: id,
      noteId: noteId,
      blockType: blockType,
      content: content,
      orderIndex: orderIndex,
      updatedAt: now,
      version: version + 1,
      deleted: deleted,
      trashedAt: now,
      createdAt: createdAt,
      section: section,
    );
  }

  /// Restore from trash
  NoteBlockModel restoreFromTrash() {
    return NoteBlockModel(
      id: id,
      noteId: noteId,
      blockType: blockType,
      content: content,
      orderIndex: orderIndex,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: null,
      createdAt: createdAt,
      section: section,
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
      other is NoteBlockModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() {
    return 'NoteBlockModel(id: $id, noteId: $noteId, type: $blockType, '
        'order: $orderIndex, v$version, deleted: $isDeleted)';
  }
}
