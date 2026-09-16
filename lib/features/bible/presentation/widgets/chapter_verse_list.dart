import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/providers/sync_providers.dart';

import '../../../../core/providers/reading_preferences.dart';
import '../../domain/models/bible_highlight_entity.dart';
import '../../domain/models/bible_verse_entity.dart';
import '../../../../core/providers/motion_preferences.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/l10n.dart';

/// Displays all verses of a Bible chapter in a scrollable list.
///
/// Reusable by both single and parallel reading modes.
/// Renders highlight backgrounds and supports long-press for highlight creation.
class ChapterVerseList extends StatefulWidget {
  final List<BibleVerseEntity> verses;
  final List<BibleHighlightEntity> highlights;
  final ScrollController scrollController;
  final void Function(BibleVerseEntity verse)? onVerseLongPress;
  final void Function(BibleVerseEntity verse)? onVerseTap;
  final int? scrollToVerse;

  /// Tags your notes have put on these verses, by verse number.
  final Map<int, Set<String>> verseTags;

  /// Opens the notes carrying [tagId].
  final void Function(String tagId)? onTagTap;

  /// Whether this column shows verse tags.
  ///
  /// Parallel view renders this widget twice side by side. The tags belong to
  /// the verse rather than to a translation, so showing them in both columns
  /// would put two controls on screen for the same thing; the primary column
  /// carries them.
  final bool showVerseTags;

  const ChapterVerseList({
    super.key,
    required this.verses,
    required this.highlights,
    required this.scrollController,
    this.onVerseLongPress,
    this.onVerseTap,
    this.scrollToVerse,
    this.verseTags = const {},
    this.onTagTap,
    this.showVerseTags = true,
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
          tagIds: widget.showVerseTags
              ? (widget.verseTags[verse.verse] ?? const {})
              : const {},
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

/// A single verse row with optional highlight background.
class _VerseRow extends ConsumerWidget {
  final BibleVerseEntity verse;
  final Set<String> tagIds;
  final void Function(String tagId)? onTagTap;
  final BibleHighlightEntity? highlight;
  final bool isFlashing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _VerseRow({
    super.key,
    required this.verse,
    this.highlight,
    this.isFlashing = false,
    this.onTap,
    this.onLongPress,
    this.tagIds = const {},
    this.onTagTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bodySize = ref.watch(readingFontSizeProvider);
    final numberSize = ref.watch(verseNumberFontSizeProvider);

    Color? bgColor;
    if (isFlashing) {
      bgColor = theme.colorScheme.primary.withAlpha(30);
    } else if (highlight != null) {
      bgColor = highlight!.color.backgroundColor;
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
            // Verse text
            Expanded(
              child: Text(
                verse.text,
                style: TextStyle(
                  fontSize: bodySize,
                  height: 1.6,
                  // A highlight paints a light pastel behind the verse in both
                  // themes, so the text must go dark when one is present.
                  // Following colorScheme.onSurface here would put near-white
                  // text on pale yellow in dark mode — 1.08:1, unreadable.
                  color: highlight != null
                      ? AppTheme.onHighlight
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
            // Highlight note indicator
            if (highlight != null && highlight!.hasNote)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 4),
                child: Icon(
                  Icons.sticky_note_2_outlined,
                  size: 14,
                  color: AppTheme.onHighlight,
                ),
              ),
            if (tagIds.isNotEmpty)
              _VerseTags(
                tagIds: tagIds,
                onTagTap: onTagTap,
                onHighlight: highlight != null,
              ),
          ],
        ),
      ),
    ),
    );
  }
}

/// Tags on a verse, at the end of the line.
///
/// Each tag is its own tap target. The row around it already has a
/// GestureDetector that opens the highlight sheet and would otherwise swallow
/// the tap, so this sits in its own gesture scope.
class _VerseTags extends ConsumerWidget {
  final Set<String> tagIds;
  final void Function(String tagId)? onTagTap;

  /// Whether the verse is highlighted, which repaints the row in a pastel that
  /// the usual ink would disappear into.
  final bool onHighlight;

  const _VerseTags({
    required this.tagIds,
    required this.onTagTap,
    required this.onHighlight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = {
      for (final t in ref.watch(tagsStreamProvider).valueOrNull ?? const [])
        t.id: t.name,
    };
    final shown = tagIds.where((id) => names[id] != null).toList()..sort();
    if (shown.isEmpty) return const SizedBox.shrink();

    final ink = onHighlight
        ? AppTheme.onHighlight
        : AppTheme.inkOnTintFor(
            AppTheme.brandPurple, Theme.of(context).brightness);

    return Padding(
      padding: const EdgeInsets.only(left: 6, top: 3),
      child: Wrap(
        spacing: 4,
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
                    Text(
                      names[id]!,
                      style: AppTheme.tiny.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w600,
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
}
