import '../../../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/drag_handle.dart';
import '../../domain/models/bible_highlight_entity.dart';
import '../../../../l10n/l10n.dart';
import '../../../../core/theme/theme_colors.dart';
import '../providers/bible_chapter_providers.dart';

/// Bottom sheet for a tapped Bible verse: highlight colour, the user's notes on
/// the verse, and shortcuts to save it as a promise or to a note.
///
/// Shown on tap or long-press of a verse in the chapter reading view.
class HighlightBottomSheet extends ConsumerStatefulWidget {
  /// Human-readable verse reference (e.g., "Genesis 1:1").
  final String reference;

  /// Full verse text — used by the Notes/Promise shortcuts.
  final String verseText;

  /// Which verse this is, to find and save its notes.
  final int bookId;
  final int chapter;
  final int verse;

  /// Existing highlight if editing, null if creating.
  final BibleHighlightEntity? existingHighlight;

  /// Called when user saves a highlight.
  final void Function(HighlightColor color) onSave;

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
    required this.bookId,
    required this.chapter,
    required this.verse,
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
    required int bookId,
    required int chapter,
    required int verse,
    BibleHighlightEntity? existingHighlight,
    required void Function(HighlightColor color) onSave,
    VoidCallback? onRemove,
    void Function(String reference, String verseText)? onSaveToPromises,
    void Function(String reference, String verseText)? onSaveToNotes,
  }) {
    return showModalBottomSheet(
      // Defaults to false: a scroll-controlled sheet otherwise draws its
      // top edge behind the notch or Dynamic Island.
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => HighlightBottomSheet(
        reference: reference,
        verseText: verseText,
        bookId: bookId,
        chapter: chapter,
        verse: verse,
        existingHighlight: existingHighlight,
        onSave: onSave,
        onRemove: onRemove,
        onSaveToPromises: onSaveToPromises,
        onSaveToNotes: onSaveToNotes,
      ),
    );
  }

  @override
  ConsumerState<HighlightBottomSheet> createState() =>
      _HighlightBottomSheetState();
}

class _HighlightBottomSheetState extends ConsumerState<HighlightBottomSheet> {
  late HighlightColor _selectedColor;
  final _noteController = TextEditingController();
  bool _showNoteField = false;
  bool _savingNote = false;

  @override
  void initState() {
    super.initState();
    _selectedColor =
        widget.existingHighlight?.color ?? HighlightColor.yellow;
    _noteController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _save() {
    widget.onSave(_selectedColor);
    Navigator.of(context).pop();
  }

  void _remove() {
    widget.onRemove?.call();
    Navigator.of(context).pop();
  }

  Future<void> _saveNote() async {
    final text = _noteController.text.trim();
    if (text.isEmpty || _savingNote) return;
    final messenger = ScaffoldMessenger.of(context);
    final failed = l10n(context).couldNotSaveVerseNote;
    setState(() => _savingNote = true);
    try {
      await ref.read(bibleVerseNoteRepositoryProvider).addNote(
            bookId: widget.bookId,
            chapter: widget.chapter,
            verse: widget.verse,
            content: text,
          );
      if (!mounted) return;
      _noteController.clear();
      setState(() {
        _showNoteField = false;
        _savingNote = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingNote = false);
      messenger.showSnackBar(SnackBar(
        content: Text(failed),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existingHighlight != null;
    final notes = ref
            .watch(verseNotesProvider(
                (bookId: widget.bookId, chapter: widget.chapter, verse: widget.verse)))
            .valueOrNull ??
        const [];
    // A note typed into a highlight before verses could have several. It is
    // still the user's writing, so it stays visible (and editable), oldest, at
    // the end. Read from the live highlight, so editing it updates the list.
    final highlights = ref
        .watch(chapterHighlightsProvider(
            (bookId: widget.bookId, chapter: widget.chapter)))
        .valueOrNull;
    final highlight = highlights
            ?.where((h) => h.coversVerse(widget.verse))
            .firstOrNull ??
        widget.existingHighlight;
    final noteRepo = ref.read(bibleVerseNoteRepositoryProvider);
    final highlightRepo = ref.read(bibleHighlightRepositoryProvider);
    final items = <_NoteItem>[
      for (final n in notes)
        _NoteItem(
          key: n.id,
          text: n.content,
          onEdit: (text) => noteRepo.updateNote(n, text),
          onDelete: () => noteRepo.deleteNote(n),
        ),
      if (highlight != null && highlight.note.isNotEmpty)
        _NoteItem(
          key: highlight.id,
          text: highlight.note,
          onEdit: (text) =>
              highlightRepo.updateHighlight(highlight.copyWithUpdate(note: text)),
          onDelete: () =>
              highlightRepo.updateHighlight(highlight.copyWithUpdate(note: '')),
        ),
    ];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
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
                  fontSize: 14,
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

              // New note
              if (_showNoteField) ...[
                TextField(
                  controller: _noteController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: l10n(context).addANote,
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
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _noteController.text.trim().isEmpty || _savingNote
                        ? null
                        : _saveNote,
                    child: Text(l10n(context).saveNote),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Quick-save shortcuts (Notes / Promise)
              if (widget.onSaveToNotes != null ||
                  widget.onSaveToPromises != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    if (widget.onSaveToPromises != null)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onSaveToPromises!(
                              widget.reference, widget.verseText);
                        },
                        icon: const Icon(Icons.bookmark_outline, size: 16),
                        label: Text(l10n(context).saveAsPromise),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    if (widget.onSaveToNotes != null)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onSaveToNotes!(
                              widget.reference, widget.verseText);
                        },
                        icon: const Icon(Icons.edit_note, size: 16),
                        label: Text(l10n(context).addToNotes),
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
                        l10n(context).remove,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  const Spacer(),
                  if (!_showNoteField)
                    TextButton(
                      onPressed: () =>
                          setState(() => _showNoteField = true),
                      child: Text(l10n(context).addNote),
                    ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _save,
                    child: Text(isEditing ? 'Update' : 'Highlight'),
                  ),
                ],
              ),

              // Your notes, below all the options
              if (items.isNotEmpty) ...[
                const SizedBox(height: 16),
                Divider(height: 1, color: context.hairline),
                const SizedBox(height: 12),
                Text(
                  l10n(context).yourNotes,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) Divider(height: 24, color: context.hairline),
                  if (i == 0) const SizedBox(height: 8),
                  VerseNoteTile(
                    key: ValueKey(items[i].key),
                    text: items[i].text,
                    onEdit: items[i].onEdit,
                    onDelete: items[i].onDelete,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One note as the sheet lists it, and what to do when it is changed.
class _NoteItem {
  /// Stable id, so a note keeps its own editing state as the list changes.
  final String key;
  final String text;
  final Future<void> Function(String text) onEdit;
  final Future<void> Function() onDelete;

  const _NoteItem({
    required this.key,
    required this.text,
    required this.onEdit,
    required this.onDelete,
  });
}

/// One note, cut to two lines with an underlined "See more" that opens it
/// in full. "See more" only appears when the text does not fit in two lines.
/// The menu beside it edits the note in place or deletes it.
class VerseNoteTile extends StatefulWidget {
  final String text;
  final Future<void> Function(String text) onEdit;
  final Future<void> Function() onDelete;

  const VerseNoteTile({
    super.key,
    required this.text,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<VerseNoteTile> createState() => _VerseNoteTileState();
}

class _VerseNoteTileState extends State<VerseNoteTile> {
  bool _expanded = false;
  bool _editing = false;
  bool _busy = false;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startEditing() {
    _controller.text = widget.text;
    setState(() => _editing = true);
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    if (text == widget.text) {
      setState(() => _editing = false);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final failed = l10n(context).couldNotSaveVerseNote;
    setState(() => _busy = true);
    try {
      await widget.onEdit(text);
      if (!mounted) return;
      setState(() {
        _editing = false;
        _busy = false;
        _expanded = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(
        content: Text(failed),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _delete() async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = l10n(context).couldNotDeleteVerseNote;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n(dialogContext).deleteVerseNoteQuestion),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n(dialogContext).actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              l10n(dialogContext).actionDelete,
              style: TextStyle(color: Theme.of(dialogContext).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.onDelete();
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: Text(failed),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) return _buildEditor(context);

    final style = TextStyle(
      fontSize: 14,
      height: 1.4,
      color: Theme.of(context).colorScheme.onSurface,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final painter = TextPainter(
                text: TextSpan(text: widget.text, style: style),
                maxLines: 2,
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout(maxWidth: constraints.maxWidth);
              final overflows = painter.didExceedMaxLines;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.text,
                    style: style,
                    maxLines: _expanded ? null : 2,
                    overflow:
                        _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                  ),
                  if (overflows && !_expanded)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _expanded = true),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 2),
                        child: Text(
                          l10n(context).seeMore,
                          style: style.copyWith(
                            decoration: TextDecoration.underline,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        PopupMenuButton<String>(
          tooltip: l10n(context).moreOptions,
          icon: const Icon(Icons.more_vert, size: 20),
          padding: EdgeInsets.zero,
          onSelected: (value) {
            if (value == 'edit') _startEditing();
            if (value == 'delete') _delete();
          },
          itemBuilder: (context) => [
            PopupMenuItem(value: 'edit', child: Text(l10n(context).edit)),
            PopupMenuItem(
              value: 'delete',
              child: Text(
                l10n(context).actionDelete,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEditor(BuildContext context) {
    final theme = Theme.of(context);
    final t = l10n(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _busy ? null : () => setState(() => _editing = false),
              child: Text(t.actionCancel),
            ),
            TextButton(
              onPressed:
                  _controller.text.trim().isEmpty || _busy ? null : _save,
              child: Text(t.actionSave),
            ),
          ],
        ),
      ],
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
    return Semantics(
      button: true,
      label: '${color.label} highlight'
          '${isSelected ? ", selected" : ""}',
      child: GestureDetector(
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
                : context.hairline,
            width: isSelected ? 2.5 : 1,
          ),
        ),
        child: isSelected
            ? Icon(
                Icons.check,
                size: 20,
                color: AppTheme.onHighlight,
              )
            : null,
      ),
    ),
    );
  }
}
