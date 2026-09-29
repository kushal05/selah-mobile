/// Sort options for the notes list.
///
/// Lives outside the screen so the screen's UI-state provider can reference it
/// without importing the 2,000-line widget file back.
///
/// [label] is a non-localised fallback, kept for logging and debug output.
/// Anything the user reads goes through `_sortLabel` in the notes screen,
/// which resolves `notesSortLastEdited` and friends from the ARB.
enum NotesSortOption {
  lastEdited('Last Edited'),
  title('Title (A-Z)'),
  createdDate('Created Date');

  final String label;
  const NotesSortOption(this.label);
}

/// Compares two note titles for [NotesSortOption.title].
///
/// `String.compareTo` is NOT usable here. It orders by UTF-16 code unit, so
/// every capital sorts before every lowercase: a list of sermon titles comes
/// out `Apple, Banana, Zion, apple, banana, zion`, and "apple" appears below
/// "Zion". Users read that as the sort being broken, which it is.
///
/// This is case-insensitive, and compares runs of digits as numbers so
/// "Week 2" precedes "Week 10" rather than following it.
///
/// Kept deliberately in step with the web client, which gets the same behaviour
/// from `Intl.Collator(undefined, {sensitivity: 'base', numeric: true})` in
/// `selah-fe/src/notes/lib/sort.ts`. The two clients sort the same notes for the
/// same person, so an order that disagrees reads as notes moving on their own.
///
/// Known limit, and the reason this is not called a full collator: it folds
/// case but not accents, so "Ángel" sorts after "Zion" rather than beside
/// "Angel". Doing that properly needs ICU collation, which Dart does not expose
/// and which is not worth a dependency for a title sort. The web's `sensitivity:
/// 'base'` does fold accents, so the two can disagree on accented titles —
/// a much narrower disagreement than the one this replaces.
int compareNoteTitles(String a, String b) {
  final x = a.toLowerCase();
  final y = b.toLowerCase();
  var i = 0;
  var j = 0;

  while (i < x.length && j < y.length) {
    final cx = x.codeUnitAt(i);
    final cy = y.codeUnitAt(j);

    if (_isDigit(cx) && _isDigit(cy)) {
      final startX = i;
      final startY = j;
      while (i < x.length && _isDigit(x.codeUnitAt(i))) {
        i++;
      }
      while (j < y.length && _isDigit(y.codeUnitAt(j))) {
        j++;
      }
      // Compared as text with leading zeros stripped, not parsed as int: a
      // title can carry a run of digits longer than int64 (a pasted id, a long
      // date string), and parsing would throw or silently wrap.
      final numX = _stripLeadingZeros(x.substring(startX, i));
      final numY = _stripLeadingZeros(y.substring(startY, j));
      if (numX.length != numY.length) return numX.length - numY.length;
      final cmp = numX.compareTo(numY);
      if (cmp != 0) return cmp;
      continue;
    }

    if (cx != cy) return cx - cy;
    i++;
    j++;
  }

  // One is a prefix of the other; the shorter sorts first.
  return (x.length - i) - (y.length - j);
}

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

String _stripLeadingZeros(String digits) {
  var k = 0;
  while (k < digits.length - 1 && digits.codeUnitAt(k) == 0x30) {
    k++;
  }
  return digits.substring(k);
}
