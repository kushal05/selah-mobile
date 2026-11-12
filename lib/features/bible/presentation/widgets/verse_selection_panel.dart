import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/models/bible_highlight_entity.dart';
import '../../domain/services/verse_selection.dart';
import '../providers/bible_chapter_providers.dart';

/// The panel that appears over the chapter when verses are selected: highlight
/// colours (one tap applies), the notes on the selected verses, and the actions
/// to add a note, save the passage as a promise or add it to a note.
///
/// Acts on the whole selection. A note can only be written when the selected
/// verses are next to each other, so it is never shown against a verse it was
/// not written on.
class VerseSelectionPanel extends ConsumerStatefulWidget {
  /// "Genesis 1:4–6", for the heading.
  final String reference;
  final int bookId;
  final int chapter;
  final Set<int> selected;

  /// Highlights in the chapter, to show the current colour.
  final List<BibleHighlightEntity> highlights;

  final void Function(HighlightColor color) onColor;
  final VoidCallback onRemoveHighlight;
  final VoidCallback onClose;
  final VoidCallback onSaveAsPromise;
  final VoidCallback onAddToNotes;

  const VerseSelectionPanel({
    super.key,
    required this.reference,
    required this.bookId,
    required this.chapter,
    required this.selected,
    required this.highlights,
    required this.onColor,
    required this.onRemoveHighlight,
    required this.onClose,
    required this.onSaveAsPromise,
    required this.onAddToNotes,
  });

  @override
  ConsumerState<VerseSelectionPanel> createState() =>
      _VerseSelectionPanelState();
}

class _VerseSelectionPanelState extends ConsumerState<VerseSelectionPanel> {
  final _noteController = TextEditingController();
  bool _showNoteField = false;
  bool _savingNote = false;

  @override
  void initState() {
    super.initState();
    _noteController.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(VerseSelectionPanel old) {
    super.didUpdateWidget(old);
    // The note belongs to the verses it was started on.
    if (old.selected.length != widget.selected.length ||
        !old.selected.containsAll(widget.selected)) {
      _showNoteField = false;
      _noteController.clear();
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _saveNote() async {
    final text = _noteController.text.trim();
    if (text.isEmpty || _savingNote || !isConsecutive(widget.selected)) return;
    final runs = verseRuns(widget.selected).single;
    final messenger = ScaffoldMessenger.of(context);
    final failed = l10n(context).couldNotSaveVerseNote;
    setState(() => _savingNote = true);
    try {
      await ref.read(bibleVerseNoteRepositoryProvider).addNote(
            bookId: widget.bookId,
            chapter: widget.chapter,
            verse: runs.start,
            verseEnd: runs.end,
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
    final t = l10n(context);
    final selected = widget.selected;
    final consecutive = isConsecutive(selected);

    final touched = [
      for (final h in widget.highlights)
        if (selected.any(h.coversVerse)) h,
    ];
    // The colour is "current" when every selected verse has the same one.
    final allCovered =
        selected.every((v) => widget.highlights.any((h) => h.coversVerse(v)));
    final colors = touched.map((h) => h.color).toSet();
    final current = allCovered && colors.length == 1 ? colors.single : null;

    final noteRepo = ref.read(bibleVerseNoteRepositoryProvider);
    final highlightRepo = ref.read(bibleHighlightRepositoryProvider);
    final chapterNotes = ref
            .watch(chapterVerseNotesProvider(
                (bookId: widget.bookId, chapter: widget.chapter)))
            .valueOrNull ??
        const [];
    // A note typed into a highlight before verses could have several. It is
    // still the user's writing, so it stays visible (and editable).
    final items = <_NoteItem>[
      for (final n in chapterNotes)
        if (selected.any((v) => v >= n.verseStart && v <= n.verseEnd))
          _NoteItem(
            key: n.id,
            start: n.verseStart,
            end: n.verseEnd,
            text: n.content,
            onEdit: (text) => noteRepo.updateNote(n, text),
            onDelete: () => noteRepo.deleteNote(n),
          ),
      for (final h in touched)
        if (h.note.isNotEmpty)
          _NoteItem(
            key: h.id,
            start: h.verseStart,
            end: h.verseEnd,
            text: h.note,
            onEdit: (text) =>
                highlightRepo.updateHighlight(h.copyWithUpdate(note: text)),
            onDelete: () =>
                highlightRepo.updateHighlight(h.copyWithUpdate(note: '')),
          ),
    ];

    final maxHeight = MediaQuery.sizeOf(context).height * 0.6;

    return Material(
      color: context.raisedSurface,
      elevation: 8,
      borderRadius: BorderRadius.circular(18),
      shadowColor: Colors.black54,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.reference,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          t.versesSelectedCount(selected.length),
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: t.clearSelection,
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final c in HighlightColor.values)
                    _ColorSwatch(
                      color: c,
                      isSelected: c == current,
                      onTap: () => widget.onColor(c),
                    ),
                ],
              ),
              if (touched.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: widget.onRemoveHighlight,
                    icon: const Icon(Icons.format_color_reset_outlined, size: 16),
                    label: Text(t.removeHighlight),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              if (_showNoteField) ...[
                TextField(
                  controller: _noteController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: t.addANote,
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed:
                        _noteController.text.trim().isEmpty || _savingNote
                            ? null
                            : _saveNote,
                    child: Text(t.saveNote),
                  ),
                ),
              ],
              Row(
                children: [
                  if (!_showNoteField)
                    Expanded(
                      child: _PanelAction(
                        icon: Icons.edit_outlined,
                        label: t.addNote,
                        onTap: consecutive
                            ? () => setState(() => _showNoteField = true)
                            : null,
                      ),
                    ),
                  Expanded(
                    child: _PanelAction(
                      icon: Icons.bookmark_outline,
                      label: t.saveAsPromise,
                      onTap: widget.onSaveAsPromise,
                    ),
                  ),
                  Expanded(
                    child: _PanelAction(
                      icon: Icons.edit_note,
                      label: t.addToNotes,
                      onTap: widget.onAddToNotes,
                    ),
                  ),
                ],
              ),
              if (!consecutive && !_showNoteField)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    t.noteNeedsNeighbouringVerses,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 12),
                Divider(height: 1, color: context.hairline),
                const SizedBox(height: 12),
                Text(
                  t.yourNotes,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) Divider(height: 24, color: context.hairline),
                  if (i == 0) const SizedBox(height: 8),
                  // Which verses it was written on, so a note on a group is
                  // never mistaken for one on a single verse.
                  Text(
                    items[i].start == items[i].end
                        ? t.noteOnVerse('${items[i].start}')
                        : t.noteOnVerses(
                            formatVerseRange(items[i].start, items[i].end)),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
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

/// One of the panel's actions: an icon over a label.
class _PanelAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _PanelAction({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    final color = enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface.withValues(alpha: 0.38);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One note as the panel lists it, and what to do when it is changed.
class _NoteItem {
  /// Stable id, so a note keeps its own editing state as the list changes.
  final String key;
  final int start;
  final int end;
  final String text;
  final Future<void> Function(String text) onEdit;
  final Future<void> Function() onDelete;

  const _NoteItem({
    required this.key,
    required this.start,
    required this.end,
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
      behavior: HitTestBehavior.opaque,
      // A 44dp touch target around the 36dp disc.
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(child: Container(
        width: 36,
        height: 36,
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
      ))),
    ),
    );
  }
}
