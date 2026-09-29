import 'package:flutter_test/flutter_test.dart';
import 'package:notify/features/notes/domain/models/notes_sort_option.dart';

void main() {
  List<String> sorted(List<String> titles) =>
      List<String>.from(titles)..sort(compareNoteTitles);

  group('compareNoteTitles folds case', () {
    /// The bug this replaces. `String.compareTo` orders by UTF-16 code unit, so
    /// every capital lands ahead of every lowercase and the list reads
    /// `Apple, Banana, Zion, apple, banana, zion`.
    test('interleaves capitals and lowercase alphabetically', () {
      expect(
        sorted(['Zion', 'apple', 'zion', 'Apple', 'Banana', 'banana']),
        ['apple', 'Apple', 'Banana', 'banana', 'Zion', 'zion'],
      );
    });

    test('apple sorts before Zion, whatever the case of either', () {
      expect(compareNoteTitles('apple', 'Zion'), lessThan(0));
      expect(compareNoteTitles('Apple', 'zion'), lessThan(0));
      expect(compareNoteTitles('Zion', 'apple'), greaterThan(0));
    });

    test('titles differing only in case compare equal', () {
      expect(compareNoteTitles('apple', 'Apple'), 0);
    });
  });

  group('compareNoteTitles reads numbers as numbers', () {
    test('Week 2 precedes Week 10', () {
      expect(sorted(['Week 10', 'Week 2', 'Week 1']), ['Week 1', 'Week 2', 'Week 10']);
    });

    test('leading zeros do not change the value', () {
      expect(compareNoteTitles('Week 007', 'Week 7'), 0);
      expect(sorted(['Week 08', 'Week 9']), ['Week 08', 'Week 9']);
    });

    /// A note titled with a pasted id or a long date run can carry more digits
    /// than an int64 holds. Parsing would throw or silently wrap, so digit runs
    /// are compared as text with leading zeros stripped.
    test('survives a digit run far longer than int64', () {
      final long = '9' * 40;
      final longer = '9' * 41;
      expect(compareNoteTitles('id $long', 'id $longer'), lessThan(0));
    });

    test('orders the dated titles this app actually produces', () {
      expect(
        sorted(['06-09-2026', '02-08-2026', '13-09-2026']),
        ['02-08-2026', '06-09-2026', '13-09-2026'],
      );
    });
  });

  group('compareNoteTitles edge cases', () {
    test('a prefix sorts before the longer title', () {
      expect(compareNoteTitles('Faith', 'Faithful'), lessThan(0));
    });

    test('empty titles sort first and compare equal to each other', () {
      expect(compareNoteTitles('', ''), 0);
      expect(compareNoteTitles('', 'anything'), lessThan(0));
    });

    test('is a consistent ordering — sorting twice does not move anything', () {
      final once = sorted(['zion', 'Apple', 'Week 10', 'week 2', '', 'apple']);
      expect(List<String>.from(once)..sort(compareNoteTitles), once);
    });
  });
}
