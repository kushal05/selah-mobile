// A read that has not returned is not an answer about the user's data.
//
// Three sites reduced an AsyncValue to `valueOrNull ?? []` and then made a
// statement from the empty list, so during the first frames after opening a
// screen the app said things that were simply not true and then corrected
// itself:
//
//   * the prayer-updates feed labelled every row "Unknown Prayer";
//   * the songs header announced "all songs" while a folder was selected;
//   * the Bible search screen pinned its translation filter to the NKJV
//     fallback and, because it does so once in initState, never corrected.
//
// These assert on the source rather than by pumping each screen: two of the
// three are single lines deep inside 900+ line screens whose full provider
// graphs (sync, auth, search isolate) are not constructible here, and the
// thing that went wrong is precisely the shape of the expression — a claim
// made without first asking whether the value had arrived.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsLinesSync()
    .map((l) => l.replaceFirst(RegExp(r'\s*//.*$'), ''))
    .join('\n');

void main() {
  test('the updates feed does not name a prayer it has not read', () {
    final src = _read(
        'lib/features/prayers/presentation/screens/prayer_updates_feed_screen.dart');

    expect(src.contains("'Unknown Prayer'"), isFalse,
        reason: 'the hardcoded label is gone from the catalogue-less path');
    expect(src.contains('prayersAsync.hasValue'), isTrue,
        reason: 'the title may only fall back once the prayers have landed');
    expect(src.contains('l10n(context).unknownPrayer'), isTrue,
        reason: 'a genuinely missing prayer still gets a localised label');
  });

  test('the songs header does not rename the scope it is showing', () {
    final src = _read(
        'lib/features/songs/presentation/screens/songs_home_screen.dart');

    expect(src.contains('foldersKnown'), isTrue,
        reason: 'the "all songs" fallback must wait for the folders');
    // The fallback itself stays — a folder that has genuinely gone away still
    // reads as all songs. This pins that it is guarded, not removed.
    expect(RegExp(r'foldersKnown \? l10n\(context\)\.allSongs').hasMatch(src),
        isTrue);
  });

  test('bible search does not pin a guessed translation', () {
    final src = _read(
        'lib/features/bible_search/presentation/screens/bible_search_screen.dart');

    expect(src.contains('bibleVersionStatesProvider).hasValue'), isTrue,
        reason: 'the default may only be applied once the versions are known');
    expect(src.contains('listenManual'), isTrue,
        reason: 'a default arriving later must still be applied');
    expect(src.contains('_filtersTouched'), isTrue,
        reason: "a late default must not overwrite the user's own choice");
    expect(src.contains('_defaultTranslationSub?.close()'), isTrue,
        reason: 'the manual subscription has to be closed');
  });
}
