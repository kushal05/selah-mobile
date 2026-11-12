import 'package:flutter_test/flutter_test.dart';

import 'package:notify/features/bible/domain/models/bible_highlight_entity.dart';
import 'package:notify/features/bible/domain/services/verse_selection.dart';

BibleHighlightEntity _h(String id, int s, int e,
        {HighlightColor color = HighlightColor.yellow, String note = ''}) =>
    BibleHighlightEntity(
      id: id,
      bookId: 1,
      chapter: 1,
      verseStart: s,
      verseEnd: e,
      color: color,
      note: note,
      createdAt: 1,
      updatedAt: 1,
    );

void main() {
  group('runs and labels', () {
    test('groups consecutive verses', () {
      expect(verseRuns({6, 2, 4, 5}),
          [const VerseRun(2, 2), const VerseRun(4, 6)]);
      expect(verseRuns(<int>{}), isEmpty);
    });

    test('consecutive means exactly one unbroken run', () {
      expect(isConsecutive({3, 4, 5}), isTrue);
      expect(isConsecutive({3}), isTrue);
      expect(isConsecutive({3, 5}), isFalse);
      expect(isConsecutive(<int>{}), isFalse);
    });

    test('labels', () {
      expect(formatVerses({4}), '4');
      expect(formatVerses({4, 5, 6}), '4–6');
      expect(formatVerses({2, 4, 5}), '2, 4–5');
      expect(formatVerseRange(4, 4), '4');
      expect(formatVerseRange(4, 6), '4–6');
    });
  });

  group('planHighlight', () {
    test('nothing there: one new highlight per run', () {
      final p = planHighlight(
          existing: [], selected: {2, 4, 5}, color: HighlightColor.blue);
      expect(p.creates, [
        const HighlightCreate(2, 2, HighlightColor.blue),
        const HighlightCreate(4, 5, HighlightColor.blue),
      ]);
      expect(p.updates, isEmpty);
      expect(p.deletes, isEmpty);
    });

    test('same colour on the same verses writes nothing', () {
      final p = planHighlight(
          existing: [_h('a', 3, 3)],
          selected: {3},
          color: HighlightColor.yellow);
      expect(p.isEmpty, isTrue);
    });

    test('recolouring exactly the highlighted verses keeps that highlight', () {
      final p = planHighlight(
          existing: [_h('a', 3, 5, note: 'n')],
          selected: {3, 4, 5},
          color: HighlightColor.green);
      expect(p.updates.single.highlight.id, 'a');
      expect(p.updates.single.color, HighlightColor.green);
      expect(p.creates, isEmpty);
      expect(p.deletes, isEmpty);
    });

    test('selection inside a highlight splits it in two', () {
      final p = planHighlight(
          existing: [_h('a', 2, 8)],
          selected: {4, 5},
          color: HighlightColor.pink);
      // The left part keeps the original, the right part and the selection
      // are new.
      expect(p.updates.single.start, 2);
      expect(p.updates.single.end, 3);
      expect(p.updates.single.color, HighlightColor.yellow);
      expect(p.creates, containsAll([
        const HighlightCreate(6, 8, HighlightColor.yellow),
        const HighlightCreate(4, 5, HighlightColor.pink),
      ]));
      expect(p.deletes, isEmpty);
    });

    test('selection overlapping one end trims the highlight', () {
      final p = planHighlight(
          existing: [_h('a', 2, 5)],
          selected: {4, 5, 6},
          color: HighlightColor.blue);
      expect(p.updates.single.start, 2);
      expect(p.updates.single.end, 3);
      expect(p.creates, [const HighlightCreate(4, 6, HighlightColor.blue)]);
    });

    test('a highlight the selection covers is replaced', () {
      final p = planHighlight(
          existing: [_h('a', 4, 4), _h('b', 5, 5)],
          selected: {3, 4, 5, 6},
          color: HighlightColor.orange);
      expect(p.deletes, unorderedEquals(['a', 'b']));
      expect(p.creates, [const HighlightCreate(3, 6, HighlightColor.orange)]);
    });

    test('a highlight elsewhere is left alone', () {
      final p = planHighlight(
          existing: [_h('a', 10, 12)],
          selected: {3},
          color: HighlightColor.blue);
      expect(p.updates, isEmpty);
      expect(p.deletes, isEmpty);
      expect(p.creates, [const HighlightCreate(3, 3, HighlightColor.blue)]);
    });

    test('a covered highlight with a note is reused, not deleted', () {
      final p = planHighlight(
          existing: [_h('a', 4, 4, note: 'keep me')],
          selected: {3, 4, 5},
          color: HighlightColor.green);
      expect(p.deletes, isEmpty);
      expect(p.orphanNotes, isEmpty);
      final u = p.updates.single;
      expect(u.highlight.id, 'a');
      expect([u.start, u.end], [3, 5]);
      expect(p.creates, isEmpty);
    });

    test('a second noted highlight in the same run keeps its note as a verse note',
        () {
      final p = planHighlight(
          existing: [_h('a', 3, 3, note: 'one'), _h('b', 4, 4, note: 'two')],
          selected: {3, 4},
          color: HighlightColor.green);
      expect(p.deletes.length, 1);
      expect(p.orphanNotes.single.text, anyOf('one', 'two'));
    });
  });

  group('planHighlight with no colour (remove)', () {
    test('removes a highlight the selection covers', () {
      final p = planHighlight(
          existing: [_h('a', 3, 4)], selected: {3, 4}, color: null);
      expect(p.deletes, ['a']);
      expect(p.creates, isEmpty);
    });

    test('removing from the middle leaves both ends', () {
      final p = planHighlight(
          existing: [_h('a', 2, 8)], selected: {5}, color: null);
      expect(p.updates.single.end, 4);
      expect(p.creates, [const HighlightCreate(6, 8, HighlightColor.yellow)]);
      expect(p.deletes, isEmpty);
    });

    test('a removed highlight with a note leaves the note behind', () {
      final p = planHighlight(
          existing: [_h('a', 3, 4, note: 'mine')], selected: {3, 4}, color: null);
      expect(p.deletes, ['a']);
      expect(p.orphanNotes.single.text, 'mine');
      expect([p.orphanNotes.single.start, p.orphanNotes.single.end], [3, 4]);
    });
  });
}
