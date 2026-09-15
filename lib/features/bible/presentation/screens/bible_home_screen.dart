import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/navigation/routes.dart';
import 'bible_version_onboarding_screen.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/bible_book_entity.dart';
import '../providers/bible_chapter_providers.dart';
import '../providers/bible_providers.dart';
import '../../../../shared/widgets/feature_intro.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';

class BibleHomeScreen extends ConsumerStatefulWidget {
  const BibleHomeScreen({super.key});

  @override
  ConsumerState<BibleHomeScreen> createState() => _BibleHomeScreenState();
}

class _BibleHomeScreenState extends ConsumerState<BibleHomeScreen> {
  BibleBookEntity? _selectedBook;

  static const _bibleGreen = AppTheme.teal;

  static const _chipColors = [
    Color(0xFF6366F1), Color(0xFF10B981), Color(0xFFF59E0B), Color(0xFFEF4444),
    Color(0xFF8B5CF6), Color(0xFF06B6D4), Color(0xFFF97316), Color(0xFF84CC16),
  ];

  static const _bookAbbreviations = {
    'Genesis': 'Gen', 'Exodus': 'Exo', 'Leviticus': 'Lev', 'Numbers': 'Num',
    'Deuteronomy': 'Deu', 'Joshua': 'Jos', 'Judges': 'Jdg', 'Ruth': 'Rut',
    '1 Samuel': '1Sa', '2 Samuel': '2Sa', '1 Kings': '1Ki', '2 Kings': '2Ki',
    '1 Chronicles': '1Ch', '2 Chronicles': '2Ch', 'Ezra': 'Ezr', 'Nehemiah': 'Neh',
    'Esther': 'Est', 'Job': 'Job', 'Psalms': 'Psa', 'Proverbs': 'Pro',
    'Ecclesiastes': 'Ecc', 'Song of Solomon': 'Sng', 'Isaiah': 'Isa', 'Jeremiah': 'Jer',
    'Lamentations': 'Lam', 'Ezekiel': 'Eze', 'Daniel': 'Dan', 'Hosea': 'Hos',
    'Joel': 'Joe', 'Amos': 'Amo', 'Obadiah': 'Oba', 'Jonah': 'Jon',
    'Micah': 'Mic', 'Nahum': 'Nah', 'Habakkuk': 'Hab', 'Zephaniah': 'Zep',
    'Haggai': 'Hag', 'Zechariah': 'Zec', 'Malachi': 'Mal',
    'Matthew': 'Mat', 'Mark': 'Mar', 'Luke': 'Luk', 'John': 'Joh',
    'Acts': 'Act', 'Romans': 'Rom', '1 Corinthians': '1Co', '2 Corinthians': '2Co',
    'Galatians': 'Gal', 'Ephesians': 'Eph', 'Philippians': 'Php', 'Colossians': 'Col',
    '1 Thessalonians': '1Th', '2 Thessalonians': '2Th', '1 Timothy': '1Ti', '2 Timothy': '2Ti',
    'Titus': 'Tit', 'Philemon': 'Phm', 'Hebrews': 'Heb', 'James': 'Jas',
    '1 Peter': '1Pe', '2 Peter': '2Pe', '1 John': '1Jo', '2 John': '2Jo',
    '3 John': '3Jo', 'Jude': 'Jud', 'Revelation': 'Rev',
  };

  void _onChapterTap(int bookId, int chapter) {
    final translation = ref.read(defaultBibleVersionProvider);
    // push, not go: opening a chapter is going *into* something, and go
    // replaces the stack so the reader had no way back to the book list.
    context.push(
      '${Routes.bible}/chapter'
      '?bookId=$bookId'
      '&chapter=$chapter'
      '&translation=$translation',
    );
  }

  @override
  Widget build(BuildContext context) {
    final parentTheme = Theme.of(context);
    final otBooks = ref.watch(bibleOldTestamentBooksProvider);
    final ntBooks = ref.watch(bibleNewTestamentBooksProvider);
    final dbOpen = ref.watch(bibleDatabaseServiceProvider).isOpen;

    final theme = parentTheme.copyWith(
      colorScheme: parentTheme.colorScheme.copyWith(
        primary: _bibleGreen,
        onPrimary: Colors.white,
        secondaryContainer: AppTheme.bibleBackground,
        onSecondaryContainer: AppTheme.bibleForeground,
      ),
    );

    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: parentTheme.scaffoldBackgroundColor,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: Text(
            l10n(context).navBible,
            style: parentTheme.textTheme.titleLarge?.copyWith(
              color: parentTheme.colorScheme.onSurface,
            ),
          ),
          actions: [
            if (dbOpen)
              IconButton(
                icon: const Icon(Icons.download_for_offline_outlined),
                tooltip: l10n(context).manageBibleVersions,
                onPressed: () => context.push(Routes.bibleVersions),
              ),
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: l10n(context).readingHistory,
              onPressed: () => context.push(Routes.bibleHistory),
            ),
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: l10n(context).searchBible,
              onPressed: () => context.push(Routes.bibleSearch),
            ),
          ],
        ),
        // One scroll view for the whole page. This was a fixed Column, so the
        // 66 book chips and the intro above them could not be scrolled to —
        // on a shorter screen (or at a large text size) the lower testament
        // was simply unreachable, and only the chapter grid scrolled.
        body: !dbOpen
            ? BibleVersionOnboardingScreen(onComplete: () {})
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: FeatureIntros.bible,
                        ),
                        // Bookmarks strip
                        _buildBookmarksStrip(theme),
                        // Book chips
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppTheme.spacing16, AppTheme.spacing12,
                            AppTheme.spacing16, AppTheme.spacing4,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildTestamentChips('Old Testament', otBooks, 0,
                                  parentTheme.colorScheme),
                              const SizedBox(height: AppTheme.spacing12),
                              _buildTestamentChips('New Testament', ntBooks, 39,
                                  parentTheme.colorScheme),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Chapter grid
                  if (_selectedBook != null)
                    ..._buildChapterSlivers(_selectedBook!, theme, parentTheme)
                  else
                    SliverFillRemaining(
                      // Centres in the leftover space when there is any, and
                      // falls back to its own height when the chips already
                      // fill the viewport.
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.spacing16,
                            vertical: AppTheme.spacing24,
                          ),
                          child: Text(
                            l10n(context).selectABookToBrowseChapters,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: parentTheme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildBookmarksStrip(ThemeData theme) {
    final bookmarksAsync = ref.watch(bibleBookmarksProvider);
    final bookmarks = bookmarksAsync.valueOrNull ?? [];
    if (bookmarks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.spacing16, AppTheme.spacing12,
            AppTheme.spacing16, AppTheme.spacing4,
          ),
          child: Row(
            children: [
              Icon(Icons.bookmark, size: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
              const SizedBox(width: 4),
              Text(
                l10n(context).bookmarks,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing16),
            itemCount: bookmarks.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final bm = bookmarks[index];
              return GestureDetector(
                onTap: () => _onChapterTap(bm.bookId, bm.chapter),
                onLongPress: () async {
                  try {
                    await ref
                        .read(bibleBookmarkRepositoryProvider)
                        .deleteBookmark(bm.id);
                  } catch (_) {
                    // Best-effort — bookmark remains if delete fails
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacing12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _bibleGreen.withValues(alpha: 0.1),
                    borderRadius: AppTheme.borderRadiusMD,
                    border: Border.all(
                        color: _bibleGreen.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '${bm.bookName} ${bm.chapter}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _bibleGreen,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppTheme.spacing8),
        Divider(color: context.hairline, height: 1),
      ],
    );
  }

  Widget _buildTestamentChips(
    String label,
    List<BibleBookEntity> books,
    int indexOffset,
    ColorScheme cs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: cs.onSurface.withValues(alpha: 0.5),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: AppTheme.spacing8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: List.generate(books.length, (i) {
            final book = books[i];
            final isSelected = _selectedBook?.id == book.id;
            final abbr = _bookAbbreviations[book.name] ??
                book.name.substring(0, book.name.length.clamp(0, 3));
            final color = _chipColors[(indexOffset + i) % _chipColors.length];

            return FilterChip(
              label: Text(abbr),
              selected: isSelected,
              onSelected: (_) => setState(() {
                _selectedBook = isSelected ? null : book;
              }),
              showCheckmark: false,
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? color.withValues(alpha: 0.9) : color.withValues(alpha: 0.7),
              ),
              backgroundColor: color.withValues(alpha: 0.08),
              selectedColor: color.withValues(alpha: 0.38),
              side: BorderSide(
                color: isSelected ? color.withValues(alpha: 0.7) : color.withValues(alpha: 0.25),
                width: isSelected ? 1.8 : 1.0,
              ),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 2),
            );
          }),
        ),
      ],
    );
  }

  /// The book heading plus its chapter grid, as slivers so they scroll with
  /// the book chips above rather than in a nested scroll view of their own.
  List<Widget> _buildChapterSlivers(
    BibleBookEntity book,
    ThemeData theme,
    ThemeData parentTheme,
  ) {
    final translations = ref.watch(bibleTranslationsProvider);
    final translation = translations.isNotEmpty ? translations.first : 'KJV';
    final chapters = ref.watch(
      bibleChaptersProvider((bookId: book.id, translation: translation)),
    );

    return [
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppTheme.spacing8),
            Divider(color: parentTheme.dividerColor, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spacing16, AppTheme.spacing12,
                AppTheme.spacing16, AppTheme.spacing4,
              ),
              child: Text(
                book.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
      if (chapters.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: AppTheme.spacing24),
            child: Center(child: Text(l10n(context).noChaptersAvailable)),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.spacing16, AppTheme.spacing4,
            AppTheme.spacing16, AppTheme.spacing16,
          ),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: AppTheme.spacing6,
              crossAxisSpacing: AppTheme.spacing6,
              childAspectRatio: 1,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final chapter = chapters[index];
                return Semantics(
                  button: true,
                  label: '${book.name} chapter $chapter',
                  excludeSemantics: true,
                  onTap: () => _onChapterTap(book.id, chapter),
                  child: GestureDetector(
                    onTap: () => _onChapterTap(book.id, chapter),
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHigh,
                        borderRadius: AppTheme.borderRadiusMD,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$chapter',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                );
              },
              childCount: chapters.length,
            ),
          ),
        ),
    ];
  }

}

