import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notify/features/bible/data/bible_paragraph_data.dart';
import 'package:notify/features/bible/presentation/providers/bible_chapter_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reads the per-book, per-chapter lists', () {
    final data = BibleParagraphData.parse('{"43":{"3":[3,4,9]},"1":{"1":[6]}}');
    expect(data.startsFor(43, 3), {3, 4, 9});
    expect(data.startsFor(1, 1), {6});
    expect(data.startsFor(43, 2), isEmpty);
    expect(data.startsFor(2, 1), isEmpty);
  });

  test('skips bad entries and keeps the good ones', () {
    final data = BibleParagraphData.parse(
        '{"1":{"1":[1,0,-2,"4",null,2.5,5],"x":[3],"2":"nope"},"y":{"1":[3]},"2":[1]}');
    expect(data.startsFor(1, 1), {5});
    expect(data.startsFor(1, 2), isEmpty);
  });

  test('damaged or unexpected input gives no paragraphs, never an error', () {
    for (final source in ['', 'not json', '[]', '"x"', '42', 'null', '{"1":']) {
      expect(BibleParagraphData.parse(source).startsFor(1, 1), isEmpty,
          reason: source);
    }
    expect(BibleParagraphData.empty.startsFor(43, 3), isEmpty);
  });

  test('the bundled asset parses to real paragraph data', () {
    // Read straight from the file: this guards the asset itself, not the bundle.
    final data = BibleParagraphData.parse(
        _read('assets/bible/paragraphs.json'));
    expect(data.startsFor(43, 3), contains(9)); // John 3
    expect(data.startsFor(43, 3), isNot(contains(1)));
    expect(data.startsFor(66, 1), isNotEmpty); // Revelation
  });

  test('the provider reads the asset from the app bundle (so pubspec lists it)',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final data = await container.read(bibleParagraphDataProvider.future);
    expect(data.startsFor(43, 3), contains(9));
  });
}

String _read(String path) => File(path).readAsStringSync();
