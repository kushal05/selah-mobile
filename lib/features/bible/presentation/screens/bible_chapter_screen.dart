import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/navigation/routes.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/bible_highlight_entity.dart';
import '../../domain/models/bible_verse_entity.dart';
import '../providers/bible_chapter_providers.dart';
import '../providers/bible_providers.dart';
import '../widgets/chapter_verse_list.dart';
import '../widgets/highlight_bottom_sheet.dart';
import '../widgets/translation_selector.dart';

/// Full chapter reading screen with highlight support and parallel view.
///
/// Features:
/// - Displays all verses of a chapter
/// - Long-press to highlight with color + note
/// - Parallel translation toggle (split-screen, synced scroll)
/// - Previous/next chapter navigation
class BibleChapterScreen extends ConsumerStatefulWidget {
  final int bookId;
  final int chapter;
  final String initialTranslation;
  final int? scrollToVerse;

  const BibleChapterScreen({
    super.key,
    required this.bookId,
    required this.chapter,
    required this.initialTranslation,
    this.scrollToVerse,
  });

  @override
  ConsumerState<BibleChapterScreen> createState() =>
      _BibleChapterScreenState();
}

class _BibleChapterScreenState extends ConsumerState<BibleChapterScreen> {
  late int _bookId;
  late int _chapter;
  late String _primaryTranslation;
  late String _secondaryTranslation;
  bool _isParallel = false;

  final _primaryScrollController = ScrollController();
  final _secondaryScrollController = ScrollController();
  bool _isSyncingScroll = false;

  /// Bible tab accent colour.
  static const _bibleGreen = AppTheme.bibleGreen;

  @override
  void initState() {
    super.initState();
    _bookId = widget.bookId;
    _chapter = widget.chapter;
    _primaryTranslation = widget.initialTranslation;

    final translations = ref.read(bibleTranslationsProvider);
    _secondaryTranslation = translations.length > 1
        ? translations.firstWhere(
            (t) => t != _primaryTranslation,
            orElse: () => translations.first,
          )
        : translations.first;

    _primaryScrollController.addListener(_onPrimaryScroll);
    _secondaryScrollController.addListener(_onSecondaryScroll);

    // Log initial chapter view to reading history
    _logBibleReference();
  }

  @override
  void dispose() {
    _primaryScrollController.dispose();
    _secondaryScrollController.dispose();
    super.dispose();
  }

  // ── Scroll sync ──────────────────────────────────────────────────────

  void _onPrimaryScroll() {
    if (!_isParallel || _isSyncingScroll) return;
    _isSyncingScroll = true;
    _syncScroll(_primaryScrollController, _secondaryScrollController);
    _isSyncingScroll = false;
  }

  void _onSecondaryScroll() {
    if (!_isParallel || _isSyncingScroll) return;
    _isSyncingScroll = true;
    _syncScroll(_secondaryScrollController, _primaryScrollController);
    _isSyncingScroll = false;
  }

  void _syncScroll(ScrollController source, ScrollController target) {
    if (!source.hasClients || !target.hasClients) return;
    final maxExtent = source.position.maxScrollExtent;
    if (maxExtent == 0) return;
    final fraction = source.offset / maxExtent;
    final targetOffset =
        (fraction * target.position.maxScrollExtent).clamp(
      0.0,
      target.position.maxScrollExtent,
    );
    target.jumpTo(targetOffset);
  }

  // ── History logging ──────────────────────────────────────────────────

  void _logBibleReference() {
    try {
      final book = ref.read(bibleRepositoryProvider).getBookById(_bookId);
      final bookName = book?.name ?? 'Book $_bookId';
      final userId = ref.read(currentUserIdProvider);
      if (userId == 'default-user-id') return; // Not yet authenticated
      ref.read(bibleReferenceHistoryRepositoryProvider).logReference(
            userId: userId,
            book: bookName,
            chapter: _chapter,
            verseStart: widget.scrollToVerse,
            translation: _primaryTranslation,
          ).then((_) {}, onError: (_) {}); // Best-effort — never block UI
    } catch (_) {
      // Best-effort logging — never propagate errors
    }
  }

  // ── Chapter navigation ───────────────────────────────────────────────

  void _navigateToChapter(int bookId, int chapter) {
    setState(() {
      _bookId = bookId;
      _chapter = chapter;
    });
    // Reset scroll positions
    if (_primaryScrollController.hasClients) {
      _primaryScrollController.jumpTo(0);
    }
    if (_secondaryScrollController.hasClients) {
      _secondaryScrollController.jumpTo(0);
    }
    // Log navigated chapter to reading history
    _logBibleReference();
  }

  void _goToPreviousChapter() {
    final chapters = ref.read(bibleChaptersProvider(
      (bookId: _bookId, translation: _primaryTranslation),
    ));
    final currentIndex = chapters.indexOf(_chapter);
    if (currentIndex > 0) {
      _navigateToChapter(_bookId, chapters[currentIndex - 1]);
    } else {
      // Go to previous book's last chapter
      final books = ref.read(bibleBooksProvider);
      final bookIndex = books.indexWhere((b) => b.id == _bookId);
      if (bookIndex > 0) {
        final prevBook = books[bookIndex - 1];
        final prevChapters = ref.read(bibleChaptersProvider(
          (bookId: prevBook.id, translation: _primaryTranslation),
        ));
        if (prevChapters.isNotEmpty) {
          _navigateToChapter(prevBook.id, prevChapters.last);
        }
      }
    }
  }

  void _goToNextChapter() {
    final chapters = ref.read(bibleChaptersProvider(
      (bookId: _bookId, translation: _primaryTranslation),
    ));
    final currentIndex = chapters.indexOf(_chapter);
    if (currentIndex < chapters.length - 1) {
      _navigateToChapter(_bookId, chapters[currentIndex + 1]);
    } else {
      // Go to next book's first chapter
      final books = ref.read(bibleBooksProvider);
      final bookIndex = books.indexWhere((b) => b.id == _bookId);
      if (bookIndex < books.length - 1) {
        final nextBook = books[bookIndex + 1];
        final nextChapters = ref.read(bibleChaptersProvider(
          (bookId: nextBook.id, translation: _primaryTranslation),
        ));
        if (nextChapters.isNotEmpty) {
          _navigateToChapter(nextBook.id, nextChapters.first);
        }
      }
    }
  }

  // ── Highlights ───────────────────────────────────────────────────────

  void _showHighlightSheet(
    BibleVerseEntity verse,
    List<BibleHighlightEntity> highlights,
  ) {
    final book = ref.read(bibleRepositoryProvider).getBookById(_bookId);
    final bookName = book?.name ?? 'Book $_bookId';
    final reference = '$bookName ${verse.chapter}:${verse.verse}';

    // Check if this verse is already highlighted
    BibleHighlightEntity? existing;
    for (final h in highlights) {
      if (h.coversVerse(verse.verse)) {
        existing = h;
        break;
      }
    }

    HighlightBottomSheet.show(
      context,
      reference: reference,
      verseText: verse.text,
      existingHighlight: existing,
      onSave: (color, note) {
        final repo = ref.read(bibleHighlightRepositoryProvider);
        if (existing != null) {
          repo.updateHighlight(existing.copyWithUpdate(
            color: color,
            note: note,
          ));
        } else {
          repo.createHighlight(
            bookId: _bookId,
            chapter: _chapter,
            verseStart: verse.verse,
            verseEnd: verse.verse,
            color: color,
            note: note,
          );
        }
      },
      onRemove: existing != null
          ? () {
              ref
                  .read(bibleHighlightRepositoryProvider)
                  .deleteHighlight(existing!.id);
            }
          : null,
      onSaveToPromises: (ref_, text) => _saveAsPromise(ref_, text),
      onSaveToNotes: (ref_, text) => _openInNotes(ref_),
    );
  }

  Future<void> _saveAsPromise(String reference, String verseText) async {
    try {
      final userId = ref.read(currentUserIdProvider);
      await ref.read(promiseRepositoryProvider).createPromise(
            userId: userId,
            reference: reference,
            content: verseText,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved "$reference" as a promise'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save promise'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _openInNotes(String reference) {
    final encoded = Uri.encodeComponent(reference);
    context.push('${Routes.notesHome}/new?initialTitle=$encoded');
  }

  // ── Bookmarks ────────────────────────────────────────────────────────

  Future<void> _toggleBookmark(String bookName) async {
    try {
      await ref.read(bibleBookmarkRepositoryProvider).toggleBookmark(
            bookId: _bookId,
            bookName: bookName,
            chapter: _chapter,
            translation: _primaryTranslation,
          );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update bookmark'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final parentTheme = Theme.of(context);
    final book = ref.watch(bibleRepositoryProvider).getBookById(_bookId);
    final bookName = book?.name ?? 'Book $_bookId';
    final translations = ref.watch(bibleTranslationsProvider);
    final highlightsAsync = ref.watch(
      chapterHighlightsProvider((bookId: _bookId, chapter: _chapter)),
    );
    final highlights = highlightsAsync.valueOrNull ?? [];
    final isBookmarked = ref
        .watch(isChapterBookmarkedProvider((bookId: _bookId, chapter: _chapter)))
        .valueOrNull ?? false;

    final primaryVerses = ref.watch(bibleVersesProvider(
      (bookId: _bookId, chapter: _chapter, translation: _primaryTranslation),
    ));

    final theme = parentTheme.copyWith(
      colorScheme: parentTheme.colorScheme.copyWith(
        primary: _bibleGreen,
        onPrimary: Colors.white,
        secondaryContainer: AppTheme.bibleBackground,
        onSecondaryContainer: AppTheme.bibleForeground,
      ),
    );

    final canParallel = translations.length > 1;

    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: parentTheme.scaffoldBackgroundColor,
          elevation: 0,
          title: Text(
            '$bookName $_chapter',
            style: AppTheme.headingMedium,
          ),
          actions: [
            // Translation selector (primary)
            if (!_isParallel)
              Padding(
                padding: const EdgeInsets.only(right: AppTheme.spacing4),
                child: TranslationSelector(
                  currentTranslation: _primaryTranslation,
                  availableTranslations: translations,
                  onChanged: (t) =>
                      setState(() => _primaryTranslation = t),
                ),
              ),
            // Bookmark toggle
            IconButton(
              icon: Icon(
                isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                color: isBookmarked ? _bibleGreen : null,
              ),
              tooltip: isBookmarked ? 'Remove bookmark' : 'Bookmark chapter',
              onPressed: () => _toggleBookmark(bookName),
            ),
            // Parallel toggle
            IconButton(
              icon: Icon(
                _isParallel ? Icons.view_agenda : Icons.view_column,
              ),
              tooltip: _isParallel ? 'Single view' : 'Parallel view',
              onPressed: canParallel
                  ? () => setState(() => _isParallel = !_isParallel)
                  : null,
            ),
          ],
        ),
        body: Stack(
          children: [
            _isParallel
                ? _buildParallelView(
                    theme, primaryVerses, highlights, translations)
                : ChapterVerseList(
                    verses: primaryVerses,
                    highlights: highlights,
                    scrollController: _primaryScrollController,
                    scrollToVerse: widget.scrollToVerse,
                    onVerseLongPress: (verse) =>
                        _showHighlightSheet(verse, highlights),
                  ),
            // Floating prev/next navigation
            Positioned(
              left: AppTheme.spacing16,
              bottom: AppTheme.spacing24,
              child: _NavButton(
                heroTag: 'prev_chapter',
                icon: Icons.chevron_left,
                onPressed: _goToPreviousChapter,
                color: theme.colorScheme.onSurface,
              ),
            ),
            Positioned(
              right: AppTheme.spacing16,
              bottom: AppTheme.spacing24,
              child: _NavButton(
                heroTag: 'next_chapter',
                icon: Icons.chevron_right,
                onPressed: _goToNextChapter,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParallelView(
    ThemeData theme,
    List<BibleVerseEntity> primaryVerses,
    List<BibleHighlightEntity> highlights,
    List<String> translations,
  ) {
    final secondaryVerses = ref.watch(bibleVersesProvider(
      (
        bookId: _bookId,
        chapter: _chapter,
        translation: _secondaryTranslation,
      ),
    ));

    return Row(
      children: [
        // Primary (left) column
        Expanded(
          child: Column(
            children: [
              _TranslationHeader(
                translation: _primaryTranslation,
                availableTranslations: translations,
                onChanged: (t) =>
                    setState(() => _primaryTranslation = t),
              ),
              Expanded(
                child: ChapterVerseList(
                  verses: primaryVerses,
                  highlights: highlights,
                  scrollController: _primaryScrollController,
                  onVerseLongPress: (verse) =>
                      _showHighlightSheet(verse, highlights),
                ),
              ),
            ],
          ),
        ),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: theme.colorScheme.outlineVariant,
        ),
        // Secondary (right) column
        Expanded(
          child: Column(
            children: [
              _TranslationHeader(
                translation: _secondaryTranslation,
                availableTranslations: translations,
                onChanged: (t) =>
                    setState(() => _secondaryTranslation = t),
              ),
              Expanded(
                child: ChapterVerseList(
                  verses: secondaryVerses,
                  highlights: highlights,
                  scrollController: _secondaryScrollController,
                  onVerseLongPress: (verse) =>
                      _showHighlightSheet(verse, highlights),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  final String heroTag;
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;

  const _NavButton({
    required this.heroTag,
    required this.icon,
    required this.onPressed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Icon(icon, size: 20, color: color.withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}

/// Translation label header for each column in parallel view.
class _TranslationHeader extends StatelessWidget {
  final String translation;
  final List<String> availableTranslations;
  final ValueChanged<String> onChanged;

  const _TranslationHeader({
    required this.translation,
    required this.availableTranslations,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing12, vertical: AppTheme.spacing8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          TranslationSelector(
            currentTranslation: translation,
            availableTranslations: availableTranslations,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
