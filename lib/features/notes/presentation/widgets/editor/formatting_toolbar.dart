import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../shared/widgets/drag_handle.dart';
import '../../../domain/models/block_type.dart';
import '../../providers/note_editor_provider.dart';

/// Contextual formatting toolbar for the editor
/// Appears when text is selected or keyboard is visible
class FormattingToolbar extends ConsumerWidget {
  final String? noteId;
  final String? focusedBlockId;
  final VoidCallback? onVersePickerPressed;

  const FormattingToolbar({
    super.key,
    required this.noteId,
    this.focusedBlockId,
    this.onVersePickerPressed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // TextFieldTapRegion prevents taps on the toolbar from unfocusing TextFields
    // This is Flutter's built-in solution for toolbar focus management
    return TextFieldTapRegion(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Bible verse picker
              if (onVersePickerPressed != null)
                _FormatButton(
                  icon: Icons.menu_book_rounded,
                  tooltip: 'Insert Verse',
                  onPressed: onVersePickerPressed!,
                ),
              if (onVersePickerPressed != null) const _ToolbarDivider(),

              // Inline formatting (always visible)
              _FormatButton(
                icon: Icons.format_bold,
                tooltip: 'Bold',
                onPressed: () => _toggleFormat(ref, bold: true),
              ),
              _FormatButton(
                icon: Icons.format_italic,
                tooltip: 'Italic',
                onPressed: () => _toggleFormat(ref, italic: true),
              ),
              _FormatButton(
                icon: Icons.format_underlined,
                tooltip: 'Underline',
                onPressed: () => _toggleFormat(ref, underline: true),
              ),
              _FormatButton(
                icon: Icons.strikethrough_s,
                tooltip: 'Strikethrough',
                onPressed: () => _toggleFormat(ref, strikethrough: true),
              ),
              const _ToolbarDivider(),

              // Heading buttons (outside dropdown)
              _FormatButton(
                icon: Icons.looks_one,
                tooltip: 'Heading',
                onPressed: () => _changeBlockType(ref, BlockType.heading2),
              ),
              _FormatButton(
                icon: Icons.looks_two,
                tooltip: 'Sub-Heading',
                onPressed: () => _changeBlockType(ref, BlockType.heading3),
              ),
              const _ToolbarDivider(),

              // Block formatting
              _FormatButton(
                icon: Icons.format_list_bulleted,
                tooltip: 'Bullet List',
                onPressed: () => _changeBlockType(ref, BlockType.bulletList),
              ),
              _FormatButton(
                icon: Icons.format_list_numbered,
                tooltip: 'Numbered List',
                onPressed: () => _changeBlockType(ref, BlockType.numberedList),
              ),
              _FormatButton(
                icon: Icons.check_box_outlined,
                tooltip: 'Checkbox',
                onPressed: () => _changeBlockType(ref, BlockType.checkbox),
              ),
              _FormatButton(
                icon: Icons.format_quote,
                tooltip: 'Quote',
                onPressed: () => _changeBlockType(ref, BlockType.quote),
              ),
              _FormatButton(
                icon: Icons.code,
                tooltip: 'Code Block',
                onPressed: () => _changeBlockType(ref, BlockType.code),
              ),

              // Indent/Outdent buttons (only for list blocks)
              if (_isListBlock(ref)) ...[
                const _ToolbarDivider(),
                _FormatButton(
                  icon: Icons.format_indent_decrease,
                  tooltip: 'Outdent (Shift+Tab)',
                  onPressed: () => _outdent(ref),
                ),
                _FormatButton(
                  icon: Icons.format_indent_increase,
                  tooltip: 'Indent (Tab)',
                  onPressed: () => _indent(ref),
                ),
              ],
              const _ToolbarDivider(),

              // Heading options (H1 and Paragraph)
              _HeadingMenu(
                noteId: noteId,
                focusedBlockId: focusedBlockId,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleFormat(WidgetRef ref, {
    bool bold = false,
    bool italic = false,
    bool underline = false,
    bool strikethrough = false,
  }) {
    if (focusedBlockId == null) return;

    final blockId = focusedBlockId!;
    final notifier = ref.read(noteEditorProvider(noteId).notifier);
    final state = ref.read(noteEditorProvider(noteId));

    final start = state.uiState.textSelectionStart;
    final end = state.uiState.textSelectionEnd;

    if (start == end) return;

    notifier.toggleFormat(
      blockId: blockId,
      start: start,
      end: end,
      bold: bold,
      italic: italic,
      underline: underline,
      strikethrough: strikethrough,
    );

    // Restore the selection after formatting so multiple formats can be applied
    _refocusBlock(ref, blockId, selectionStart: start, selectionEnd: end);
  }

  void _changeBlockType(WidgetRef ref, BlockType type) {
    if (focusedBlockId == null) return;

    final blockId = focusedBlockId!;
    final notifier = ref.read(noteEditorProvider(noteId).notifier);
    final state = ref.read(noteEditorProvider(noteId));
    final block = state.document.getBlockById(blockId);

    if (block == null) return;

    if (block.type == type) {
      notifier.changeBlockType(blockId, BlockType.paragraph);
    } else {
      notifier.changeBlockType(blockId, type);
    }

    _refocusBlock(ref, blockId);
  }

  /// Request focus back on a block after a toolbar action.
  /// If [selectionStart] and [selectionEnd] are provided, the selection range
  /// is restored; otherwise the cursor is placed at its previous position.
  void _refocusBlock(
    WidgetRef ref,
    String blockId, {
    int? selectionStart,
    int? selectionEnd,
  }) {
    assert(
      (selectionStart != null && selectionEnd != null) ||
          (selectionStart == null && selectionEnd == null),
      'selectionStart and selectionEnd must both be provided or both be null',
    );
    final notifier = ref.read(noteEditorProvider(noteId).notifier);
    final focusNode = notifier.getBlockFocusNode(blockId);

    // Captured before the post-frame so focus changes don't clear it
    final cursorOffset = selectionStart == null
        ? notifier.getRefocusTarget()?.cursorOffset
        : null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (focusNode.canRequestFocus) {
        focusNode.requestFocus();
        SystemChannels.textInput.invokeMethod('TextInput.show');

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (selectionStart != null && selectionEnd != null) {
            notifier.restoreSelection(blockId, selectionStart, selectionEnd);
          } else if (cursorOffset != null) {
            notifier.setCursorPosition(blockId, cursorOffset);
          }
        });
      }
    });
  }

  /// Check if the focused block is a list type
  bool _isListBlock(WidgetRef ref) {
    if (focusedBlockId == null) return false;
    final state = ref.read(noteEditorProvider(noteId));
    final block = state.document.getBlockById(focusedBlockId!);
    return block?.type.isList ?? false;
  }

  /// Indent the focused block
  void _indent(WidgetRef ref) {
    if (focusedBlockId == null) return;
    final blockId = focusedBlockId!;
    ref.read(noteEditorProvider(noteId).notifier).indentBlock(blockId);
    _refocusBlock(ref, blockId);
  }

  /// Outdent the focused block
  void _outdent(WidgetRef ref) {
    if (focusedBlockId == null) return;
    final blockId = focusedBlockId!;
    ref.read(noteEditorProvider(noteId).notifier).outdentBlock(blockId);
    _refocusBlock(ref, blockId);
  }
}

class _FormatButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _FormatButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            icon,
            size: 20,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.grey.shade300,
    );
  }
}

class _HeadingMenu extends ConsumerWidget {
  final String? noteId;
  final String? focusedBlockId;

  const _HeadingMenu({
    required this.noteId,
    required this.focusedBlockId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<BlockType>(
      tooltip: 'More Styles',
      icon: const Icon(Icons.title, size: 20),
      itemBuilder: (context) => [
        _buildMenuItem(BlockType.heading1, 'Title', 20),
        const PopupMenuDivider(),
        _buildMenuItem(BlockType.paragraph, 'Paragraph', 14),
      ],
      onSelected: (type) {
        if (focusedBlockId == null) return;
        final blockId = focusedBlockId!;
        final notifier = ref.read(noteEditorProvider(noteId).notifier);
        notifier.changeBlockType(blockId, type);

        // Request focus back on the block after popup menu closes
        // Use longer delay since popup menu animation takes time
        final focusNode = notifier.getBlockFocusNode(blockId);
        Future.delayed(const Duration(milliseconds: 150), () {
          if (focusNode.canRequestFocus) {
            focusNode.requestFocus();
          }
        });
      },
      onCanceled: () {
        // Restore focus when menu is dismissed without selection
        if (focusedBlockId == null) return;
        final notifier = ref.read(noteEditorProvider(noteId).notifier);
        final focusNode = notifier.getBlockFocusNode(focusedBlockId!);
        Future.delayed(const Duration(milliseconds: 150), () {
          if (focusNode.canRequestFocus) {
            focusNode.requestFocus();
          }
        });
      },
    );
  }

  PopupMenuItem<BlockType> _buildMenuItem(BlockType type, String label, double fontSize) {
    return PopupMenuItem(
      value: type,
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: type.isHeading ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

/// Floating toolbar that positions itself near the selection
class FloatingFormattingToolbar extends StatelessWidget {
  final Widget child;
  final bool isVisible;
  final Offset? anchorPosition;

  const FloatingFormattingToolbar({
    super.key,
    required this.child,
    required this.isVisible,
    this.anchorPosition,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    return Positioned(
      left: anchorPosition?.dx ?? 16,
      top: anchorPosition?.dy ?? 0,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: child,
      ),
    );
  }
}

void showEditorGuide(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const _EditorHelpSheet(),
  );
}

class _EditorHelpSheet extends StatelessWidget {
  const _EditorHelpSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          const DragHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Icon(Icons.help_outline_rounded, color: theme.colorScheme.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Editor Guide',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: const [
                _HelpSection(
                  title: 'Text Formatting',
                  subtitle: 'Select text first, then tap a format button.',
                  items: [
                    _HelpItem(icon: Icons.format_bold, label: 'Bold', description: 'Make selected text bold.'),
                    _HelpItem(icon: Icons.format_italic, label: 'Italic', description: 'Italicise selected text.'),
                    _HelpItem(icon: Icons.format_underlined, label: 'Underline', description: 'Underline selected text.'),
                    _HelpItem(icon: Icons.strikethrough_s, label: 'Strikethrough', description: 'Cross out selected text.'),
                  ],
                ),
                SizedBox(height: 20),
                _HelpSection(
                  title: 'Headings & Styles',
                  subtitle: 'Place your cursor in a block, then tap a style.',
                  items: [
                    _HelpItem(icon: Icons.title, label: 'Title', description: 'Large title — use for the main section heading.'),
                    _HelpItem(icon: Icons.looks_one, label: 'Heading', description: 'Medium heading for sub-sections.'),
                    _HelpItem(icon: Icons.looks_two, label: 'Sub-Heading', description: 'Smaller heading for nested sections.'),
                    _HelpItem(icon: Icons.text_fields, label: 'Paragraph', description: 'Standard body text (default).'),
                  ],
                ),
                SizedBox(height: 20),
                _HelpSection(
                  title: 'Lists',
                  subtitle: 'Converts the current block into a list item. Tap again to toggle off.',
                  items: [
                    _HelpItem(icon: Icons.format_list_bulleted, label: 'Bullet List', description: 'Unordered list of items.'),
                    _HelpItem(icon: Icons.format_list_numbered, label: 'Numbered List', description: 'Ordered, auto-numbered list.'),
                    _HelpItem(icon: Icons.check_box_outlined, label: 'Checkbox', description: 'Tap the checkbox to mark items complete.'),
                    _HelpItem(icon: Icons.format_indent_increase, label: 'Indent (Tab)', description: 'Nest the list item one level deeper.'),
                    _HelpItem(icon: Icons.format_indent_decrease, label: 'Outdent (Shift+Tab)', description: 'Move the list item one level up.'),
                  ],
                ),
                SizedBox(height: 20),
                _HelpSection(
                  title: 'Bible Verse',
                  items: [
                    _HelpItem(
                      icon: Icons.menu_book_rounded,
                      label: 'Insert Verse',
                      description: 'Search and insert any Bible verse as a formatted card. Tap the card to expand or edit it.',
                    ),
                  ],
                ),
                SizedBox(height: 20),
                _HelpSection(
                  title: 'Editing Actions',
                  subtitle: 'Available in the top bar.',
                  items: [
                    _HelpItem(icon: Icons.undo, label: 'Undo', description: 'Undo the last change.'),
                    _HelpItem(icon: Icons.redo, label: 'Redo', description: 'Redo the last undone change.'),
                    _HelpItem(icon: Icons.info_outline, label: 'Metadata', description: 'Set the date, preacher, and tags for this note.'),
                  ],
                ),
                SizedBox(height: 20),
                _HelpSection(
                  title: 'Note Sections',
                  subtitle: 'Tap the section header to expand or collapse.',
                  items: [
                    _HelpItem(icon: Icons.person_outline, label: 'Personal Application', description: 'Write how the message applies to your own life.'),
                    _HelpItem(icon: Icons.volunteer_activism_outlined, label: 'Prayer', description: 'Record prayers prompted by the message.'),
                  ],
                ),
                SizedBox(height: 20),
                _HelpSection(
                  title: 'Keyboard Shortcuts',
                  items: [
                    _HelpItem(icon: Icons.keyboard_return, label: 'Enter', description: 'Start a new block at the cursor position.'),
                    _HelpItem(icon: Icons.backspace_outlined, label: 'Backspace at start', description: 'Merge with the block above, or remove list style.'),
                    _HelpItem(icon: Icons.tab, label: 'Tab / Shift+Tab', description: 'Indent or outdent a list item.'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<_HelpItem> items;

  const _HelpSection({required this.title, this.subtitle, required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
        const SizedBox(height: 10),
        ...items,
      ],
    );
  }
}

class _HelpItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;

  const _HelpItem({required this.icon, required this.label, required this.description});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(description, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom-docked toolbar (fallback when floating isn't possible)
class DockedFormattingToolbar extends StatelessWidget {
  final Widget toolbar;
  final bool isVisible;

  const DockedFormattingToolbar({
    super.key,
    required this.toolbar,
    required this.isVisible,
  });

  @override
  Widget build(BuildContext context) {
    // Wrap entire docked area in TextFieldTapRegion to prevent unfocusing
    return TextFieldTapRegion(
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 200),
        offset: isVisible ? Offset.zero : const Offset(0, 1),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: isVisible ? 1.0 : 0.0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Center(child: toolbar),
            ),
          ),
        ),
      ),
    );
  }
}
