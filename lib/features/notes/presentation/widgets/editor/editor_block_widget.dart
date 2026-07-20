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
import '../../../domain/models/editor_cursor.dart';
import '../../../domain/models/note_table.dart';
import '../../providers/note_editor_provider.dart';
import 'bible_reference_block_widget.dart';
import 'bible_reference_picker.dart';
import 'formatted_text_controller.dart';
import 'formatted_text_span.dart' show kMonospaceFallback;
import 'note_table_widget.dart';

/// Base widget for rendering editor blocks
/// Each block type extends this with specific styling
class EditorBlockWidget extends ConsumerStatefulWidget {
  final EditorBlock block;
  final String? noteId;
  final int blockIndex;
  final bool autoFocus;
  final bool isSelected;
  final bool isMultiSelectActive;

  /// The portion of this block covered by an active cross-block text selection
  /// (Phase 3), painted as a highlight. Null when this block isn't in a text
  /// range.
  final TextSelection? textHighlight;

  const EditorBlockWidget({
    super.key,
    required this.block,
    required this.noteId,
    required this.blockIndex,
    this.autoFocus = false,
    this.isSelected = false,
    this.isMultiSelectActive = false,
    this.textHighlight,
  });

  @override
  ConsumerState<EditorBlockWidget> createState() => _EditorBlockWidgetState();
}

class _EditorBlockWidgetState extends ConsumerState<EditorBlockWidget> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  final GlobalKey _textFieldKey = GlobalKey();

  /// The last style handed to the TextField — used by the drag hit-test to map
  /// a point to a text offset with a matching TextPainter.
  TextStyle _effectiveTextStyle = const TextStyle(fontSize: 16, height: 1.4);

  /// Anchor cursor of an in-progress cross-block text drag.
  EditorCursor? _dragTextAnchor;

  /// Captured in initState so dispose (where `ref` is unusable) can still
  /// unregister the hit-test resolver. The provider is stable per noteId.
  late final NoteEditorNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(noteEditorProvider(widget.noteId).notifier);
    final notifier = _notifier;
    _controller = notifier.getBlockController(widget.block.id);
    _focusNode = notifier.getBlockFocusNode(widget.block.id);

    _focusNode.addListener(_onFocusChange);
    _controller.addListener(_onSelectionChange);
    notifier.registerBlockTextHit(widget.block.id, _textOffsetAtGlobal);

    if (widget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  /// Map a global point to a text offset within this block's content, using a
  /// TextPainter that mirrors the field's style/width. May be a character off
  /// from the TextField's own layout at the very edges (device-tuning item).
  int _textOffsetAtGlobal(Offset global) {
    final box = _textFieldKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return 0;
    final local = box.globalToLocal(global);
    final tp = TextPainter(
      text: TextSpan(text: _controller.text, style: _effectiveTextStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: box.size.width);
    return tp.getPositionForOffset(local).offset;
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

      // Re-point the text hit-test resolver at the new block id.
      notifier.unregisterBlockTextHit(oldWidget.block.id);
      notifier.registerBlockTextHit(widget.block.id, _textOffsetAtGlobal);
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
            // Restore cursor position in the next frame — but only if the
            // controller lost its selection. Overwriting a still-valid
            // selection collapses ranges and can jump the caret (the same
            // controller instance survives a block type change, so its
            // selection is normally still intact here).
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || !_focusNode.hasFocus) return;
              if (_controller.selection.isValid) return;
              _controller.selection = TextSelection.collapsed(
                offset: _controller.text.length,
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

        // Only place a caret when the controller has no valid selection.
        // Reassigning an existing selection collapses range selections (e.g.
        // text selected for formatting) and can jump the caret on refocus.
        if (_controller.selection.isValid) return;
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
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
      final notifier = ref.read(noteEditorProvider(widget.noteId).notifier);
      // In multi-select mode: tap toggles this block; a vertical drag extends
      // the selection across the blocks it passes over. The drag builds both a
      // precise cross-block TEXT selection (for the partial-end highlight and a
      // merging delete) and the whole-block range (for the action-bar count).
      // The whole subtree is AbsorbPointer'd so the TextField ignores these.
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => notifier.toggleBlockSelection(widget.block.id),
        onVerticalDragStart: (details) {
          _dragTextAnchor = notifier.textCursorAt(details.globalPosition);
        },
        onVerticalDragUpdate: (details) {
          final focus = notifier.textCursorAt(details.globalPosition);
          if (focus == null) return;
          notifier.selectBlockRange(focus.blockId);
          if (_dragTextAnchor != null) {
            notifier.setTextRangeSelection(_dragTextAnchor!, focus);
          }
        },
        onVerticalDragEnd: (_) => _dragTextAnchor = null,
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

    // Selection highlight. A precise text-range highlight (painted inside the
    // TextField) takes precedence; otherwise the subtle whole-block tint.
    if (widget.textHighlight == null && widget.isSelected) {
      content = ColoredBox(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        child: content,
      );
    }

    // Stable key on the outer box so drag-extend can hit-test which block a
    // pointer is over, in any section.
    return KeyedSubtree(
      key: ref.read(noteEditorProvider(widget.noteId).notifier)
          .blockHitKey(widget.block.id),
      child: content,
    );
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
      case BlockType.quote:
        return _buildQuote();
      case BlockType.code:
        return _buildCodeBlock();
      case BlockType.table:
        return _buildTable();
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

  Widget _buildQuote() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.primary.withValues(alpha: 0.5),
            width: 3,
          ),
        ),
      ),
      child: _buildTextField(
        style: TextStyle(
          fontSize: 16,
          height: 1.4,
          fontStyle: FontStyle.italic,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
        ),
      ),
    );
  }

  Widget _buildCodeBlock() {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: _buildTextField(
        style: const TextStyle(
          fontSize: 14,
          height: 1.45,
          fontFamily: 'monospace',
          fontFamilyFallback: kMonospaceFallback,
        ),
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

  Widget _buildTable() {
    NoteTable table;
    try {
      table = NoteTable.fromJson(
          jsonDecode(widget.block.content) as Map<String, dynamic>);
    } catch (_) {
      table = NoteTable.empty;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: NoteTableWidget(
        table: table,
        onRemove: () => ref
            .read(noteEditorProvider(widget.noteId).notifier)
            .deleteBlock(widget.block.id),
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
    // Remember the style so the drag hit-test lays out with matching metrics.
    _effectiveTextStyle = effectiveStyle;

    final field = TextField(
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
      contextMenuBuilder: (context, editableState) {
        // Route the default "Paste" through the markdown-aware paste so pasted
        // markdown reconstructs formatting, and offer a literal paste beside it
        // for text that only looks like markdown. Other actions stay default.
        final items = List<ContextMenuButtonItem>.from(
          editableState.contextMenuButtonItems,
        );
        final pasteIndex =
            items.indexWhere((b) => b.type == ContextMenuButtonType.paste);
        if (pasteIndex != -1) {
          items[pasteIndex] = ContextMenuButtonItem(
            type: ContextMenuButtonType.paste,
            onPressed: () {
              editableState.hideToolbar();
              _pasteFromClipboard();
            },
          );
          // Only offered when a Paste item exists, i.e. the clipboard has text.
          items.insert(
            pasteIndex + 1,
            ContextMenuButtonItem(
              label: 'Paste as plain text',
              onPressed: () {
                editableState.hideToolbar();
                _pasteFromClipboard(asMarkdown: false);
              },
            ),
          );
        }
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: editableState.contextMenuAnchors,
          buttonItems: items,
        );
      },
    );

    final highlight = widget.textHighlight;
    if (highlight == null || highlight.isCollapsed) return field;

    // Paint the cross-block text-selection highlight behind the text. The
    // painter lays out with the same style/width as the field, so the boxes
    // align with the rendered glyphs.
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _SelectionHighlightPainter(
                text: _controller.text,
                style: effectiveStyle,
                selection: highlight,
                color: theme.colorScheme.primary.withValues(alpha: 0.28),
              ),
            ),
          ),
        ),
        field,
      ],
    );
  }

  /// Read the clipboard and paste at the current selection. Parses the text as
  /// markdown unless [asMarkdown] is false.
  Future<void> _pasteFromClipboard({bool asMarkdown = true}) async {
    final selection = _controller.selection;
    final start =
        selection.isValid ? selection.start : _controller.text.length;
    final end = selection.isValid ? selection.end : start;

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text;
    if (raw == null || raw.isEmpty || !mounted) return;

    ref.read(noteEditorProvider(widget.noteId).notifier).pasteText(
          blockId: widget.block.id,
          selectionStart: start,
          selectionEnd: end,
          rawText: raw,
          asMarkdown: asMarkdown,
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

    // Handle Ctrl/Cmd+V — route hardware-keyboard paste through markdown parsing.
    if (event.logicalKey == LogicalKeyboardKey.keyV &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed)) {
      _pasteFromClipboard();
      return true; // Suppress the built-in paste.
    }

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
    // selection.end drops any selected text, which Enter replaces.
    notifier.splitBlock(widget.block.id, selection.start, selection.end);
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _focusNode.removeListener(_onFocusChange);
    _controller.removeListener(_onSelectionChange);
    _notifier.unregisterBlockTextHit(widget.block.id);
    super.dispose();
  }
}

/// Paints the highlight rectangles for [selection] over a block's text, laid
/// out with the same [style]/width as the field so the boxes line up.
class _SelectionHighlightPainter extends CustomPainter {
  const _SelectionHighlightPainter({
    required this.text,
    required this.style,
    required this.selection,
    required this.color,
  });

  final String text;
  final TextStyle style;
  final TextSelection selection;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (selection.isCollapsed || text.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    final paint = Paint()..color = color;
    for (final box in tp.getBoxesForSelection(selection)) {
      canvas.drawRect(box.toRect(), paint);
    }
  }

  @override
  bool shouldRepaint(_SelectionHighlightPainter old) =>
      text != old.text ||
      style != old.style ||
      selection != old.selection ||
      color != old.color;
}
