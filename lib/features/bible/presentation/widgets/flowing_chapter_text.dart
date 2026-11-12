import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/reading_preferences.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/l10n.dart';
import '../../data/bible_paragraph_data.dart';
import '../../domain/models/bible_highlight_entity.dart';
import '../../domain/models/bible_verse_entity.dart';
import '../providers/bible_chapter_providers.dart';
import '../providers/bible_reader_preferences.dart';

/// A chapter set as a page of text: the verses run on one after another with a
/// small raised number in front of each, instead of one row per verse.
///
/// Tapping a verse selects it (and unselects it again). Highlights are a
/// background on the verse's own words, a note is marked by a small icon after
/// the verse, and a tag by its name, which opens the notes carrying it.
class FlowingChapterText extends ConsumerStatefulWidget {
  /// What stands above the text: the chapter's title.
  final Widget header;
  final int bookId;
  final int chapter;
  final List<BibleVerseEntity> verses;
  final List<BibleHighlightEntity> highlights;
  final Set<int> selected;
  final ScrollController scrollController;
  final int? scrollToVerse;

  /// Room under the text, for the selection panel that may cover it.
  final double bottomInset;

  /// Tags your notes have put on these verses, by verse number.
  final Map<int, Set<String>> verseTags;
  final void Function(String tagId)? onTagTap;
  final void Function(BibleVerseEntity verse) onVerseTap;

  const FlowingChapterText({
    super.key,
    required this.header,
    required this.bookId,
    required this.chapter,
    required this.verses,
    required this.highlights,
    required this.selected,
    required this.scrollController,
    required this.onVerseTap,
    this.scrollToVerse,
    this.bottomInset = 96,
    this.verseTags = const {},
    this.onTagTap,
  });

  @override
  ConsumerState<FlowingChapterText> createState() => _FlowingChapterTextState();
}

class _FlowingChapterTextState extends ConsumerState<FlowingChapterText> {
  final _textKey = GlobalKey();
  /// One recogniser per verse (and per tag on it), kept between builds. They
  /// were disposed and rebuilt on every build, so a rebuild in the middle of a
  /// tap (a stream update, the flash timer) cancelled that tap.
  final _recognizers = <String, TapGestureRecognizer>{};

  TapGestureRecognizer _tap(String key, VoidCallback onTap) =>
      (_recognizers[key] ??= TapGestureRecognizer())..onTap = onTap;

  /// Where each verse starts in the text, for scrolling to it.
  final _offsets = <int, int>{};
  int? _flashingVerse;

  @override
  void initState() {
    super.initState();
    if (widget.scrollToVerse != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollToAndFlash(widget.scrollToVerse!));
    }
  }

  @override
  void didUpdateWidget(FlowingChapterText old) {
    super.didUpdateWidget(old);
    if (widget.scrollToVerse != null &&
        widget.scrollToVerse != old.scrollToVerse) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollToAndFlash(widget.scrollToVerse!));
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers.values) {
      r.dispose();
    }
    _recognizers.clear();
  }

  void _scrollToAndFlash(int verse) {
    final offset = _offsets[verse];
    final render = _textKey.currentContext?.findRenderObject();
    if (offset != null && render is RenderParagraph && mounted) {
      final caret = render.getOffsetForCaret(TextPosition(offset: offset), Rect.zero);
      final scrollable = Scrollable.maybeOf(_textKey.currentContext!);
      final viewport = scrollable?.context.findRenderObject();
      if (viewport is RenderBox) {
        final top = render.localToGlobal(Offset.zero, ancestor: viewport).dy;
        final target = widget.scrollController.offset +
            top +
            caret.dy -
            viewport.size.height * 0.3;
        widget.scrollController.animateTo(
          target.clamp(0.0, widget.scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
    setState(() => _flashingVerse = verse);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _flashingVerse = null);
    });
  }

  BibleHighlightEntity? _highlightFor(int verse) {
    for (final h in widget.highlights) {
      if (h.coversVerse(verse)) return h;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodySize = ref.watch(readingFontSizeProvider);
    final numberSize = ref.watch(verseNumberFontSizeProvider) * 0.78;
    final typeface = ref.watch(readerTypefaceProvider);
    final spacing = ref.watch(readerLineSpacingProvider);
    final showNumbers = ref.watch(readerShowVerseNumbersProvider);
    final noted = ref
            .watch(chapterNotedVersesProvider(
                (bookId: widget.bookId, chapter: widget.chapter)))
            .valueOrNull ??
        const <int>{};
    final tagNames = {
      for (final t in ref.watch(tagsStreamProvider).valueOrNull ?? const [])
        t.id: t.name,
    };

    _offsets.clear();

    // Where paragraphs open; one block until the data is read, and when it is missing.
    final paragraphStarts = (ref.watch(bibleParagraphDataProvider).valueOrNull ??
            BibleParagraphData.empty)
        .startsFor(widget.bookId, widget.chapter);

    final base = TextStyle(
      fontSize: bodySize,
      height: spacing.height,
      fontFamily: typeface.family,
      fontFamilyFallback: typeface.fallback,
      color: theme.colorScheme.onSurface,
    );

    final spans = <InlineSpan>[];
    var at = 0; // plain-text offset: a WidgetSpan counts as one character

    for (final verse in widget.verses) {
      final n = verse.verse;
      // A paragraph ends the line and leaves a short gap: a second, half-size
      // line break. Both count as characters for the verse offsets below.
      if (spans.isNotEmpty && paragraphStarts.contains(n)) {
        spans.add(const TextSpan(text: '\n'));
        spans.add(TextSpan(
          text: '\n',
          style: TextStyle(fontSize: bodySize * 0.5, height: 1),
        ));
        at += 2;
      }
      final highlight = _highlightFor(n);
      final isSelected = widget.selected.contains(n);
      final isFlashing = _flashingVerse == n;
      _offsets[n] = at;

      final tap = _tap('v$n', () => widget.onVerseTap(verse));
      // On a highlight the words are dark on a pastel, so the underline that
      // marks a selection (or a jump to the verse) is dark too: the accent
      // colour is a pale green on the dark pages and vanishes on the pastel.
      final marked = isSelected || (isFlashing && highlight != null);

      Color? background;
      if (highlight != null) {
        background = highlight.color.backgroundColor;
      } else if (isSelected || isFlashing) {
        background = theme.colorScheme.primary.withAlpha(isSelected ? 48 : 30);
      }
      // A highlight is a pastel in both themes, so its text goes dark.
      final ink = highlight != null ? AppTheme.onHighlight : null;
      // The number, the note marker and the tags sit between the verses, off
      // the highlight's pastel, so they keep the page's own colours. Only the
      // verse's words are painted on the highlight and go dark.
      final accent = theme.colorScheme.primary;

      if (showNumbers) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.top,
          child: Semantics(
            button: true,
            selected: isSelected,
            label: l10n(context).noteOnVerse('$n'),
            excludeSemantics: true,
            onTap: () => widget.onVerseTap(verse),
            child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onVerseTap(verse),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, end: 3),
              child: Text(
                '$n',
                style: TextStyle(
                  fontSize: numberSize,
                  fontWeight: FontWeight.w700,
                  color: accent,
                  height: 1.1,
                  fontFamily: null,
                ),
              ),
            ),
          ),
          ),
        ));
        at += 1;
      }

      final text = '${verse.text} ';
      spans.add(TextSpan(
        text: text,
        recognizer: tap,
        style: TextStyle(
          color: ink,
          backgroundColor: background,
          decoration: marked ? TextDecoration.underline : null,
          decorationColor:
              highlight != null ? AppTheme.onHighlight : theme.colorScheme.primary,
          decorationThickness: 2,
        ),
      ));
      at += text.length;

      if (noted.contains(n)) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(
              Icons.sticky_note_2_outlined,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ));
        at += 1;
      }

      final tags = (widget.verseTags[n] ?? const <String>{})
          .where((id) => tagNames[id] != null)
          .toList()
        ..sort();
      for (final id in tags) {
        final recognizer = _tap('t$n:$id', () => widget.onTagTap?.call(id));
        final label = '#${tagNames[id]} ';
        spans.add(TextSpan(
          text: label,
          recognizer: recognizer,
          semanticsLabel: tagNames[id],
          style: TextStyle(
            fontSize: bodySize * 0.72,
            fontWeight: FontWeight.w600,
            fontFamily: null,
            color: AppTheme.inkOnTintFor(
                AppTheme.brandPurple, theme.brightness),
          ),
        ));
        at += label.length;
      }
    }

    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: EdgeInsets.fromLTRB(22, 8, 22, widget.bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.header,
          if (widget.verses.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(
                l10n(context).noVersesAvailable,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            Text.rich(
              TextSpan(children: spans),
              key: _textKey,
              style: base,
            ),
        ],
      ),
    );
  }
}
