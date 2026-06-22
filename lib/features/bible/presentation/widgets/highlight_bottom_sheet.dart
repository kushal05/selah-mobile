import 'package:flutter/material.dart';

import '../../../../shared/widgets/drag_handle.dart';
import '../../domain/models/bible_highlight_entity.dart';

/// Bottom sheet for creating or editing a Bible verse highlight.
///
/// Shows a color palette, optional note field, and save/remove actions.
/// Also surfaces "Save as Promise" and "Add to Notes" shortcuts.
/// Shown on long-press of a verse in the chapter reading view.
class HighlightBottomSheet extends StatefulWidget {
  /// Human-readable verse reference (e.g., "Genesis 1:1").
  final String reference;

  /// Full verse text — used by the Notes/Promise shortcuts.
  final String verseText;

  /// Existing highlight if editing, null if creating.
  final BibleHighlightEntity? existingHighlight;

  /// Called when user saves a highlight.
  final void Function(HighlightColor color, String note) onSave;

  /// Called when user removes an existing highlight.
  final VoidCallback? onRemove;

  /// Called when user taps "Save as Promise". Receives (reference, verseText).
  final void Function(String reference, String verseText)? onSaveToPromises;

  /// Called when user taps "Add to Notes". Receives (reference, verseText).
  final void Function(String reference, String verseText)? onSaveToNotes;

  const HighlightBottomSheet({
    super.key,
    required this.reference,
    required this.verseText,
    this.existingHighlight,
    required this.onSave,
    this.onRemove,
    this.onSaveToPromises,
    this.onSaveToNotes,
  });

  /// Show the highlight bottom sheet and return the result.
  static Future<void> show(
    BuildContext context, {
    required String reference,
    required String verseText,
    BibleHighlightEntity? existingHighlight,
    required void Function(HighlightColor color, String note) onSave,
    VoidCallback? onRemove,
    void Function(String reference, String verseText)? onSaveToPromises,
    void Function(String reference, String verseText)? onSaveToNotes,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => HighlightBottomSheet(
        reference: reference,
        verseText: verseText,
        existingHighlight: existingHighlight,
        onSave: onSave,
        onRemove: onRemove,
        onSaveToPromises: onSaveToPromises,
        onSaveToNotes: onSaveToNotes,
      ),
    );
  }

  @override
  State<HighlightBottomSheet> createState() => _HighlightBottomSheetState();
}

class _HighlightBottomSheetState extends State<HighlightBottomSheet> {
  late HighlightColor _selectedColor;
  late TextEditingController _noteController;
  bool _showNoteField = false;

  @override
  void initState() {
    super.initState();
    _selectedColor =
        widget.existingHighlight?.color ?? HighlightColor.yellow;
    _noteController = TextEditingController(
      text: widget.existingHighlight?.note ?? '',
    );
    _showNoteField = widget.existingHighlight?.hasNote ?? false;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _save() {
    widget.onSave(_selectedColor, _noteController.text.trim());
    Navigator.of(context).pop();
  }

  void _remove() {
    widget.onRemove?.call();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existingHighlight != null;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DragHandle(),

            // Header
            Text(
              widget.reference,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isEditing ? 'Edit highlight' : 'Highlight verse',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // Color palette
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: HighlightColor.values
                  .map((color) => _ColorSwatch(
                        color: color,
                        isSelected: color == _selectedColor,
                        onTap: () =>
                            setState(() => _selectedColor = color),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),

            // Note field
            if (_showNoteField) ...[
              TextField(
                controller: _noteController,
                decoration: InputDecoration(
                  hintText: 'Add a note...',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
            ],

            // Quick-save shortcuts (Notes / Promise)
            if (widget.onSaveToNotes != null || widget.onSaveToPromises != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  if (widget.onSaveToPromises != null)
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onSaveToPromises!(widget.reference, widget.verseText);
                      },
                      icon: const Icon(Icons.bookmark_outline, size: 16),
                      label: const Text('Save as Promise'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  if (widget.onSaveToNotes != null)
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onSaveToNotes!(widget.reference, widget.verseText);
                      },
                      icon: const Icon(Icons.edit_note, size: 16),
                      label: const Text('Add to Notes'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            // Actions
            Row(
              children: [
                if (isEditing)
                  TextButton(
                    onPressed: _remove,
                    child: Text(
                      'Remove',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                const Spacer(),
                if (!_showNoteField)
                  TextButton(
                    onPressed: () =>
                        setState(() => _showNoteField = true),
                    child: const Text('Add Note'),
                  ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _save,
                  child: Text(isEditing ? 'Update' : 'Highlight'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular color swatch with selection indicator.
class _ColorSwatch extends StatelessWidget {
  final HighlightColor color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.backgroundColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? color.foregroundColor
                : Colors.grey.shade300,
            width: isSelected ? 2.5 : 1,
          ),
        ),
        child: isSelected
            ? Icon(
                Icons.check,
                size: 20,
                color: color.foregroundColor,
              )
            : null,
      ),
    );
  }
}
