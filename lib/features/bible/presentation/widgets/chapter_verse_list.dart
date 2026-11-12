import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/providers/sync_providers.dart';

import '../../../../core/providers/reading_preferences.dart';
import '../../domain/models/bible_highlight_entity.dart';
import '../../domain/models/bible_verse_entity.dart';
import '../providers/bible_chapter_providers.dart';
import '../../../../core/providers/motion_preferences.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/l10n.dart';

/// Displays all verses of a Bible chapter in a scrollable list.
///
/// Renders highlight backgrounds and supports long-press for highlight creation.
/// In the compare view each verse also carries the other versions of it, one
/// after another under the first.
class ChapterVerseList extends StatefulWidget {
  final List<BibleVerseEntity> verses;
  final List<BibleHighlightEntity> highlights;
  final ScrollController scrollController;
  final void Function(BibleVerseEntity verse)? onVerseLongPress;
  final void Function(BibleVerseEntity verse)? onVerseTap;
  final int? scrollToVerse;

  /// Verses the user has selected, drawn with a tint.
  final Set<int> selected;

  /// Room under the last verse, for the selection panel.
  final double bottomInset;

  /// Tags your notes have put on these verses, by verse number.
  final Map<int, Set<String>> verseTags;

  /// Opens the notes carrying [tagId].
  final void Function(String tagId)? onTagTap;

  /// Compare view: the name of the version [verses] is in, shown above its
  /// text. Null in the single-version view, where the text stands alone.
  final String? versionLabel;

  /// Compare view: the other versions of each verse, by verse number, in the
  /// order they are shown under [verses].
  final Map<int, List<VerseVersionText>> otherVersions;

  const ChapterVerseList({
    super.key,
    required this.verses,
    required this.highlights,
    required this.scrollController,
    this.onVerseLongPress,
    this.onVerseTap,
    this.scrollToVerse,
    this.selected = const {},
    this.bottomInset = 12,
    this.verseTags = const {},
    this.onTagTap,
    this.versionLabel,
    this.otherVersions = const {},
  });

  @override
  State<ChapterVerseList> createState() => _ChapterVerseListState();
}

class _ChapterVerseListState extends State<ChapterVerseList> {
  int? _flashingVerse;
  final Map<int, GlobalKey> _verseKeys = {};

  @override
  void initState() {
    super.initState();
    if (widget.scrollToVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToAndFlash(widget.scrollToVerse!);
      });
    }
  }

  @override
  void didUpdateWidget(ChapterVerseList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scrollToVerse != oldWidget.scrollToVerse &&
        widget.scrollToVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToAndFlash(widget.scrollToVerse!);
      });
    }
  }

  void _scrollToAndFlash(int verseNumber) {
    final key = _verseKeys[verseNumber];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.3,
      );
    }
    setState(() => _flashingVerse = verseNumber);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _flashingVerse = null);
    });
  }

  /// Find the highlight covering a given verse number.
  BibleHighlightEntity? _findHighlight(int verseNumber) {
    for (final h in widget.highlights) {
      if (h.coversVerse(verseNumber)) return h;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.verses.isEmpty) {
      return Center(
        child: Text(
          l10n(context).noVersesAvailable,
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      controller: widget.scrollController,
      padding: EdgeInsets.fromLTRB(16, 12, 16, widget.bottomInset),
      itemCount: widget.verses.length,
      itemBuilder: (context, index) {
        final verse = widget.verses[index];
        final highlight = _findHighlight(verse.verse);
        final isFlashing = _flashingVerse == verse.verse;

        // Ensure a key exists for scroll-to support
        _verseKeys.putIfAbsent(verse.verse, () => GlobalKey());

        return _VerseRow(
          key: _verseKeys[verse.verse],
          verse: verse,
          highlight: highlight,
          isFlashing: isFlashing,
          isSelected: widget.selected.contains(verse.verse),
          tagIds: widget.verseTags[verse.verse] ?? const {},
          versionLabel: widget.versionLabel,
          others: widget.otherVersions[verse.verse] ?? const [],
          onTagTap: widget.onTagTap,
          onTap: widget.onVerseTap != null
              ? () => widget.onVerseTap!(verse)
              : null,
          onLongPress: widget.onVerseLongPress != null
              ? () => widget.onVerseLongPress!(verse)
              : null,
        );
      },
    );
  }
}

/// One version's wording of a verse, for the compare view. [text] is null where
/// that version has no such verse.
class VerseVersionText {
  final String label;
  final String? text;

  const VerseVersionText(this.label, this.text);
}

/// A single verse row with optional highlight background.
class _VerseRow extends ConsumerWidget {
  final BibleVerseEntity verse;
  final String? versionLabel;
  final List<VerseVersionText> others;
  final Set<String> tagIds;
  final void Function(String tagId)? onTagTap;
  final BibleHighlightEntity? highlight;
  final bool isFlashing;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _VerseRow({
    super.key,
    required this.verse,
    this.versionLabel,
    this.others = const [],
    this.highlight,
    this.isFlashing = false,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
    this.tagIds = const {},
    this.onTagTap,
  });

  /// Tags on this verse, under it and to the right.
  ///
  /// Each one is its own tap target: the row's GestureDetector opens the
  /// highlight sheet and would otherwise swallow the tap.
  Widget _buildTags(BuildContext context, WidgetRef ref) {
    if (tagIds.isEmpty) return const SizedBox.shrink();

    final names = {
      for (final t in ref.watch(tagsStreamProvider).valueOrNull ?? const [])
        t.id: t.name,
    };
    // A tag whose name has not arrived is skipped rather than shown as an id.
    final shown = tagIds.where((id) => names[id] != null).toList()..sort();
    if (shown.isEmpty) return const SizedBox.shrink();

    // A highlight repaints the row in a pastel that the usual ink would
    // disappear into, so the tag follows the verse text's own colour there.
    final ink = highlight != null
        ? AppTheme.onHighlight
        : AppTheme.inkOnTintFor(
            AppTheme.brandPurple, Theme.of(context).brightness);

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 2,
        children: [
          for (final id in shown)
            Semantics(
              button: onTagTap != null,
              label: names[id],
              child: GestureDetector(
                onTap: onTagTap == null ? null : () => onTagTap!(id),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_offer_outlined, size: 12, color: ink),
                    const SizedBox(width: 2),
                    // Capped and ellipsised. A span gets the line's
                    // remaining width, but its child does not inherit that
                    // bound — a long tag name still ran the row off the
                    // edge. Half the screen is always narrower than the
                    // paragraph, so a tag that needs more simply wraps to
                    // its own line and truncates there.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.5,
                    ),
                    child: Text(
                      names[id]!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.tiny.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A version's name (when comparing) and its wording of this verse.
  Widget _versionBlock(
    BuildContext context,
    double bodySize, {
    required String? label,
    required String? text,
  }) {
    final theme = Theme.of(context);
    // A highlight paints a light pastel behind the verse in both themes, so the
    // text must go dark when one is present. Following colorScheme.onSurface
    // here would put near-white text on pale yellow in dark mode — 1.08:1,
    // unreadable.
    final ink = highlight != null
        ? AppTheme.onHighlight
        : theme.colorScheme.onSurface;
    final muted = highlight != null
        ? AppTheme.onHighlight
        : theme.colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 1),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: muted,
              ),
            ),
          ),
        Text(
          text ?? l10n(context).bibleVersionNotAvailable,
          style: TextStyle(
            fontSize: bodySize,
            height: 1.6,
            fontStyle: text == null ? FontStyle.italic : FontStyle.normal,
            color: text == null ? muted : ink,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bodySize = ref.watch(readingFontSizeProvider);
    final numberSize = ref.watch(verseNumberFontSizeProvider);
    final hasVerseNote = ref
            .watch(chapterNotedVersesProvider(
                (bookId: verse.bookId, chapter: verse.chapter)))
            .valueOrNull
            ?.contains(verse.verse) ??
        false;

    Color? bgColor;
    if (highlight != null) {
      bgColor = highlight!.color.backgroundColor;
    } else if (isSelected) {
      bgColor = theme.colorScheme.primary.withAlpha(48);
    } else if (isFlashing) {
      bgColor = theme.colorScheme.primary.withAlpha(30);
    }

    return Semantics(
      button: true,
      child: GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: context.motion(const Duration(milliseconds: 300)),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
          // A highlighted verse that is also selected keeps its colour and
          // gets an outline, so the selection still shows.
          border: isSelected && highlight != null
              ? Border.all(color: AppTheme.onHighlight, width: 2)
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Verse number
            SizedBox(
              // Sized from the text, not a fixed 28px: a 3-digit verse number
              // at the largest reading size overflows a fixed gutter.
              width: numberSize * 2.2,
              child: Text(
                '${verse.verse}',
                style: TextStyle(
                  fontSize: numberSize,
                  fontWeight: FontWeight.w600,
                  color: highlight != null
                      ? AppTheme.onHighlight
                      : theme.colorScheme.primary,
                  height: 1.8,
                ),
              ),
            ),
            // Verse text, with any tags under it at the right.
            //
            // Under, not beside: as a sibling in this Row the tags had no
            // width to share with the text, and two ordinary tag names on a
            // 320pt screen ran the row 222px off the edge. Below the verse
            // they are still at its end and still right-aligned, and they
            // wrap instead of overflowing.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The verse in each version being compared, one after another;
                  // just the one text when not comparing.
                  _versionBlock(context, bodySize,
                      label: others.isEmpty ? null : versionLabel,
                      text: verse.text),
                  for (final other in others) ...[
                    const SizedBox(height: 10),
                    _versionBlock(context, bodySize,
                        label: other.label, text: other.text),
                  ],
                  _buildTags(context, ref),
                ],
              ),
            ),
            // Note indicator: a note on the highlight, or any note written on
            // this verse from its sheet.
            if ((highlight != null && highlight!.hasNote) || hasVerseNote)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 4),
                child: Icon(
                  Icons.sticky_note_2_outlined,
                  size: 14,
                  // The dark ink belongs on a highlight's pastel only; on the
                  // plain page in the dark theme it was dark on dark.
                  color: highlight != null
                      ? AppTheme.onHighlight
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),

          ],
        ),
      ),
    ),
    );
  }
}
