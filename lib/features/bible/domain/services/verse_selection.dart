import '../models/bible_highlight_entity.dart';

/// A run of consecutive verses, both ends included.
class VerseRun {
  final int start;
  final int end;

  const VerseRun(this.start, this.end);

  @override
  bool operator ==(Object other) =>
      other is VerseRun && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'VerseRun($start, $end)';
}

/// The runs of consecutive verses in [verses]: {2, 4, 5, 6} is 2 and 4–6.
List<VerseRun> verseRuns(Iterable<int> verses) {
  final sorted = verses.toSet().toList()..sort();
  final runs = <VerseRun>[];
  for (final v in sorted) {
    if (runs.isNotEmpty && runs.last.end == v - 1) {
      runs[runs.length - 1] = VerseRun(runs.last.start, v);
    } else {
      runs.add(VerseRun(v, v));
    }
  }
  return runs;
}

/// Whether [verses] are one unbroken run (and not empty). A note can only be
/// written on such a selection.
bool isConsecutive(Iterable<int> verses) => verseRuns(verses).length == 1;

/// "4", "4–6" or "2, 4–6": the verse numbers of a selection, for a label.
String formatVerses(Iterable<int> verses) => verseRuns(verses)
    .map((r) => r.start == r.end ? '${r.start}' : '${r.start}–${r.end}')
    .join(', ');

/// A verse range as the label above a note: "Verse 4" or "Verses 4–6".
String formatVerseRange(int start, int end) =>
    start == end ? '$start' : '$start–$end';

/// A highlight to write.
class HighlightCreate {
  final int start;
  final int end;
  final HighlightColor color;

  const HighlightCreate(this.start, this.end, this.color);

  @override
  bool operator ==(Object other) =>
      other is HighlightCreate &&
      other.start == start &&
      other.end == end &&
      other.color == color;

  @override
  int get hashCode => Object.hash(start, end, color);

  @override
  String toString() => 'HighlightCreate($start, $end, $color)';
}

/// An existing highlight to move to a new range and/or colour.
class HighlightUpdate {
  final BibleHighlightEntity highlight;
  final int start;
  final int end;
  final HighlightColor color;

  const HighlightUpdate(this.highlight, this.start, this.end, this.color);
}

/// A note that belonged to a highlight being removed. It is the user's
/// writing, so it is kept as a verse note over the same verses.
class OrphanNote {
  final int start;
  final int end;
  final String text;

  const OrphanNote(this.start, this.end, this.text);
}

/// What to write so that every selected verse is [color] (or no longer
/// highlighted when [color] is null), and no other verse changes.
class HighlightPlan {
  final List<HighlightCreate> creates;
  final List<HighlightUpdate> updates;
  final List<String> deletes;
  final List<OrphanNote> orphanNotes;

  const HighlightPlan({
    this.creates = const [],
    this.updates = const [],
    this.deletes = const [],
    this.orphanNotes = const [],
  });

  bool get isEmpty =>
      creates.isEmpty &&
      updates.isEmpty &&
      deletes.isEmpty &&
      orphanNotes.isEmpty;
}

/// Plans the highlight writes for [selected] verses.
///
/// A highlight that reaches outside the selection is cut back to the part that
/// is outside (split in two if the selection is in its middle), so recolouring
/// or removing three verses never touches the others. A highlight that the
/// selection covers entirely is reused for the selection when it matches a run
/// exactly or carries a note, and otherwise replaced.
HighlightPlan planHighlight({
  required List<BibleHighlightEntity> existing,
  required Set<int> selected,
  required HighlightColor? color,
}) {
  // Verses already in this colour need nothing, so choosing the colour a
  // highlight already has never cuts it up.
  if (color != null) {
    selected = {
      for (final v in selected)
        if (!existing.any((h) => h.color == color && h.coversVerse(v))) v,
    };
  }
  final runs = verseRuns(selected);
  final creates = <HighlightCreate>[];
  final updates = <HighlightUpdate>[];
  final deletes = <String>[];
  final orphans = <OrphanNote>[];
  final covered = <BibleHighlightEntity>[];

  for (final h in existing) {
    final overlaps = selected.any(h.coversVerse);
    if (!overlaps) continue;

    final outside = verseRuns([
      for (var v = h.verseStart; v <= h.verseEnd; v++)
        if (!selected.contains(v)) v,
    ]);
    if (outside.isEmpty) {
      covered.add(h);
      continue;
    }
    // Cut back: the first piece keeps this highlight (and its note), any
    // second piece is a new one in the same colour.
    updates.add(HighlightUpdate(h, outside.first.start, outside.first.end, h.color));
    for (final piece in outside.skip(1)) {
      creates.add(HighlightCreate(piece.start, piece.end, h.color));
    }
  }

  final reused = <String>{};
  if (color != null) {
    for (final run in runs) {
      BibleHighlightEntity? pick;
      for (final h in covered) {
        if (reused.contains(h.id)) continue;
        if (h.verseStart == run.start && h.verseEnd == run.end) {
          pick = h;
          break;
        }
      }
      pick ??= covered
          .where((h) =>
              !reused.contains(h.id) &&
              h.hasNote &&
              h.verseStart <= run.end &&
              h.verseEnd >= run.start)
          .firstOrNull;
      if (pick == null) {
        creates.add(HighlightCreate(run.start, run.end, color));
      } else {
        reused.add(pick.id);
        if (pick.verseStart != run.start ||
            pick.verseEnd != run.end ||
            pick.color != color) {
          updates.add(HighlightUpdate(pick, run.start, run.end, color));
        }
      }
    }
  }

  for (final h in covered) {
    if (reused.contains(h.id)) continue;
    deletes.add(h.id);
    if (h.hasNote) orphans.add(OrphanNote(h.verseStart, h.verseEnd, h.note));
  }

  return HighlightPlan(
    creates: creates,
    updates: updates,
    deletes: deletes,
    orphanNotes: orphans,
  );
}
