// Tags your notes put on verses, read back in the Bible reader.
//
// The editor writes them onto Bible reference blocks; this is the reverse
// direction. A verse tagged from two different notes carries both — the reader
// answers "what have I called this verse", not "what did that one note call
// it".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/sync/models/tag_model.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/bible/domain/models/bible_highlight_entity.dart';
import 'package:notify/features/bible/domain/models/bible_verse_entity.dart';
import 'package:notify/features/bible/presentation/widgets/chapter_verse_list.dart';

TagModel tag(String id, String name) =>
    TagModel.create(id: id, userId: 'u', name: name);

BibleVerseEntity verse(int n) => BibleVerseEntity(
      id: n,
      translation: 'nkjv',
      bookId: 43,
      chapter: 3,
      verse: n,
      text: 'Verse $n text',
    );

void main() {
  String? tapped;

  setUp(() => tapped = null);

  Future<void> pumpList(
    WidgetTester tester, {
    Map<int, Set<String>> verseTags = const {},
    List<TagModel> tags = const [],
    bool showVerseTags = true,
    List<BibleHighlightEntity> highlights = const [],
  }) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final controller = ScrollController();
    addTearDown(controller.dispose);

    // The verse row reads its font size from reading preferences.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        tagsStreamProvider.overrideWith((ref) => Stream.value(tags)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ChapterVerseList(
            verses: [verse(16), verse(17)],
            highlights: highlights,
            scrollController: controller,
            verseTags: verseTags,
            showVerseTags: showVerseTags,
            onTagTap: (id) => tapped = id,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('a tagged verse shows the tag at the end of the line',
      (tester) async {
    await pumpList(
      tester,
      verseTags: {16: {'t1'}},
      tags: [tag('t1', 'faith')],
    );

    expect(find.text('faith'), findsOneWidget);
  });

  testWidgets('only the tagged verse carries it', (tester) async {
    await pumpList(
      tester,
      verseTags: {16: {'t1'}},
      tags: [tag('t1', 'faith')],
    );

    // Verse 17 is on screen and untagged.
    expect(find.text('Verse 17 text'), findsOneWidget);
    expect(find.text('faith'), findsOneWidget);
  });

  testWidgets('a verse tagged from two notes shows both', (tester) async {
    await pumpList(
      tester,
      verseTags: {16: {'t1', 't2'}},
      tags: [tag('t1', 'faith'), tag('t2', 'grace')],
    );

    expect(find.text('faith'), findsOneWidget);
    expect(find.text('grace'), findsOneWidget);
  });

  testWidgets('tapping a tag reports it', (tester) async {
    await pumpList(
      tester,
      verseTags: {16: {'t1'}},
      tags: [tag('t1', 'faith')],
    );

    await tester.tap(find.text('faith'));
    await tester.pump();

    expect(tapped, 't1',
        reason: 'the row gesture detector swallowed the tap');
  });

  testWidgets('the secondary parallel column shows no tags', (tester) async {
    // The tags belong to the verse, not a translation, so showing them in
    // both columns would put two controls on screen for one thing.
    await pumpList(
      tester,
      verseTags: {16: {'t1'}},
      tags: [tag('t1', 'faith')],
      showVerseTags: false,
    );

    expect(find.text('faith'), findsNothing);
  });

  testWidgets('a tag whose name has not loaded is not shown as a raw id',
      (tester) async {
    await pumpList(tester, verseTags: {16: {'t-unknown'}});

    expect(find.text('t-unknown'), findsNothing);
  });

  testWidgets('no tags means nothing extra on the row', (tester) async {
    await pumpList(tester);

    expect(find.byIcon(Icons.local_offer_outlined), findsNothing);
  });
}
