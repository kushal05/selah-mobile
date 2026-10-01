import 'package:flutter/material.dart';

import '../../../../core/sync/models/folder_model.dart';
import '../../../../core/sync/models/tag_model.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/filter_pill.dart';

/// What song search is narrowed by. Immutable, so the screen and the dialog
/// can never be looking at two different versions of it.
@immutable
class SongSearchFilters {
  final String? scale;
  final Set<String> tagIds;
  final String? folderId;

  const SongSearchFilters({this.scale, this.tagIds = const {}, this.folderId});

  static const none = SongSearchFilters();

  /// How many of the three kinds are set — the number on the filter button.
  int get activeCount =>
      (scale != null ? 1 : 0) +
      (tagIds.isNotEmpty ? 1 : 0) +
      (folderId != null ? 1 : 0);

  bool get isEmpty => activeCount == 0;

  @override
  bool operator ==(Object other) =>
      other is SongSearchFilters &&
      other.scale == scale &&
      other.folderId == folderId &&
      other.tagIds.length == tagIds.length &&
      other.tagIds.containsAll(tagIds);

  @override
  int get hashCode =>
      Object.hash(scale, folderId, Object.hashAllUnordered(tagIds));
}

/// Key, tags and songbook, chosen together and applied once.
///
/// These were three separate bottom sheets behind three chips under the search
/// field. The tag sheet changed the screen's selection as you ticked, but only
/// searched when you pressed Apply, so dismissing it by swiping left the chip
/// saying "Tags (2)" over results that were not filtered at all. Here every
/// choice is a draft until Apply: Cancel, a tap outside or the back gesture all
/// leave the search exactly as it was.
class SongFilterDialog extends StatefulWidget {
  final SongSearchFilters initial;
  final List<String> scales;
  final List<TagModel> tags;
  final List<FolderModel> songbooks;

  const SongFilterDialog({
    super.key,
    required this.initial,
    required this.scales,
    required this.tags,
    required this.songbooks,
  });

  /// The chosen filters, or null if the dialog was dismissed without applying.
  static Future<SongSearchFilters?> show(
    BuildContext context, {
    required SongSearchFilters initial,
    required List<String> scales,
    required List<TagModel> tags,
    required List<FolderModel> songbooks,
  }) {
    return showDialog<SongSearchFilters>(
      context: context,
      builder: (_) => SongFilterDialog(
        initial: initial,
        scales: scales,
        tags: tags,
        songbooks: songbooks,
      ),
    );
  }

  @override
  State<SongFilterDialog> createState() => _SongFilterDialogState();
}

class _SongFilterDialogState extends State<SongFilterDialog> {
  late String? _scale = widget.initial.scale;
  late final Set<String> _tagIds = {...widget.initial.tagIds};
  late String? _folderId = widget.initial.folderId;

  SongSearchFilters get _draft =>
      SongSearchFilters(scale: _scale, tagIds: {..._tagIds}, folderId: _folderId);

  @override
  Widget build(BuildContext context) {
    final t = l10n(context);
    final theme = Theme.of(context);

    // Cancel and Clear all, in the text colour rather than an accent. Left to
    // the theme they were brandBlue — the colour this screen was asked to drop.
    // Orange would be the obvious swap, but as *text* on the light dialog
    // surface it measures 4.33:1, under the 4.5 a label needs (the glyph-tuned
    // orange is for icons). So the secondary actions are neutral and the one
    // primary action, Apply, carries the songs colour.
    final secondary = TextButton.styleFrom(foregroundColor: context.primaryText);

    return AlertDialog(
      // Clear all lives up here, not among the actions. It used to sit on the
      // left of the action bar, which meant grouping Cancel and Apply in a Row
      // on the right — and a Row cannot wrap, so at 320pt with large text Apply
      // was pushed off the edge of the dialog. Here, a Wrap lets it drop under
      // the title when the two do not fit side by side, and the actions are a
      // plain pair the dialog already knows how to stack.
      title: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(t.filterSongs),
          // Clears the draft, not the search: it is still a choice you can
          // Cancel, which matters for the one control here that discards work.
          TextButton(
            style: secondary,
            onPressed: _draft.isEmpty
                ? null
                : () => setState(() {
                      _scale = null;
                      _folderId = null;
                      _tagIds.clear();
                    }),
            child: Text(t.clearAll),
          ),
        ],
      ),
      // The body scrolls; the actions do not. Twenty-five keys and an open-ended
      // tag list can outgrow a phone in landscape, and Apply has to stay
      // reachable when they do.
      scrollable: true,
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Section(
              label: t.songKeyLabel,
              children: [
                _pill(
                  label: t.anyKey,
                  selected: _scale == null,
                  onTap: () => setState(() => _scale = null),
                ),
                for (final s in widget.scales)
                  _pill(
                    label: s,
                    selected: _scale == s,
                    // Tapping the chosen key again lets it go, the same as
                    // choosing "Any key".
                    onTap: () => setState(() => _scale = _scale == s ? null : s),
                  ),
              ],
            ),
            _Section(
              label: t.tags,
              empty: widget.tags.isEmpty ? t.noTagsAvailable : null,
              children: [
                for (final tag in widget.tags)
                  _pill(
                    label: tag.name,
                    selected: _tagIds.contains(tag.id),
                    onTap: () => setState(() {
                      if (!_tagIds.remove(tag.id)) _tagIds.add(tag.id);
                    }),
                  ),
              ],
            ),
            // No songbooks, no section — the old chip hid itself the same way,
            // and a heading over a lone "All songbooks" would ask a question
            // with only one answer.
            if (widget.songbooks.isNotEmpty)
              _Section(
                label: t.songbooks,
                children: [
                  _pill(
                    label: t.allSongbooks,
                    selected: _folderId == null,
                    onTap: () => setState(() => _folderId = null),
                  ),
                  for (final f in widget.songbooks)
                    _pill(
                      label: f.name,
                      selected: _folderId == f.id,
                      onTap: () => setState(
                          () => _folderId = _folderId == f.id ? null : f.id),
                    ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          style: secondary,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.actionCancel),
        ),
        // The true songs orange with a dark label, not the darkened
        // orangeSurface with a white one: onAccent puts textDark on it at
        // 8.3:1, which clears the 4.5 a label needs and keeps the button the
        // colour of its tab rather than brown.
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.orange,
            foregroundColor: AppTheme.onAccent(AppTheme.orange),
            textStyle: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          onPressed: () => Navigator.of(context).pop(_draft),
          child: Text(t.apply),
        ),
      ],
    );
  }

  Widget _pill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      FilterPill(
        label: label,
        selected: selected,
        onTap: onTap,
        accent: AppTheme.orange,
        dense: true,
      );
}

/// A heading and a wrap of choices beneath it.
class _Section extends StatelessWidget {
  final String label;
  final List<Widget> children;

  /// Shown in place of the choices when there are none to make.
  final String? empty;

  const _Section({required this.label, required this.children, this.empty});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: context.mutedText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (empty != null)
            Text(empty!, style: TextStyle(color: context.mutedText))
          else
            // Horizontal gap only. The dense pills already carry 4pt of tap
            // margin above and below, so rows sit 8pt apart without asking.
            Wrap(spacing: 8, children: children),
        ],
      ),
    );
  }
}
