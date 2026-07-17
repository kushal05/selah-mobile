import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../bible/domain/models/bible_reference.dart';
import '../../domain/models/block_type.dart';
import '../../domain/models/editor_block.dart';
import '../../domain/models/editor_cursor.dart';
import '../../domain/models/editor_document.dart';
import '../../domain/models/editor_operation.dart';
import '../../domain/models/note.dart';
import '../../domain/models/note_section.dart';
import '../../domain/models/text_span_format.dart';
import '../../data/converters/markdown_block_converter.dart';
import '../widgets/editor/formatted_text_controller.dart';
import 'database_provider.dart';

/// UI state for the editor (ephemeral)
@immutable
class EditorUIState extends Equatable {
  final bool isKeyboardVisible;
  final bool isToolbarVisible;
  final double scrollOffset;
  final String? focusedBlockId;

  /// Current text selection within the focused block (for toolbar formatting)
  final int textSelectionStart;
  final int textSelectionEnd;

  /// Whether the Bible reference picker should be shown
  final bool showBibleReferencePicker;

  /// The block ID that triggered the Bible reference picker (to remove @ from)
  final String? bibleReferenceTriggeredBlockId;

  /// Block IDs selected for multi-block operations (delete, etc.)
  final Set<String> selectedBlockIds;

  /// Whether multi-block selection mode is active
  bool get isMultiSelectActive => selectedBlockIds.isNotEmpty;

  const EditorUIState({
    this.isKeyboardVisible = false,
    this.isToolbarVisible = false,
    this.scrollOffset = 0,
    this.focusedBlockId,
    this.textSelectionStart = 0,
    this.textSelectionEnd = 0,
    this.showBibleReferencePicker = false,
    this.bibleReferenceTriggeredBlockId,
    this.selectedBlockIds = const {},
  });

  /// Whether there's an active text selection (not collapsed)
  bool get hasTextSelection => textSelectionStart != textSelectionEnd;

  EditorUIState copyWith({
    bool? isKeyboardVisible,
    bool? isToolbarVisible,
    double? scrollOffset,
    String? focusedBlockId,
    int? textSelectionStart,
    int? textSelectionEnd,
    bool? showBibleReferencePicker,
    String? bibleReferenceTriggeredBlockId,
    Set<String>? selectedBlockIds,
  }) {
    return EditorUIState(
      isKeyboardVisible: isKeyboardVisible ?? this.isKeyboardVisible,
      isToolbarVisible: isToolbarVisible ?? this.isToolbarVisible,
      scrollOffset: scrollOffset ?? this.scrollOffset,
      focusedBlockId: focusedBlockId ?? this.focusedBlockId,
      textSelectionStart: textSelectionStart ?? this.textSelectionStart,
      textSelectionEnd: textSelectionEnd ?? this.textSelectionEnd,
      showBibleReferencePicker: showBibleReferencePicker ?? this.showBibleReferencePicker,
      bibleReferenceTriggeredBlockId: bibleReferenceTriggeredBlockId ?? this.bibleReferenceTriggeredBlockId,
      selectedBlockIds: selectedBlockIds ?? this.selectedBlockIds,
    );
  }

  @override
  List<Object?> get props => [isKeyboardVisible, isToolbarVisible, scrollOffset, focusedBlockId, textSelectionStart, textSelectionEnd, showBibleReferencePicker, bibleReferenceTriggeredBlockId, selectedBlockIds];
}

/// Complete editor state
@immutable
class NoteEditorState extends Equatable {
  /// The note being edited (null for new notes until first save)
  final Note? note;

  /// Current document state
  final EditorDocument document;

  /// Current title
  final String title;

  /// Canonical cursor position (source of truth)
  final EditorCursor cursor;

  /// Current selection (collapsed = no selection)
  final EditorSelection selection;

  /// UI state
  final EditorUIState uiState;

  /// Whether the editor is loading
  final bool isLoading;

  /// Whether the editor has unsaved changes
  final bool isDirty;

  /// Whether a save operation is in progress
  final bool isSaving;

  /// Error message if any
  final String? error;

  /// Note metadata
  final DateTime? noteDate;
  final String? preacherId;
  final String? folderId;
  final List<String> tagIds;

  const NoteEditorState({
    this.note,
    required this.document,
    required this.title,
    required this.cursor,
    required this.selection,
    this.uiState = const EditorUIState(),
    this.isLoading = false,
    this.isDirty = false,
    this.isSaving = false,
    this.error,
    this.noteDate,
    this.preacherId,
    this.folderId,
    this.tagIds = const [],
  });

  /// Create initial state for a new note
  factory NoteEditorState.newNote({String? folderId}) {
    final document = EditorDocument.empty();
    final cursor = EditorCursor.atStart(document.blocks.first.id);
    return NoteEditorState(
      document: document,
      title: '',
      cursor: cursor,
      selection: EditorSelection.collapsed(cursor),
      folderId: folderId,
    );
  }

  /// Create state from an existing note
  factory NoteEditorState.fromNote(Note note, {List<String> tagIds = const []}) {
    final doc = note.document.blocks.isEmpty ? EditorDocument.empty() : note.document;
    final cursor = EditorCursor.atStart(doc.blocks.first.id);
    return NoteEditorState(
      note: note,
      document: doc,
      title: note.title,
      cursor: cursor,
      selection: EditorSelection.collapsed(cursor),
      noteDate: note.noteDate,
      preacherId: note.preacherId,
      folderId: note.folderId,
      tagIds: tagIds,
    );
  }

  /// Whether this is a new (unsaved) note
  bool get isNewNote => note == null;

  NoteEditorState copyWith({
    Note? note,
    EditorDocument? document,
    String? title,
    EditorCursor? cursor,
    EditorSelection? selection,
    EditorUIState? uiState,
    bool? isLoading,
    bool? isDirty,
    bool? isSaving,
    String? error,
    DateTime? noteDate,
    String? preacherId,
    String? folderId,
    List<String>? tagIds,
    bool clearNote = false,
    bool clearError = false,
    bool clearNoteDate = false,
    bool clearPreacherId = false,
    bool clearFolderId = false,
  }) {
    return NoteEditorState(
      note: clearNote ? null : (note ?? this.note),
      document: document ?? this.document,
      title: title ?? this.title,
      cursor: cursor ?? this.cursor,
      selection: selection ?? this.selection,
      uiState: uiState ?? this.uiState,
      isLoading: isLoading ?? this.isLoading,
      isDirty: isDirty ?? this.isDirty,
      isSaving: isSaving ?? this.isSaving,
      error: clearError ? null : (error ?? this.error),
      noteDate: clearNoteDate ? null : (noteDate ?? this.noteDate),
      preacherId: clearPreacherId ? null : (preacherId ?? this.preacherId),
      folderId: clearFolderId ? null : (folderId ?? this.folderId),
      tagIds: tagIds ?? this.tagIds,
    );
  }

  @override
  List<Object?> get props => [
        note,
        document,
        title,
        cursor,
        selection,
        uiState,
        isLoading,
        isDirty,
        isSaving,
        error,
        noteDate,
        preacherId,
        folderId,
        tagIds,
      ];
}

/// State notifier for the note editor
class NoteEditorNotifier extends StateNotifier<NoteEditorState> {
  final Ref _ref;
  final String? _noteId;
  String? _folderId;
  bool _disposed = false;

  /// Undo/redo stacks
  final List<EditorOperation> _undoStack = [];
  final List<EditorOperation> _redoStack = [];
  static const int _maxUndoHistory = 100;

  /// Debounce timer for auto-save
  Timer? _saveTimer;
  static const _saveDebounce = Duration(milliseconds: 300);

  /// Block text controllers (managed here, not in widgets)
  final Map<String, TextEditingController> _blockControllers = {};
  final Map<String, FocusNode> _blockFocusNodes = {};

  /// Flag to prevent pushing undo operations during undo/redo
  bool _isApplyingOperation = false;

  /// Word-level undo tracking
  /// Stores the last committed content for each block
  final Map<String, String> _committedContent = {};

  /// Stores the cursor offset at the last commit for each block
  final Map<String, int> _committedCursorOffset = {};

  /// Timer for committing text changes after a typing pause
  Timer? _textCommitTimer;
  static const _textCommitDelay = Duration(milliseconds: 800);

  /// Track which block is currently being edited for commit purposes
  String? _currentEditingBlockId;

  NoteEditorNotifier(this._ref, this._noteId) : super(NoteEditorState.newNote()) {
    _initialize();
  }

  /// Set the folder ID for new notes (called from screen)
  void setFolderId(String? folderId) {
    _folderId = folderId;
    if (state.isNewNote) {
      state = state.copyWith(folderId: folderId);
    }
  }

  /// Get text controller for a block (creates if needed)
  FormattedTextEditingController getBlockController(String blockId) {
    if (!_blockControllers.containsKey(blockId)) {
      final block = state.document.getBlockById(blockId);
      final content = block?.content ?? '';
      final controller = FormattedTextEditingController(
        text: content,
        formats: block?.formats ?? [],
      );
      _blockControllers[blockId] = controller;
      // Initialize committed content for new controller
      if (!_committedContent.containsKey(blockId)) {
        _committedContent[blockId] = content;
        _committedCursorOffset[blockId] = content.length;
      }
    }
    return _blockControllers[blockId]! as FormattedTextEditingController;
  }

  /// Get focus node for a block (creates if needed)
  FocusNode getBlockFocusNode(String blockId) {
    if (!_blockFocusNodes.containsKey(blockId)) {
      _blockFocusNodes[blockId] = FocusNode();
    }
    return _blockFocusNodes[blockId]!;
  }

  /// Focus [blockId] after the current frame, optionally moving the caret to
  /// [caretOffset] (clamped to the text length).
  ///
  /// A freshly created controller starts with an invalid selection (offset -1);
  /// on focus the field then defaults the caret to the END of the text. Pass
  /// [caretOffset] whenever the block's controller was just (re)created or had
  /// its text replaced, so the caret lands at the intended position. Omit it to
  /// keep the field's current selection (e.g. when only the block's type or
  /// indent changed and the same controller is reused).
  void _focusBlock(String blockId, {int? caretOffset}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The editor may be disposed (autoDispose) before this frame callback
      // runs. dispose() disposes the focus nodes and controllers, so touching
      // them here would throw "used after being disposed".
      if (_disposed) return;
      final focusNode = getBlockFocusNode(blockId);
      if (focusNode.canRequestFocus) {
        focusNode.requestFocus();
      }
      if (caretOffset != null) {
        final controller = _blockControllers[blockId];
        if (controller != null) {
          final clamped = caretOffset.clamp(0, controller.text.length);
          controller.selection = TextSelection.collapsed(offset: clamped);
        }
      }
    });
  }

  Future<void> _initialize() async {
    if (_noteId != null) {
      await _loadNote(_noteId);
    }
  }

  Future<void> _loadNote(String noteId) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final repository = _ref.read(notesRepositoryProvider);
      final note = await repository.getNoteById(noteId);

      if (note != null) {
        final tagIds = await repository.getTagsForNote(noteId);
        state = NoteEditorState.fromNote(note, tagIds: tagIds);
        _initializeBlockControllers();
      } else {
        state = state.copyWith(
          isLoading: false,
          error: 'Note not found',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load note: $e',
      );
    }
  }

  void _initializeBlockControllers() {
    // Clean up old controllers
    for (final controller in _blockControllers.values) {
      controller.dispose();
    }
    for (final node in _blockFocusNodes.values) {
      node.dispose();
    }
    _blockControllers.clear();
    _blockFocusNodes.clear();
    _committedContent.clear();
    _committedCursorOffset.clear();

    // Create controllers for all blocks
    for (final block in state.document.blocks) {
      _blockControllers[block.id] = FormattedTextEditingController(
        text: block.content,
        formats: block.formats,
      );
      _blockFocusNodes[block.id] = FocusNode();
      // Initialize committed content to current content
      _committedContent[block.id] = block.content;
      _committedCursorOffset[block.id] = block.content.length;
    }
  }

  // ==================== Title Operations ====================

  void updateTitle(String title) {
    state = state.copyWith(title: title, isDirty: true);
    _scheduleSave();
  }

  // ==================== Cursor Operations ====================

  void setCursor(EditorCursor cursor) {
    state = state.copyWith(
      cursor: cursor,
      selection: EditorSelection.collapsed(cursor),
    );
  }

  void setSelection(EditorSelection selection) {
    state = state.copyWith(
      cursor: selection.focus,
      selection: selection,
    );
  }

  void focusBlock(String blockId) {
    final block = state.document.getBlockById(blockId);
    if (block == null) return;

    final cursor = EditorCursor(blockId: blockId, offset: 0);
    state = state.copyWith(
      cursor: cursor,
      selection: EditorSelection.collapsed(cursor),
      uiState: state.uiState.copyWith(focusedBlockId: blockId),
    );
  }

  // ==================== Multi-Block Selection ====================

  /// Toggle a block's selection state. Long-press initiates selection mode;
  /// subsequent taps toggle individual blocks.
  void toggleBlockSelection(String blockId) {
    if (state.document.getBlockById(blockId) == null) return;

    final current = Set<String>.from(state.uiState.selectedBlockIds);
    if (current.contains(blockId)) {
      current.remove(blockId);
    } else {
      current.add(blockId);
    }

    state = state.copyWith(
      uiState: state.uiState.copyWith(selectedBlockIds: current),
    );
  }

  /// Clear multi-block selection
  void clearBlockSelection() {
    if (state.uiState.selectedBlockIds.isEmpty) return;
    state = state.copyWith(
      uiState: state.uiState.copyWith(selectedBlockIds: const {}),
    );
  }

  /// Delete all currently selected blocks
  void deleteSelectedBlocks() {
    final ids = state.uiState.selectedBlockIds;
    if (ids.isEmpty) return;

    // Keep at least one block in the document
    final remainingCount = state.document.blockCount - ids.length;
    if (remainingCount < 1) return;

    var updatedDocument = state.document;
    for (final id in ids) {
      if (updatedDocument.getBlockById(id) == null) continue;
      // Clean up controllers
      _blockControllers[id]?.dispose();
      _blockControllers.remove(id);
      _blockFocusNodes[id]?.dispose();
      _blockFocusNodes.remove(id);
      _committedContent.remove(id);
      _committedCursorOffset.remove(id);
      updatedDocument = updatedDocument.deleteBlock(id);
    }

    // Move cursor to first remaining block
    final firstBlock = updatedDocument.blocks.first;
    final newCursor = EditorCursor.atStart(firstBlock.id);

    state = state.copyWith(
      document: updatedDocument,
      cursor: newCursor,
      selection: EditorSelection.collapsed(newCursor),
      isDirty: true,
      uiState: state.uiState.copyWith(
        selectedBlockIds: const {},
        focusedBlockId: firstBlock.id,
      ),
    );
    _scheduleSave();
  }

  /// Focus the last block in the document and position cursor at the end
  /// Used when tapping on empty space in the editor
  void focusLastBlock() {
    if (state.document.blocks.isEmpty) return;

    final lastBlock = state.document.blocks.last;
    final blockId = lastBlock.id;
    final contentLength = lastBlock.content.length;

    // Update cursor position to end of last block
    final cursor = EditorCursor(blockId: blockId, offset: contentLength);
    state = state.copyWith(
      cursor: cursor,
      selection: EditorSelection.collapsed(cursor),
      uiState: state.uiState.copyWith(focusedBlockId: blockId),
    );

    // Request focus and set the caret to the end of the last block
    _focusBlock(blockId, caretOffset: contentLength);
  }

  /// Get the focus node, cursor offset, and block ID for refocusing
  /// Returns null if no valid block to focus
  /// Used by the screen widget to handle focus with proper context
  ({FocusNode focusNode, int cursorOffset, String blockId})? getRefocusTarget() {
    if (state.document.blocks.isEmpty) return null;

    // Use the last focused block if available, otherwise use cursor's block
    final blockId = state.uiState.focusedBlockId ?? state.cursor.blockId;
    final block = state.document.getBlockById(blockId);

    // Fallback to last block if the tracked block no longer exists
    if (block == null) {
      final lastBlock = state.document.blocks.last;
      final lastBlockId = lastBlock.id;
      final focusNode = _blockFocusNodes[lastBlockId];
      if (focusNode == null) return null;
      return (focusNode: focusNode, cursorOffset: lastBlock.content.length, blockId: lastBlockId);
    }

    final focusNode = _blockFocusNodes[blockId];
    final controller = _blockControllers[blockId];

    if (focusNode == null) return null;

    // Capture the current selection from the controller (preserves where user was typing)
    // Fall back to end of content if no valid selection
    final currentSelection = controller?.selection;
    final cursorOffset = (currentSelection != null && currentSelection.isValid)
        ? currentSelection.baseOffset.clamp(0, block.content.length)
        : block.content.length;

    return (focusNode: focusNode, cursorOffset: cursorOffset, blockId: blockId);
  }

  /// Set cursor position after focus is granted
  void setCursorPosition(String blockId, int offset) {
    final controller = _blockControllers[blockId];
    if (controller == null) return;

    final clampedOffset = offset.clamp(0, controller.text.length);
    controller.selection = TextSelection.collapsed(offset: clampedOffset);
  }

  void restoreSelection(String blockId, int start, int end) {
    final controller = _blockControllers[blockId];
    if (controller == null) return;

    final length = controller.text.length;
    controller.selection = TextSelection(
      baseOffset: start.clamp(0, length),
      extentOffset: end.clamp(0, length),
    );
  }

  // ==================== Document Operations ====================

  void updateBlockContent(String blockId, String content) {
    // Skip if we're applying an undo/redo operation
    // (the controller text change triggers onChanged, but we don't want to push new operations)
    if (_isApplyingOperation) return;

    final block = state.document.getBlockById(blockId);
    if (block == null) return;

    // Skip if content hasn't actually changed
    if (block.content == content) return;

    // Newlines in a block's content mean Enter (mobile soft keyboards insert a
    // literal '\n' rather than delivering a key event to onKeyEvent) or a
    // multi-line paste (e.g. pasted markdown). Blocks are single-line, so split
    // into one block per line instead of storing the newlines. Deferred to a
    // post-frame callback because modifying this controller mid-onChanged is
    // unsafe.
    if (content.contains('\n')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_disposed) return;
        _splitBlockOnNewlines(blockId);
      });
      return;
    }

    final previousContent = block.content;

    // Initialize committed content if not set
    if (!_committedContent.containsKey(blockId)) {
      _committedContent[blockId] = previousContent;
      _committedCursorOffset[blockId] = previousContent.length;
    }

    // If switching to a different block, commit the previous block's changes first
    if (_currentEditingBlockId != null && _currentEditingBlockId != blockId) {
      _commitTextChanges(_currentEditingBlockId!);
    }
    _currentEditingBlockId = blockId;

    // Check if a word boundary character was typed
    final bool wordBoundaryTyped = _isWordBoundaryChange(previousContent, content);

    if (wordBoundaryTyped) {
      // Commit changes before the word boundary
      _commitTextChanges(blockId);
    } else {
      // Reset the debounce timer - will commit after typing pause
      _textCommitTimer?.cancel();
      _textCommitTimer = Timer(_textCommitDelay, () {
        _commitTextChanges(blockId);
      });
    }

    // Update document
    final updatedBlock = block.copyWith(content: content);
    final updatedDocument = state.document.updateBlock(blockId, updatedBlock);

    state = state.copyWith(
      document: updatedDocument,
      isDirty: true,
    );
    _scheduleSave();

    // Detect @ trigger for Bible reference picker
    if (content.length == previousContent.length + 1) {
      final insertedIndex = content.length - 1;
      if (insertedIndex >= 0 && content[insertedIndex] == '@') {
        // Check if @ is at start of line or after whitespace
        if (insertedIndex == 0 ||
            content[insertedIndex - 1] == ' ' ||
            content[insertedIndex - 1] == '\n') {
          state = state.copyWith(
            uiState: state.uiState.copyWith(
              showBibleReferencePicker: true,
              bibleReferenceTriggeredBlockId: blockId,
            ),
          );
        }
      }
    }
  }

  /// Check if the change involves a word boundary character (space, punctuation, newline)
  bool _isWordBoundaryChange(String previousContent, String newContent) {
    // Detect if a word boundary character was added
    if (newContent.length > previousContent.length) {
      // Find what was added
      final addedLength = newContent.length - previousContent.length;
      if (addedLength == 1) {
        // Single character added - check if it's a word boundary
        for (int i = 0; i < newContent.length; i++) {
          if (i >= previousContent.length || newContent[i] != previousContent[i]) {
            final addedChar = newContent[i];
            return _isWordBoundaryChar(addedChar);
          }
        }
      }
    }
    return false;
  }

  /// Check if a character is a word boundary
  bool _isWordBoundaryChar(String char) {
    if (char.isEmpty) return false;
    final code = char.codeUnitAt(0);
    // Space, newline, tab, or common punctuation
    return char == ' ' ||
        char == '\n' ||
        char == '\t' ||
        char == '.' ||
        char == ',' ||
        char == '!' ||
        char == '?' ||
        char == ';' ||
        char == ':' ||
        char == '-' ||
        char == '(' ||
        char == ')' ||
        char == '[' ||
        char == ']' ||
        char == '{' ||
        char == '}' ||
        char == '"' ||
        char == "'" ||
        code < 32; // Control characters
  }

  /// Commit text changes for a block, creating an undo operation
  void _commitTextChanges(String blockId) {
    _textCommitTimer?.cancel();

    final block = state.document.getBlockById(blockId);
    if (block == null) return;

    final committedContent = _committedContent[blockId];
    final currentContent = block.content;

    // Only commit if content actually changed since last commit
    if (committedContent == null || committedContent == currentContent) {
      return;
    }

    // Get cursor positions
    final cursorBefore = _committedCursorOffset[blockId] ?? 0;
    final controller = _blockControllers[blockId];
    final cursorAfter = controller?.selection.isValid == true
        ? controller!.selection.baseOffset
        : currentContent.length;

    // Create and push the operation
    final operation = TextContentOperation(
      blockId: blockId,
      contentBefore: committedContent,
      contentAfter: currentContent,
      cursorOffsetBefore: cursorBefore,
      cursorOffsetAfter: cursorAfter,
    );
    _pushUndo(operation);

    // Update committed state
    _committedContent[blockId] = currentContent;
    _committedCursorOffset[blockId] = cursorAfter;
  }

  void splitBlock(String blockId, int offset) {
    // Commit any pending text changes first
    _commitTextChanges(blockId);

    final block = state.document.getBlockById(blockId);
    if (block == null) return;

    final blockIndex = state.document.getBlockIndex(blockId);
    if (blockIndex == null) return;

    // Handle Enter on empty list item
    if (block.type.isList && block.content.isEmpty) {
      if (block.indentLevel > 0) {
        // Nested empty item -> outdent
        outdentBlock(blockId);
        return;
      } else {
        // Top-level empty item -> convert to paragraph
        changeBlockType(blockId, BlockType.paragraph);
        return;
      }
    }

    // Split the content at the cursor.
    _splitBlockInto(
      block,
      block.content.substring(0, offset),
      block.content.substring(offset),
      splitOffset: offset,
    );
  }

  /// Split [block] into two: [firstContent] stays in place and [secondContent]
  /// moves into a new block inserted after it, with the caret at the start of
  /// the new block. [splitOffset] is recorded on the undo operation.
  ///
  /// Shared by [splitBlock] (Enter via key event) and the newline handler in
  /// [updateBlockContent] (Enter inserted as a literal '\n' on mobile).
  void _splitBlockInto(
    EditorBlock block,
    String firstContent,
    String secondContent, {
    required int splitOffset,
  }) {
    final blockId = block.id;

    // Determine new block type and properties
    BlockType newBlockType;
    int newIndentLevel = 0;
    bool? newIsChecked;

    if (block.type.isList) {
      newBlockType = block.type;
      newIndentLevel = block.indentLevel; // Inherit indent level
      if (block.type == BlockType.checkbox) {
        newIsChecked = false; // New checkbox is unchecked
      }
    } else {
      // Headings and paragraphs both continue as a paragraph.
      newBlockType = BlockType.paragraph;
    }

    // Create new block (inherits section from original)
    final newBlock = EditorBlock(
      id: const Uuid().v4(),
      type: newBlockType,
      content: secondContent,
      indentLevel: newIndentLevel,
      isChecked: newIsChecked,
      section: block.section,
    );

    // Update first block
    final updatedFirstBlock = block.copyWith(content: firstContent);

    // Update document
    var updatedDocument = state.document.updateBlock(blockId, updatedFirstBlock);
    updatedDocument = updatedDocument.insertBlockAfter(blockId, newBlock);

    // Create operation for undo
    final operation = SplitBlockOperation(
      blockId: blockId,
      splitOffset: splitOffset,
      blockBefore: block,
      firstBlockAfter: updatedFirstBlock,
      secondBlockAfter: newBlock,
    );
    _pushUndo(operation);

    // Update cursor to start of new block
    final newCursor = EditorCursor.atStart(newBlock.id);

    // Create controller for new block
    _blockControllers[newBlock.id] = FormattedTextEditingController(
      text: secondContent,
      formats: newBlock.formats,
    );
    _blockFocusNodes[newBlock.id] = FocusNode();
    // Initialize committed content for new block
    _committedContent[newBlock.id] = secondContent;
    _committedCursorOffset[newBlock.id] = 0;

    // Update first block controller and committed content
    _blockControllers[blockId]?.text = firstContent;
    _committedContent[blockId] = firstContent;
    _committedCursorOffset[blockId] = firstContent.length;

    state = state.copyWith(
      document: updatedDocument,
      cursor: newCursor,
      selection: EditorSelection.collapsed(newCursor),
      uiState: state.uiState.copyWith(focusedBlockId: newBlock.id),
      isDirty: true,
    );
    _scheduleSave();

    // Focus the new block with the caret at the start of the moved content.
    _focusBlock(newBlock.id, caretOffset: 0);
  }

  /// Split a block whose content received one or more newlines into separate
  /// blocks — one per line. Handles a single Enter (one '\n') and a multi-line
  /// paste (several '\n' arriving in one change, e.g. pasted markdown), which
  /// would otherwise all land in a single block.
  void _splitBlockOnNewlines(String blockId) {
    // Read the CURRENT controller text rather than the value captured at
    // onChanged time. If the key-event path (splitBlock) already handled this
    // Enter — as happens on keyboards that emit both a key event and an IME
    // newline — the controller no longer contains a newline and we skip,
    // avoiding a double split.
    final newText = _blockControllers[blockId]?.text ?? '';
    if (!newText.contains('\n')) return;

    _commitTextChanges(blockId);

    final block = state.document.getBlockById(blockId);
    if (block == null) return;

    // Enter on an empty list item -> outdent / convert (matches splitBlock).
    if (block.type.isList && newText == '\n') {
      if (block.indentLevel > 0) {
        outdentBlock(blockId);
      } else {
        changeBlockType(blockId, BlockType.paragraph);
      }
      return;
    }

    // Repeatedly split off the tail after each newline. Each split reuses
    // _splitBlockInto so controllers, undo ops, and focus are handled the same
    // way as a normal Enter. Focus ends on the last line's block.
    var currentId = blockId;
    var remaining = newText;
    while (true) {
      final idx = remaining.indexOf('\n');
      if (idx == -1) break;
      final current = state.document.getBlockById(currentId);
      if (current == null) break;
      _splitBlockInto(
        current,
        remaining.substring(0, idx),
        remaining.substring(idx + 1),
        splitOffset: idx,
      );
      currentId = state.uiState.focusedBlockId ?? currentId;
      remaining = remaining.substring(idx + 1);
    }
  }

  // ==================== Markdown paste ====================

  /// Paste [rawText] into [blockId], replacing the range
  /// [[selectionStart], [selectionEnd]).
  ///
  /// When [asMarkdown] is true the text is parsed as Markdown and spliced in as
  /// typed blocks with inline formatting; when false it is inserted verbatim as
  /// one paragraph per line. Undoable as a single operation either way.
  void pasteText({
    required String blockId,
    required int selectionStart,
    required int selectionEnd,
    required String rawText,
    bool asMarkdown = true,
  }) {
    if (rawText.isEmpty) return;

    // Flush any pending typing so committed content is accurate.
    _commitTextChanges(blockId);
    _textCommitTimer?.cancel();

    final block = state.document.getBlockById(blockId);
    final index = state.document.getBlockIndex(blockId);
    if (block == null || index == null) return;

    final parsed = asMarkdown
        ? MarkdownBlockConverter.parse(rawText, section: block.section)
        : MarkdownBlockConverter.parsePlain(rawText, section: block.section);
    // Drop a single trailing empty paragraph produced by a trailing newline so
    // "foo\n" doesn't leave a stray empty block.
    if (parsed.length > 1 &&
        parsed.last.type == BlockType.paragraph &&
        parsed.last.content.isEmpty) {
      parsed.removeLast();
    }
    if (parsed.isEmpty) return;

    // Non-editable cards (bible reference, table) have no caret and store JSON
    // in `content` — insert the parsed blocks after the card rather than
    // splicing text into their payload.
    if (block.type.isAtomic) {
      final caret = EditorCursor(
        blockId: parsed.last.id,
        offset: parsed.last.content.length,
      );
      _spliceBlocks(index + 1, 0, parsed, cursorAfter: caret);
      return;
    }

    final len = block.content.length;
    final s = selectionStart.clamp(0, len);
    final e = selectionEnd.clamp(s, len);

    final head = block.content.substring(0, s);
    final tail = block.content.substring(e);
    final headFormats = _sliceFormats(block.formats, 0, s);
    final tailFormats = _sliceFormats(block.formats, e, len); // rebased to 0

    final inserted = <EditorBlock>[];
    late final EditorCursor caret;

    if (parsed.length == 1 && !parsed.first.type.isAtomic) {
      // Fast path: a single text block merges inline with head/tail.
      final p = parsed.first;
      final merged = head + p.content + tail;
      final mergedFormats = <TextSpanFormat>[
        ...headFormats,
        ..._shiftFormats(p.formats, head.length),
        ..._shiftFormats(tailFormats, head.length + p.content.length),
      ];
      // Adopt the pasted block's type only when the target was empty / fully
      // replaced; otherwise a heading pasted mid-paragraph stays inline text.
      final adopt = head.isEmpty && tail.isEmpty;
      final block0 = adopt
          ? p.copyWith(
              id: block.id, section: block.section,
              content: merged, formats: mergedFormats)
          : block.copyWith(content: merged, formats: mergedFormats);
      inserted.add(block0);
      caret = EditorCursor(
          blockId: block.id, offset: head.length + p.content.length);
    } else {
      final work = List<EditorBlock>.from(parsed);

      // --- Head ---
      if (head.isEmpty) {
        // Nothing to keep: the first pasted block takes over the target's id so
        // its controller survives.
        final first = work.removeAt(0);
        inserted.add(first.copyWith(id: block.id, section: block.section));
      } else if (!work.first.type.isAtomic) {
        final first = work.removeAt(0);
        inserted.add(block.copyWith(
          content: head + first.content,
          formats: [
            ...headFormats,
            ..._shiftFormats(first.formats, head.length),
          ],
        ));
      } else {
        // An atomic block can't absorb the head — keep the head as its own
        // block and let the card follow it.
        inserted.add(block.copyWith(content: head, formats: headFormats));
      }

      // --- Tail ---
      EditorBlock? tailBlock;
      var tailCaret = 0;
      if (work.isNotEmpty && !work.last.type.isAtomic) {
        final last = work.removeLast();
        tailBlock = last.copyWith(
          content: last.content + tail,
          formats: [
            ...last.formats,
            ..._shiftFormats(tailFormats, last.content.length),
          ],
        );
        tailCaret = last.content.length;
      } else if (tail.isNotEmpty) {
        // Trailing text can't merge into an atomic block — give it its own
        // paragraph after the card.
        tailBlock = EditorBlock(
          id: const Uuid().v4(),
          type: BlockType.paragraph,
          content: tail,
          formats: tailFormats,
          section: block.section,
        );
      }

      inserted.addAll(work);
      if (tailBlock != null) inserted.add(tailBlock);

      // A note must not end on a caret-less card, or there is nowhere left to
      // type (mirrors the trailing block added after a Bible reference).
      if (tailBlock == null && inserted.last.type.isAtomic) {
        tailBlock = EditorBlock(
          id: const Uuid().v4(),
          type: BlockType.paragraph,
          content: '',
          section: block.section,
        );
        inserted.add(tailBlock);
      }

      caret = tailBlock != null
          ? EditorCursor(blockId: tailBlock.id, offset: tailCaret)
          : EditorCursor(
              blockId: inserted.last.id,
              offset: inserted.last.content.length,
            );
    }

    _spliceBlocks(index, 1, inserted, cursorAfter: caret, removed: [block]);
  }

  /// Serialize the currently multi-selected blocks (in document order) to
  /// Markdown for "Copy as Markdown".
  String selectedBlocksMarkdown() {
    final selected = state.uiState.selectedBlockIds;
    final blocks =
        state.document.blocks.where((b) => selected.contains(b.id)).toList();
    return MarkdownBlockConverter.toMarkdown(blocks);
  }

  /// Splice [inserted] into the document in place of [removeCount] blocks
  /// starting at [index]. Reconciles controllers/committed maps and (unless
  /// [pushUndo] is false) records a [PasteBlocksOperation].
  void _spliceBlocks(
    int index,
    int removeCount,
    List<EditorBlock> inserted, {
    required EditorCursor cursorAfter,
    List<EditorBlock>? removed,
    bool pushUndo = true,
  }) {
    final blocks = List<EditorBlock>.from(state.document.blocks);
    if (index < 0 || index + removeCount > blocks.length) return;

    final removedBlocks =
        removed ?? blocks.sublist(index, index + removeCount);
    final cursorBefore = state.cursor;

    blocks.replaceRange(index, index + removeCount, inserted);
    final doc = EditorDocument(blocks: blocks);

    final removedIds = removedBlocks.map((b) => b.id).toSet();
    final insertedIds = inserted.map((b) => b.id).toSet();

    // Create or refresh controllers for inserted blocks.
    for (final b in inserted) {
      final existing = _blockControllers[b.id];
      if (existing is FormattedTextEditingController) {
        existing.text = b.content;
        existing.updateFormats(b.formats);
      } else {
        _blockControllers[b.id] = FormattedTextEditingController(
          text: b.content,
          formats: b.formats,
        );
        _blockFocusNodes[b.id] = FocusNode();
      }
      _committedContent[b.id] = b.content;
      _committedCursorOffset[b.id] = b.content.length;
    }

    // Move focus to the surviving caret block BEFORE disposing any node. This
    // matters on undo, where the block that currently holds focus is one of the
    // blocks being removed: disposing a focused node makes the framework hand
    // focus to an arbitrary block, scrolling the view and dropping the caret
    // (same hazard guarded against in [mergeWithPreviousBlock]).
    getBlockFocusNode(cursorAfter.blockId).requestFocus();

    // Dispose controllers for blocks that are gone.
    for (final id in removedIds.difference(insertedIds)) {
      _blockControllers[id]?.dispose();
      _blockControllers.remove(id);
      _blockFocusNodes[id]?.dispose();
      _blockFocusNodes.remove(id);
      _committedContent.remove(id);
      _committedCursorOffset.remove(id);
    }

    if (pushUndo) {
      _pushUndo(PasteBlocksOperation(
        index: index,
        removed: removedBlocks,
        inserted: inserted,
        cursorBefore: cursorBefore,
        cursorAfter: cursorAfter,
      ));
    }

    state = state.copyWith(
      document: doc,
      cursor: cursorAfter,
      selection: EditorSelection.collapsed(cursorAfter),
      uiState: state.uiState.copyWith(focusedBlockId: cursorAfter.blockId),
      isDirty: true,
    );
    _scheduleSave();
    _focusBlock(cursorAfter.blockId, caretOffset: cursorAfter.offset);
  }

  /// Clip [formats] to [[from], [to]) and rebase so `from` -> 0.
  List<TextSpanFormat> _sliceFormats(
      List<TextSpanFormat> formats, int from, int to) {
    final out = <TextSpanFormat>[];
    for (final f in formats) {
      final a = f.start < from ? from : f.start;
      final b = f.end > to ? to : f.end;
      if (a < b) out.add(f.copyWith(start: a - from, end: b - from));
    }
    return out;
  }

  /// Shift all offsets in [formats] by [delta].
  List<TextSpanFormat> _shiftFormats(List<TextSpanFormat> formats, int delta) {
    return formats
        .map((f) => f.copyWith(start: f.start + delta, end: f.end + delta))
        .toList();
  }

  void _applyPasteBlocks(PasteBlocksOperation op) {
    _spliceBlocks(
      op.index,
      op.removed.length,
      op.inserted,
      cursorAfter: op.cursorAfter,
      removed: op.removed,
      pushUndo: false,
    );
  }

  void mergeWithPreviousBlock(String blockId) {
    // Commit any pending text changes first
    _commitTextChanges(blockId);

    final block = state.document.getBlockById(blockId);
    if (block == null) return;

    // Handle Backspace at start of list item
    if (block.type.isList) {
      if (block.indentLevel > 0) {
        // Nested list item -> outdent instead of merge
        outdentBlock(blockId);
        return;
      } else {
        // Top-level list item -> convert to paragraph instead of merge
        changeBlockType(blockId, BlockType.paragraph);
        return;
      }
    }

    // Only merge within the same section
    final previousBlock = state.document.getPreviousBlockInSection(blockId);
    if (previousBlock == null) return; // First block in section, can't merge

    final mergeOffset = previousBlock.content.length;

    // Merge content
    final mergedContent = previousBlock.content + block.content;
    final updatedPreviousBlock = previousBlock.copyWith(content: mergedContent);

    // Create operation for undo
    final operation = MergeBlocksOperation(
      firstBlockId: previousBlock.id,
      secondBlockId: blockId,
      firstBlockBefore: previousBlock,
      secondBlockBefore: block,
      mergeOffset: mergeOffset,
    );
    _pushUndo(operation);

    // Update document
    var updatedDocument = state.document.updateBlock(previousBlock.id, updatedPreviousBlock);
    updatedDocument = updatedDocument.deleteBlock(blockId);

    // Update cursor to merge point
    final newCursor = EditorCursor(
      blockId: previousBlock.id,
      offset: mergeOffset,
    );

    // Update controller and committed content
    _blockControllers[previousBlock.id]?.text = mergedContent;
    _committedContent[previousBlock.id] = mergedContent;
    _committedCursorOffset[previousBlock.id] = mergeOffset;

    // Move focus to the merge target BEFORE disposing the deleted block's
    // focus node. Disposing a node that currently holds focus makes the
    // framework hand focus to an arbitrary block, which scrolls the view and
    // drops the caret into the middle of some other block.
    getBlockFocusNode(previousBlock.id).requestFocus();

    // Clean up removed block's controller and committed state
    _blockControllers[blockId]?.dispose();
    _blockControllers.remove(blockId);
    _blockFocusNodes[blockId]?.dispose();
    _blockFocusNodes.remove(blockId);
    _committedContent.remove(blockId);
    _committedCursorOffset.remove(blockId);

    state = state.copyWith(
      document: updatedDocument,
      cursor: newCursor,
      selection: EditorSelection.collapsed(newCursor),
      uiState: state.uiState.copyWith(focusedBlockId: previousBlock.id),
      isDirty: true,
    );
    _scheduleSave();

    // Place the caret at the merge point once the merged text has rendered.
    _focusBlock(previousBlock.id, caretOffset: mergeOffset);
  }

  /// Delete a block by ID regardless of its content (e.g. Bible reference blocks).
  void deleteBlock(String blockId) {
    if (state.document.blockCount <= 1) return;
    if (state.document.getBlockById(blockId) == null) return;

    _deleteBlockInternal(blockId);
  }

  void deleteEmptyBlock(String blockId) {
    if (state.document.blockCount <= 1) return; // Keep at least one block

    final block = state.document.getBlockById(blockId);
    if (block == null || block.content.isNotEmpty) return;

    // Locked separator between two bible references — removing it would
    // collapse the two reference cards back onto the same line.
    if (_isReferenceSeparator(blockId)) return;

    _deleteBlockInternal(blockId);
  }

  bool _isReferenceSeparator(String blockId) {
    final block = state.document.getBlockById(blockId);
    if (block == null ||
        block.type != BlockType.paragraph ||
        block.content.isNotEmpty) {
      return false;
    }
    final prev = state.document.getPreviousBlock(blockId);
    final next = state.document.getNextBlock(blockId);
    return prev != null &&
        next != null &&
        prev.type == BlockType.bibleReference &&
        next.type == BlockType.bibleReference;
  }

  void _deleteBlockInternal(String blockId) {
    final previousBlock = state.document.getPreviousBlock(blockId);
    final nextBlock = state.document.getNextBlock(blockId);

    // Cursor moves to the previous block (end) or, if none, the next (start).
    final targetBlock = previousBlock ?? nextBlock;

    // Move focus to the target BEFORE disposing the deleted block's focus
    // node. Disposing a node that currently holds focus makes the framework
    // hand focus to an arbitrary block, scrolling the view and dropping the
    // caret into some other block.
    if (targetBlock != null) {
      getBlockFocusNode(targetBlock.id).requestFocus();
    }

    // Delete block
    final updatedDocument = state.document.deleteBlock(blockId);

    // Clean up controller and committed state
    _blockControllers[blockId]?.dispose();
    _blockControllers.remove(blockId);
    _blockFocusNodes[blockId]?.dispose();
    _blockFocusNodes.remove(blockId);
    _committedContent.remove(blockId);
    _committedCursorOffset.remove(blockId);

    if (targetBlock == null) return;

    final caretOffset =
        previousBlock != null ? previousBlock.content.length : 0;
    final newCursor = previousBlock != null
        ? EditorCursor.atEnd(previousBlock.id, previousBlock.content.length)
        : EditorCursor.atStart(nextBlock!.id);

    state = state.copyWith(
      document: updatedDocument,
      cursor: newCursor,
      selection: EditorSelection.collapsed(newCursor),
      uiState: state.uiState.copyWith(focusedBlockId: targetBlock.id),
      isDirty: true,
    );
    _scheduleSave();

    // Place the caret at the join point once the update has rendered.
    _focusBlock(targetBlock.id, caretOffset: caretOffset);
  }

  // ==================== Block Type Operations ====================

  void changeBlockType(String blockId, BlockType newType) {
    final block = state.document.getBlockById(blockId);
    if (block == null) return;

    final updatedBlock = block.copyWith(
      type: newType,
      isChecked: newType == BlockType.checkbox ? false : null,
    );

    // Create operation for undo
    final operation = ChangeBlockTypeOperation(
      blockId: blockId,
      blockBefore: block,
      blockAfter: updatedBlock,
    );
    _pushUndo(operation);

    final updatedDocument = state.document.updateBlock(blockId, updatedBlock);

    state = state.copyWith(
      document: updatedDocument,
      isDirty: true,
    );
    _scheduleSave();

    // Refocus the block, keeping the caret where it was (same controller).
    _focusBlock(blockId);
  }

  void toggleCheckbox(String blockId) {
    final block = state.document.getBlockById(blockId);
    if (block == null || block.type != BlockType.checkbox) return;

    final updatedBlock = block.copyWith(isChecked: !(block.isChecked ?? false));
    final updatedDocument = state.document.updateBlock(blockId, updatedBlock);

    state = state.copyWith(
      document: updatedDocument,
      isDirty: true,
    );
    _scheduleSave();
  }

  // ==================== List Indentation Operations ====================

  /// Get derived list number for display (for numbered lists)
  int getListNumber(String blockId) {
    return state.document.calculateListNumber(blockId);
  }

  /// Indent a list block (Tab key)
  /// Only allowed if there is a previous sibling at the same level
  void indentBlock(String blockId) {
    final block = state.document.getBlockById(blockId);
    if (block == null || !block.type.isList) return;

    // Check if can indent
    if (!state.document.canIndent(blockId)) return;

    // Max indent level is 5
    if (block.indentLevel >= 5) return;

    final newLevel = block.indentLevel + 1;
    final updatedBlock = block.copyWith(indentLevel: newLevel);

    // Create operation for undo
    final operation = IndentBlockOperation(
      blockId: blockId,
      blockBefore: block,
      blockAfter: updatedBlock,
    );
    _pushUndo(operation);

    final updatedDocument = state.document.updateBlock(blockId, updatedBlock);

    state = state.copyWith(
      document: updatedDocument,
      isDirty: true,
    );
    _scheduleSave();

    // Refocus the block, keeping the caret where it was (same controller).
    _focusBlock(blockId);
  }

  /// Outdent a list block (Shift+Tab key)
  /// If at indent level > 0, decreases indent
  /// If at indent level 0, converts to paragraph
  void outdentBlock(String blockId) {
    final block = state.document.getBlockById(blockId);
    if (block == null || !block.type.isList) return;

    if (block.indentLevel > 0) {
      // Decrease indent level
      final newLevel = block.indentLevel - 1;

      // Restore the parent list type: search backwards for a list block
      // at the target indent level to determine what type the outer list is.
      BlockType? parentType;
      final blockIndex = state.document.getBlockIndex(blockId);
      if (blockIndex != null) {
        for (int i = blockIndex - 1; i >= 0; i--) {
          final prev = state.document.blocks[i];
          if (prev.indentLevel == newLevel && prev.type.isList) {
            parentType = prev.type;
            break;
          }
          // Stop if we pass a block at a lower indent level
          if (prev.indentLevel < newLevel) break;
        }
      }

      final updatedBlock = block.copyWith(
        indentLevel: newLevel,
        type: parentType,
      );

      // Create operation for undo
      final operation = IndentBlockOperation(
        blockId: blockId,
        blockBefore: block,
        blockAfter: updatedBlock,
      );
      _pushUndo(operation);

      final updatedDocument = state.document.updateBlock(blockId, updatedBlock);

      state = state.copyWith(
        document: updatedDocument,
        isDirty: true,
      );
    } else {
      // Convert to paragraph (exit list)
      final updatedBlock = block.copyWith(
        type: BlockType.paragraph,
        indentLevel: 0,
        isChecked: null,
      );

      // Create operation for undo
      final operation = IndentBlockOperation(
        blockId: blockId,
        blockBefore: block,
        blockAfter: updatedBlock,
      );
      _pushUndo(operation);

      final updatedDocument = state.document.updateBlock(blockId, updatedBlock);

      state = state.copyWith(
        document: updatedDocument,
        isDirty: true,
      );
    }
    _scheduleSave();

    // Refocus the block, keeping the caret where it was (same controller).
    _focusBlock(blockId);
  }

  // ==================== Formatting Operations ====================

  void toggleFormat({
    required String blockId,
    required int start,
    required int end,
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
  }) {
    if (start >= end) return;

    final block = state.document.getBlockById(blockId);
    if (block == null) return;

    // Determine which format type is being toggled
    final isBoldToggle = bold == true;
    final isItalicToggle = italic == true;
    final isUnderlineToggle = underline == true;
    final isStrikethroughToggle = strikethrough == true;

    // Check if the selected range already has this format applied
    bool rangeHasFormat = _rangeHasFormat(
      block.formats,
      start,
      end,
      isBold: isBoldToggle,
      isItalic: isItalicToggle,
      isUnderline: isUnderlineToggle,
      isStrikethrough: isStrikethroughToggle,
    );

    List<TextSpanFormat> updatedFormats;

    if (rangeHasFormat) {
      // Toggle OFF: Remove the format from the range
      updatedFormats = _removeFormatFromRange(
        block.formats,
        start,
        end,
        removeBold: isBoldToggle,
        removeItalic: isItalicToggle,
        removeUnderline: isUnderlineToggle,
        removeStrikethrough: isStrikethroughToggle,
      );
    } else {
      // Toggle ON: Add/merge the format to the range
      updatedFormats = _addFormatToRange(
        block.formats,
        start,
        end,
        addBold: isBoldToggle,
        addItalic: isItalicToggle,
        addUnderline: isUnderlineToggle,
        addStrikethrough: isStrikethroughToggle,
      );
    }

    final updatedBlock = block.copyWith(formats: updatedFormats);

    // Note: Format operations are not pushed to undo stack because
    // tracking format state changes is complex (overlapping ranges, partial changes).
    // Structural operations (split, merge, block type) are still undoable.

    final updatedDocument = state.document.updateBlock(blockId, updatedBlock);

    state = state.copyWith(
      document: updatedDocument,
      isDirty: true,
    );
    _scheduleSave();
  }

  /// Check if the entire range has the specified format applied
  bool _rangeHasFormat(
    List<TextSpanFormat> formats,
    int start,
    int end, {
    bool isBold = false,
    bool isItalic = false,
    bool isUnderline = false,
    bool isStrikethrough = false,
  }) {
    // Check each character in the range
    for (int i = start; i < end; i++) {
      bool charHasFormat = false;
      for (final format in formats) {
        if (i >= format.start && i < format.end) {
          if ((isBold && format.isBold) ||
              (isItalic && format.isItalic) ||
              (isUnderline && format.isUnderline) ||
              (isStrikethrough && format.isStrikethrough)) {
            charHasFormat = true;
            break;
          }
        }
      }
      if (!charHasFormat) return false;
    }
    return true;
  }

  /// Remove a format type from a range, splitting existing formats as needed
  List<TextSpanFormat> _removeFormatFromRange(
    List<TextSpanFormat> formats,
    int start,
    int end, {
    bool removeBold = false,
    bool removeItalic = false,
    bool removeUnderline = false,
    bool removeStrikethrough = false,
  }) {
    final result = <TextSpanFormat>[];

    for (final format in formats) {
      // No overlap - keep as is
      if (format.end <= start || format.start >= end) {
        result.add(format);
        continue;
      }

      // Part before the removal range
      if (format.start < start) {
        result.add(format.copyWith(end: start));
      }

      // The overlapping part - remove the specified format type
      final overlapStart = format.start < start ? start : format.start;
      final overlapEnd = format.end > end ? end : format.end;

      final modifiedFormat = format.copyWith(
        start: overlapStart,
        end: overlapEnd,
        isBold: removeBold ? false : format.isBold,
        isItalic: removeItalic ? false : format.isItalic,
        isUnderline: removeUnderline ? false : format.isUnderline,
        isStrikethrough: removeStrikethrough ? false : format.isStrikethrough,
      );

      // Only add if it still has some formatting
      if (modifiedFormat.hasFormatting) {
        result.add(modifiedFormat);
      }

      // Part after the removal range
      if (format.end > end) {
        result.add(format.copyWith(start: end));
      }
    }

    return result;
  }

  /// Add a format type to a range, merging with existing formats
  List<TextSpanFormat> _addFormatToRange(
    List<TextSpanFormat> formats,
    int start,
    int end, {
    bool addBold = false,
    bool addItalic = false,
    bool addUnderline = false,
    bool addStrikethrough = false,
  }) {
    final result = <TextSpanFormat>[];
    bool rangeHandled = false;

    for (final format in formats) {
      // No overlap - keep as is
      if (format.end <= start || format.start >= end) {
        result.add(format);
        continue;
      }

      // Part before the new format range (keep original formatting)
      if (format.start < start) {
        result.add(format.copyWith(end: start));
      }

      // The overlapping part - merge formats
      final overlapStart = format.start < start ? start : format.start;
      final overlapEnd = format.end > end ? end : format.end;

      result.add(format.copyWith(
        start: overlapStart,
        end: overlapEnd,
        isBold: addBold ? true : format.isBold,
        isItalic: addItalic ? true : format.isItalic,
        isUnderline: addUnderline ? true : format.isUnderline,
        isStrikethrough: addStrikethrough ? true : format.isStrikethrough,
      ));

      rangeHandled = true;

      // Part after the new format range (keep original formatting)
      if (format.end > end) {
        result.add(format.copyWith(start: end));
      }
    }

    // If no existing format overlapped, add the new format
    if (!rangeHandled) {
      result.add(TextSpanFormat(
        start: start,
        end: end,
        isBold: addBold,
        isItalic: addItalic,
        isUnderline: addUnderline,
        isStrikethrough: addStrikethrough,
      ));
    } else {
      // Fill in any gaps in the range that weren't covered by existing formats
      result.sort((a, b) => a.start.compareTo(b.start));
      final gaps = <TextSpanFormat>[];
      int currentPos = start;

      for (final format in result) {
        if (format.start > currentPos && format.start <= end && currentPos < end) {
          // There's a gap - add new format for this gap
          gaps.add(TextSpanFormat(
            start: currentPos,
            end: format.start < end ? format.start : end,
            isBold: addBold,
            isItalic: addItalic,
            isUnderline: addUnderline,
            isStrikethrough: addStrikethrough,
          ));
        }
        if (format.end > currentPos) {
          currentPos = format.end;
        }
      }

      // Handle gap at the end
      if (currentPos < end) {
        gaps.add(TextSpanFormat(
          start: currentPos,
          end: end,
          isBold: addBold,
          isItalic: addItalic,
          isUnderline: addUnderline,
          isStrikethrough: addStrikethrough,
        ));
      }

      result.addAll(gaps);
    }

    // Sort by start position for consistency
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }

  // ==================== Metadata Operations ====================

  void setNoteDate(DateTime? date) {
    state = state.copyWith(
      noteDate: date,
      clearNoteDate: date == null,
      isDirty: true,
    );
    _scheduleSave();
  }

  void setPreacher(String? preacherId) {
    state = state.copyWith(
      preacherId: preacherId,
      clearPreacherId: preacherId == null,
      isDirty: true,
    );
    _scheduleSave();
  }

  void setTags(List<String> tagIds) {
    state = state.copyWith(tagIds: tagIds, isDirty: true);
    _scheduleSave();
  }

  // ==================== UI State Operations ====================

  void setKeyboardVisible(bool visible) {
    state = state.copyWith(
      uiState: state.uiState.copyWith(isKeyboardVisible: visible),
    );
  }

  void setToolbarVisible(bool visible) {
    state = state.copyWith(
      uiState: state.uiState.copyWith(isToolbarVisible: visible),
    );
  }

  /// Update the current text selection within the focused block
  void setTextSelection(int start, int end) {
    if (state.uiState.textSelectionStart == start &&
        state.uiState.textSelectionEnd == end) {
      return;
    }
    state = state.copyWith(
      uiState: state.uiState.copyWith(
        textSelectionStart: start,
        textSelectionEnd: end,
      ),
    );
  }

  void setScrollOffset(double offset) {
    state = state.copyWith(
      uiState: state.uiState.copyWith(scrollOffset: offset),
    );
  }

  // ==================== Undo/Redo Operations ====================

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void undo() {
    // Commit any pending text changes first
    if (_currentEditingBlockId != null) {
      _commitTextChanges(_currentEditingBlockId!);
    }

    if (_undoStack.isEmpty) return;

    final operation = _undoStack.removeLast();
    final inverse = operation.invert();
    _redoStack.add(operation);

    _applyOperation(inverse);
  }

  void redo() {
    // Commit any pending text changes first
    if (_currentEditingBlockId != null) {
      _commitTextChanges(_currentEditingBlockId!);
    }

    if (_redoStack.isEmpty) return;

    final operation = _redoStack.removeLast();
    _undoStack.add(operation);

    _applyOperation(operation);
  }

  void _pushUndo(EditorOperation operation) {
    _undoStack.add(operation);
    _redoStack.clear();

    // Cap undo history
    if (_undoStack.length > _maxUndoHistory) {
      _undoStack.removeAt(0);
    }
  }

  void _applyOperation(EditorOperation operation) {
    // Set flag to prevent updateBlockContent from pushing new operations
    _isApplyingOperation = true;

    try {
      switch (operation) {
        case SplitBlockOperation op:
          _applySplitBlock(op);
          break;
        case MergeBlocksOperation op:
          _applyMergeBlocks(op);
          break;
        case ChangeBlockTypeOperation op:
          _applyChangeBlockType(op);
          break;
        case IndentBlockOperation op:
          _applyIndentBlock(op);
          break;
        case InsertBlockOperation op:
          _applyInsertBlock(op);
          break;
        case DeleteBlockOperation op:
          _applyDeleteBlock(op);
          break;
        case FormatTextOperation op:
          _applyFormatText(op);
          break;
        case InsertTextOperation op:
          _applyInsertText(op);
          break;
        case DeleteTextOperation op:
          _applyDeleteText(op);
          break;
        case TextContentOperation op:
          _applyTextContent(op);
          break;
        case PasteBlocksOperation op:
          _applyPasteBlocks(op);
          break;
        default:
          // Unknown operation type
          break;
      }

      state = state.copyWith(isDirty: true);
      _scheduleSave();
    } finally {
      // Always reset the flag
      _isApplyingOperation = false;
    }
  }

  void _applySplitBlock(SplitBlockOperation op) {
    // Split one block into two blocks
    // Find the original block (should match blockBefore)
    final blockIndex = state.document.getBlockIndex(op.blockId);
    if (blockIndex == null) return;

    // Replace the block with firstBlockAfter
    var doc = state.document.replaceBlockAt(blockIndex, op.firstBlockAfter);

    // Insert secondBlockAfter after it
    doc = doc.insertBlockAt(blockIndex + 1, op.secondBlockAfter);

    // Update controller for first block
    _blockControllers[op.firstBlockAfter.id]?.text = op.firstBlockAfter.content;

    // Create controller for second block
    if (!_blockControllers.containsKey(op.secondBlockAfter.id)) {
      _blockControllers[op.secondBlockAfter.id] = FormattedTextEditingController(
        text: op.secondBlockAfter.content,
        formats: op.secondBlockAfter.formats,
      );
      _blockFocusNodes[op.secondBlockAfter.id] = FocusNode();
    } else {
      _blockControllers[op.secondBlockAfter.id]?.text = op.secondBlockAfter.content;
    }

    state = state.copyWith(
      document: doc,
      uiState: state.uiState.copyWith(focusedBlockId: op.secondBlockAfter.id),
    );

    // Set cursor to start of second block after frame renders
    _focusBlock(op.secondBlockAfter.id, caretOffset: 0);
  }

  void _applyMergeBlocks(MergeBlocksOperation op) {
    // Merge two blocks into one
    final firstBlockIndex = state.document.getBlockIndex(op.firstBlockId);
    if (firstBlockIndex == null) return;

    // Merge content
    final mergedContent = op.firstBlockBefore.content + op.secondBlockBefore.content;
    final mergedBlock = op.firstBlockBefore.copyWith(content: mergedContent);

    // Replace first block with merged content
    var doc = state.document.replaceBlockAt(firstBlockIndex, mergedBlock);

    // Delete second block
    doc = doc.deleteBlock(op.secondBlockId);

    // Update controller for merged block
    _blockControllers[op.firstBlockId]?.text = mergedContent;

    // Clean up second block controller
    _blockControllers[op.secondBlockId]?.dispose();
    _blockControllers.remove(op.secondBlockId);
    _blockFocusNodes[op.secondBlockId]?.dispose();
    _blockFocusNodes.remove(op.secondBlockId);

    state = state.copyWith(
      document: doc,
      uiState: state.uiState.copyWith(focusedBlockId: op.firstBlockId),
    );

    // Set cursor to the merge point after frame renders
    _focusBlock(op.firstBlockId, caretOffset: op.mergeOffset);
  }

  void _applyChangeBlockType(ChangeBlockTypeOperation op) {
    // Restore the original block
    final doc = state.document.updateBlock(op.blockId, op.blockAfter);

    state = state.copyWith(
      document: doc,
      uiState: state.uiState.copyWith(focusedBlockId: op.blockId),
    );
  }

  void _applyIndentBlock(IndentBlockOperation op) {
    // Restore the original block (with different indent level)
    final doc = state.document.updateBlock(op.blockId, op.blockAfter);

    state = state.copyWith(
      document: doc,
      uiState: state.uiState.copyWith(focusedBlockId: op.blockId),
    );
  }

  void _applyInsertBlock(InsertBlockOperation op) {
    // Insert the block at the specified index
    var doc = state.document.insertBlockAt(op.index, op.block);

    // Create controller for the block
    _blockControllers[op.block.id] = FormattedTextEditingController(
      text: op.block.content,
      formats: op.block.formats,
    );
    _blockFocusNodes[op.block.id] = FocusNode();

    state = state.copyWith(
      document: doc,
      uiState: state.uiState.copyWith(focusedBlockId: op.block.id),
    );

    // Focus the re-inserted block with the caret at the end of its restored
    // content, matching the other undo/redo handlers. The fresh controller
    // starts with an invalid selection, so the offset must be set explicitly.
    _focusBlock(op.block.id, caretOffset: op.block.content.length);
  }

  void _applyDeleteBlock(DeleteBlockOperation op) {
    // Delete the block
    var doc = state.document.deleteBlock(op.blockId);

    // Clean up controller
    _blockControllers[op.blockId]?.dispose();
    _blockControllers.remove(op.blockId);
    _blockFocusNodes[op.blockId]?.dispose();
    _blockFocusNodes.remove(op.blockId);

    // Focus previous block if possible
    String? newFocusId;
    if (op.originalIndex > 0 && doc.blocks.isNotEmpty) {
      final prevIndex = (op.originalIndex - 1).clamp(0, doc.blocks.length - 1);
      newFocusId = doc.blocks[prevIndex].id;
    } else if (doc.blocks.isNotEmpty) {
      newFocusId = doc.blocks.first.id;
    }

    state = state.copyWith(
      document: doc,
      uiState: state.uiState.copyWith(focusedBlockId: newFocusId),
    );
  }

  void _applyFormatText(FormatTextOperation op) {
    final block = state.document.getBlockById(op.blockId);
    if (block == null) return;

    // Apply the format by replacing the block's formats
    // This is simplified - ideally we'd merge properly
    List<TextSpanFormat> newFormats;

    if (op.format.hasFormatting) {
      // Add or update the format
      newFormats = _addFormatToRange(
        block.formats,
        op.format.start,
        op.format.end,
        addBold: op.format.isBold,
        addItalic: op.format.isItalic,
        addUnderline: op.format.isUnderline,
        addStrikethrough: op.format.isStrikethrough,
      );
    } else {
      // Remove formatting from the range
      newFormats = _removeFormatFromRange(
        block.formats,
        op.format.start,
        op.format.end,
        removeBold: true,
        removeItalic: true,
        removeUnderline: true,
        removeStrikethrough: true,
      );
    }

    final updatedBlock = block.copyWith(formats: newFormats);
    final doc = state.document.updateBlock(op.blockId, updatedBlock);

    // Update controller formats
    final controller = _blockControllers[op.blockId];
    if (controller is FormattedTextEditingController) {
      controller.updateFormats(newFormats);
    }

    state = state.copyWith(document: doc);
  }

  void _applyInsertText(InsertTextOperation op) {
    final block = state.document.getBlockById(op.blockId);
    if (block == null) return;

    // Insert text at the offset
    final newContent = block.content.substring(0, op.offset) +
        op.text +
        block.content.substring(op.offset);

    final updatedBlock = block.copyWith(content: newContent);
    final doc = state.document.updateBlock(op.blockId, updatedBlock);

    // Update controller
    _blockControllers[op.blockId]?.text = newContent;

    state = state.copyWith(
      document: doc,
      uiState: state.uiState.copyWith(focusedBlockId: op.blockId),
    );

    // Set cursor after inserted text
    setCursorPosition(op.blockId, op.offset + op.text.length);
  }

  void _applyDeleteText(DeleteTextOperation op) {
    final block = state.document.getBlockById(op.blockId);
    if (block == null) return;

    // Delete text at the offset
    final endOffset = (op.offset + op.length).clamp(0, block.content.length);
    final newContent = block.content.substring(0, op.offset) +
        block.content.substring(endOffset);

    final updatedBlock = block.copyWith(content: newContent);
    final doc = state.document.updateBlock(op.blockId, updatedBlock);

    // Update controller
    _blockControllers[op.blockId]?.text = newContent;

    state = state.copyWith(
      document: doc,
      uiState: state.uiState.copyWith(focusedBlockId: op.blockId),
    );

    // Set cursor at deletion point
    setCursorPosition(op.blockId, op.offset);
  }

  void _applyTextContent(TextContentOperation op) {
    final block = state.document.getBlockById(op.blockId);
    if (block == null) return;

    // Replace the block content with contentAfter
    final updatedBlock = block.copyWith(content: op.contentAfter);
    final doc = state.document.updateBlock(op.blockId, updatedBlock);

    // Update controller
    _blockControllers[op.blockId]?.text = op.contentAfter;

    // Update committed state to match the new content
    _committedContent[op.blockId] = op.contentAfter;
    _committedCursorOffset[op.blockId] = op.cursorOffsetAfter;

    state = state.copyWith(
      document: doc,
      uiState: state.uiState.copyWith(focusedBlockId: op.blockId),
    );

    // Set cursor position after frame renders to ensure text is updated
    _focusBlock(op.blockId, caretOffset: op.cursorOffsetAfter);
  }

  // ==================== Persistence ====================

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, _save);
  }

  Future<void> _save() async {
    if (!state.isDirty || state.isSaving) return;

    // Mark as saving and clear dirty flag upfront.
    // If changes occur during the async save (e.g. user sets preacher/date),
    // those change handlers will set isDirty back to true.
    state = state.copyWith(isSaving: true, isDirty: false);

    try {
      final repository = _ref.read(notesRepositoryProvider);

      // Generate title if empty
      var title = state.title.trim();
      if (title.isEmpty) {
        // Use first non-empty block content
        for (final block in state.document.blocks) {
          if (block.content.trim().isNotEmpty) {
            title = block.content.trim();
            if (title.length > 50) {
              title = '${title.substring(0, 47)}...';
            }
            break;
          }
        }
        if (title.isEmpty) {
          title = 'Untitled Note';
        }
      }

      if (state.isNewNote) {
        // Create new note
        final noteId = const Uuid().v4();
        final note = Note(
          id: noteId,
          title: title,
          document: state.document,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          version: 1,
          preacherId: state.preacherId,
          folderId: state.folderId ?? _folderId,
          noteDate: state.noteDate,
        );

        await repository.createNote(note);
        if (_disposed) return;

        if (state.tagIds.isNotEmpty) {
          await repository.setTagsForNote(noteId, state.tagIds);
          if (_disposed) return;
        }

        state = state.copyWith(
          note: note,
          title: title,
          isSaving: false,
        );
      } else {
        // Update existing note
        final updatedNote = state.note!.update(
          title: title,
          document: state.document,
          preacherId: state.preacherId,
          folderId: state.folderId,
          noteDate: state.noteDate,
          clearPreacherId: state.preacherId == null,
          clearNoteDate: state.noteDate == null,
        );

        await repository.updateNote(updatedNote);
        if (_disposed) return;
        await repository.setTagsForNote(updatedNote.id, state.tagIds);
        if (_disposed) return;

        state = state.copyWith(
          note: updatedNote,
          title: title,
          isSaving: false,
        );
      }

      // If changes were made during the save, reschedule
      if (state.isDirty) {
        _scheduleSave();
      }
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(
        isSaving: false,
        isDirty: true,
        error: 'Failed to save: $e',
      );
    }
  }

  // ==================== Bible Reference Operations ====================

  /// Dismiss the Bible reference picker without inserting
  /// Ensures bibleReferenceTriggeredBlockId is set, using the focused block
  /// as fallback. Called before showing the picker from the toolbar button
  /// where no "@" was typed.
  void ensureBibleReferenceTriggeredBlock() {
    final triggered = state.uiState.bibleReferenceTriggeredBlockId;
    if (triggered != null && triggered.isNotEmpty) return;

    // Use the currently focused block, or fall back to the last block
    final focusedId = state.uiState.focusedBlockId;
    final blockId = focusedId ?? state.document.blocks.last.id;

    state = state.copyWith(
      uiState: state.uiState.copyWith(
        bibleReferenceTriggeredBlockId: blockId,
      ),
    );
  }

  void dismissBibleReferencePicker() {
    state = state.copyWith(
      uiState: state.uiState.copyWith(
        showBibleReferencePicker: false,
        bibleReferenceTriggeredBlockId: '',
      ),
    );
  }

  /// Insert a Bible reference block after the current block.
  ///
  /// Called when the Bible reference picker completes. Stores ONLY the
  /// reference coordinates (translation, bookId, chapter, verse) and a
  /// display string. Verse text is NOT stored — it is resolved dynamically
  /// from the local Bible SQLite database at render time via VerseLookupService.
  ///
  /// This design means:
  /// - Blocks are lightweight (just coordinates, no text payload)
  /// - Translation switching works without re-inserting blocks
  /// - Verse text always reflects the current installed Bible DB
  void insertBibleReferenceBlock({
    required String book,
    required int chapter,
    required List<int> verses,
    required String version,
  }) {
    final triggeredBlockId = state.uiState.bibleReferenceTriggeredBlockId;
    if (triggeredBlockId == null || triggeredBlockId.isEmpty) return;

    final block = state.document.getBlockById(triggeredBlockId);
    if (block == null) return;

    // Remove the @ character from the triggering block's content
    String triggerContent = block.content;
    final atIndex = triggerContent.lastIndexOf('@');
    if (atIndex >= 0) {
      triggerContent =
          triggerContent.substring(0, atIndex) +
          triggerContent.substring(atIndex + 1);
    }

    // Build the reference-only Bible block content.
    // No verse text is stored — resolved at render time from the Bible DB.
    final bibleRef = BibleReference(
      reference: BibleVerseReference(
        book: book,
        chapter: chapter,
        verses: verses,
        version: version,
      ),
      text: const [], // Empty: text resolved dynamically from Bible DB
      source: 'local',
      insertedAt: DateTime.now().millisecondsSinceEpoch,
      display: const BibleVerseDisplay(),
      pending: false,
    );
    final bibleBlock = EditorBlock(
      id: const Uuid().v4(),
      type: BlockType.bibleReference,
      content: jsonEncode(bibleRef.toJson()),
    );

    var updatedDocument = state.document;

    // Check context on the original document before any mutation.
    final triggerIdx = state.document.blocks.indexWhere((b) => b.id == triggeredBlockId);
    final prevBlockIsBibleRef = triggerIdx > 0 &&
        state.document.blocks[triggerIdx - 1].type == BlockType.bibleReference;

    if (triggerContent.trim().isEmpty) {
      if (prevBlockIsBibleRef) {
        // The trigger block sits directly after an existing bible reference.
        // Keep it as a separator instead of replacing it — insert the new
        // reference after it so the layout becomes:
        // [prev_ref][empty_separator][new_ref]
        updatedDocument = updatedDocument.insertBlockAfter(triggeredBlockId, bibleBlock);
      } else {
        // No preceding reference — replace the empty trigger in-place so
        // there is no orphan blank line above the new reference.
        updatedDocument = updatedDocument.updateBlock(triggeredBlockId, bibleBlock);

        // Clean up the text controller / focus node for the replaced block.
        _blockControllers[triggeredBlockId]?.dispose();
        _blockControllers.remove(triggeredBlockId);
        _blockFocusNodes[triggeredBlockId]?.dispose();
        _blockFocusNodes.remove(triggeredBlockId);
        _committedContent.remove(triggeredBlockId);
        _committedCursorOffset.remove(triggeredBlockId);
      }
    } else {
      // Triggering block still has text: keep it and insert the Bible
      // reference after it.
      final updatedTriggerBlock = block.copyWith(content: triggerContent);
      updatedDocument = updatedDocument.updateBlock(triggeredBlockId, updatedTriggerBlock);
      updatedDocument = updatedDocument.insertBlockAfter(triggeredBlockId, bibleBlock);

      // Sync the text controller
      final controller = _blockControllers[triggeredBlockId];
      if (controller != null) {
        controller.text = triggerContent;
        controller.selection =
            TextSelection.collapsed(offset: atIndex >= 0 ? atIndex : 0);
      }
      _committedContent[triggeredBlockId] = triggerContent;
    }

    // Add exactly 1 empty paragraph below the new reference so the user
    // has a place to continue writing. One line is enough — the separator
    // above (when consecutive refs exist) is the preserved trigger block.
    final trailingBlock = EditorBlock.paragraph();
    updatedDocument = updatedDocument.insertBlockAfter(bibleBlock.id, trailingBlock);

    // Move cursor to the new empty paragraph
    final newCursor = EditorCursor.atStart(trailingBlock.id);

    // Dismiss the picker and set cursor below the verse
    state = state.copyWith(
      document: updatedDocument,
      cursor: newCursor,
      selection: EditorSelection.collapsed(newCursor),
      isDirty: true,
      uiState: state.uiState.copyWith(
        showBibleReferencePicker: false,
        bibleReferenceTriggeredBlockId: '',
        focusedBlockId: trailingBlock.id,
      ),
    );

    // Explicitly focus the new block after the widget tree rebuilds.
    _focusBlock(trailingBlock.id);

    _scheduleSave();
  }

  /// Replace the content of an existing Bible reference block with a new
  /// selection. Used by the "Edit Reference" action.
  void updateBibleReferenceBlock({
    required String blockId,
    required String book,
    required int chapter,
    required List<int> verses,
    required String version,
  }) {
    final block = state.document.getBlockById(blockId);
    if (block == null || block.type != BlockType.bibleReference) return;

    final bibleRef = BibleReference(
      reference: BibleVerseReference(
        book: book,
        chapter: chapter,
        verses: verses,
        version: version,
      ),
      text: const [],
      source: 'local',
      insertedAt: DateTime.now().millisecondsSinceEpoch,
      display: const BibleVerseDisplay(),
      pending: false,
    );

    final updatedBlock = block.copyWith(
      content: jsonEncode(bibleRef.toJson()),
    );
    final updatedDocument = state.document.updateBlock(blockId, updatedBlock);

    state = state.copyWith(
      document: updatedDocument,
      isDirty: true,
    );
    _scheduleSave();
  }

  // ==================== Section Operations ====================

  /// Ensure a section has at least one empty block.
  /// Called when user expands an empty section to start editing.
  /// Returns the block ID of the first (or newly created) block in the section.
  String ensureSectionBlock(NoteSection section) {
    final sectionBlocks = state.document.getBlocksForSection(section);
    if (sectionBlocks.isNotEmpty) {
      return sectionBlocks.first.id;
    }

    // Create an empty paragraph in this section
    final newBlock = EditorBlock.paragraph(section: section);

    final updatedDocument = state.document.addBlockToSection(section, newBlock);

    // Create controller for new block
    _blockControllers[newBlock.id] = FormattedTextEditingController(
      text: '',
      formats: [],
    );
    _blockFocusNodes[newBlock.id] = FocusNode();
    _committedContent[newBlock.id] = '';
    _committedCursorOffset[newBlock.id] = 0;

    final newCursor = EditorCursor.atStart(newBlock.id);

    state = state.copyWith(
      document: updatedDocument,
      cursor: newCursor,
      selection: EditorSelection.collapsed(newCursor),
      uiState: state.uiState.copyWith(focusedBlockId: newBlock.id),
      isDirty: true,
    );
    _scheduleSave();

    // Focus the new (empty) block.
    _focusBlock(newBlock.id);

    return newBlock.id;
  }

  /// Ensures the main section ends with at least one editable text block.
  ///
  /// When a Bible reference block is the last block in the main section the
  /// reference card is not a text field, so tapping in the empty area below
  /// would do nothing. This method inserts up to 3 empty paragraph blocks after
  /// the reference, focuses the first one, and returns true so the caller knows
  /// a new block was added (and should skip the normal refocus logic).
  ///
  /// If the last main-section block is already a text block, returns false.
  bool ensureTrailingTextBlock() {
    final mainBlocks = state.document.getBlocksForSection(NoteSection.main);
    if (mainBlocks.isEmpty) return false;

    final lastBlock = mainBlocks.last;
    if (lastBlock.type != BlockType.bibleReference) return false;

    // Add 1 trailing empty paragraph so the user has a place to write.
    final trailingBlocks = List.generate(1, (_) => EditorBlock.paragraph());
    var updatedDocument = state.document;
    String prevId = lastBlock.id;
    for (final tb in trailingBlocks) {
      updatedDocument = updatedDocument.insertBlockAfter(prevId, tb);
      prevId = tb.id;
    }

    final firstTrailing = trailingBlocks.first;
    final newCursor = EditorCursor.atStart(firstTrailing.id);

    state = state.copyWith(
      document: updatedDocument,
      cursor: newCursor,
      selection: EditorSelection.collapsed(newCursor),
      isDirty: true,
      uiState: state.uiState.copyWith(focusedBlockId: firstTrailing.id),
    );

    _scheduleSave();

    _focusBlock(firstTrailing.id);

    return true;
  }

  /// Force save immediately (for app lifecycle events)
  Future<void> forceSave() async {
    _saveTimer?.cancel();
    await _save();
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    _textCommitTimer?.cancel();

    // Dispose all controllers
    for (final controller in _blockControllers.values) {
      controller.dispose();
    }
    for (final node in _blockFocusNodes.values) {
      node.dispose();
    }

    super.dispose();
  }
}

/// Provider family for note editor state
/// Pass noteId for existing notes, null for new notes
/// Uses autoDispose to reset state when navigating away (important for new notes)
final noteEditorProvider = StateNotifierProvider.autoDispose
    .family<NoteEditorNotifier, NoteEditorState, String?>(
  (ref, noteId) => NoteEditorNotifier(ref, noteId),
);
