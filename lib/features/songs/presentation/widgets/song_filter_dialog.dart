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
  final String? language;

  const SongSearchFilters({
    this.scale,
    this.tagIds = const {},
    this.folderId,
    this.language,
  });

  static const none = SongSearchFilters();

  /// How many of the four kinds are set — the number on the filter button.
  int get activeCount =>
      (scale != null ? 1 : 0) +
      (tagIds.isNotEmpty ? 1 : 0) +
      (folderId != null ? 1 : 0) +
      (language != null ? 1 : 0);

  bool get isEmpty => activeCount == 0;

  @override
  bool operator ==(Object other) =>
      other is SongSearchFilters &&
      other.scale == scale &&
      other.folderId == folderId &&
      other.language == language &&
      other.tagIds.length == tagIds.length &&
      other.tagIds.containsAll(tagIds);

  @override
  int get hashCode => Object.hash(
      scale, folderId, language, Object.hashAllUnordered(tagIds));
}

/// The kinds of filter, one button each.
enum _Category { key, tags, songbook, language }

/// Key, tags, songbook and language, chosen together and applied once.
///
/// Each kind is a button, and its choices open beneath the row when it is
/// tapped — one kind at a time. Every kind used to be laid out at once, which
/// put twenty-five keys between you and the tags; this is the shape the notes
/// filters already have. The buttons carry what is chosen ("Key: G", "Tags 2",
/// "Telugu"), so the dialog says what is set without anything being open.
///
/// Every choice is a draft until Apply. The filters used to be three bottom
/// sheets, and the tag sheet changed the screen's selection as you ticked but
/// searched only on Apply, so swiping it away left "Tags (2)" over unfiltered
/// results. Cancel, a tap outside or the back gesture leave the search exactly
/// as it was.
class SongFilterDialog extends StatefulWidget {
  final SongSearchFilters initial;
  final List<String> scales;
  final List<TagModel> tags;
  final List<FolderModel> songbooks;
  final List<String> languages;

  const SongFilterDialog({
    super.key,
    required this.initial,
    required this.scales,
    required this.tags,
    required this.songbooks,
    this.languages = const [],
  });

  /// The chosen filters, or null if the dialog was dismissed without applying.
  static Future<SongSearchFilters?> show(
    BuildContext context, {
    required SongSearchFilters initial,
    required List<String> scales,
    required List<TagModel> tags,
    required List<FolderModel> songbooks,
    List<String> languages = const [],
  }) {
    return showDialog<SongSearchFilters>(
      context: context,
      builder: (_) => SongFilterDialog(
        initial: initial,
        scales: scales,
        tags: tags,
        songbooks: songbooks,
        languages: languages,
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
  late String? _language = widget.initial.language;

  /// The kind whose choices are showing, if any. Nothing is open to begin
  /// with: the buttons already say what is set.
  _Category? _open;

  SongSearchFilters get _draft => SongSearchFilters(
        scale: _scale,
        tagIds: {..._tagIds},
        folderId: _folderId,
        language: _language,
      );

  /// The kinds worth offering. Songbook and language each hide when there is
  /// no choice to make — no songbooks, or every song in one language — the
  /// way the songbook chip always did. Either stays while a filter of its kind
  /// is in force, so there is always a way to take it off.
  List<_Category> get _categories => [
        _Category.key,
        _Category.tags,
        if (widget.songbooks.isNotEmpty || _folderId != null)
          _Category.songbook,
        if (widget.languages.length > 1 || _language != null)
          _Category.language,
      ];

  @override
  Widget build(BuildContext context) {
    final t = l10n(context);
    final theme = Theme.of(context);
    final categories = _categories;
    // A kind can stop being offered while open — Clear all can drop the last
    // language filter when there is only one language — and its choices must
    // not hang beneath a row that no longer has its button.
    final open = categories.contains(_open) ? _open : null;

    // Cancel and Clear all, in the text colour rather than an accent. Left to
    // the theme they were brandBlue — the colour this screen was asked to drop.
    // Orange would be the obvious swap, but as *text* on the light dialog
    // surface it measures 4.33:1, under the 4.5 a label needs (the glyph-tuned
    // orange is for icons). So the secondary actions are neutral and the one
    // primary action, Apply, carries the songs colour.
    final secondary = TextButton.styleFrom(foregroundColor: context.primaryText);

    return AlertDialog(
      // Clear all lives up here, not among the actions. Beside Cancel and Apply
      // it needed a Row to keep the other two together, and a Row cannot wrap:
      // at 320pt with large text Apply was pushed off the dialog. A Wrap lets it
      // drop under the title instead.
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
                      _language = null;
                      _tagIds.clear();
                    }),
            child: Text(t.clearAll),
          ),
        ],
      ),
      // The body scrolls; the actions do not. Open on Key, the choices run to
      // twenty-five, and Apply has to stay reachable when they do.
      scrollable: true,
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A Wrap, not a Row: four buttons with their summaries do not fit
            // one line on a small phone with large text.
            Wrap(
              spacing: 8,
              children: [for (final c in categories) _button(context, c, open)],
            ),
            AnimatedSize(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              alignment: Alignment.topCenter,
              child: open == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: _choices(context, open),
                    ),
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

  /// One kind's button: its name, or what is chosen, and a chevron saying
  /// whether its choices are open. Tinted while a filter of its kind is set.
  Widget _button(BuildContext context, _Category c, _Category? open) {
    final t = l10n(context);
    final isOpen = open == c;

    final (IconData icon, String label, int? count, bool set) = switch (c) {
      _Category.key => (
          Icons.music_note_rounded,
          _scale == null ? t.songKeyLabel : t.songKeyChosen(_scale!),
          null,
          _scale != null,
        ),
      _Category.tags => (
          Icons.label_outlined,
          t.tags,
          _tagIds.isEmpty ? null : _tagIds.length,
          _tagIds.isNotEmpty,
        ),
      _Category.songbook => (
          Icons.library_books_outlined,
          _songbookName ?? t.songbookLabel,
          null,
          _folderId != null,
        ),
      _Category.language => (
          Icons.translate_rounded,
          _language ?? t.songLanguageLabel,
          null,
          _language != null,
        ),
    };

    return FilterPill(
      icon: icon,
      label: label,
      count: count,
      selected: set,
      trailingIcon:
          isOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded,
      expanded: isOpen,
      // Tapping the open one closes it.
      onTap: () => setState(() => _open = isOpen ? null : c),
      accent: AppTheme.orange,
      dense: true,
    );
  }

  String? get _songbookName {
    if (_folderId == null) return null;
    for (final f in widget.songbooks) {
      if (f.id == _folderId) return f.name;
    }
    return null;
  }

  /// The choices for the open kind.
  Widget _choices(BuildContext context, _Category c) {
    final t = l10n(context);
    return switch (c) {
      _Category.key => _Section(
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
      _Category.tags => _Section(
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
      // Singular, to match the button that opened it — as Key, Tags and
      // Language each do.
      _Category.songbook => _Section(
          label: t.songbookLabel,
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
      _Category.language => _Section(
          label: t.songLanguageLabel,
          children: [
            _pill(
              label: t.anyLanguage,
              selected: _language == null,
              onTap: () => setState(() => _language = null),
            ),
            for (final l in widget.languages)
              _pill(
                label: l,
                selected: _language == l,
                onTap: () =>
                    setState(() => _language = _language == l ? null : l),
              ),
          ],
        ),
    };
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
    return Column(
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
    );
  }
}
