import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'block_type.dart';
import 'editor_block.dart';
import 'note_section.dart';

/// Represents the complete editor document state
/// This is the single source of truth for the editor content
@immutable
class EditorDocument extends Equatable {
  /// Ordered list of blocks in the document
  final List<EditorBlock> blocks;

  const EditorDocument({
    required this.blocks,
  });

  /// Create an empty document with a single paragraph
  factory EditorDocument.empty() {
    return EditorDocument(
      blocks: [EditorBlock.paragraph()],
    );
  }

  /// Whether the document is empty (single empty block)
  bool get isEmpty => blocks.length == 1 && blocks.first.isEmpty;

  /// Total number of blocks
  int get blockCount => blocks.length;

  /// Get block by ID
  EditorBlock? getBlockById(String id) {
    return blocks.firstWhereOrNull((block) => block.id == id);
  }

  /// Get block index by ID
  int? getBlockIndex(String id) {
    final index = blocks.indexWhere((block) => block.id == id);
    return index == -1 ? null : index;
  }

  /// Get block at index
  EditorBlock? getBlockAt(int index) {
    if (index < 0 || index >= blocks.length) return null;
    return blocks[index];
  }

  /// Get previous block
  EditorBlock? getPreviousBlock(String currentBlockId) {
    final index = getBlockIndex(currentBlockId);
    if (index == null || index == 0) return null;
    return blocks[index - 1];
  }

  /// Get next block
  EditorBlock? getNextBlock(String currentBlockId) {
    final index = getBlockIndex(currentBlockId);
    if (index == null || index >= blocks.length - 1) return null;
    return blocks[index + 1];
  }

  /// Update a block
  EditorDocument updateBlock(String blockId, EditorBlock newBlock) {
    final index = getBlockIndex(blockId);
    if (index == null) return this;

    final newBlocks = List<EditorBlock>.from(blocks);
    newBlocks[index] = newBlock;

    return EditorDocument(blocks: newBlocks);
  }

  /// Insert a block at a specific index
  EditorDocument insertBlockAt(int index, EditorBlock block) {
    final newBlocks = List<EditorBlock>.from(blocks);
    newBlocks.insert(index, block);

    return EditorDocument(blocks: newBlocks);
  }

  /// Insert a block after another block
  EditorDocument insertBlockAfter(String afterBlockId, EditorBlock block) {
    final index = getBlockIndex(afterBlockId);
    if (index == null) return this;

    return insertBlockAt(index + 1, block);
  }

  /// Delete a block
  EditorDocument deleteBlock(String blockId) {
    final newBlocks = blocks.where((block) => block.id != blockId).toList();

    // Always keep at least one block
    if (newBlocks.isEmpty) {
      return EditorDocument(blocks: [EditorBlock.paragraph()]);
    }

    return EditorDocument(blocks: newBlocks);
  }

  /// Replace a block at index
  EditorDocument replaceBlockAt(int index, EditorBlock block) {
    if (index < 0 || index >= blocks.length) return this;

    final newBlocks = List<EditorBlock>.from(blocks);
    newBlocks[index] = block;

    return EditorDocument(blocks: newBlocks);
  }

  /// Calculate display number for a numbered list item
  /// Numbers are derived based on position within same indent level
  int calculateListNumber(String blockId) {
    final block = getBlockById(blockId);
    final index = getBlockIndex(blockId);
    if (block == null || index == null || block.type != BlockType.numberedList) {
      return 1;
    }

    int number = 1;
    final targetIndent = block.indentLevel;

    // Walk backward counting items at same indent level.
    // Skip over children (higher indent) regardless of their type,
    // so nested bullet lists inside a numbered list don't break the count.
    for (int i = index - 1; i >= 0; i--) {
      final prev = blocks[i];
      // Skip children (higher indent) - continue loop
      if (prev.indentLevel > targetIndent) continue;
      // Stop if we hit parent level (lower indent)
      if (prev.indentLevel < targetIndent) break;
      // Same indent level: count if numbered, stop otherwise
      if (prev.type == BlockType.numberedList) {
        number++;
      } else {
        break;
      }
    }

    return number;
  }

  /// Check if block can be indented (needs previous sibling at same level)
  bool canIndent(String blockId) {
    final block = getBlockById(blockId);
    final index = getBlockIndex(blockId);
    if (block == null || index == null || !block.type.isList || index == 0) {
      return false;
    }

    // Check for previous sibling at same or lower indent level
    for (int i = index - 1; i >= 0; i--) {
      final prev = blocks[i];
      // Not a list block - can't indent
      if (!prev.type.isList) return false;
      // Found sibling at same level - can indent
      if (prev.indentLevel == block.indentLevel) return true;
      // Hit parent level - no sibling found
      if (prev.indentLevel < block.indentLevel) return false;
    }
    return false;
  }

  /// Check if block can be outdented (is a list block)
  bool canOutdent(String blockId) {
    final block = getBlockById(blockId);
    return block != null && block.type.isList;
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'blocks': blocks.map((b) => b.toJson()).toList(),
      'version': 1, // Document schema version
    };
  }

  /// Create from JSON
  factory EditorDocument.fromJson(Map<String, dynamic> json) {
    final blocksJson = json['blocks'] as List<dynamic>?;

    if (blocksJson == null || blocksJson.isEmpty) {
      return EditorDocument.empty();
    }

    final blocks = blocksJson
        .map((b) => EditorBlock.fromJson(b as Map<String, dynamic>))
        .toList();

    return EditorDocument(blocks: blocks);
  }

  // ==================== Section Operations ====================

  /// Get all blocks for a specific section
  List<EditorBlock> getBlocksForSection(NoteSection section) {
    return blocks.where((b) => b.section == section).toList();
  }

  /// Whether a section has any non-empty content
  bool isSectionEmpty(NoteSection section) {
    final sectionBlocks = getBlocksForSection(section);
    return sectionBlocks.isEmpty ||
        (sectionBlocks.length == 1 && sectionBlocks.first.isEmpty);
  }

  /// Get the previous block within the same section
  EditorBlock? getPreviousBlockInSection(String currentBlockId) {
    final block = getBlockById(currentBlockId);
    if (block == null) return null;

    final sectionBlocks = getBlocksForSection(block.section);
    final sectionIndex = sectionBlocks.indexWhere((b) => b.id == currentBlockId);
    if (sectionIndex <= 0) return null;
    return sectionBlocks[sectionIndex - 1];
  }

  /// Get the next block within the same section
  EditorBlock? getNextBlockInSection(String currentBlockId) {
    final block = getBlockById(currentBlockId);
    if (block == null) return null;

    final sectionBlocks = getBlocksForSection(block.section);
    final sectionIndex = sectionBlocks.indexWhere((b) => b.id == currentBlockId);
    if (sectionIndex < 0 || sectionIndex >= sectionBlocks.length - 1) return null;
    return sectionBlocks[sectionIndex + 1];
  }

  /// Add a block at the end of a section
  EditorDocument addBlockToSection(NoteSection section, EditorBlock block) {
    final newBlocks = List<EditorBlock>.from(blocks);
    // Find the last block in this section
    int insertIndex = newBlocks.length;
    for (int i = newBlocks.length - 1; i >= 0; i--) {
      if (newBlocks[i].section == section) {
        insertIndex = i + 1;
        break;
      }
    }
    // If no blocks exist for this section yet, insert after the last block
    // of the previous section (maintain section ordering)
    if (!newBlocks.any((b) => b.section == section)) {
      final sectionOrder = [NoteSection.main, NoteSection.personalApplication, NoteSection.prayer];
      final targetIdx = sectionOrder.indexOf(section);
      // Find last block of any prior section
      insertIndex = 0;
      for (int s = targetIdx - 1; s >= 0; s--) {
        for (int i = newBlocks.length - 1; i >= 0; i--) {
          if (newBlocks[i].section == sectionOrder[s]) {
            insertIndex = i + 1;
            break;
          }
        }
        if (insertIndex > 0) break;
      }
      if (insertIndex == 0) insertIndex = newBlocks.length;
    }
    newBlocks.insert(insertIndex, block);
    return EditorDocument(blocks: newBlocks);
  }

  /// Delete a block, but ensure at least one block remains in the main section
  EditorDocument deleteBlockInSection(String blockId) {
    final block = getBlockById(blockId);
    if (block == null) return this;

    final newBlocks = blocks.where((b) => b.id != blockId).toList();

    // If main section is now empty, add a default paragraph
    if (block.section == NoteSection.main &&
        !newBlocks.any((b) => b.section == NoteSection.main)) {
      newBlocks.insert(0, EditorBlock.paragraph());
    }

    return EditorDocument(blocks: newBlocks);
  }

  /// Copy with modifications
  EditorDocument copyWith({
    List<EditorBlock>? blocks,
  }) {
    return EditorDocument(
      blocks: blocks ?? this.blocks,
    );
  }

  @override
  List<Object?> get props => [blocks];

  @override
  String toString() => 'EditorDocument(blockCount: $blockCount)';
}
