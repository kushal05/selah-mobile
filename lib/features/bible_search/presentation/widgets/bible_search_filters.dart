import 'package:flutter/material.dart';

import '../../../bible/domain/models/bible_book_entity.dart';
import '../../../bible/domain/models/bible_version_info.dart';
import '../../../bible/domain/models/bible_books.dart';
import '../../../notes/presentation/widgets/editor/bible_reference_picker.dart';
import '../../domain/models/bible_search_result.dart';

/// A horizontal row of filter chips for Bible verse search with multi-select.
///
/// Supports:
/// - Testament toggle (OT / NT — both can be active)
/// - Multi-book picker
/// - Multi-translation picker
/// - Active filter summary row with individual dismiss
class BibleSearchFiltersBar extends StatelessWidget {
  final BibleSearchFilters filters;
  final ValueChanged<BibleSearchFilters> onChanged;
  final List<BibleBookEntity> allBooks;
  final List<String> availableTranslations;

  const BibleSearchFiltersBar({
    super.key,
    required this.filters,
    required this.onChanged,
    this.allBooks = const [],
    this.availableTranslations = const [],
  });

  String? _resolveBookName(int bookId) {
    if (bookId >= 1 && bookId <= BibleBooks.books.length) {
      return BibleBooks.books[bookId - 1].name;
    }
    final match = allBooks.where((b) => b.id == bookId);
    return match.isNotEmpty ? match.first.name : null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Filter chip buttons row
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // Testament: OT
              FilterChip(
                label: const Text('OT'),
                selected: filters.testaments.contains(0),
                onSelected: (selected) {
                  final updated = Set<int>.from(filters.testaments);
                  if (selected) {
                    updated.add(0);
                  } else {
                    updated.remove(0);
                  }
                  onChanged(filters.copyWith(testaments: updated));
                },
                labelStyle: TextStyle(color: cs.onSurface),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),

              // Testament: NT
              FilterChip(
                label: const Text('NT'),
                selected: filters.testaments.contains(1),
                onSelected: (selected) {
                  final updated = Set<int>.from(filters.testaments);
                  if (selected) {
                    updated.add(1);
                  } else {
                    updated.remove(1);
                  }
                  onChanged(filters.copyWith(testaments: updated));
                },
                labelStyle: TextStyle(color: cs.onSurface),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),

              // Book picker
              FilterChip(
                avatar: filters.bookIds.isEmpty
                    ? const Icon(Icons.book, size: 16)
                    : null,
                label: Text(_bookChipLabel()),
                selected: filters.bookIds.isNotEmpty,
                onSelected: (_) => _showBookPicker(context),
                labelStyle: TextStyle(color: cs.onSurface),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),

              // Translation picker
              if (availableTranslations.length > 1) ...[
                FilterChip(
                  label: Text(_translationChipLabel()),
                  selected: filters.translations.isNotEmpty,
                  onSelected: (_) => _showTranslationPicker(context),
                  labelStyle: TextStyle(color: cs.onSurface),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
        ),

        // Active filter values row
        if (filters.hasActiveFilters) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              // Testament chips
              for (final t in filters.testaments)
                _dismissChip(
                  label: t == 0 ? 'Old Testament' : 'New Testament',
                  cs: cs,
                  onDeleted: () {
                    final updated = Set<int>.from(filters.testaments)
                      ..remove(t);
                    onChanged(filters.copyWith(testaments: updated));
                  },
                ),
              // Book chips
              for (final bookId in filters.bookIds)
                _dismissChip(
                  label: _resolveBookName(bookId) ?? 'Book $bookId',
                  cs: cs,
                  onDeleted: () {
                    final updated = Set<int>.from(filters.bookIds)
                      ..remove(bookId);
                    onChanged(filters.copyWith(bookIds: updated));
                  },
                ),
              // Translation chips
              for (final t in filters.translations)
                _dismissChip(
                  label: _translationName(t),
                  cs: cs,
                  onDeleted: () {
                    final updated = Set<String>.from(filters.translations)
                      ..remove(t);
                    onChanged(filters.copyWith(translations: updated));
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _dismissChip({
    required String label,
    required ColorScheme cs,
    required VoidCallback onDeleted,
  }) {
    return InputChip(
      label: Text(
        label,
        style: TextStyle(fontSize: 12, color: cs.onSurface),
      ),
      deleteIcon: Icon(Icons.close,
          size: 14, color: cs.onSurface.withValues(alpha: 0.6)),
      onDeleted: onDeleted,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  String _bookChipLabel() {
    if (filters.bookIds.isEmpty) return 'Book';
    if (filters.bookIds.length == 1) {
      return _resolveBookName(filters.bookIds.first) ?? 'Book';
    }
    return '${filters.bookIds.length} Books';
  }

  String _translationChipLabel() {
    if (filters.translations.isEmpty) return 'Translation';
    if (filters.translations.length == 1) {
      return filters.translations.first.toUpperCase();
    }
    return '${filters.translations.length} Translations';
  }

  void _showBookPicker(BuildContext context) async {
    final currentBooks = filters.bookIds
        .where((id) => id >= 1 && id <= BibleBooks.books.length)
        .map((id) => BibleBooks.books[id - 1])
        .toSet();

    final picked = await BibleReferencePicker.showMultiBookPicker(
      context,
      selectedBooks: currentBooks,
    );

    if (picked == null) return; // dismissed

    final bookIds =
        picked.map((book) => BibleBooks.books.indexOf(book) + 1).toSet();
    onChanged(filters.copyWith(bookIds: bookIds));
  }

  void _showTranslationPicker(BuildContext context) {
    var selected = Set<String>.from(filters.translations);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) {
          final cs = Theme.of(ctx).colorScheme;
          return SimpleDialog(
            title: const Text('Select Translations'),
            children: [
              ...availableTranslations.map((t) {
                final isSelected = selected.contains(t);
                return ListTile(
                  title: Text(t.toUpperCase()),
                  subtitle: Text(_translationName(t)),
                  trailing: isSelected
                      ? Icon(Icons.check, color: cs.primary)
                      : null,
                  selected: isSelected,
                  onTap: () {
                    setLocalState(() {
                      if (isSelected) {
                        selected.remove(t);
                      } else {
                        selected.add(t);
                      }
                    });
                  },
                );
              }),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: FilledButton(
                  onPressed: () {
                    onChanged(filters.copyWith(translations: selected));
                    Navigator.pop(ctx);
                  },
                  child: const Text('Apply'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _translationName(String code) => bibleVersionDisplayName(code);
}
