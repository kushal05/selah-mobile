import '../../domain/models/block_type.dart' as domain;
import '../../domain/models/editor_block.dart';
import '../../domain/models/editor_document.dart';
import '../../domain/models/note.dart' as domain;
import '../../domain/models/note_section.dart';
import '../../domain/models/text_span_format.dart';
import '../../../../core/sync/models/note_block_model.dart';
import '../../../../core/sync/models/note_model.dart';

/// Converts between domain EditorBlock/EditorDocument and sync NoteBlockModel/NoteModel.
///
/// This is the bridge between the UI layer (EditorBlock) and the sync layer (NoteBlockModel).
class NoteBlockConverter {
  /// Convert a [NoteBlockModel] (sync) → [EditorBlock] (domain)
  static EditorBlock toEditorBlock(NoteBlockModel blockModel) {
    final content = blockModel.content;
    final text = content['text'] as String? ?? '';

    // Parse formatting spans
    final formatsList = content['formats'] as List<dynamic>?;
    final formats = formatsList
            ?.map((f) => TextSpanFormat.fromJson(f as Map<String, dynamic>))
            .toList() ??
        [];

    final isChecked = content['checked'] as bool?;
    final indentLevel = content['indentLevel'] as int? ?? 0;

    return EditorBlock(
      id: blockModel.id,
      type: _syncBlockTypeToDomain(blockModel.blockType),
      content: text,
      formats: formats,
      isChecked: isChecked,
      indentLevel: indentLevel,
      section: NoteSection.fromDbValue(blockModel.section),
    );
  }

  /// Convert an [EditorBlock] (domain) → content map for [NoteBlockModel]
  static Map<String, dynamic> buildContentMap(EditorBlock block) {
    // For bible reference blocks, content is already JSON-encoded
    if (block.type == domain.BlockType.bibleReference) {
      return {
        'text': block.content,
        if (block.formats.isNotEmpty)
          'formats': block.formats.map((f) => f.toJson()).toList(),
      };
    }

    return {
      'text': block.content,
      if (block.formats.isNotEmpty)
        'formats': block.formats.map((f) => f.toJson()).toList(),
      if (block.isChecked != null) 'checked': block.isChecked,
      if (block.indentLevel > 0) 'indentLevel': block.indentLevel,
    };
  }

  /// Convert a list of [NoteBlockModel]s → [EditorDocument]
  ///
  /// All blocks (across all sections) are included in a single document.
  /// Blocks retain their section tag for rendering in the editor.
  static EditorDocument toEditorDocument(List<NoteBlockModel> blocks) {
    if (blocks.isEmpty) {
      return EditorDocument.empty();
    }

    final editorBlocks = blocks.map(toEditorBlock).toList();
    return EditorDocument(blocks: editorBlocks);
  }

  /// Convert an [EditorDocument] → list of content maps + block types for creation
  ///
  /// Returns a list of records containing blockType, content map, orderIndex,
  /// and section, ordered by position in the document.
  /// Order indices are assigned per-section (each section starts at 0).
  static List<({BlockType blockType, Map<String, dynamic> content, int orderIndex, String section})>
      fromEditorDocument(EditorDocument document) {
    final result = <({BlockType blockType, Map<String, dynamic> content, int orderIndex, String section})>[];

    // Track order index per section independently
    final sectionCounters = <String, int>{};

    for (final block in document.blocks) {
      final sectionName = block.section.toDbValue();
      final orderIndex = sectionCounters[sectionName] ?? 0;
      sectionCounters[sectionName] = orderIndex + 1;

      result.add((
        blockType: _domainBlockTypeToSync(block.type),
        content: buildContentMap(block),
        orderIndex: orderIndex,
        section: sectionName,
      ));
    }

    return result;
  }

  /// Convert [NoteModel] + [List<NoteBlockModel>] → domain [Note]
  static domain.Note toDomainNote(
    NoteModel noteModel,
    List<NoteBlockModel> blocks,
  ) {
    final document = toEditorDocument(blocks);

    return domain.Note(
      id: noteModel.id,
      title: noteModel.title,
      document: document,
      createdAt: DateTime.fromMillisecondsSinceEpoch(noteModel.createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(noteModel.updatedAt),
      version: noteModel.version,
      preacherId: noteModel.preacherId,
      folderId: noteModel.folderId,
      noteDate: noteModel.noteDate != null
          ? DateTime.fromMillisecondsSinceEpoch(noteModel.noteDate!)
          : null,
    );
  }

  // ==================== Private Helpers ====================

  /// Map sync BlockType → domain BlockType
  static domain.BlockType _syncBlockTypeToDomain(BlockType syncType) {
    return domain.BlockType.values.firstWhere(
      (d) => d.name == syncType.name,
      orElse: () => domain.BlockType.paragraph,
    );
  }

  /// Map domain BlockType → sync BlockType
  static BlockType _domainBlockTypeToSync(domain.BlockType domainType) {
    return BlockType.values.firstWhere(
      (s) => s.name == domainType.name,
      orElse: () => BlockType.paragraph,
    );
  }
}
