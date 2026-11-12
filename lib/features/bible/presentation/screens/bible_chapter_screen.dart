import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/navigation/routes.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/selectable_chip.dart';
import '../../domain/models/bible_version_info.dart';
import '../../domain/models/bible_highlight_entity.dart';
import '../../domain/models/bible_verse_entity.dart';
import '../../domain/services/verse_selection.dart';
import '../../../../core/theme/theme_colors.dart';
import '../providers/bible_chapter_providers.dart';
import '../providers/verse_tag_providers.dart';
import '../providers/bible_providers.dart';
import '../providers/bible_reader_preferences.dart';
import '../widgets/add_verse_to_note_sheet.dart';
import '../widgets/chapter_verse_list.dart';
import '../widgets/chapter_picker_sheet.dart';
import '../widgets/flowing_chapter_text.dart';
import '../widgets/reader_settings_sheet.dart';
import '../widgets/verse_selection_panel.dart';
import '../widgets/translation_selector.dart';
import '../../../notes/domain/models/editor_block.dart';
import '../../../notes/domain/models/editor_document.dart';
import '../../../notes/domain/models/note.dart';
import '../../../notes/domain/services/bible_verse_block.dart';
import '../../../notes/presentation/providers/database_provider.dart';
import '../../../../l10n/l10n.dart';

/// Full chapter reading screen with highlight support and a compare view.
///
/// Features:
/// - Displays all verses of a chapter
/// - Long-press to highlight with color + note
/// - Compare versions: pick versions along the top and each verse shows them
///   one after another
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

  /// A verse to scroll to when the reader opens. Used once: moving to another
  /// chapter, or switching views, must not scroll to it again.
  int? _scrollToVerse;

  /// Compare view: several versions of each verse, one after another.
  bool _isComparing = false;

  /// The versions being compared, in the order they are shown.
  List<String> _compared = [];

  /// Verse numbers the user has selected; the panel acts on these.
  final Set<int> _selected = {};

  final _primaryScrollController = ScrollController();

  /// Bible tab accent colour.
  static const _bibleGreen = AppTheme.bibleGreen;

  @override
  void initState() {
    super.initState();
    _bookId = widget.bookId;
    _chapter = widget.chapter;
    _primaryTranslation = widget.initialTranslation;
    _scrollToVerse = widget.scrollToVerse;

    // Log initial chapter view to reading history
    _logBibleReference();
  }

  @override
  void dispose() {
    _primaryScrollController.dispose();
    super.dispose();
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
      _selected.clear();
      _scrollToVerse = null;
    });
    // Reset scroll positions
    if (_primaryScrollController.hasClients) {
      _primaryScrollController.jumpTo(0);
    }
    // Log navigated chapter to reading history
    _logBibleReference();
  }

  /// Opens the chapter picker from the title; on a result, jumps there.
  Future<void> _openChapterPicker(ThemeData theme) async {
    final choice = await showChapterPicker(
      context,
      theme: theme,
      bookId: _bookId,
      chapter: _chapter,
    );
    if (choice == null || !mounted) return;
    _navigateToChapter(choice.bookId, choice.chapter);
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

  // ── Versions ─────────────────────────────────────────────────────────

  /// Opens the versions screen. If the user picks a different default there,
  /// the reader switches to it on the way back. Only a change made on that
  /// screen counts, so a chapter opened in another version (from a note's
  /// verse, say) is not switched just because the default finished loading.
  Future<void> _openVersions() async {
    final before = ref.read(defaultBibleVersionProvider);
    await context.push(Routes.bibleVersions);
    if (!mounted) return;
    final chosen = ref.read(defaultBibleVersionProvider);
    if (chosen == before) return;
    final translations = ref.read(bibleTranslationsProvider);
    final match = translations
        .where((t) => t.toLowerCase() == chosen.toLowerCase())
        .firstOrNull;
    if (match == null) return; // chosen but not downloaded
    setState(() {
      _primaryTranslation = match;
      // Comparing: the chosen version leads, the rest follow.
      if (_isComparing) {
        _compared = [
          match,
          ..._compared.where((c) => c != match && translations.contains(c)),
        ];
      }
    });
  }

  // ── Compare ──────────────────────────────────────────────────────────

  /// Turns the compare view on or off. Turning it on starts with the version
  /// being read and one other.
  void _toggleCompare(List<String> translations) {
    setState(() {
      _isComparing = !_isComparing;
      _scrollToVerse = null;
      if (_isComparing) {
        final other = translations.firstWhere(
          (t) => t != _primaryTranslation,
          orElse: () => _primaryTranslation,
        );
        _compared = [
          _primaryTranslation,
          if (other != _primaryTranslation) other,
        ];
      }
    });
  }

  /// Adds a version to the comparison (at the end), or takes it out. One always
  /// stays.
  void _toggleComparedVersion(String code) {
    setState(() {
      if (_compared.contains(code)) {
        if (_compared.length > 1) _compared = [..._compared]..remove(code);
      } else {
        _compared = [..._compared, code];
      }
    });
  }

  // ── Selection and highlights ─────────────────────────────────────────

  void _toggleVerse(BibleVerseEntity verse) {
    setState(() {
      if (!_selected.remove(verse.verse)) _selected.add(verse.verse);
    });
  }

  void _clearSelection() {
    if (_selected.isEmpty) return;
    setState(_selected.clear);
  }

  /// "Genesis 1:4–6" for the selected verses.
  String _selectionReference(String bookName) =>
      '$bookName $_chapter:${formatVerses(_selected)}';

  /// The selected verses' text, in order, as one passage.
  String _selectionText(List<BibleVerseEntity> verses) => [
        for (final v in verses)
          if (_selected.contains(v.verse)) v.text,
      ].join(' ');

  /// Highlight writes run one after another. A second tap while one is still
  /// saving would otherwise be planned from the same stale list and write two
  /// updates at the same version.
  Future<void> _highlightQueue = Future.value();

  /// Makes every selected verse [color] (or clears them when it is null),
  /// leaving every other verse as it was. The selection stays, so a colour can
  /// be changed again.
  Future<void> _applyHighlight(HighlightColor? color) {
    final verses = {..._selected};
    final messenger = ScaffoldMessenger.of(context);
    final t = l10n(context);
    final repo = ref.read(bibleHighlightRepositoryProvider);
    final notes = ref.read(bibleVerseNoteRepositoryProvider);
    final bookId = _bookId;
    final chapter = _chapter;

    return _highlightQueue = _highlightQueue.then((_) async {
      try {
        // Read what is stored now, not what the screen last drew.
        final stored = await repo.getHighlightsForChapter(
            bookId: bookId, chapter: chapter);
        final plan =
            planHighlight(existing: stored, selected: verses, color: color);
        if (plan.isEmpty) return;
        await repo.applyPlan(plan,
            bookId: bookId, chapter: chapter, notes: notes);
      } catch (_) {
        messenger.showSnackBar(SnackBar(
          content: Text(color == null
              ? t.couldNotRemoveHighlight
              : t.couldNotSaveHighlight),
          behavior: SnackBarBehavior.floating,
        ));
      }
    });
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
            content: Text(l10n(context).savedReferenceAsPromise(reference)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n(context).couldNotSavePromise),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// "Add to notes": asks where, then puts the verse in the body of a new note
  /// or at the end of an existing one. Not in the title.
  Future<void> _addVerseToNote(String bookName) async {
    final target = await AddVerseToNoteSheet.show(context);
    if (target == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final t = l10n(context);
    final repo = ref.read(notesRepositoryProvider);
    final block = buildBibleVerseBlock(
      book: bookName,
      chapter: _chapter,
      verses: ([..._selected]..sort()),
      version: _primaryTranslation,
    );

    try {
      final chosen = target.note;
      if (chosen == null) {
        final note = Note.create(
          id: const Uuid().v4(),
          document: EditorDocument(
            blocks: [block, EditorBlock.paragraph()],
          ),
        );
        await repo.createNote(note);
        router.push(Routes.noteEditFor(note.id));
      } else {
        // Re-read: the list the user picked from may be a moment old.
        final current = await repo.getNoteById(chosen.id);
        if (current == null) throw StateError('note ${chosen.id} is gone');
        await repo.updateNote(current.copyWith(
          document: appendBlockAtEnd(current.document, block),
        ));
        messenger.showSnackBar(SnackBar(
          content: Text(t.addedVerseToNote(current.displayTitle)),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: Text(t.couldNotAddVerseToNote),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  // ── Tags ─────────────────────────────────────────────────────────────

  /// Opens the notes carrying [tagId].
  void _openNotesWithTag(String tagId) {
    context.push('${Routes.notesHome}?tagId=$tagId');
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final parentTheme = Theme.of(context);
    final book = ref.watch(bibleRepositoryProvider).getBookById(_bookId);
    final bookName = book?.name ?? 'Book $_bookId';
    final translations = ref.watch(bibleTranslationsProvider);
    final verseTags = ref.watch(
      chapterVerseTagsProvider((bookId: _bookId, chapter: _chapter)),
    );
    final highlightsAsync = ref.watch(
      chapterHighlightsProvider((bookId: _bookId, chapter: _chapter)),
    );
    // A failed read renders every verse unhighlighted, which does not look
    // like a failure — it looks like the highlights are gone. Say so instead.
    final highlightsFailed = highlightsAsync.hasError;
    final highlights = highlightsAsync.valueOrNull ?? [];

    // Comparing: the versions chosen, in order, that are still installed. The
    // first drives the list; the others are laid under each verse.
    final compared = [
      for (final c in _compared)
        if (translations.contains(c)) c,
    ];
    final comparing = _isComparing && compared.isNotEmpty;
    final listVersion = comparing ? compared.first : _primaryTranslation;
    final verses = ref.watch(bibleVersesProvider(
      (bookId: _bookId, chapter: _chapter, translation: listVersion),
    ));
    final otherVersions = <int, List<VerseVersionText>>{};
    if (comparing) {
      for (final code in compared.skip(1)) {
        final byVerse = {
          for (final v in ref.watch(bibleVersesProvider(
            (bookId: _bookId, chapter: _chapter, translation: code),
          )))
            v.verse: v.text,
        };
        for (final v in verses) {
          (otherVersions[v.verse] ??= []).add(
            VerseVersionText(bibleVersionDisplayName(code), byVerse[v.verse]),
          );
        }
      }
    }

    final autoTheme = parentTheme.copyWith(
      colorScheme: parentTheme.colorScheme.copyWith(
        primary: _bibleGreen,
        onPrimary: AppTheme.onAccent(_bibleGreen),
        // Brightness-aware: the light pair was applied in both themes, so the
        // translation pill came out a light green chip on a near-black bar.
        secondaryContainer: AppTheme.bibleSurfaceFor(parentTheme.brightness),
        onSecondaryContainer: AppTheme.bibleInkFor(parentTheme.brightness),
      ),
    );

    // The reader's own page colours (sepia, night...), or the app's theme.
    final theme = ref.watch(readerThemeProvider).apply(autoTheme);

    final canCompare = translations.length > 1;
    final selecting = _selected.isNotEmpty;
    // The panel can grow to 60% of the screen; keep the text scrollable above it.
    final panelRoom = MediaQuery.sizeOf(context).height * 0.6 + 24;
    final typeface = ref.watch(readerTypefaceProvider);

    final chapterHeader = Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$bookName $_chapter',
            style: TextStyle(
              fontSize: 28,
              height: 1.15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              fontFamily: typeface.family,
              fontFamilyFallback: typeface.fallback,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            bibleVersionDisplayName(_primaryTranslation),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    return Theme(
      data: theme,
      child: PopScope(
        // Back clears a selection before it leaves the chapter.
        canPop: !selecting,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _clearSelection();
        },
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: theme.scaffoldBackgroundColor,
            elevation: 0,
            titleSpacing: 12,
            // The chapter as a pill: tap to choose another. One line, the book
            // name shrinking before the chapter number does, so the chapter is
            // never the part that gets cut off.
            title: Align(
              alignment: Alignment.centerLeft,
              child: Material(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _openChapterPicker(theme),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            bookName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: AppTheme.bodyBase.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                        Text(
                          ' $_chapter',
                          maxLines: 1,
                          style: AppTheme.bodyBase.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                        Icon(Icons.expand_more,
                            size: 18,
                            color: theme.colorScheme.onSecondaryContainer),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              // Version pill: tap opens the downloader, long-press switches.
              if (!comparing)
                TranslationSelector(
                  currentTranslation: _primaryTranslation,
                  availableTranslations: translations,
                  onChanged: (t) => setState(() => _primaryTranslation = t),
                  onManage: _openVersions,
                ),
              IconButton(
                tooltip: l10n(context).readingSettings,
                icon: const Icon(Icons.text_fields_rounded),
                visualDensity: VisualDensity.compact,
                onPressed: () => showReaderSettingsSheet(context, theme: theme),
              ),
              // Compare and version management share one menu, to leave the
              // chapter pill the width it needs at 360dp.
              PopupMenuButton<String>(
                tooltip: l10n(context).moreOptions,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                onSelected: (v) {
                  switch (v) {
                    case 'compare':
                      _toggleCompare(translations);
                    case 'versions':
                      _openVersions();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'compare',
                    enabled: canCompare,
                    child: Text(comparing
                        ? l10n(context).singleVersion
                        : l10n(context).compareVersions),
                  ),
                  PopupMenuItem(
                    value: 'versions',
                    child: Text(l10n(context).bibleVersions),
                  ),
                ],
              ),
            ],
          ),
          body: Stack(
            children: [
              if (highlightsFailed)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Material(
                    color: AppTheme.warning.withValues(alpha: 0.12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacing16,
                          vertical: AppTheme.spacing8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n(context).highlightsCouldntBeLoaded,
                              style: AppTheme.caption
                                  .copyWith(color: context.warningText),
                            ),
                          ),
                          TextButton(
                            onPressed: () => ref.invalidate(
                              chapterHighlightsProvider(
                                  (bookId: _bookId, chapter: _chapter)),
                            ),
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: const Size(0, 32),
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(l10n(context).retry),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned.fill(
                child: Column(
                  children: [
                    // Compare view: pick the versions here, and they are laid
                    // out one after another under each verse.
                    if (comparing)
                      _CompareVersionsBar(
                        available: translations,
                        selected: compared,
                        onToggle: _toggleComparedVersion,
                      ),
                    Expanded(
                      child: comparing
                          ? ChapterVerseList(
                              verses: verses,
                              highlights: highlights,
                              selected: _selected,
                              verseTags: verseTags,
                              onTagTap: _openNotesWithTag,
                              scrollController: _primaryScrollController,
                              scrollToVerse: _scrollToVerse,
                              versionLabel:
                                  bibleVersionDisplayName(compared.first),
                              otherVersions: otherVersions,
                              bottomInset: selecting ? panelRoom : 12,
                              onVerseTap: _toggleVerse,
                              onVerseLongPress: _toggleVerse,
                            )
                          : FlowingChapterText(
                              header: chapterHeader,
                              bookId: _bookId,
                              chapter: _chapter,
                              verses: verses,
                              highlights: highlights,
                              selected: _selected,
                              verseTags: verseTags,
                              onTagTap: _openNotesWithTag,
                              scrollController: _primaryScrollController,
                              scrollToVerse: _scrollToVerse,
                              bottomInset: selecting ? panelRoom : 96,
                              onVerseTap: _toggleVerse,
                            ),
                    ),
                  ],
                ),
              ),
              if (!selecting) ...[
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
              if (selecting)
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10 + MediaQuery.paddingOf(context).bottom,
                  child: VerseSelectionPanel(
                    reference: _selectionReference(bookName),
                    bookId: _bookId,
                    chapter: _chapter,
                    selected: {..._selected},
                    highlights: highlights,
                    onColor: _applyHighlight,
                    onRemoveHighlight: () => _applyHighlight(null),
                    onClose: _clearSelection,
                    onSaveAsPromise: () => _saveAsPromise(
                        _selectionReference(bookName), _selectionText(verses)),
                    onAddToNotes: () => _addVerseToNote(bookName),
                  ),
                ),
            ],
          ),
        ),
      ),
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

/// The versions to compare, as chips along the top: tap to add one to the
/// comparison (it goes at the end) or to take it out. One always stays.
class _CompareVersionsBar extends StatelessWidget {
  final List<String> available;
  final List<String> selected;
  final ValueChanged<String> onToggle;

  const _CompareVersionsBar({
    required this.available,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: l10n(context).versionsToCompare,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.outlineVariant,
              width: 0.5,
            ),
          ),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacing16, vertical: AppTheme.spacing8),
          child: Row(
            children: [
              for (final code in available)
                Padding(
                  padding: const EdgeInsets.only(right: AppTheme.spacing8),
                  child: SelectableChip(
                    label: bibleVersionDisplayName(code),
                    accent: AppTheme.emerald,
                    isSelected: selected.contains(code),
                    onTap: () => onToggle(code),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
