import 'package:flutter/material.dart';

import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/drag_handle.dart';
import '../../domain/models/bible_books.dart';

/// A chapter the user picked: the book's id (its place in the canonical list,
/// starting at 1, as the Bible database numbers them) and the chapter.
typedef ChapterChoice = ({int bookId, int chapter});

/// Opens the chapter picker as a tall sheet and returns what was chosen, or
/// null if it was dismissed.
Future<ChapterChoice?> showChapterPicker(
  BuildContext context, {
  required int bookId,
  required int chapter,
  ThemeData? theme,
}) {
  return showModalBottomSheet<ChapterChoice>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor:
        (theme ?? Theme.of(context)).colorScheme.surfaceContainerHigh,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) {
      final sheet = FractionallySizedBox(
        heightFactor: 0.92,
        child: ChapterPickerSheet(bookId: bookId, chapter: chapter),
      );
      return theme == null ? sheet : Theme(data: theme, child: sheet);
    },
  );
}

/// One screen to get anywhere in the Bible: a search box, the Old and New
/// Testament, and a tap on a book opens its chapters in place.
///
/// Typing a reference such as "John 3" or "1 co 13" offers a jump straight to
/// it; typing part of a name narrows the books.
class ChapterPickerSheet extends StatefulWidget {
  final int bookId;
  final int chapter;

  const ChapterPickerSheet({
    super.key,
    required this.bookId,
    required this.chapter,
  });

  @override
  State<ChapterPickerSheet> createState() => _ChapterPickerSheetState();
}

class _ChapterPickerSheetState extends State<ChapterPickerSheet> {
  final _search = TextEditingController();
  late Testament _testament;
  int? _expanded; // book id
  final _currentKey = GlobalKey();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _expanded = widget.bookId;
    final book = _bookById(widget.bookId);
    _testament = book?.testament ?? Testament.old;
    _search.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _currentKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: 0.1);
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  static BibleBook? _bookById(int id) =>
      id >= 1 && id <= BibleBooks.books.length ? BibleBooks.books[id - 1] : null;

  static int _idOf(BibleBook b) => BibleBooks.books.indexOf(b) + 1;

  /// "John 3", "1 co 13:4": a book and a chapter that exists, or null.
  ChapterChoice? get _typedReference {
    final m = RegExp(r'^\s*(.*?)\s+(\d{1,3})(?::\d+)?\s*$')
        .firstMatch(_search.text);
    if (m == null) return null;
    final book = BibleBooks.findBook(m.group(1)!);
    final chapter = int.parse(m.group(2)!);
    if (book == null || chapter < 1 || chapter > book.chapterCount) {
      return null;
    }
    return (bookId: _idOf(book), chapter: chapter);
  }

  List<BibleBook> get _books {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) {
      return BibleBooks.books.where((b) => b.testament == _testament).toList();
    }
    // A search looks through both testaments.
    return BibleBooks.books
        .where((b) => b.name.toLowerCase().contains(q))
        .toList();
  }

  void _pick(int bookId, int chapter) =>
      Navigator.of(context).pop((bookId: bookId, chapter: chapter));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = l10n(context);
    final searching = _search.text.trim().isNotEmpty;
    final typed = _typedReference;
    final books = _books;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Column(
            children: [
              const DragHandle(),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t.chooseChapter,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: t.close,
                    icon: Icon(Icons.close, color: theme.colorScheme.onSurface),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) {
              if (typed != null) _pick(typed.bookId, typed.chapter);
            },
            decoration: InputDecoration(
              hintText: t.searchBookOrReference,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searching
                  ? IconButton(
                      tooltip: t.clearSelection,
                      icon: Icon(Icons.close,
                          color: theme.colorScheme.onSurfaceVariant),
                      onPressed: _search.clear,
                    )
                  : null,
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        if (!searching)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<Testament>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: Testament.old, label: Text(t.oldTestament)),
                ButtonSegment(
                    value: Testament.new_, label: Text(t.newTestament)),
              ],
              selected: {_testament},
              onSelectionChanged: (s) {
                setState(() => _testament = s.single);
                // The other testament's books start from the top.
                if (_scroll.hasClients) _scroll.jumpTo(0);
              },
            ),
          ),
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (typed != null)
                ListTile(
                  leading: Icon(Icons.arrow_forward_rounded,
                      color: theme.colorScheme.primary),
                  title: Text(
                    t.goToReference(
                        '${_bookById(typed.bookId)!.name} ${typed.chapter}'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () => _pick(typed.bookId, typed.chapter),
                ),
              if (books.isEmpty && typed == null)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    t.noResultsFor(_search.text.trim()),
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              for (final book in books) _bookRow(context, book),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bookRow(BuildContext context, BibleBook book) {
    final theme = Theme.of(context);
    final id = _idOf(book);
    final open = _expanded == id;
    final isCurrent = id == widget.bookId;

    return Column(
      key: isCurrent ? _currentKey : ValueKey('book-$id'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: open,
          child: InkWell(
            onTap: () => setState(() => _expanded = open ? null : id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      book.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                        color: isCurrent
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 6,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (var c = 1; c <= book.chapterCount; c++)
                  _ChapterCell(
                    chapter: c,
                    book: book.name,
                    isCurrent: isCurrent && c == widget.chapter,
                    onTap: () => _pick(id, c),
                  ),
              ],
            ),
          ),
        Divider(height: 1, color: context.hairline),
      ],
    );
  }
}

class _ChapterCell extends StatelessWidget {
  final int chapter;
  final String book;
  final bool isCurrent;
  final VoidCallback onTap;

  const _ChapterCell({
    required this.chapter,
    required this.book,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: isCurrent,
      label: l10n(context).chapterNumberOf(book, chapter),
      child: ExcludeSemantics(
        child: Material(
          color: isCurrent
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Center(
              child: Text(
                '$chapter',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isCurrent
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
