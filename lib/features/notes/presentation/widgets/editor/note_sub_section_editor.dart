import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/note_section.dart';
import '../../providers/note_editor_provider.dart';
import 'editor_block_widget.dart';

/// Collapsible rich-text subsection for Personal Application / Prayer.
///
/// Renders a section header with expand/collapse toggle, and when expanded
/// shows all blocks belonging to that section using the same [EditorBlockWidget]
/// as the main editor.
class NoteSubSectionEditor extends ConsumerStatefulWidget {
  final NoteSection section;
  final String? noteId;

  const NoteSubSectionEditor({
    super.key,
    required this.section,
    required this.noteId,
  });

  @override
  ConsumerState<NoteSubSectionEditor> createState() =>
      _NoteSubSectionEditorState();
}

class _NoteSubSectionEditorState extends ConsumerState<NoteSubSectionEditor> {
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    // Auto-expand if section already has content
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final editorState = ref.read(noteEditorProvider(widget.noteId));
      final hasContent = !editorState.document.isSectionEmpty(widget.section);
      if (hasContent && !_isExpanded) {
        setState(() => _isExpanded = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(noteEditorProvider(widget.noteId));
    final sectionBlocks =
        editorState.document.getBlocksForSection(widget.section);
    final isEmpty = sectionBlocks.isEmpty ||
        (sectionBlocks.length == 1 && sectionBlocks.first.isEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Divider
        Divider(color: Colors.grey.shade200, height: 1),
        const SizedBox(height: 8),

        // Section header (tappable to expand/collapse)
        GestureDetector(
          onTap: _toggleExpanded,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: _isExpanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  widget.section.displayTitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                    letterSpacing: 0.5,
                  ),
                ),
                if (!_isExpanded && !isEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getPreviewText(sectionBlocks),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade400,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Expanded content
        if (_isExpanded) ...[
          if (sectionBlocks.isEmpty)
            // Empty placeholder — tap to start editing
            GestureDetector(
              onTap: _activateSection,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  widget.section.placeholder,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey.shade400,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            )
          else
            // Render section blocks using the same editor widgets
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < sectionBlocks.length; i++)
                  Padding(
                    // Key by block id so inserting/splitting a block keeps each
                    // EditorBlockWidget's State (controller, focus node, cursor)
                    // bound to its block instead of being reused positionally.
                    key: ValueKey(sectionBlocks[i].id),
                    padding: const EdgeInsets.only(bottom: 4),
                    child: EditorBlockWidget(
                      block: sectionBlocks[i],
                      noteId: widget.noteId,
                      blockIndex: i,
                    ),
                  ),
              ],
            ),

          const SizedBox(height: 8),
        ],
      ],
    );
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
    // If expanding an empty section, create the first block
    if (_isExpanded) {
      final editorState = ref.read(noteEditorProvider(widget.noteId));
      if (editorState.document.getBlocksForSection(widget.section).isEmpty) {
        _activateSection();
      }
    }
  }

  void _activateSection() {
    ref
        .read(noteEditorProvider(widget.noteId).notifier)
        .ensureSectionBlock(widget.section);
  }

  String _getPreviewText(List sectionBlocks) {
    for (final block in sectionBlocks) {
      if (block.content.trim().isNotEmpty) {
        final text = block.content.trim();
        return text.length > 60 ? '${text.substring(0, 57)}...' : text;
      }
    }
    return '';
  }
}
