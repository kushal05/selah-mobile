import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../domain/models/note_section.dart';
import '../providers/note_editor_provider.dart';
import '../widgets/editor/bible_reference_picker.dart';
import '../widgets/editor/editor_block_widget.dart';
import '../widgets/editor/formatting_toolbar.dart';
import '../widgets/editor/metadata_panel.dart';
import '../widgets/editor/note_sub_section_editor.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/utils/date_format.dart';

/// Note editor screen for creating and editing notes
/// Implements a block-based rich text editor with auto-save
class NoteEditorScreen extends ConsumerStatefulWidget {
  final String? noteId;
  final String? folderId;

  /// Pre-filled title for new notes (e.g. a Bible verse reference).
  final String? initialTitle;

  const NoteEditorScreen({super.key, this.noteId, this.folderId, this.initialTitle});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

/// Every control in the editor's app bar uses one glyph size and one square
/// slot, so the row reads as a single set rather than as controls of three
/// different weights.
const double _kBarIcon = AppTheme.iconBase;
const double _kBarSlot = 44;

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen>
    with WidgetsBindingObserver {
  final _titleController = TextEditingController();
  final _titleFocusNode = FocusNode();
  final _scrollController = ScrollController();

  bool _isKeyboardVisible = false;
  bool _titleInitialized = false;
  bool _isPickerShowing = false;

  /// GlobalKeys for each block to enable scroll-to-visible
  final Map<String, GlobalKey> _blockKeys = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // For new notes, focus title immediately after first build
    if (widget.noteId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Set folder ID for new notes
        if (widget.folderId != null) {
          ref.read(noteEditorProvider(widget.noteId).notifier).setFolderId(widget.folderId);
        }
        // Pre-fill title when opening from Bible (verse reference)
        if (widget.initialTitle != null && _titleController.text.isEmpty) {
          _titleController.text = widget.initialTitle!;
        }
        _titleFocusNode.requestFocus();
        _titleInitialized = true;
      });
    }
    // For existing notes, title will be set via ref.listen when loading completes
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // Detect keyboard visibility
    final bottomInset = View.of(context).viewInsets.bottom;
    final newKeyboardVisible = bottomInset > 0;

    if (_isKeyboardVisible != newKeyboardVisible) {
      setState(() => _isKeyboardVisible = newKeyboardVisible);
      ref.read(noteEditorProvider(widget.noteId).notifier).setKeyboardVisible(newKeyboardVisible);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Save on app background/pause
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      ref.read(noteEditorProvider(widget.noteId).notifier).forceSave();

      // Persist scroll position
      ref.read(noteEditorProvider(widget.noteId).notifier)
          .setScrollOffset(_scrollController.offset);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _titleController.dispose();
    _titleFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(noteEditorProvider(widget.noteId));

    // Single consolidated listener for all editor state changes.
    // Avoids registering 3 separate listeners that each evaluate on every
    // state change — reduces listener overhead by ~3x.
    ref.listen<NoteEditorState>(
      noteEditorProvider(widget.noteId),
      (previous, next) {
        // 1) Initialize title when loading completes for existing notes
        if (!_titleInitialized &&
            widget.noteId != null &&
            previous?.isLoading == true &&
            next.isLoading == false &&
            next.note != null) {
          _titleController.text = next.title;
          _titleInitialized = true;
        }

        // 2) Trigger Bible reference picker (@ typed in editor)
        if (next.uiState.showBibleReferencePicker &&
            !(previous?.uiState.showBibleReferencePicker ?? false) &&
            !_isPickerShowing) {
          _showBibleReferencePicker();
        }

        // 3) Scroll to keep focused block visible
        final focusedBlockId = next.uiState.focusedBlockId;

        // Scroll when focused block changes
        if (previous?.uiState.focusedBlockId != focusedBlockId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToFocusedBlock(focusedBlockId);
          });
          return;
        }

        // Scroll when a new block is added (block count increases)
        if (previous != null &&
            next.document.blocks.length > previous.document.blocks.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToFocusedBlock(focusedBlockId);
          });
          return;
        }

        // Scroll when content changes in the focused block (user is typing)
        if (focusedBlockId != null && previous != null) {
          final prevBlock = previous.document.getBlockById(focusedBlockId);
          final nextBlock = next.document.getBlockById(focusedBlockId);
          if (prevBlock != null && nextBlock != null &&
              prevBlock.content != nextBlock.content) {
            // Only scroll if content increased (typing, not deleting)
            if (nextBlock.content.length > prevBlock.content.length) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scrollToFocusedBlock(focusedBlockId);
              });
            }
          }
        }
      },
    );

    return Scaffold(
      appBar: _buildAppBar(context, editorState),
      body: SafeArea(
        child: Stack(
          children: [
            // Main editor content
            SingleChildScrollView(
              controller: _scrollController,
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: _isKeyboardVisible ? 80 : 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Metadata row (tappable to edit)
                  _buildMetadataRow(context, editorState),

                  const SizedBox(height: 16),

                  // Title field
                  _buildTitleField(),

                  const SizedBox(height: 12),

                  // Block editor (main section only)
                  _buildBlockEditor(editorState),

                  const SizedBox(height: 24),

                  // Subsections: Personal Application & Prayer
                  NoteSubSectionEditor(
                    section: NoteSection.personalApplication,
                    noteId: widget.noteId,
                  ),
                  NoteSubSectionEditor(
                    section: NoteSection.prayer,
                    noteId: widget.noteId,
                  ),

                  // Spacer to allow scrolling past content.
                  // Tapping here refocuses the editor at the last cursor
                  // position — a convenience for a pointer. Hidden from the
                  // semantics tree: to a screen reader it would be a
                  // half-screen unlabelled target sitting between the note
                  // and everything after it, and focusing the block directly
                  // already does the same thing.
                  ExcludeSemantics(
                    child: GestureDetector(
                      onTap: () => _handleEmptyAreaTap(context),
                      child: Container(
                        height: MediaQuery.of(context).size.height * 0.5,
                        width: double.infinity,
                        color: Colors.transparent,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Selection action bar or formatting toolbar
            if (editorState.uiState.isMultiSelectActive)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildSelectionActionBar(context, editorState),
              )
            else
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DockedFormattingToolbar(
                  isVisible: _isKeyboardVisible,
                  toolbar: FormattingToolbar(
                    noteId: widget.noteId,
                    focusedBlockId: editorState.uiState.focusedBlockId,
                    onVersePickerPressed: _showBibleReferencePicker,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, NoteEditorState editorState) {
    final cs = Theme.of(context).colorScheme;
    final notifier = ref.read(noteEditorProvider(widget.noteId).notifier);

    // Every control in this bar is one square of [_kBarSlot] with one glyph
    // size. Setting AppBar.actionsIconTheme is not enough on its own: in
    // Material 3 an IconButton takes its size from its own ButtonStyle
    // default (24) and ignores the ambient IconTheme, so the row rendered at
    // three different sizes — 24 for the buttons, 20 for Help, 16 for the
    // save indicator — with three different footprints beside them.
    Widget barButton({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
    }) {
      return IconButton(
        icon: Icon(icon),
        iconSize: _kBarIcon,
        tooltip: tooltip,
        onPressed: onPressed,
        constraints: const BoxConstraints.tightFor(
            width: _kBarSlot, height: _kBarSlot),
        padding: EdgeInsets.zero,
      );
    }

    // The save state is status, not a control, but it sits in the same row —
    // so it takes the same slot and glyph size and is told apart by colour.
    Widget statusSlot(Widget child) => SizedBox(
          width: _kBarSlot,
          height: _kBarSlot,
          child: Center(child: child),
        );

    return AppBar(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      elevation: 0,
      titleSpacing: 0,
      iconTheme: IconThemeData(color: cs.onSurface, size: _kBarIcon),
      actionsIconTheme:
          IconThemeData(color: cs.onSurfaceVariant, size: _kBarIcon),
      leading: barButton(
        icon: Icons.arrow_back,
        tooltip: l10n(context).actionBack,
        onPressed: _handleBack,
      ),
      title: editorState.isLoading ? Text(l10n(context).loading) : null,
      actions: [
        barButton(
          icon: Icons.undo,
          tooltip: l10n(context).actionUndo,
          onPressed: notifier.canUndo ? notifier.undo : null,
        ),
        barButton(
          icon: Icons.redo,
          tooltip: l10n(context).redo,
          onPressed: notifier.canRedo ? notifier.redo : null,
        ),
        barButton(
          icon: Icons.info_outline,
          tooltip: l10n(context).noteDetails,
          onPressed: () => showMetadataPanel(context, widget.noteId),
        ),

        // Editor guide. Labelled rather than a bare glyph: the guide is
        // genuinely good, and the people who need it are exactly the ones who
        // will not recognise a "?" icon or think to long-press it for a
        // tooltip. Its glyph and height still match the buttons beside it.
        TextButton.icon(
          icon: const Icon(Icons.help_outline_rounded, size: _kBarIcon),
          label: Text(l10n(context).help),
          onPressed: () => showEditorGuide(context),
          style: TextButton.styleFrom(
            foregroundColor: cs.primary,
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing8),
            minimumSize: const Size(0, _kBarSlot),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),

        // Saving indicator - three states: saving, pending changes, saved
        if (editorState.isSaving)
          statusSlot(const SizedBox(
            width: _kBarIcon,
            height: _kBarIcon,
            child: CircularProgressIndicator(strokeWidth: 2),
          ))
        else if (editorState.isDirty)
          statusSlot(Icon(Icons.cloud_upload_outlined,
              size: _kBarIcon,
              color: AppTheme.semanticFor(
                  AppTheme.warning, Theme.of(context).brightness)))
        else
          statusSlot(Icon(Icons.cloud_done_outlined,
              size: _kBarIcon,
              color: AppTheme.semanticFor(
                  AppTheme.success, Theme.of(context).brightness))),
        const SizedBox(width: AppTheme.spacing4),
      ],
    );
  }

  Widget _buildMetadataRow(BuildContext context, NoteEditorState editorState) {
    final preacherName = editorState.preacherId != null
        ? ref.watch(personByIdProvider(editorState.preacherId!))
        : null;

    final hasDate = editorState.noteDate != null;
    final resolvedName = preacherName?.valueOrNull?.name;
    final hasPreacher = resolvedName != null;

    return Semantics(
      button: true,
      child: GestureDetector(
      onTap: () => showMetadataPanel(context, widget.noteId),
      child: !hasDate && !hasPreacher
          ? Row(
              children: [
                Icon(Icons.add, size: 16, color: context.hintText),
                const SizedBox(width: 4),
                Text(
                  l10n(context).addDatePreacher,
                  style: TextStyle(
                    fontSize: 16,
                    color: context.hintText,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            )
          : Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                if (hasDate)
                  _MetadataItem(
                    icon: Icons.calendar_today,
                    text: _formatDate(editorState.noteDate!),
                  ),
                if (hasPreacher)
                  _MetadataItem(
                    icon: Icons.person,
                    text: resolvedName,
                  ),
              ],
            ),
    ),
    );
  }

  String _formatDate(DateTime date) {
    return formatLongDate(date);
  }

  Widget _buildTitleField() {
    return TextField(
      controller: _titleController,
      focusNode: _titleFocusNode,
      decoration: InputDecoration(
        hintText: l10n(context).noteTitle,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        // Same size as the saved title so the field does not visibly resize
        // the moment the user types, and a hint that actually meets contrast
        // — grey.shade400 was 1.94:1.
        hintStyle: AppTheme.noteTitle.copyWith(
          fontWeight: FontWeight.w500,
          color: context.hintText,
        ),
        contentPadding: EdgeInsets.zero,
        isDense: true,
      ),
      style: AppTheme.noteTitle,
      maxLines: 1,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.next,
      onChanged: (value) {
        ref.read(noteEditorProvider(widget.noteId).notifier).updateTitle(value);
      },
      onSubmitted: (_) {
        // Move focus to first main-section block
        final state = ref.read(noteEditorProvider(widget.noteId));
        final mainBlocks = state.document.getBlocksForSection(NoteSection.main);
        if (mainBlocks.isNotEmpty) {
          final firstBlockId = mainBlocks.first.id;
          ref.read(noteEditorProvider(widget.noteId).notifier).focusBlock(firstBlockId);
          ref.read(noteEditorProvider(widget.noteId).notifier)
              .getBlockFocusNode(firstBlockId)
              .requestFocus();
        }
      },
    );
  }

  Widget _buildBlockEditor(NoteEditorState editorState) {
    if (editorState.isLoading) {
      return const DetailPageSkeleton(hasMetadataRow: false);
    }

    if (editorState.error != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: context.dangerText),
          const SizedBox(height: 16),
          Text(
            editorState.error!,
            style: TextStyle(color: context.dangerText),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _handleBack,
            child: Text(l10n(context).goBack),
          ),
        ],
      );
    }

    final mainBlocks = editorState.document.getBlocksForSection(NoteSection.main);

    // Clean up keys for removed blocks (use Set for O(n) instead of O(n²))
    final allBlocks = editorState.document.blocks;
    final blockIds = allBlocks.map((b) => b.id).toSet();
    _blockKeys.removeWhere((id, _) => !blockIds.contains(id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int index = 0; index < mainBlocks.length; index++)
          RepaintBoundary(
            key: _getBlockKey(mainBlocks[index].id),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: EditorBlockWidget(
                block: mainBlocks[index],
                noteId: widget.noteId,
                blockIndex: index,
                autoFocus: index == 0 && editorState.isNewNote && _titleController.text.isNotEmpty,
                isSelected: editorState.uiState.selectedBlockIds.contains(mainBlocks[index].id),
                isMultiSelectActive: editorState.uiState.isMultiSelectActive,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSelectionActionBar(BuildContext context, NoteEditorState editorState) {
    final theme = Theme.of(context);
    final count = editorState.uiState.selectedBlockIds.length;
    final notifier = ref.read(noteEditorProvider(widget.noteId).notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$count selected',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 16),
                Semantics(
                  button: true,
                  label: l10n(context).deleteSelectedBlocks,
                  child: GestureDetector(
                  onTap: () => notifier.deleteSelectedBlocks(),
                  child: Icon(
                    Icons.delete_outline,
                    size: 22,
                    color: context.dangerText,
                  ),
                ),
                ),
                const SizedBox(width: 16),
                Semantics(
                  button: true,
                  label: l10n(context).clearSelection,
                  child: GestureDetector(
                  onTap: () => notifier.clearBlockSelection(),
                  child: Icon(
                    Icons.close,
                    size: 22,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleBack() {
    // Force save before navigating back
    ref.read(noteEditorProvider(widget.noteId).notifier).forceSave();
    Navigator.of(context).pop();
  }

  /// Scroll to ensure the focused block is visible
  void _scrollToFocusedBlock(String? blockId) {
    if (blockId == null) return;

    final key = _blockKeys[blockId];
    if (key?.currentContext == null) return;

    // Use ensureVisible to smoothly scroll the block into view
    Scrollable.ensureVisible(
      key!.currentContext!,
      alignment: 0.3, // Position block at 30% from top for comfortable viewing
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  /// Get or create a GlobalKey for a block
  GlobalKey _getBlockKey(String blockId) {
    return _blockKeys.putIfAbsent(blockId, () => GlobalKey());
  }

  /// Show the Bible reference picker and handle the result.
  ///
  /// Verse text is NOT stored in the block. Only the reference coordinates
  /// (translation, bookId, chapter, verse) are persisted. Verse text is
  /// resolved dynamically from the local Bible SQLite database at render time
  /// via [VerseLookupService]. This keeps blocks lightweight and allows
  /// translation switching without re-inserting blocks.
  void _showBibleReferencePicker() async {
    if (_isPickerShowing) return;
    _isPickerShowing = true;
    final notifier = ref.read(noteEditorProvider(widget.noteId).notifier);

    // When invoked from the toolbar (no "@" typed), set the triggered block
    // so insertBibleReferenceBlock knows where to insert.
    notifier.ensureBibleReferenceTriggeredBlock();

    try {
      final selection = await BibleReferencePicker.show(
        context,
      );

      if (!mounted) return;

      if (selection == null) {
        notifier.dismissBibleReferencePicker();
        _isPickerShowing = false;
        return;
      }

      // Insert a reference-only block (no verse text stored).
      // Text will be resolved from the Bible DB at render time.
      notifier.insertBibleReferenceBlock(
        book: selection.book.name,
        chapter: selection.chapter,
        verses: selection.verses,
        version: selection.version,
      );
    } catch (_) {
      if (mounted) {
        notifier.dismissBibleReferencePicker();
      }
    } finally {
      _isPickerShowing = false;
    }
  }

  void _handleEmptyAreaTap(BuildContext context) {
    final notifier = ref.read(noteEditorProvider(widget.noteId).notifier);

    // If the last main-section block is a Bible reference card (non-editable),
    // insert trailing text blocks and focus the first one.
    if (notifier.ensureTrailingTextBlock()) return;

    final target = notifier.getRefocusTarget();

    if (target == null) return;

    // If already focused, just set cursor position
    if (target.focusNode.hasFocus) {
      notifier.setCursorPosition(target.blockId, target.cursorOffset);
      SystemChannels.textInput.invokeMethod('TextInput.show');
      return;
    }

    // Add a one-time listener to set cursor after focus is actually granted
    void onFocusChange() {
      if (target.focusNode.hasFocus) {
        target.focusNode.removeListener(onFocusChange);

        // Set cursor position after focus is confirmed
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          notifier.setCursorPosition(target.blockId, target.cursorOffset);
          SystemChannels.textInput.invokeMethod('TextInput.show');
        });
      }
    }

    target.focusNode.addListener(onFocusChange);

    // Request focus using FocusScope for proper context
    FocusScope.of(context).requestFocus(target.focusNode);
  }
}

class _MetadataItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetadataItem({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
