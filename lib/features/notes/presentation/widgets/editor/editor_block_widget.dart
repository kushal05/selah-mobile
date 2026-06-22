import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../bible/presentation/providers/bible_providers.dart';
import '../../../../bible/domain/models/bible_books.dart';
import '../../../../bible/domain/models/bible_reference.dart';
import '../../../domain/models/block_type.dart';
import '../../../domain/models/editor_block.dart';
import '../../providers/note_editor_provider.dart';
import 'bible_reference_block_widget.dart';
import 'bible_reference_picker.dart';
import 'formatted_text_controller.dart';

/// Base widget for rendering editor blocks
/// Each block type extends this with specific styling
class EditorBlockWidget extends ConsumerStatefulWidget {
  final EditorBlock block;
  final String? noteId;
  final int blockIndex;
  final bool autoFocus;
  final bool isSelected;
  final bool isMultiSelectActive;

  const EditorBlockWidget({
    super.key,
    required this.block,
    required this.noteId,
    required this.blockIndex,
    this.autoFocus = false,
    this.isSelected = false,
    this.isMultiSelectActive = false,
  });

  @override
  ConsumerState<EditorBlockWidget> createState() => _EditorBlockWidgetState();
}

class _EditorBlockWidgetState extends ConsumerState<EditorBlockWidget> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  final GlobalKey _textFieldKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final notifier = ref.read(noteEditorProvider(widget.noteId).notifier);
    _controller = notifier.getBlockController(widget.block.id);
    _focusNode = notifier.getBlockFocusNode(widget.block.id);

    _focusNode.addListener(_onFocusChange);
    _controller.addListener(_onSelectionChange);

    if (widget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  void _onSelectionChange() {
    // Only track selection for the focused block
    if (!_focusNode.hasFocus) return;

    final selection = _controller.selection;
    if (selection.isValid) {
      ref.read(noteEditorProvider(widget.noteId).notifier).setTextSelection(
            selection.start,
            selection.end,
          );
    }
  }

  @override
  void didUpdateWidget(EditorBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block.id != widget.block.id) {
      // Remove old listeners
      _controller.removeListener(_onSelectionChange);

      final notifier = ref.read(noteEditorProvider(widget.noteId).notifier);
      _controller = notifier.getBlockController(widget.block.id);
      _focusNode = notifier.getBlockFocusNode(widget.block.id);

      // Add new listener
      _controller.addListener(_onSelectionChange);
    }

    // Detect block type change and restore focus if this block was focused
    if (oldWidget.block.type != widget.block.type) {
      final state = ref.read(noteEditorProvider(widget.noteId));
      if (state.uiState.focusedBlockId == widget.block.id) {
        // Schedule focus restoration after the widget tree settles
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_focusNode.canRequestFocus) {
            _focusNode.requestFocus();
            // Show keyboard explicitly
            SystemChannels.textInput.invokeMethod('TextInput.show');
            // Restore cursor position in the next frame
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || !_focusNode.hasFocus) return;
              final currentOffset = _controller.selection.isValid
                  ? _controller.selection.baseOffset
                  : _controller.text.length;
              _controller.selection = TextSelection.collapsed(
                offset: currentOffset.clamp(0, _controller.text.length),
              );
            });
          }
        });
      }
    }
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      ref.read(noteEditorProvider(widget.noteId).notifier).focusBlock(widget.block.id);

      // Ensure cursor is visible when focus is gained
      // This handles cases where focus was lost and regained (e.g., after toolbar tap)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_focusNode.hasFocus) return;

        // Show keyboard explicitly to ensure cursor becomes visible
        SystemChannels.textInput.invokeMethod('TextInput.show');

        // Get current selection position, default to end of text
        final currentOffset = _controller.selection.isValid
            ? _controller.selection.baseOffset
            : _controller.text.length;

        // Re-set the selection to ensure cursor blink timer starts
        _controller.selection = TextSelection.collapsed(
          offset: currentOffset.clamp(0, _controller.text.length),
        );
      });
    }
  }

  Timer? _longPressTimer;
  static const _kLongPressDuration = Duration(milliseconds: 800);
  static const _kMoveSlop = 10.0; // px of movement before cancelling
  Offset? _pointerDownPosition;

  void _onPointerDown(PointerDownEvent event) {
    if (widget.isMultiSelectActive) return;
    _pointerDownPosition = event.position;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(_kLongPressDuration, () {
      HapticFeedback.mediumImpact();
      ref
          .read(noteEditorProvider(widget.noteId).notifier)
          .toggleBlockSelection(widget.block.id);
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_longPressTimer == null || _pointerDownPosition == null) return;
    final distance = (event.position - _pointerDownPosition!).distance;
    if (distance > _kMoveSlop) {
      _longPressTimer?.cancel();
      _longPressTimer = null;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget content = Focus(
      onKeyEvent: (node, event) {
        final result = _handleKeyEvent(event);
        return result ? KeyEventResult.handled : KeyEventResult.ignored;
      },
      child: _buildBlockContent(),
    );

    if (widget.isMultiSelectActive) {
      // In multi-select mode, intercept all taps to toggle selection
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          ref
              .read(noteEditorProvider(widget.noteId).notifier)
              .toggleBlockSelection(widget.block.id);
        },
        child: AbsorbPointer(child: content),
      );
    } else {
      // Use Listener to detect long-press without losing gesture arena to TextField
      content = Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: content,
      );
    }

    // Subtle selection highlight — just a light background tint
    if (widget.isSelected) {
      content = ColoredBox(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        child: content,
      );
    }

    return content;
  }

  Widget _buildBlockContent() {
    switch (widget.block.type) {
      case BlockType.heading1:
        return _buildHeading(28, FontWeight.bold);
      case BlockType.heading2:
        return _buildHeading(24, FontWeight.bold);
      case BlockType.heading3:
        return _buildHeading(20, FontWeight.bold);
      case BlockType.bulletList:
        return _buildListItem(bullet: true);
      case BlockType.numberedList:
        return _buildListItem(numbered: true);
      case BlockType.checkbox:
        return _buildCheckboxItem();
      case BlockType.paragraph:
        return _buildParagraph();
      case BlockType.bibleReference:
        return _buildBibleReference();
    }
  }

  Widget _buildParagraph() {
    return _buildTextField(
      style: const TextStyle(fontSize: 16, height: 1.4),
    );
  }

  Widget _buildHeading(double fontSize, FontWeight fontWeight) {
    return _buildTextField(
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: 1.3,
      ),
    );
  }

  Widget _buildListItem({bool bullet = false, bool numbered = false}) {
    final indentLevel = widget.block.indentLevel;
    final indentPadding = indentLevel * 24.0;

    // Get the prefix (bullet or number)
    String prefix;
    if (bullet) {
      prefix = _getBulletForLevel(indentLevel);
    } else {
      // Get derived number from provider
      final number = ref.read(noteEditorProvider(widget.noteId).notifier)
          .getListNumber(widget.block.id);
      prefix = '$number.';
    }

    return Padding(
      padding: EdgeInsets.only(left: indentPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 24,
            child: Text(
              prefix,
              style: TextStyle(
                fontSize: 16,
                height: 1.4,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: _buildTextField(
              style: const TextStyle(fontSize: 16, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  /// Get different bullet styles for different indent levels
  String _getBulletForLevel(int level) {
    const bullets = ['•', '◦', '▪', '▫', '●'];
    return bullets[level % bullets.length];
  }

  Widget _buildCheckboxItem() {
    final isChecked = widget.block.isChecked ?? false;
    final indentLevel = widget.block.indentLevel;
    final indentPadding = indentLevel * 24.0;

    return Padding(
      padding: EdgeInsets.only(left: indentPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Checkbox aligned with first line of text
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: isChecked,
                onChanged: (value) {
                  ref.read(noteEditorProvider(widget.noteId).notifier).toggleCheckbox(widget.block.id);
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildTextField(
              style: TextStyle(
                fontSize: 16,
                height: 1.4,
                decoration: isChecked ? TextDecoration.lineThrough : null,
                color: isChecked ? Colors.grey : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBibleReference() {
    // Parse the BibleReference from the block's content JSON
    BibleReference reference;
    try {
      final contentMap = jsonDecode(widget.block.content) as Map<String, dynamic>;
      reference = BibleReference.fromJson(contentMap);
    } catch (_) {
      reference = BibleReference.empty();
    }

    // Dynamic verse resolution from the local Bible SQLite database.
    // Legacy blocks with inline text render as-is. New blocks (empty text
    // list) resolve from the DB at render time.
    final needsLookup = reference.text.isEmpty && !reference.pending;
    final resolved = needsLookup
        ? reference.copyWith(
            text: ref.watch(verseLookupProvider(reference.reference)))
        : reference;

    return BibleReferenceBlockWidget(
      reference: resolved,
      availableTranslations: ref.watch(bibleTranslationsProvider),
      onEdit: () async {
        final ref_ = reference.reference;
        final existingBook =
            BibleBooks.books.where((b) => b.name == ref_.book).firstOrNull;
        final selection = await BibleReferencePicker.show(
          context,
          defaultVersion: ref_.version,
          initialBook: existingBook,
          initialChapter: ref_.chapter,
          initialVerseStart: ref_.verses.isNotEmpty ? ref_.verses.first : null,
          initialVerseEnd:
              ref_.verses.length > 1 ? ref_.verses.last : null,
        );
        if (selection == null) return;
        final verses = selection.verseEnd != null
            ? List.generate(
                selection.verseEnd! - selection.verseStart + 1,
                (i) => selection.verseStart + i,
              )
            : [selection.verseStart];
        ref.read(noteEditorProvider(widget.noteId).notifier)
            .updateBibleReferenceBlock(
          blockId: widget.block.id,
          book: selection.book.name,
          chapter: selection.chapter,
          verses: verses,
          version: selection.version,
        );
      },
      onRemove: () {
        ref.read(noteEditorProvider(widget.noteId).notifier)
            .deleteBlock(widget.block.id);
      },
    );
  }

  Widget _buildTextField({required TextStyle style}) {
    final theme = Theme.of(context);

    // Update the controller's formats so it renders formatted text correctly
    // The FormattedTextEditingController handles rendering via buildTextSpan
    final formattedController = _controller as FormattedTextEditingController;
    formattedController.updateFormats(widget.block.formats);

    // Apply theme color to style if not already set
    final effectiveStyle = style.copyWith(
      color: style.color ?? theme.textTheme.bodyLarge?.color ?? Colors.black,
    );

    return TextField(
      key: _textFieldKey,
      controller: _controller,
      focusNode: _focusNode,
      style: effectiveStyle,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        contentPadding: EdgeInsets.zero,
        isDense: true,
        isCollapsed: true,
        hintText: _getHintText(),
        hintStyle: effectiveStyle.copyWith(color: Colors.grey.shade400),
      ),
      maxLines: null,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      cursorWidth: 2.0,
      cursorColor: theme.colorScheme.primary,
      showCursor: true,
      onChanged: _onTextChanged,
      onSubmitted: (_) => _handleEnter(),
    );
  }

  String _getHintText() {
    // Only show hint on the first block when document is essentially empty
    if (widget.blockIndex == 0 && widget.block.content.isEmpty) {
      final state = ref.read(noteEditorProvider(widget.noteId));
      // Only show if there's just one block (the empty first block)
      if (state.document.blocks.length == 1) {
        return 'Start writing...';
      }
    }
    return '';
  }

  void _onTextChanged(String text) {
    ref.read(noteEditorProvider(widget.noteId).notifier).updateBlockContent(
          widget.block.id,
          text,
        );
  }

  /// Handle key events, returns true if the event was handled
  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final notifier = ref.read(noteEditorProvider(widget.noteId).notifier);
    final selection = _controller.selection;

    // Handle Tab key (indent) and Shift+Tab (outdent)
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (widget.block.type.isList) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          notifier.outdentBlock(widget.block.id);
        } else {
          notifier.indentBlock(widget.block.id);
        }
        return true; // Handled - prevent default tab behavior
      }
      return false; // Let default tab behavior occur for non-list blocks
    }

    // Handle Enter key
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _handleEnter();
      return true;
    }

    // Handle Backspace at start of block
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (selection.isCollapsed && selection.start == 0) {
        if (widget.block.type.isList) {
          // List item - handle according to spec
          if (widget.block.indentLevel > 0) {
            // Nested -> outdent
            notifier.outdentBlock(widget.block.id);
          } else {
            // Top-level -> convert to paragraph
            notifier.changeBlockType(widget.block.id, BlockType.paragraph);
          }
          return true;
        }
        // Non-list block
        if (widget.block.content.isEmpty && widget.blockIndex > 0) {
          notifier.deleteEmptyBlock(widget.block.id);
          return true;
        } else if (widget.blockIndex > 0) {
          notifier.mergeWithPreviousBlock(widget.block.id);
          return true;
        }
      }
    }

    return false; // Event not handled
  }

  void _handleEnter() {
    final selection = _controller.selection;
    if (!selection.isValid) return;

    final notifier = ref.read(noteEditorProvider(widget.noteId).notifier);

    // splitBlock handles all the logic:
    // - Empty list item: outdent (if nested) or convert to paragraph (if top-level)
    // - Non-empty: split at cursor position, new block inherits list type and indent level
    notifier.splitBlock(widget.block.id, selection.start);
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _focusNode.removeListener(_onFocusChange);
    _controller.removeListener(_onSelectionChange);
    super.dispose();
  }
}
