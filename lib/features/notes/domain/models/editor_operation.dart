import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'editor_block.dart';
import 'editor_cursor.dart';
import 'text_span_format.dart';

/// Base class for editor operations (for undo/redo)
@immutable
abstract class EditorOperation extends Equatable {
  const EditorOperation();

  /// Invert this operation (for undo)
  EditorOperation invert();
}

/// Insert text operation
@immutable
class InsertTextOperation extends EditorOperation {
  final String blockId;
  final int offset;
  final String text;
  final EditorCursor? cursorAfter;

  const InsertTextOperation({
    required this.blockId,
    required this.offset,
    required this.text,
    this.cursorAfter,
  });

  @override
  EditorOperation invert() {
    return DeleteTextOperation(
      blockId: blockId,
      offset: offset,
      length: text.length,
      deletedText: text,
    );
  }

  @override
  List<Object?> get props => [blockId, offset, text, cursorAfter];
}

/// Delete text operation
@immutable
class DeleteTextOperation extends EditorOperation {
  final String blockId;
  final int offset;
  final int length;
  final String deletedText;
  final EditorCursor? cursorAfter;

  const DeleteTextOperation({
    required this.blockId,
    required this.offset,
    required this.length,
    required this.deletedText,
    this.cursorAfter,
  });

  @override
  EditorOperation invert() {
    return InsertTextOperation(
      blockId: blockId,
      offset: offset,
      text: deletedText,
    );
  }

  @override
  List<Object?> get props => [blockId, offset, length, deletedText, cursorAfter];
}

/// Insert block operation
@immutable
class InsertBlockOperation extends EditorOperation {
  final int index;
  final EditorBlock block;
  final EditorCursor? cursorAfter;

  const InsertBlockOperation({
    required this.index,
    required this.block,
    this.cursorAfter,
  });

  @override
  EditorOperation invert() {
    return DeleteBlockOperation(
      blockId: block.id,
      deletedBlock: block,
      originalIndex: index,
    );
  }

  @override
  List<Object?> get props => [index, block, cursorAfter];
}

/// Delete block operation
@immutable
class DeleteBlockOperation extends EditorOperation {
  final String blockId;
  final EditorBlock deletedBlock;
  final int originalIndex;
  final EditorCursor? cursorAfter;

  const DeleteBlockOperation({
    required this.blockId,
    required this.deletedBlock,
    required this.originalIndex,
    this.cursorAfter,
  });

  @override
  EditorOperation invert() {
    return InsertBlockOperation(
      index: originalIndex,
      block: deletedBlock,
    );
  }

  @override
  List<Object?> get props => [blockId, deletedBlock, originalIndex, cursorAfter];
}

/// Merge blocks operation
@immutable
class MergeBlocksOperation extends EditorOperation {
  final String firstBlockId;
  final String secondBlockId;
  final EditorBlock firstBlockBefore;
  final EditorBlock secondBlockBefore;
  final int mergeOffset;
  final EditorCursor? cursorAfter;

  const MergeBlocksOperation({
    required this.firstBlockId,
    required this.secondBlockId,
    required this.firstBlockBefore,
    required this.secondBlockBefore,
    required this.mergeOffset,
    this.cursorAfter,
  });

  @override
  EditorOperation invert() {
    return SplitBlockOperation(
      blockId: firstBlockId,
      splitOffset: mergeOffset,
      blockBefore: firstBlockBefore,
      firstBlockAfter: firstBlockBefore,
      secondBlockAfter: secondBlockBefore,
    );
  }

  @override
  List<Object?> get props => [
        firstBlockId,
        secondBlockId,
        firstBlockBefore,
        secondBlockBefore,
        mergeOffset,
        cursorAfter,
      ];
}

/// Split block operation
@immutable
class SplitBlockOperation extends EditorOperation {
  final String blockId;
  final int splitOffset;
  final EditorBlock blockBefore;
  final EditorBlock firstBlockAfter;
  final EditorBlock secondBlockAfter;
  final EditorCursor? cursorAfter;

  const SplitBlockOperation({
    required this.blockId,
    required this.splitOffset,
    required this.blockBefore,
    required this.firstBlockAfter,
    required this.secondBlockAfter,
    this.cursorAfter,
  });

  @override
  EditorOperation invert() {
    return MergeBlocksOperation(
      firstBlockId: firstBlockAfter.id,
      secondBlockId: secondBlockAfter.id,
      firstBlockBefore: firstBlockAfter,
      secondBlockBefore: secondBlockAfter,
      mergeOffset: splitOffset,
    );
  }

  @override
  List<Object?> get props => [
        blockId,
        splitOffset,
        blockBefore,
        firstBlockAfter,
        secondBlockAfter,
        cursorAfter,
      ];
}

/// Format text operation
@immutable
class FormatTextOperation extends EditorOperation {
  final String blockId;
  final TextSpanFormat format;
  final TextSpanFormat? previousFormat;
  final EditorCursor? cursorAfter;

  const FormatTextOperation({
    required this.blockId,
    required this.format,
    this.previousFormat,
    this.cursorAfter,
  });

  @override
  EditorOperation invert() {
    // If there was a previous format, restore it; otherwise remove the format
    return FormatTextOperation(
      blockId: blockId,
      format: previousFormat ?? TextSpanFormat.none(start: format.start, end: format.end),
      previousFormat: format,
    );
  }

  @override
  List<Object?> get props => [blockId, format, previousFormat, cursorAfter];
}

/// Change block type operation
@immutable
class ChangeBlockTypeOperation extends EditorOperation {
  final String blockId;
  final EditorBlock blockBefore;
  final EditorBlock blockAfter;
  final EditorCursor? cursorAfter;

  const ChangeBlockTypeOperation({
    required this.blockId,
    required this.blockBefore,
    required this.blockAfter,
    this.cursorAfter,
  });

  @override
  EditorOperation invert() {
    return ChangeBlockTypeOperation(
      blockId: blockId,
      blockBefore: blockAfter,
      blockAfter: blockBefore,
    );
  }

  @override
  List<Object?> get props => [blockId, blockBefore, blockAfter, cursorAfter];
}

/// Indent/Outdent block operation
/// Used for both indent (Tab) and outdent (Shift+Tab) operations
@immutable
class IndentBlockOperation extends EditorOperation {
  final String blockId;
  final EditorBlock blockBefore;
  final EditorBlock blockAfter;
  final EditorCursor? cursorAfter;

  const IndentBlockOperation({
    required this.blockId,
    required this.blockBefore,
    required this.blockAfter,
    this.cursorAfter,
  });

  @override
  EditorOperation invert() {
    return IndentBlockOperation(
      blockId: blockId,
      blockBefore: blockAfter,
      blockAfter: blockBefore,
    );
  }

  @override
  List<Object?> get props => [blockId, blockBefore, blockAfter, cursorAfter];
}

/// Text content change operation (for word-level undo/redo)
/// Captures the content before and after a word-level change
@immutable
class TextContentOperation extends EditorOperation {
  final String blockId;
  final String contentBefore;
  final String contentAfter;
  final int cursorOffsetBefore;
  final int cursorOffsetAfter;

  const TextContentOperation({
    required this.blockId,
    required this.contentBefore,
    required this.contentAfter,
    required this.cursorOffsetBefore,
    required this.cursorOffsetAfter,
  });

  @override
  EditorOperation invert() {
    return TextContentOperation(
      blockId: blockId,
      contentBefore: contentAfter,
      contentAfter: contentBefore,
      cursorOffsetBefore: cursorOffsetAfter,
      cursorOffsetAfter: cursorOffsetBefore,
    );
  }

  @override
  List<Object?> get props => [
        blockId,
        contentBefore,
        contentAfter,
        cursorOffsetBefore,
        cursorOffsetAfter,
      ];
}
