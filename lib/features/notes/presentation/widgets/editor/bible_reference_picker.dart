import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../bible/domain/models/bible_version_info.dart';
import '../../../../bible/presentation/providers/bible_providers.dart';
import '../../../../bible/domain/models/bible_books.dart';

/// Tabbed Bible reference picker displayed as a dialog popup.
///
/// Flow: Select Book → Select Chapter → Select Verse(s) → OK
/// Version is configurable via the settings gear icon.
class BibleReferencePicker extends StatefulWidget {
  final String? defaultVersion;
  final void Function(BibleReferenceSelection selection) onSelect;

  const BibleReferencePicker({
    super.key,
    this.defaultVersion,
    required this.onSelect,
  });

  /// Show the full picker (Book → Chapter → Verse) as a dialog.
  ///
  /// When [initialBook], [initialChapter], and [initialVerseStart] are
  /// provided the picker opens pre-populated with that reference so the user
  /// can see what they are editing.
  static Future<BibleReferenceSelection?> show(
    BuildContext context, {
    String? defaultVersion,
    BibleBook? initialBook,
    int? initialChapter,
    int? initialVerseStart,
    int? initialVerseEnd,
  }) {
    return showDialog<BibleReferenceSelection>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: AppTheme.spacing16, vertical: 40),
        shape: RoundedRectangleBorder(
          borderRadius: AppTheme.borderRadius3XL,
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: _PickerContent(
            defaultVersion: defaultVersion,
            initialBook: initialBook,
            initialChapter: initialChapter,
            initialVerseStart: initialVerseStart,
            initialVerseEnd: initialVerseEnd,
          ),
        ),
      ),
    );
  }

  /// Show only the book selection grid as a dialog (single-select).
  ///
  /// Returns the selected [BibleBook], or `null` if dismissed.
  /// Pass [selectedBook] to highlight the currently active book.
  static Future<BibleBook?> showBookPicker(
    BuildContext context, {
    BibleBook? selectedBook,
  }) {
    return showDialog<BibleBook>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: AppTheme.spacing16, vertical: 40),
        shape: RoundedRectangleBorder(
          borderRadius: AppTheme.borderRadius3XL,
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: _PickerContent(
            bookOnly: true,
            initialBook: selectedBook,
          ),
        ),
      ),
    );
  }

  /// Show the book selection grid with multi-select support.
  ///
  /// Returns the selected set of [BibleBook]s, or `null` if dismissed.
  /// Pass [selectedBooks] to pre-select books.
  static Future<Set<BibleBook>?> showMultiBookPicker(
    BuildContext context, {
    Set<BibleBook> selectedBooks = const {},
  }) {
    return showDialog<Set<BibleBook>>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: AppTheme.spacing16, vertical: 40),
        shape: RoundedRectangleBorder(
          borderRadius: AppTheme.borderRadius3XL,
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: _PickerContent(
            bookOnly: true,
            multiSelect: true,
            initialBooks: selectedBooks,
          ),
        ),
      ),
    );
  }

  @override
  State<BibleReferencePicker> createState() => _BibleReferencePickerState();
}

class _BibleReferencePickerState extends State<BibleReferencePicker> {
  @override
  Widget build(BuildContext context) {
    return _PickerContent(
      defaultVersion: widget.defaultVersion,
      onSelect: widget.onSelect,
    );
  }
}

enum _PickerTab { book, chapter, verse }

class _PickerContent extends ConsumerStatefulWidget {
  final String? defaultVersion;
  final void Function(BibleReferenceSelection selection)? onSelect;
  final bool bookOnly;
  final bool multiSelect;
  final BibleBook? initialBook;
  final int? initialChapter;
  final int? initialVerseStart;
  final int? initialVerseEnd;
  final Set<BibleBook> initialBooks;

  const _PickerContent({
    this.defaultVersion,
    this.onSelect,
    this.bookOnly = false,
    this.multiSelect = false,
    this.initialBook,
    this.initialChapter,
    this.initialVerseStart,
    this.initialVerseEnd,
    this.initialBooks = const {},
  });

  @override
  ConsumerState<_PickerContent> createState() => _PickerContentState();
}

class _PickerContentState extends ConsumerState<_PickerContent> {
  _PickerTab _activeTab = _PickerTab.book;
  BibleBook? _selectedBook;
  int? _selectedChapter;
  int? _selectedVerseStart;
  int? _selectedVerseEnd;
  String? _selectedVersion;
  late Set<BibleBook> _selectedBooks;

  @override
  void initState() {
    super.initState();
    _selectedVersion = widget.defaultVersion;
    _selectedBook = widget.initialBook;
    _selectedChapter = widget.initialChapter;
    _selectedVerseStart = widget.initialVerseStart;
    _selectedVerseEnd = widget.initialVerseEnd;
    _selectedBooks = Set.from(widget.initialBooks);

    // Open on the most specific tab that has a pre-selected value so the user
    // can see the existing reference and tweak from there.
    if (_selectedBook != null && _selectedChapter != null) {
      _activeTab = _PickerTab.verse;
    } else if (_selectedBook != null) {
      _activeTab = _PickerTab.chapter;
    }
  }

  String _effectiveVersion(List<String> available) {
    if (_selectedVersion != null && available.contains(_selectedVersion)) {
      return _selectedVersion!;
    }
    // Fall back to the user's configured default. Read rather than watch
    // because this is called from callbacks too; build sites explicitly
    // watch the provider so rebuilds happen when the backing stream emits.
    final userDefault = ref.read(defaultBibleVersionProvider);
    if (available.contains(userDefault)) {
      return userDefault;
    }
    return available.isNotEmpty ? available.first : '';
  }

  void _selectBook(BibleBook book) {
    if (widget.bookOnly) {
      if (widget.multiSelect) {
        setState(() {
          if (_selectedBooks.contains(book)) {
            _selectedBooks.remove(book);
          } else {
            _selectedBooks.add(book);
          }
        });
      } else {
        Navigator.of(context).pop(book);
      }
      return;
    }
    setState(() {
      _selectedBook = book;
      _selectedChapter = null;
      _selectedVerseStart = null;
      _selectedVerseEnd = null;
      _activeTab = _PickerTab.chapter;
    });
  }

  void _selectChapter(int chapter) {
    setState(() {
      _selectedChapter = chapter;
      _selectedVerseStart = null;
      _selectedVerseEnd = null;
      _activeTab = _PickerTab.verse;
    });
  }

  void _selectVerse(int verse) {
    setState(() {
      if (_selectedVerseStart == null) {
        _selectedVerseStart = verse;
      } else if (_selectedVerseEnd == null && verse != _selectedVerseStart) {
        if (verse < _selectedVerseStart!) {
          _selectedVerseEnd = _selectedVerseStart;
          _selectedVerseStart = verse;
        } else {
          _selectedVerseEnd = verse;
        }
      } else {
        _selectedVerseStart = verse;
        _selectedVerseEnd = null;
      }
    });
  }

  void _confirm() {
    final translations = ref.read(bibleTranslationsProvider);
    final version = _effectiveVersion(translations);
    if (version.isEmpty) return;

    final selection = BibleReferenceSelection(
      book: _selectedBook!,
      chapter: _selectedChapter!,
      verseStart: _selectedVerseStart!,
      verseEnd: _selectedVerseEnd,
      version: version,
    );

    if (widget.onSelect != null) {
      widget.onSelect!(selection);
    } else {
      Navigator.of(context).pop(selection);
    }
  }

  void _switchTab(_PickerTab tab) {
    if (tab == _PickerTab.chapter && _selectedBook == null) {
      return;
    }
    if (tab == _PickerTab.verse &&
        (_selectedBook == null || _selectedChapter == null)) {
      return;
    }
    setState(() => _activeTab = tab);
  }

  void _showVersionPicker() {
    final translations = ref.read(bibleTranslationsProvider);
    if (translations.isEmpty) return;

    final effective = _effectiveVersion(translations);

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select Version'),
        children: translations.map((code) {
          final displayName = bibleVersionDisplayName(code);
          final isSelected = code == effective;
          return ListTile(
            title: Text(displayName),
            subtitle: Text(code),
            trailing: isSelected
                ? Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary)
                : null,
            selected: isSelected,
            onTap: () {
              setState(() => _selectedVersion = code);
              Navigator.of(ctx).pop();
            },
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipRect(
      child: Column(
      children: [
        // Title bar
        Padding(
          padding: const EdgeInsets.fromLTRB(AppTheme.spacing4, AppTheme.spacing4, AppTheme.spacing4, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, size: AppTheme.iconBase),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    widget.bookOnly ? 'Select Book' : 'Bible Navigation',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 48), // balance for close button
            ],
          ),
        ),
        // Tab selector (hidden in book-only mode)
        if (!widget.bookOnly)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing20, vertical: AppTheme.spacing8),
            child: Row(
              children: [
                _tabChip(
                    _PickerTab.book, Icons.menu_book_outlined, 'BOOK', cs),
                const SizedBox(width: AppTheme.spacing8),
                _tabChip(_PickerTab.chapter, Icons.bookmark_border,
                    'CHAPTER', cs),
                const SizedBox(width: AppTheme.spacing8),
                _tabChip(_PickerTab.verse, Icons.auto_stories_outlined,
                    'VERSE', cs),
              ],
            ),
          ),
        // Content
        Expanded(
          child: ClipRect(
            child: widget.bookOnly ? _buildBookGrid(cs) : _buildContent(cs),
          ),
        ),
        // OK button for multi-select book-only mode
        if (widget.bookOnly && widget.multiSelect)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppTheme.spacing16, 0, AppTheme.spacing16, AppTheme.spacing16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(_selectedBooks),
                child: Text(
                  _selectedBooks.isEmpty
                      ? 'OK'
                      : 'OK (${_selectedBooks.length} selected)',
                ),
              ),
            ),
          ),
      ],
      ),
    );
  }

  Widget _tabChip(
    _PickerTab tab,
    IconData icon,
    String label,
    ColorScheme cs,
  ) {
    final isActive = _activeTab == tab;
    final isEnabled = tab == _PickerTab.book ||
        (tab == _PickerTab.chapter && _selectedBook != null) ||
        (tab == _PickerTab.verse && _selectedChapter != null);

    final color = isActive
        ? cs.primary
        : isEnabled
            ? cs.onSurface.withValues(alpha: 0.6)
            : cs.onSurface.withValues(alpha: 0.3);

    return Expanded(
      child: GestureDetector(
        onTap: isEnabled ? () => _switchTab(tab) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isActive ? cs.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: AppTheme.iconSM, color: color),
              const SizedBox(width: AppTheme.spacing4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ColorScheme cs) {
    switch (_activeTab) {
      case _PickerTab.book:
        return _buildBookGrid(cs);
      case _PickerTab.chapter:
        return _buildChapterGrid(cs);
      case _PickerTab.verse:
        return _buildVerseGrid(cs);
    }
  }

  // ── Book Tab ──

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

  static const _chipColors = [
    Color(0xFF6366F1), Color(0xFF10B981), Color(0xFFF59E0B), Color(0xFFEF4444),
    Color(0xFF8B5CF6), Color(0xFF06B6D4), Color(0xFFF97316), Color(0xFF84CC16),
  ];

  Widget _buildBookGrid(ColorScheme cs) {
    final otBooks = BibleBooks.books.sublist(0, 39);
    final ntBooks = BibleBooks.books.sublist(39);

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacing16, AppTheme.spacing8,
        AppTheme.spacing16, AppTheme.spacing8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTestamentChips('Old Testament', otBooks, 0, cs),
          const SizedBox(height: AppTheme.spacing12),
          _buildTestamentChips('New Testament', ntBooks, 39, cs),
        ],
      ),
    );
  }

  Widget _buildTestamentChips(
    String label,
    List<BibleBook> books,
    int indexOffset,
    ColorScheme cs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
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
            final isSelected = widget.multiSelect
                ? _selectedBooks.contains(book)
                : _selectedBook?.name == book.name;
            final abbr = _bookAbbreviations[book.name] ??
                book.name.substring(0, book.name.length.clamp(0, 3));
            final color = _chipColors[(indexOffset + i) % _chipColors.length];

            return FilterChip(
              label: Text(abbr),
              selected: isSelected,
              onSelected: (_) => _selectBook(book),
              showCheckmark: false,
              labelStyle: TextStyle(
                fontSize: 11,
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

  // ── Chapter Tab ──

  Widget _buildChapterGrid(ColorScheme cs) {
    final chapterCount = _selectedBook?.chapterCount ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing16, vertical: AppTheme.spacing4),
          child: Text(
            _selectedBook?.name ?? '',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(AppTheme.spacing16, AppTheme.spacing4, AppTheme.spacing16, AppTheme.spacing16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: AppTheme.spacing8,
              crossAxisSpacing: AppTheme.spacing8,
              childAspectRatio: 1.2,
            ),
            itemCount: chapterCount,
            itemBuilder: (context, index) {
              final chapter = index + 1;
              final isSelected = _selectedChapter == chapter;

              return GestureDetector(
                onTap: () => _selectChapter(chapter),
                child: Container(
                  decoration: BoxDecoration(
                    color:
                        isSelected ? cs.primary : cs.surfaceContainerHigh,
                    borderRadius: AppTheme.borderRadiusMD,
                  ),
                  child: Center(
                    child: Text(
                      '$chapter',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isSelected ? cs.onPrimary : cs.onSurface,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Verse Tab ──

  Widget _buildVerseGrid(ColorScheme cs) {
    final verseCount =
        _selectedBook?.getVerseCount(_selectedChapter ?? 1) ?? 0;
    final hasSelection = _selectedVerseStart != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Breadcrumb + selection info
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing16, vertical: AppTheme.spacing4),
          child: Row(
            children: [
              Text(
                '${_selectedBook?.name} $_selectedChapter',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
              if (hasSelection)
                Text(
                  _selectedVerseEnd != null
                      ? ':$_selectedVerseStart-$_selectedVerseEnd'
                      : ':$_selectedVerseStart',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
              const Spacer(),
              if (hasSelection)
                GestureDetector(
                  onTap: () => setState(() {
                    _selectedVerseStart = null;
                    _selectedVerseEnd = null;
                  }),
                  child: Text(
                    'Clear',
                    style: TextStyle(fontSize: 12, color: cs.primary),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: AppTheme.paddingH16,
          child: Text(
            'Tap once for single verse, tap another for range',
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spacing4),
        // Verse grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(AppTheme.spacing16, AppTheme.spacing4, AppTheme.spacing16, AppTheme.spacing8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: AppTheme.spacing8,
              crossAxisSpacing: AppTheme.spacing8,
              childAspectRatio: 1.2,
            ),
            itemCount: verseCount,
            itemBuilder: (context, index) {
              final verse = index + 1;
              final isStart = verse == _selectedVerseStart;
              final isEnd = verse == _selectedVerseEnd;
              final isInRange = _selectedVerseStart != null &&
                  _selectedVerseEnd != null &&
                  verse >= _selectedVerseStart! &&
                  verse <= _selectedVerseEnd!;

              Color bgColor;
              Color textColor;
              if (isStart || isEnd) {
                bgColor = cs.primary;
                textColor = cs.onPrimary;
              } else if (isInRange) {
                bgColor = cs.primary.withValues(alpha: 0.15);
                textColor = cs.primary;
              } else {
                bgColor = cs.surfaceContainerHigh;
                textColor = cs.onSurface;
              }

              return GestureDetector(
                onTap: () => _selectVerse(verse),
                child: Container(
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: AppTheme.borderRadiusMD,
                  ),
                  child: Center(
                    child: Text(
                      '$verse',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Verse preview (Item 11)
        if (hasSelection) _buildVersePreview(cs),

        // Version selector + OK button
        if (hasSelection) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(AppTheme.spacing16, 0, AppTheme.spacing16, AppTheme.spacing8),
            child: GestureDetector(
              onTap: _showVersionPicker,
              child: Consumer(
                builder: (context, ref, _) {
                  final translations =
                      ref.watch(bibleTranslationsProvider);
                  // Subscribe so the chip updates when the user's default
                  // resolves from the async version-states stream.
                  ref.watch(defaultBibleVersionProvider);
                  final version = _effectiveVersion(translations);
                  final displayName = bibleVersionDisplayName(version);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacing12, vertical: AppTheme.spacing10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius: AppTheme.borderRadiusMD,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.translate,
                            size: AppTheme.iconMD,
                            color:
                                cs.onSurface.withValues(alpha: 0.6)),
                        const SizedBox(width: AppTheme.spacing8),
                        Expanded(
                          child: Text(
                            displayName,
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          version.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color:
                                cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(width: AppTheme.spacing4),
                        Icon(Icons.chevron_right,
                            size: AppTheme.iconMD,
                            color:
                                cs.onSurface.withValues(alpha: 0.4)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppTheme.spacing16, 0, AppTheme.spacing16, AppTheme.spacing16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _confirm,
                child: const Text('OK'),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── Verse Preview (Item 11) ──

  Widget _buildVersePreview(ColorScheme cs) {
    final translations = ref.watch(bibleTranslationsProvider);
    ref.watch(defaultBibleVersionProvider);
    final version = _effectiveVersion(translations);
    if (version.isEmpty || _selectedBook == null || _selectedChapter == null) {
      return const SizedBox.shrink();
    }

    final bookIdx = BibleBooks.books.indexOf(_selectedBook!);
    if (bookIdx < 0) return const SizedBox.shrink();

    final verses = ref.watch(bibleVersesProvider(
      (
        bookId: bookIdx + 1,
        chapter: _selectedChapter!,
        translation: version,
      ),
    ));

    if (verses.isEmpty) return const SizedBox.shrink();

    String previewText;
    if (_selectedVerseEnd != null && _selectedVerseEnd != _selectedVerseStart) {
      // Range: show start verse ... end verse
      final startVerse = verses
          .where((v) => v.verse == _selectedVerseStart)
          .firstOrNull;
      final endVerse = verses
          .where((v) => v.verse == _selectedVerseEnd)
          .firstOrNull;
      final startText = startVerse?.text ?? '';
      final endText = endVerse?.text ?? '';
      previewText = '$startText ... $endText';
    } else {
      // Single verse
      final verse = verses
          .where((v) => v.verse == _selectedVerseStart)
          .firstOrNull;
      previewText = verse?.text ?? '';
    }

    if (previewText.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppTheme.spacing16, AppTheme.spacing4, AppTheme.spacing16, AppTheme.spacing8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppTheme.spacing12),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.06),
          borderRadius: AppTheme.borderRadiusLG,
          border: Border.all(
            color: cs.primary.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.format_quote_rounded,
              size: AppTheme.iconMD,
              color: cs.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(width: AppTheme.spacing8),
            Expanded(
              child: Text(
                previewText,
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: cs.onSurface.withValues(alpha: 0.7),
                  height: 1.4,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

}


/// Result of the Bible reference picker
class BibleReferenceSelection {
  final BibleBook book;
  final int chapter;
  final int verseStart;
  final int? verseEnd;
  final String version;

  const BibleReferenceSelection({
    required this.book,
    required this.chapter,
    required this.verseStart,
    this.verseEnd,
    required this.version,
  });

  /// Generate the list of verse numbers from the selection range
  List<int> get verses {
    if (verseEnd == null || verseEnd == verseStart) {
      return [verseStart];
    }
    return List.generate(verseEnd! - verseStart + 1, (i) => verseStart + i);
  }

  /// Build display reference string
  String get displayReference {
    final range =
        (verseEnd != null && verseEnd != verseStart) ? '-$verseEnd' : '';
    return '${book.name} $chapter:$verseStart$range (${version.toUpperCase()})';
  }
}
